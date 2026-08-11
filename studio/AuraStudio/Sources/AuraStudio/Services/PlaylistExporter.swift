import Foundation

/// Fase 24 (PLAN-UX.md): genera el contenido de un `.m3u8` que el
/// firmware ya sabe leer -- `aura_music_list_playlists`/
/// `aura_music_play_playlist` (`apps/aura/aura_music.c`) escanean
/// `/Playlists` buscando `.m3u`/`.m3u8` y se los pasan tal cual a
/// `playlist_create()` (Rockbox), que acepta rutas UNIX absolutas sin
/// modificarlas (`apps/playlist.c:540-545`, regla 1) -- por eso las
/// entradas son `/Music/...` y no rutas relativas al archivo de
/// playlist, evitando cualquier ambiguedad de resolucion.
enum PlaylistExporter {
    static func fileName(for playlistName: String) -> String {
        PathSanitizer.sanitize(playlistName) + ".m3u8"
    }

    /// `trackDestinationPaths` son las mismas `destinationRelativePath`
    /// que `LibrarySync` usa para copiar cada pista (sin el "/" inicial);
    /// esta funcion es la unica responsable de agregarselo.
    static func m3u8Contents(trackDestinationPaths: [String]) -> String {
        var lines = ["#EXTM3U"]
        lines.append(contentsOf: trackDestinationPaths.map { "/" + $0 })
        return lines.joined(separator: "\n") + "\n"
    }
}
