import Foundation

/// Fase 24 (PLAN-UX.md): contadores y bytes por tipo tras un sync, para
/// que "Acerca de" en el firmware pueda mostrar cuanto hay realmente en
/// el dispositivo. El firmware no tiene parser de JSON (su unico formato
/// de config es el `key: value` plano que ya usa `aura.cfg`, ver
/// `aura_settings_load`/`settings_parseline`) -- en vez de escribir un
/// parser JSON en C para un solo archivo, `CatalogSummaryWriter` emite
/// ese mismo formato plano. `sync_manifest.json` (SyncManifest, en este
/// mismo directorio) sigue siendo JSON porque es enteramente interno de
/// Studio -- el firmware nunca lo lee.
struct CatalogTypeSummary: Equatable {
    var count: Int = 0
    var bytes: Int64 = 0
}

struct CatalogSummary: Equatable {
    var music = CatalogTypeSummary()
    var video = CatalogTypeSummary()
    var photo = CatalogTypeSummary()
    var playlistCount = 0
}

enum CatalogSummaryWriter {
    static func serialize(_ summary: CatalogSummary) -> String {
        """
        music_count: \(summary.music.count)
        music_bytes: \(summary.music.bytes)
        video_count: \(summary.video.count)
        video_bytes: \(summary.video.bytes)
        photo_count: \(summary.photo.count)
        photo_bytes: \(summary.photo.bytes)
        playlist_count: \(summary.playlistCount)

        """
    }
}
