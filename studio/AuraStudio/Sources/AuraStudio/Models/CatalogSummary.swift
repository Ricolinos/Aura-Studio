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

/// Lee de vuelta el mismo archivo que escribe `CatalogSummaryWriter`.
/// Studio lo usa para contar lo que YA hay en el iPod sin recorrer el
/// disco entero: el resumen lo dejo el ultimo sync, y el firmware lo lee
/// igual para su pantalla "Acerca de".
enum CatalogSummaryReader {
    static func parse(_ text: String) -> CatalogSummary {
        var values: [String: Int64] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let raw = parts[1].trimmingCharacters(in: .whitespaces)
            guard let value = Int64(raw) else { continue }
            values[key] = value
        }

        var summary = CatalogSummary()
        summary.music = CatalogTypeSummary(count: Int(values["music_count"] ?? 0),
                                            bytes: values["music_bytes"] ?? 0)
        summary.video = CatalogTypeSummary(count: Int(values["video_count"] ?? 0),
                                            bytes: values["video_bytes"] ?? 0)
        summary.photo = CatalogTypeSummary(count: Int(values["photo_count"] ?? 0),
                                            bytes: values["photo_bytes"] ?? 0)
        summary.playlistCount = Int(values["playlist_count"] ?? 0)
        return summary
    }
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
