import Foundation

/// ST-193: decidir si hay una versión más nueva **de Aura Studio** y
/// cuál archivo le corresponde a esta plataforma.
///
/// Es la pieza nueva de la propuesta de ST-191, y es **pura a
/// propósito**: no consulta la red, no lee el bundle, no toca disco. Se
/// le dan la versión instalada y los Releases ya traídos, y devuelve una
/// decisión. Por eso se puede probar entera sin red y por eso sirve como
/// **referencia para Windows**, que la porta citando esta ST (acuerdo de
/// la sesión maestra: Swift es la referencia).
///
/// ## Las reglas, en orden
///
/// 1. Un **draft** nunca cuenta: no es instalable.
/// 2. Una **prerelease** cuenta solo si `includePrereleases`. Hoy todo
///    lo publicado es beta, así que en la práctica cuenta siempre; el
///    interruptor importa el día que exista un canal estable.
/// 3. El tag se lee como SemVer (`v0.3.0` → `0.3.0`). Un tag que no
///    parsea **se ignora**, no rompe nada.
/// 4. De los que quedan, gana el mayor.
/// 5. Solo hay novedad si ese mayor es **estrictamente mayor** que lo
///    instalado. Nunca se ofrece "actualizar" hacia atrás.
/// 6. El asset se busca por **nombre exacto**, según el patrón congelado
///    (ver `AppUpdatePlatform.assetName`). Si no está, **igual se avisa
///    de la versión nueva**, pero sin botón de descarga: se enlaza la
///    página del Release. Un botón "Descargar" que falla es peor que no
///    tenerlo.
enum AppUpdateDecision {
    /// El repositorio donde se publican los instaladores de la app --
    /// distinto del del firmware (`Aura-Firmware` y hermanos).
    static let repository = "Ricolinos/Aura-Studio"

    /// Lo que hay que mostrar cuando hay una versión más nueva.
    struct Available: Equatable {
        /// La versión publicada, ya parseada.
        let version: SemVer
        /// El tag tal cual lo publicó GitHub (`v0.3.0`) -- es lo que se
        /// persiste para no repetir el aviso.
        let tag: String
        /// La página del Release, para "Ver novedades".
        let releasePageURL: URL?
        /// El archivo a bajar para ESTA plataforma. `nil` si el Release
        /// no trae el asset esperado.
        let downloadURL: URL?
        /// El nombre del asset esperado, para poder decirlo si falta.
        let assetName: String
    }

    /// El resultado de una comprobación, para la que el usuario pidió a
    /// mano. El chequeo automático solo mira `.available`.
    enum Outcome: Equatable {
        case available(Available)
        /// Consultado con éxito: no hay nada más nuevo.
        case upToDate
        /// No se pudo preguntar. **No es lo mismo que "no hay
        /// novedades"** y la UI no puede decirlo igual -- es el defecto
        /// que Windows arregló en ST-210 para el chequeo del firmware.
        case couldNotCheck(String)
    }

    /// Decide. `installedVersion` es la versión de la app corriendo
    /// (`AppVersion.current`); `releases` es lo que devolvió GitHub.
    ///
    /// Devuelve `nil` cuando no hay nada que ofrecer -- incluido el caso
    /// de una versión instalada que no parsea, donde lo prudente es
    /// callar: sin saber qué hay instalado no se puede afirmar que algo
    /// sea más nuevo.
    static func decide(installedVersion: String,
                       releases: [GitHubRelease],
                       includePrereleases: Bool,
                       platform: AppUpdatePlatform = .current) -> Available? {
        guard let installed = SemVer.parse(installedVersion) else { return nil }
        guard let latest = GitHubReleaseChecker.pickLatest(from: releases,
                                                          includePrereleases: includePrereleases),
              let latestVersion = SemVer.parse(latest.tagName),
              installed < latestVersion else {
            return nil
        }

        let assetName = platform.assetName(forVersion: latestVersion)
        let download = latest.asset(named: assetName)?.browserDownloadURL.flatMap(URL.init(string:))

        return Available(version: latestVersion,
                         tag: latest.tagName,
                         releasePageURL: releasePageURL(for: latest),
                         downloadURL: download,
                         assetName: assetName)
    }

    /// La página del Release. Se prefiere la que da GitHub; si no vino
    /// (respuesta recortada, caché viejo), se arma con el repo y el tag
    /// -- es una URL estable y documentada de GitHub.
    static func releasePageURL(for release: GitHubRelease) -> URL? {
        if let html = release.htmlURL, let url = URL(string: html) { return url }
        return URL(string: "https://github.com/\(repository)/releases/tag/\(release.tagName)")
    }
}


/// ST-193: para qué plataforma se busca el instalador.
///
/// Las tres están acá aunque macOS solo use una, y es deliberado: el
/// patrón de nombres de los assets es **el único contrato nuevo** de
/// esta funcionalidad, lo congeló la sesión maestra para las dos
/// plataformas, y tenerlo escrito en un solo lugar es lo que hace que
/// Windows pueda portarlo sin volver a decidir nada.
///
/// El patrón, tal como quedó fijado (y tal como ya lo cumplen los
/// Releases v0.2.2 y v0.2.3):
///
/// ```
/// tag:  v<versión>
/// mac:  AuraStudio-<versión>.dmg
/// win:  AuraStudioSetup-<versión>-arm64.exe
///       AuraStudioSetup-<versión>-x64.exe
/// ```
///
/// **Ningún otro asset cuenta.** En Windows, elegir mal la arquitectura
/// es peor que no ofrecer nada: ST-135 documenta que el Setup x64 en una
/// máquina ARM avisa y deja continuar, así que ofrecerlo por defecto
/// sería empujar al usuario a la versión lenta.
enum AppUpdatePlatform: Equatable, Sendable {
    case mac
    case windowsARM64
    case windowsX64

    /// La de esta app. En macOS siempre `.mac` -- el `.dmg` es
    /// universal, no hay variante por arquitectura.
    static var current: AppUpdatePlatform { .mac }

    /// El nombre EXACTO del asset. La versión va sin la `v` del tag.
    func assetName(forVersion version: SemVer) -> String {
        switch self {
        case .mac: return "AuraStudio-\(version.releaseString).dmg"
        case .windowsARM64: return "AuraStudioSetup-\(version.releaseString)-arm64.exe"
        case .windowsX64: return "AuraStudioSetup-\(version.releaseString)-x64.exe"
        }
    }
}

extension SemVer {
    /// La versión como aparece en el NOMBRE de un asset y en el tag
    /// (sin la `v`): `0.3.0`, o `0.3.0-beta` si tuviera sufijo.
    var releaseString: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.map { "\(core)-\($0)" } ?? core
    }
}

/// ST-193: la versión de ESTA app.
///
/// La app nunca había necesitado saber su propia versión, así que no
/// había de dónde leerla. Sale de `CFBundleShortVersionString`, que ya
/// se sube en cada release junto con `MARKETING_VERSION` y las dos de
/// Windows (regla de `CLAUDE.md` § Releases: los tres lugares a la vez,
/// en el mismo commit).
///
/// `overrideForTesting` existe porque bajo `swift test` no hay bundle de
/// app: el Info.plist con esa clave solo está en el `.app` que arma
/// `xcodebuild`. Sin esto, cualquier prueba que toque esto mediría el
/// bundle del ejecutable de pruebas, que no tiene versión.
enum AppVersion {
    nonisolated(unsafe) static var overrideForTesting: String?

    static var current: String {
        if let overrideForTesting { return overrideForTesting }
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
}
