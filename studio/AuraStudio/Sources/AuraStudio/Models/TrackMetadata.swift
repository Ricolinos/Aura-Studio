import Foundation

/// Metadata enriquecida de una pista, ya sea leida del archivo original
/// o completada via MusicBrainz/Cover Art Archive/LRCLIB (o Genius/
/// Musixmatch si el usuario cargo su propia API key, ver
/// APIKeySettings). `source` indica de donde vino cada pieza para que
/// la vista de revision pueda mostrar "esto lo completamos nosotros"
/// vs "esto ya lo tenia el archivo".
struct TrackMetadata: Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var year: String?
    var genre: String?
    /// Autor/compositor (TCOM en ID3, `tag_composer` en el tagcache de
    /// Rockbox) -- el firmware ya sabe organizar musica por "Autores"
    /// (AURA_SCREEN_MUSIC_COMPOSERS), este campo es lo que faltaba en
    /// Aura Studio para poblarlo.
    var composer: String?
    var trackNumber: Int?
    var coverArtData: Data?
    /// Letra en formato LRC. Normalmente con marcas `[mm:ss.xx]` (LRCLIB
    /// `syncedLyrics`); puede ser letra plana si solo habia esa (ST-012)
    /// -- el nombre se conserva por compatibilidad con `biblioteca.json`.
    var syncedLyrics: String?
    var musicBrainzRecordingID: String?
    var musicBrainzReleaseID: String?
    /// Duracion real del archivo (D-198, columna "Duración" de la tabla
    /// de biblioteca) -- medida best-effort con ffmpeg al procesar
    /// (`FFmpegTranscoder.probeDurationSeconds`), nunca bloquea el
    /// pipeline si ffmpeg no esta instalado (queda nil, la tabla
    /// muestra "--").
    var durationSeconds: Double?
    /// Calificacion 0-5 estrellas (D-199, encargo del dueno: "se
    /// sincronizaria con el iPod... en el reproductor tenemos
    /// oportunidad de elegir cuantas estrellas le damos a la cancion").
    /// nil = sin calificar (distinto de 0, que seria "0 estrellas"
    /// puesto a proposito).
    var rating: Int?
    /// Favorito (ST-019): marca binaria independiente de `rating`, la
    /// misma idea que el corazon/estrella de Music.app -- alimenta el
    /// filtro "Solo favoritos" y la columna/orden "Favorito". Vive solo
    /// en el catalogo de Studio (no hay frame ID3 estandar para esto).
    var isFavorite: Bool
    /// Numero de disco (TPOS / `disk` en MP4), para ordenar cajas de
    /// varios discos antes que por numero de pista.
    var discNumber: Int?

    init(title: String? = nil, artist: String? = nil, album: String? = nil,
         albumArtist: String? = nil, year: String? = nil, genre: String? = nil,
         composer: String? = nil,
         trackNumber: Int? = nil, coverArtData: Data? = nil, syncedLyrics: String? = nil,
         musicBrainzRecordingID: String? = nil, musicBrainzReleaseID: String? = nil,
         durationSeconds: Double? = nil, rating: Int? = nil,
         isFavorite: Bool = false, discNumber: Int? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.year = year
        self.genre = genre
        self.composer = composer
        self.trackNumber = trackNumber
        self.coverArtData = coverArtData
        self.syncedLyrics = syncedLyrics
        self.musicBrainzRecordingID = musicBrainzRecordingID
        self.musicBrainzReleaseID = musicBrainzReleaseID
        self.durationSeconds = durationSeconds
        self.rating = rating
        self.isFavorite = isFavorite
        self.discNumber = discNumber
    }

    var isComplete: Bool {
        title != nil && artist != nil && album != nil
    }
}
