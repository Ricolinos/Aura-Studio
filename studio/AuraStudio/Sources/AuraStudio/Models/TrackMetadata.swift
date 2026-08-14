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
    var trackNumber: Int?
    var coverArtData: Data?
    var syncedLyrics: String?
    var musicBrainzRecordingID: String?
    var musicBrainzReleaseID: String?
    /// Duracion real del archivo (D-198, columna "Duración" de la tabla
    /// de biblioteca) -- medida best-effort con ffmpeg al procesar
    /// (`FFmpegTranscoder.probeDurationSeconds`), nunca bloquea el
    /// pipeline si ffmpeg no esta instalado (queda nil, la tabla
    /// muestra "--").
    var durationSeconds: Double?

    init(title: String? = nil, artist: String? = nil, album: String? = nil,
         albumArtist: String? = nil, year: String? = nil, genre: String? = nil,
         trackNumber: Int? = nil, coverArtData: Data? = nil, syncedLyrics: String? = nil,
         musicBrainzRecordingID: String? = nil, musicBrainzReleaseID: String? = nil,
         durationSeconds: Double? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.year = year
        self.genre = genre
        self.trackNumber = trackNumber
        self.coverArtData = coverArtData
        self.syncedLyrics = syncedLyrics
        self.musicBrainzRecordingID = musicBrainzRecordingID
        self.musicBrainzReleaseID = musicBrainzReleaseID
        self.durationSeconds = durationSeconds
    }

    var isComplete: Bool {
        title != nil && artist != nil && album != nil
    }
}
