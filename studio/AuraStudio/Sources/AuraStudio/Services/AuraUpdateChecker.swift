import Foundation

/// Decide si el firmware Aura instalado en el iPod es mas viejo que el
/// que trae embebida ESTA version de Aura Studio.
///
/// La comparacion es por hash SHA-256 de `rockbox.ipod`, no por numero
/// de version ni fecha: el binario embebido es la fuente de verdad de
/// "lo mas nuevo que esta app conoce", y dos binarios distintos = hay
/// algo que actualizar (en cualquier direccion -- si el usuario tiene
/// una app vieja y un firmware mas nuevo, actualizar lo "regresaria";
/// ese caso se resuelve actualizando la app, y el texto de la UI habla
/// de "esta version de Aura Studio" a proposito).
///
/// NOTA sobre GitHub (encargo del dueño, 2026-08-13, resuelto
/// 2026-08-17 -- ver ST-006): la idea original era consultar el
/// ultimo release publicado del repositorio. El repo ya es publico y
/// tiene su primer Release (`v0.1.0-beta`) -- `checkForUpdate(_:)`
/// abajo es ese punto: compara el tag mas nuevo de GitHub contra
/// `.rockbox/aura/version.txt` del dispositivo (PLAN-release-updates.md
/// S1.0/S1.5). El chequeo por hash de esta funcion NO se reemplaza --
/// sigue siendo el respaldo para dispositivos sin `version.txt`
/// (instalados antes de esta funcionalidad, o por fuera de un Release
/// etiquetado) y para cuando no hay red.
enum AuraUpdateChecker {
    /// Rutas candidatas del binario instalado, en orden de preferencia:
    /// el que arranca el bootloader es `/.rockbox/rockbox.ipod` (viaja
    /// en el arbol desde D-178); el de la raiz es la copia que el
    /// instalador dejaba desde el principio.
    static let installedRelativePaths = [".rockbox/rockbox.ipod", "rockbox.ipod"]

    /// `.rockbox/aura/version.txt` (D-290 en Aura-Firmware): el tag
    /// exacto del Release con el que se empaqueto el `rockbox.zip`
    /// instalado, escrito por `package_dist.sh --release-tag`. El
    /// firmware nunca lo lee de vuelta -- es puramente para Studio.
    static let versionMarkerRelativePath = ".rockbox/aura/version.txt"

    static func installedVersionTag(deviceMountPath: String) -> String? {
        guard !deviceMountPath.isEmpty, deviceMountPath.hasPrefix("/") else { return nil }
        let url = URL(fileURLWithPath: deviceMountPath).appendingPathComponent(versionMarkerRelativePath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Compara el Release mas nuevo de GitHub (con cache, ver
    /// `ReleaseCache`) contra `version.txt` del dispositivo. Si
    /// cualquier paso no da una respuesta utilizable -- sin
    /// `version.txt`, tag ilegible, sin red y sin cache -- cae a
    /// `isUpdateAvailable(deviceMountPath:)` (hash local, sin red).
    /// `includePrereleases` en `true` por defecto: mientras el unico
    /// canal publicado sea beta, no tiene sentido pedir opt-in (Q6).
    ///
    /// `forceRefresh` (D-300 en Aura-Firmware / cross-repo, encargo del
    /// dueño: "aura studio [no] pudo acceder a el para que me
    /// apareciera"): reportado en vivo -- se publico v0.2.1-beta y ni
    /// reabrir Aura Studio con el pin nuevo lo detecto. Causa real: el
    /// TTL de 24h de `ReleaseCache` es correcto para el chequeo
    /// AUTOMATICO al conectar (evita pegarle a la API de GitHub en cada
    /// conexion), pero **ninguna** ruta -- ni siquiera el boton manual
    /// "Buscar actualizaciones de Aura" -- tenia forma de saltarselo: si
    /// la cache se lleno un rato ANTES de que el Release nuevo se
    /// publicara, el usuario podia apretar ese boton, reabrir la app,
    /// lo que fuera, y seguir viendo "al dia" hasta que el TTL venciera
    /// solo. `false` por defecto (mismo comportamiento de siempre para
    /// el chequeo automatico); una revision manual explicita del
    /// usuario SI debe ser una consulta en vivo de verdad.
    /// `family` (ST-046): a que repositorio se le pregunta, y si el
    /// respaldo por hash aplica. `.aura` por defecto -- es lo que significa
    /// la ausencia de `firmware_family` en `aura.cfg`, y mantiene el
    /// comportamiento historico para todo iPod con Aura.
    static func checkForUpdate(deviceMountPath: String,
                                family: FirmwareFamily = .aura,
                                session: URLSession = .shared,
                                defaults: UserDefaults = .standard,
                                includePrereleases: Bool = true,
                                forceRefresh: Bool = false) async -> Bool {
        guard !deviceMountPath.isEmpty, deviceMountPath.hasPrefix("/") else { return false }
        // Familia desconocida: no hay repo que consultar ni binario
        // embebido con el que comparar. Callar es lo correcto -- ofrecer
        // "actualizar" aqui significaria ofrecer SOBRESCRIBIRLO con otro
        // firmware.
        guard family.releaseRepository != nil else { return false }

        if let installedTag = installedVersionTag(deviceMountPath: deviceMountPath),
           let installed = SemVer.parse(installedTag) {
            var releases = forceRefresh ? nil : ReleaseCache.load(defaults: defaults, family: family)
            if releases == nil {
                releases = try? await fetchAndCache(session: session, defaults: defaults, family: family)
            }
            if let releases,
               let latest = GitHubReleaseChecker.pickLatest(from: releases, includePrereleases: includePrereleases),
               let latestVersion = SemVer.parse(latest.tagName) {
                return installed < latestVersion
            }
            // Sin red y sin cache: no se puede comparar por version.
            // Cae al hash en vez de reportar "sin actualizacion".
        }

        return await isUpdateAvailable(deviceMountPath: deviceMountPath, family: family)
    }

    /// Tag del Release mas nuevo que Studio conoce para esa familia, para
    /// poder NOMBRARLO en la interfaz ("Metro v0.5.0 disponible") en vez de
    /// solo decir que hay algo. Lee unicamente el cache -- no toca la red:
    /// se llama justo despues de `checkForUpdate`, que acaba de llenarlo.
    /// `nil` si no hay cache vigente, y entonces la UI se queda con el
    /// texto generico.
    static func latestKnownTag(family: FirmwareFamily = .aura,
                                defaults: UserDefaults = .standard,
                                includePrereleases: Bool = true) -> String? {
        guard let releases = ReleaseCache.load(defaults: defaults, family: family) else { return nil }
        return GitHubReleaseChecker.pickLatest(from: releases,
                                                includePrereleases: includePrereleases)?.tagName
    }

    private static func fetchAndCache(session: URLSession,
                                       defaults: UserDefaults,
                                       family: FirmwareFamily) async throws -> [GitHubRelease] {
        let releases = try await GitHubReleaseChecker.fetchReleases(session: session, family: family)
        // ST-074: un rechazo del token devuelve [] sin lanzar. No se
        // cachea: si no, arreglar el token en Ajustes no surtiría efecto
        // hasta que venciera el TTL de 24 h.
        if releases.isEmpty, GitHubReleaseChecker.lastAuthFailure { return releases }
        ReleaseCache.store(releases, defaults: defaults, family: family)
        return releases
    }

    /// Respaldo por hash contra el binario EMBEBIDO de LA MISMA familia.
    /// ST-046 descubrio el bug de comparar el `rockbox.ipod` de Metro
    /// contra el de Aura embebido (el hash siempre difiere -> "hay
    /// actualizacion" eternamente -> sobrescribir Metro con Aura). ST-047
    /// embebe todas las familias instalables, asi que cada una se compara contra
    /// la suya; una familia que esta version no trae embebida
    /// (`isInstallable == false`) devuelve `false`: sin binario propio no
    /// hay nada que comparar, y no compararlo es mejor que compararlo mal.
    static func isUpdateAvailable(deviceMountPath: String,
                                   family: FirmwareFamily = .aura) async -> Bool {
        guard family.isInstallable else { return false }
        guard !deviceMountPath.isEmpty, deviceMountPath.hasPrefix("/"),
              let bundledURL = BundledArtifacts.forFamily(family).url(for: .firmware) else { return false }

        let root = URL(fileURLWithPath: deviceMountPath)
        let fm = FileManager.default
        guard let installedURL = installedRelativePaths
            .map({ root.appendingPathComponent($0) })
            .first(where: { fm.fileExists(atPath: $0.path) }) else {
            // Aura detectada pero sin binario a la vista (arbol a medio
            // copiar): eso lo arregla reinstalar, asi que cuenta como
            // actualizacion disponible.
            return true
        }

        let bundledHash = try? BundledArtifacts.sha256Hex(of: bundledURL)
        let installedHash = try? BundledArtifacts.sha256Hex(of: installedURL)
        guard let bundledHash, let installedHash else { return false }
        return bundledHash != installedHash
    }
}

/// Cache de la lista de Releases de GitHub en `UserDefaults`, con TTL
/// de 24h (PLAN-release-updates.md S1.5, Q7): evita pegarle a la API
/// en cada conexion de dispositivo -- el limite anonimo de GitHub
/// (60 req/hora) no es el problema real, es no depender de la red
/// para algo que casi nunca cambia. Vencido el TTL, el proximo
/// `checkForUpdate` vuelve a consultar y renueva el cache.
/// ST-046: el cache es POR FAMILIA. Con una sola llave, la lista de
/// Releases de Metro habria quedado guardada bajo la de Aura (y al reves):
/// conectar un iPod con Metro y despues uno con Aura le habria mostrado al
/// segundo los tags del primero durante 24h, comparados contra su propio
/// `version.txt`. Las llaves historicas se conservan tal cual para Aura,
/// asi que ningun usuario pierde su cache al actualizar Studio.
enum ReleaseCache {
    static let dataKey = "AuraUpdateChecker.cachedReleases"
    static let timestampKey = "AuraUpdateChecker.cachedReleasesTimestamp"

    static func dataKey(for family: FirmwareFamily) -> String {
        guard let suffix = family.configValue else { return dataKey }
        return "\(dataKey).\(suffix)"
    }

    static func timestampKey(for family: FirmwareFamily) -> String {
        guard let suffix = family.configValue else { return timestampKey }
        return "\(timestampKey).\(suffix)"
    }
    static let ttl: TimeInterval = 24 * 3600

    static func load(defaults: UserDefaults, family: FirmwareFamily = .aura) -> [GitHubRelease]? {
        guard let timestamp = defaults.object(forKey: timestampKey(for: family)) as? Date,
              Date().timeIntervalSince(timestamp) < ttl,
              let data = defaults.data(forKey: dataKey(for: family)) else { return nil }
        return try? JSONDecoder().decode([GitHubRelease].self, from: data)
    }

    static func store(_ releases: [GitHubRelease], defaults: UserDefaults, family: FirmwareFamily = .aura) {
        guard let data = try? JSONEncoder().encode(releases) else { return }
        defaults.set(data, forKey: dataKey(for: family))
        defaults.set(Date(), forKey: timestampKey(for: family))
    }
}
