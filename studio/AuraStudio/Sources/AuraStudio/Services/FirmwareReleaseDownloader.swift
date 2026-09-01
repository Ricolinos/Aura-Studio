import Foundation

/// ST-077: baja los artefactos del Release MAS NUEVO de una familia y
/// los deja verificados en un directorio local, para que el instalador
/// escriba en el iPod esa version y no la que quedo empotrada en la app
/// al compilar (`FIRMWARE_VERSION`, `BundledArtifacts`).
///
/// Por que existe: hasta ST-076 el pin de `FIRMWARE_VERSION` era la
/// UNICA fuente de instalacion. El aviso de "hay version nueva" si
/// consultaba GitHub (ST-074), asi que Studio podia saber que existia
/// v0.5.0 y aun asi instalar v0.4.4 desde cero -- y la pastilla de
/// Extras mostraba el pin, no lo disponible. Encargo del dueño
/// (2026-08-27): "por si hay que instalar desde cero, que instale el
/// mas reciente".
///
/// Lo que NO cambia: los binarios embebidos siguen viajando en la app y
/// siguen siendo el respaldo. Sin red, sin token, con un Release
/// incompleto o con cualquier verificacion fallida, el instalador usa
/// lo embebido y lo dice -- nunca se queda sin instalar, y nunca
/// escribe en el iPod algo que no haya verificado.
///
/// Contrato: §A ya define la lista exacta de assets de un Release y su
/// `checksums.txt`; esta clase la consume tal cual. §E (el pin) pasa a
/// ser el respaldo en vez de la unica via.
enum FirmwareReleaseDownloader {

    /// Los cinco assets de la tabla §A que hacen falta para instalar.
    /// `checksums.txt` va primero a proposito: es contra quien se
    /// verifican los otros cuatro.
    static let requiredAssets: [BundledArtifacts.Name] = [
        .checksums, .firmware, .rockboxTree, .bootloader, .mks5lboot,
    ]

    /// `~/Library/Application Support/AuraStudio/firmware-cache/<familia>/<tag>/`.
    /// Por tag: bajar una version nueva no pisa la anterior, y volver a
    /// una ya bajada no vuelve a descargar nada.
    static func cacheDirectory(family: FirmwareFamily, tag: String) -> URL? {
        guard let suffix = family.configValue ?? (family == .aura ? "aura" : nil) else { return nil }
        // El tag viaja a una ruta: solo se acepta el juego de caracteres
        // de un tag SemVer real, nunca lo que venga de la red tal cual.
        guard isSafeTagComponent(tag) else { return nil }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return base?
            .appendingPathComponent("AuraStudio", isDirectory: true)
            .appendingPathComponent("firmware-cache", isDirectory: true)
            .appendingPathComponent(suffix, isDirectory: true)
            .appendingPathComponent(tag, isDirectory: true)
    }

    /// Un tag que va a formar parte de una ruta de archivo. Deliberadamente
    /// estrecho -- alfanumericos, punto, guion y guion bajo, sin `/`, sin
    /// `..`, sin vacio. Mismo criterio que `AuraThemeID.isValid()` para
    /// los ids de tema: nada que venga de fuera toca una ruta sin pasar
    /// por aqui.
    static func isSafeTagComponent(_ tag: String) -> Bool {
        guard !tag.isEmpty, tag.count <= 64, tag != ".", tag != ".." else { return false }
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        return tag.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// true si ese directorio ya tiene los cinco assets. No re-verifica
    /// los hashes aqui: eso lo hace `BundledArtifacts.verifyAll()` sobre
    /// el directorio, y el instalador lo corre igual antes de copiar.
    static func isComplete(directory: URL) -> Bool {
        let fm = FileManager.default
        return requiredAssets.allSatisfy {
            fm.fileExists(atPath: directory.appendingPathComponent($0.rawValue).path)
        }
    }

    /// Resultado de `prepareLatest`: donde quedaron los artefactos y de
    /// que tag son.
    struct Prepared: Equatable {
        let tag: String
        let directory: URL
    }

    /// Deja listos los artefactos del Release mas nuevo de `family`.
    ///
    /// - Si ya estaban bajados y completos, no toca la red.
    /// - Si algo falla en cualquier punto, LANZA -- el llamador
    ///   (`InstallerViewModel`) trata eso como "usa lo embebido", nunca
    ///   como un error de instalacion.
    ///
    /// `progress` recibe texto de cara al usuario para la pantalla del
    /// instalador. `@Sendable` porque esta funcion es `nonisolated async`
    /// y el llamador real (`InstallerViewModel`, `@MainActor`) le pasa un
    /// cierre desde su propio aislamiento: sin la anotacion, la
    /// concurrencia estricta de Swift 6 lo rechaza ("sending value of
    /// non-Sendable type"). El build de SPM no lo detectaba; el de
    /// `xcodebuild` sí, y ese es el que produce la app.
    static func prepareLatest(family: FirmwareFamily,
                               session: URLSession = .shared,
                               token: String? = GitHubToken.load(),
                               includePrereleases: Bool = true,
                               progress: (@Sendable (String) -> Void)? = nil) async throws -> Prepared {
        guard family.isInstallable else {
            throw InstallerError.releaseDownloadFailed(
                family: family.displayName, reason: "esta versión de Aura Studio no instala esa familia")
        }
        progress?("Buscando la versión más reciente de \(family.displayName)...")

        let releases = try await GitHubReleaseChecker.fetchReleases(
            session: session, family: family, token: token)
        guard let latest = GitHubReleaseChecker.pickLatest(
                from: releases, includePrereleases: includePrereleases) else {
            // Lista vacia con token = rechazo de autenticacion (ST-074).
            let reason = GitHubReleaseChecker.lastAuthFailure
                ? "el token de GitHub no tiene acceso a ese repositorio"
                : "GitHub no devolvió ningún Release utilizable"
            throw InstallerError.releaseDownloadFailed(family: family.displayName, reason: reason)
        }
        guard let directory = cacheDirectory(family: family, tag: latest.tagName) else {
            throw InstallerError.releaseDownloadFailed(
                family: family.displayName, reason: "el tag \(latest.tagName) no es un nombre de carpeta válido")
        }
        if isComplete(directory: directory) {
            progress?("\(family.displayName) \(latest.tagName) ya estaba descargado.")
            return Prepared(tag: latest.tagName, directory: directory)
        }

        // Se baja a un directorio aparte y solo se publica entero: un
        // corte a la mitad nunca deja un directorio "completo" a medias
        // que la proxima corrida daria por bueno.
        let fm = FileManager.default
        let staging = directory.deletingLastPathComponent()
            .appendingPathComponent(".descarga-\(latest.tagName)", isDirectory: true)
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        for name in requiredAssets {
            guard let asset = latest.asset(named: name.rawValue) else {
                throw InstallerError.releaseMissingAsset(tag: latest.tagName, asset: name.rawValue)
            }
            progress?("Descargando \(name.rawValue) de \(family.displayName) \(latest.tagName)...")
            let data = try await downloadAsset(asset, session: session, token: token,
                                                family: family, tag: latest.tagName)
            let destination = staging.appendingPathComponent(name.rawValue)
            try data.write(to: destination, options: .atomic)
            // Los permisos POSIX no viajan en una descarga: `mks5lboot`
            // llega sin el bit de ejecucion y `MKS5LBootRunner` lo
            // rechaza (`binaryNotExecutable`). En el bundle venia
            // ejecutable porque lo empaqueta el build.
            if name == .mks5lboot {
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
            }
        }

        // El tag, junto a los artefactos: es lo que lee
        // `BundledArtifacts.releaseTag` para la pantalla de Licencias y
        // para el manifiesto de instalacion (contrato v11).
        try "\(latest.tagName)\n".write(to: staging.appendingPathComponent("firmware-version.txt"),
                                         atomically: true, encoding: .utf8)

        // Verificacion COMPLETA antes de publicar: hashes contra el
        // checksums.txt del propio Release y, para rockbox.zip, que de
        // verdad traiga codecs y plugins (D-297/D-298 -- un checksum
        // correcto por si solo no detecta un Release mal empaquetado).
        progress?("Verificando integridad de \(family.displayName) \(latest.tagName)...")
        try BundledArtifacts(directory: staging, family: family).verifyAll()

        try? fm.removeItem(at: directory)
        try fm.createDirectory(at: directory.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        try fm.moveItem(at: staging, to: directory)
        return Prepared(tag: latest.tagName, directory: directory)
    }

    /// Baja un asset por la URL del API. En un repositorio privado esta
    /// es la unica via que funciona con token: `browser_download_url`
    /// redirige a un host de almacenamiento que **rechaza** la cabecera
    /// `Authorization` ("only one auth mechanism allowed"). Por eso
    /// tambien el delegado de abajo: GitHub responde 302 hacia ese host
    /// y hay que soltar la cabecera en el salto.
    static func downloadAsset(_ asset: GitHubReleaseAsset,
                               session: URLSession = .shared,
                               token: String?,
                               family: FirmwareFamily,
                               tag: String) async throws -> Data {
        guard let url = URL(string: asset.url) else {
            throw InstallerError.releaseDownloadFailed(
                family: family.displayName, reason: "la URL de \(asset.name) no es válida")
        }
        var request = URLRequest(url: url)
        request.setValue("AuraStudio", forHTTPHeaderField: "User-Agent")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let delegate = RedirectAuthStripper()
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request, delegate: delegate)
        } catch {
            throw InstallerError.releaseDownloadFailed(
                family: family.displayName, reason: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw InstallerError.releaseDownloadFailed(
                family: family.displayName,
                reason: "GitHub respondió \(code) al pedir \(asset.name) de \(tag)")
        }
        // El tamaño que anuncia el Release es una comprobacion barata de
        // "llego entero" ANTES del hash, que es lo caro. Un asset de 0
        // bytes o truncado se detecta aqui con un mensaje entendible.
        guard asset.size <= 0 || data.count == asset.size else {
            throw InstallerError.releaseDownloadFailed(
                family: family.displayName,
                reason: "\(asset.name) llegó incompleto (\(data.count) de \(asset.size) bytes)")
        }
        return data
    }
}

/// Suelta `Authorization` cuando el redirect cambia de host. GitHub
/// contesta la descarga de un asset con un 302 hacia su almacenamiento
/// de objetos, que devuelve 400 si le llega la cabecera de GitHub.
/// `URLSession` reenvia las cabeceras por su cuenta, asi que hay que
/// reconstruir la peticion.
final class RedirectAuthStripper: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard let originalHost = task.originalRequest?.url?.host,
              let newHost = request.url?.host,
              originalHost.caseInsensitiveCompare(newHost) != .orderedSame else {
            return request
        }
        var stripped = request
        stripped.setValue(nil, forHTTPHeaderField: "Authorization")
        return stripped
    }
}
