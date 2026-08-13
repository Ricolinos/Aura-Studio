import Foundation

/// Catalogo persistido de la biblioteca Aura (`biblioteca.json` en la
/// raiz de la carpeta de biblioteca, D-180). Todas las rutas son
/// RELATIVAS a esa carpeta: mover la carpeta entera a otro disco y
/// apuntar la preferencia ahi conserva la biblioteca intacta.
///
/// La portada NO se serializa dentro del JSON (una imagen por pista
/// inflaria el catalogo a decenas de MB y cada guardado seria una
/// reescritura completa): vive como archivo en `Portadas/<id>.jpg` y
/// aca solo viaja su ruta.
struct PersistedLibrary: Codable {
    var items: [PersistedLibraryItem] = []
    var playlists: [PersistedPlaylist] = []

    static let catalogFileName = "biblioteca.json"
    static let originalsDirName = "Originales"
    static let preparedDirName = "Preparados"
    static let coversDirName = "Portadas"
}

struct PersistedLibraryItem: Codable {
    var id: UUID
    /// Relativa a la carpeta de biblioteca (la copia en `Originales/`).
    var sourceRelativePath: String
    var kind: String
    /// Solo estados estables: `ready` / `needsReview` / `queued`. Los
    /// transitorios (enriqueciendo, transcodificando) y los fallidos se
    /// guardan como `queued` -- al reabrir la app se reintentan, en vez
    /// de quedar congelados en un estado que ya no corre.
    var status: String
    var metadata: PersistedTrackMetadata?
    var preparedRelativePath: String?
    var coverRelativePath: String?
}

struct PersistedTrackMetadata: Codable {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var year: String?
    var genre: String?
    var trackNumber: Int?
    var syncedLyrics: String?
    var musicBrainzRecordingID: String?
    var musicBrainzReleaseID: String?
}

struct PersistedPlaylist: Codable {
    var id: UUID
    var name: String
    var trackItemIDs: [UUID]
}

/// Mapeo entre el modelo vivo y el persistido, como funciones puras
/// para poder probarlas sin tocar disco.
enum LibraryPersistenceMapper {
    static func persistedStatus(_ status: LibraryItemStatus) -> String {
        switch status {
        case .ready: return "ready"
        case .needsReview: return "needsReview"
        case .queued, .enriching, .transcoding, .failed: return "queued"
        }
    }

    static func liveStatus(_ raw: String) -> LibraryItemStatus {
        switch raw {
        case "ready": return .ready
        case "needsReview": return .needsReview
        default: return .queued
        }
    }

    static func persistedKind(_ kind: LibraryItemKind) -> String {
        switch kind {
        case .music: return "music"
        case .video: return "video"
        case .photo: return "photo"
        case .unsupported: return "unsupported"
        }
    }

    static func liveKind(_ raw: String) -> LibraryItemKind {
        switch raw {
        case "music": return .music
        case "video": return .video
        case "photo": return .photo
        default: return .unsupported
        }
    }

    static func persistedMetadata(_ metadata: TrackMetadata?) -> PersistedTrackMetadata? {
        guard let m = metadata else { return nil }
        return PersistedTrackMetadata(
            title: m.title, artist: m.artist, album: m.album,
            albumArtist: m.albumArtist, year: m.year, genre: m.genre,
            trackNumber: m.trackNumber, syncedLyrics: m.syncedLyrics,
            musicBrainzRecordingID: m.musicBrainzRecordingID,
            musicBrainzReleaseID: m.musicBrainzReleaseID)
    }

    static func liveMetadata(_ persisted: PersistedTrackMetadata?, coverArtData: Data?) -> TrackMetadata? {
        guard let p = persisted else { return nil }
        return TrackMetadata(
            title: p.title, artist: p.artist, album: p.album,
            albumArtist: p.albumArtist, year: p.year, genre: p.genre,
            trackNumber: p.trackNumber, coverArtData: coverArtData,
            syncedLyrics: p.syncedLyrics,
            musicBrainzRecordingID: p.musicBrainzRecordingID,
            musicBrainzReleaseID: p.musicBrainzReleaseID)
    }
}
