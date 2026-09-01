import Foundation

/// ST-077: qué versión de cada firmware se instalaría **hoy**, para que
/// Extras muestre eso y no el pin de `FIRMWARE_VERSION` horneado al
/// compilar.
///
/// El bug que arregla (reporte del dueño, 2026-08-27): la pastilla de
/// cada tarjeta de firmware salía de `BundledArtifacts.releaseTag`, así
/// que un Release publicado después de compilar la app era invisible
/// ahí — aunque el aviso de actualizaciones (`AuraUpdateChecker`, con el
/// token de ST-074) ya lo conociera. Extras y el instalador tienen que
/// coincidir: desde ST-077 los dos miran el Release más nuevo.
///
/// Nunca deja la pastilla vacía: sin red, sin token o con un repo sin
/// Releases utilizables, cae al tag embebido y lo marca como tal
/// (`isLatestFromGitHub == false`) para que la UI pueda decir "incluida"
/// en vez de aparentar que eso es lo último publicado.
@MainActor
final class AvailableFirmwareVersions: ObservableObject {
    struct Entry: Equatable {
        let tag: String?
        /// true si `tag` es el Release más nuevo de GitHub; false si es
        /// el que trae embebido esta build de Aura Studio.
        let fromGitHub: Bool
    }

    /// Lista, no diccionario: `FirmwareFamily` no es `Hashable` (lleva
    /// un caso con valor asociado) y su única enumeración legítima es
    /// `FirmwareFamily.installable`. Son tres elementos.
    @Published private(set) var entries: [(family: FirmwareFamily, entry: Entry)] = []
    @Published private(set) var isRefreshing = false

    private var hasLoaded = false

    func entry(for family: FirmwareFamily) -> Entry {
        entries.first { $0.family == family }?.entry
            ?? Entry(tag: BundledArtifacts.forFamily(family).releaseTag, fromGitHub: false)
    }

    private func record(_ family: FirmwareFamily, _ entry: Entry) {
        if let index = entries.firstIndex(where: { $0.family == family }) {
            entries[index] = (family, entry)
        } else {
            entries.append((family, entry))
        }
    }

    /// Carga una vez por aparición de la pantalla. `force` (el botón de
    /// recargar) salta el caché de 24 h de `ReleaseCache` — misma razón
    /// que `forceRefresh` en `AuraUpdateChecker.checkForUpdate` (D-300):
    /// una revisión manual del usuario debe ser una consulta en vivo.
    func load(force: Bool = false, session: URLSession = .shared) async {
        guard force || !hasLoaded else { return }
        hasLoaded = true
        isRefreshing = true
        defer { isRefreshing = false }

        for family in FirmwareFamily.installable {
            let bundled = BundledArtifacts.forFamily(family).releaseTag
            var releases = force ? nil : ReleaseCache.load(defaults: .standard, family: family)
            if releases == nil {
                releases = try? await GitHubReleaseChecker.fetchReleases(session: session, family: family)
                // ST-074: `[]` con fallo de token no se cachea -- arreglar
                // el token en Ajustes debe surtir efecto de inmediato.
                if let releases, !(releases.isEmpty && GitHubReleaseChecker.lastAuthFailure) {
                    ReleaseCache.store(releases, defaults: .standard, family: family)
                }
            }
            if let releases,
               let latest = GitHubReleaseChecker.pickLatest(from: releases, includePrereleases: true) {
                record(family, Entry(tag: latest.tagName, fromGitHub: true))
            } else {
                record(family, Entry(tag: bundled, fromGitHub: false))
            }
        }
    }
}
