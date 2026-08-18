import Foundation

/// Resuelve la foto de un artista a partir de su nombre (ST-021):
/// 1. fanart.tv (`artistthumb`, curada, cuadrada) -- necesita el
///    MusicBrainz artist ID, que se busca en MusicBrainz por nombre con
///    umbral de score (nunca por "el primero que salga"); solo si el
///    usuario configuro su API key de fanart.tv (`APIKeyStore`).
/// 2. Deezer (`picture_xl`, sin key) como respaldo si esta habilitado
///    en Ajustes -- exige coincidencia exacta de nombre normalizado.
/// Mejor esfuerzo: cada fuente se intenta con `try?`; sin resultado se
/// devuelve nil y la vista sigue con la portada de un álbum.
struct ArtistImageResolver {
    var musicBrainz: MusicBrainzClient = MusicBrainzClient()
    var fanart: FanartTVClient = FanartTVClient()
    var deezer: DeezerClient = DeezerClient()
    /// Inyectable para tests (el Keychain real no se toca en la suite).
    var hasFanartKey: () -> Bool = { APIKeyStore.hasKey(for: .fanartTV) }
    var deezerEnabled: Bool = true

    enum Source: Equatable { case fanartTV, deezer }

    struct Result: Equatable {
        let data: Data
        let source: Source
    }

    func resolve(artistName: String) async -> Result? {
        let name = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != LibraryGrouping.unknownArtistName else { return nil }

        if hasFanartKey(),
           let artist = try? await musicBrainz.searchArtist(name: name),
           let data = try? await fanart.fetchArtistThumb(musicBrainzArtistID: artist.id),
           !data.isEmpty {
            return Result(data: data, source: .fanartTV)
        }
        if deezerEnabled,
           let data = try? await deezer.fetchArtistPicture(name: name),
           !data.isEmpty {
            return Result(data: data, source: .deezer)
        }
        return nil
    }
}
