import Foundation

/// Importa una playlist M3U/M3U8 de otro programa o servicio (encargo
/// del dueño, 2026-08-13: "si tiene playlist en otros servicios o
/// archivos, tambien las podria sincronizar, o copiar"). El formato es
/// el mismo que ya escribe `PlaylistExporter` al sincronizar con el
/// iPod, asi que leerlo es el camino simetrico: cualquier programa que
/// exporte M3U/M3U8 (iTunes, Music.app, VLC, Winamp, la mayoria de
/// servicios de streaming con exportador local) sirve como fuente.
///
/// Logica de parseo PURA (sin tocar disco ni el catalogo) para poder
/// testearla sin fixtures reales -- resolver cada linea a un
/// `LibraryItem` existente es responsabilidad de quien llama
/// (`PlaylistsView`), que es quien tiene el catalogo cargado.
enum PlaylistImporter {
    /// Devuelve las rutas de archivo referenciadas, en el orden del
    /// M3U/M3U8 -- ignora lineas de comentario (`#EXTM3U`, `#EXTINF...`)
    /// y lineas vacias. Las rutas relativas (frecuentes en playlists
    /// exportadas por otros programas) se resuelven contra la carpeta
    /// donde vive el propio archivo .m3u/.m3u8, igual que hace
    /// cualquier reproductor al abrir uno.
    static func parseTrackPaths(contents: String, playlistDirectory: URL) -> [String] {
        contents
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { line -> String in
                if line.hasPrefix("/") { return line }
                if let url = URL(string: line), url.scheme == "file" { return url.path }
                return playlistDirectory.appendingPathComponent(line).standardizedFileURL.path
            }
    }

    /// Nombre sugerido para la playlist importada: el nombre del
    /// archivo sin extension.
    static func suggestedName(for fileURL: URL) -> String {
        fileURL.deletingPathExtension().lastPathComponent
    }
}
