import Foundation

/// Catalogo persistido de la biblioteca Aura (`biblioteca.json` en la
/// raiz de la carpeta de biblioteca, D-180). Todas las rutas son
/// RELATIVAS a esa carpeta: mover la carpeta entera a otro disco y
/// apuntar la preferencia ahi conserva la biblioteca intacta.
///
/// La portada NO se serializa dentro del JSON (una imagen por pista
/// inflaria el catalogo a decenas de MB y cada guardado seria una
/// reescritura completa): vive como archivo en `.portadas/<id>.jpg` y
/// aca solo viaja su ruta.
struct PersistedLibrary: Codable {
    var items: [PersistedLibraryItem] = []
    var playlists: [PersistedPlaylist] = []

    static let catalogFileName = "biblioteca.json"
    /// D-228: ya no hay una unica carpeta "Originales" plana -- el
    /// destino real de cada item depende de su tipo/artista/album/
    /// categoria (ver LibrarySync.localLibraryRelativePath). Estas tres
    /// raices son lo que el usuario ve en Finder; `preparados`/
    /// `portadas` quedan con punto adelante para que Finder las oculte
    /// por default (son tecnicas, no de cara al usuario).
    static let musicDirName = "Música"
    static let imagesDirName = "Imágenes"
    static let videosDirName = "Videos"
    static let preparedDirName = ".preparados"
    static let coversDirName = ".portadas"

    /// Nombres del esquema VIEJO (D-180), usados solo por la migracion
    /// de bibliotecas existentes -- ver
    /// LibraryViewModel.migrateLegacyLibraryLayoutIfNeeded().
    static let legacyOriginalsDirName = "Originales"
    static let legacyPreparedDirName = "Preparados"
    static let legacyCoversDirName = "Portadas"
}

struct PersistedLibraryItem: Codable {
    var id: UUID
    /// Relativa a la carpeta de biblioteca (D-228: `Música/<Artista>/
    /// <Álbum>/`, `Imágenes/<Colección>/` o `Videos/<Categoría>/` segun
    /// el tipo -- ver LibrarySync.localLibraryRelativePath).
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
    var category: String?
    /// Opcional (no `Bool` a secas): catalogos guardados antes de este
    /// campo no lo tienen, y un `Bool` no-opcional en un `Codable`
    /// sintetizado exige la clave -- ausente, `try? decode(...)` en
    /// `loadCatalog()` tiraria el catalogo ENTERO, no solo este campo.
    /// Mismo criterio que `imageRelativePath` de `PersistedPlaylist`.
    var metadataEditedByUser: Bool?
    /// Fecha en que se agrego a la biblioteca (ST-019, columna/orden
    /// "Fecha en que se agregó"). Opcional por la misma razon que
    /// `metadataEditedByUser`: catalogos anteriores no la tienen.
    var addedAt: Date?
}

struct PersistedTrackMetadata: Codable {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var year: String?
    var genre: String?
    var composer: String?
    var trackNumber: Int?
    var syncedLyrics: String?
    var musicBrainzRecordingID: String?
    var musicBrainzReleaseID: String?
    var durationSeconds: Double?
    var rating: Int?
    /// Opcionales (ST-019): catalogos viejos no los traen.
    var isFavorite: Bool?
    var discNumber: Int?
}

struct PersistedPlaylist: Codable {
    var id: UUID
    var name: String
    var trackItemIDs: [UUID]
    /// Ver `Playlist.imageRelativePath` -- archivo en `.portadas/`, no
    /// Data embebida. Opcional en la decodificacion (catalogos viejos,
    /// anteriores a este campo, no lo tienen) via el default `nil`.
    var imageRelativePath: String?
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
            composer: m.composer,
            trackNumber: m.trackNumber, syncedLyrics: m.syncedLyrics,
            musicBrainzRecordingID: m.musicBrainzRecordingID,
            musicBrainzReleaseID: m.musicBrainzReleaseID,
            durationSeconds: m.durationSeconds, rating: m.rating,
            isFavorite: m.isFavorite ? true : nil, discNumber: m.discNumber)
    }

    static func liveMetadata(_ persisted: PersistedTrackMetadata?, coverArtData: Data?) -> TrackMetadata? {
        guard let p = persisted else { return nil }
        return TrackMetadata(
            title: p.title, artist: p.artist, album: p.album,
            albumArtist: p.albumArtist, year: p.year, genre: p.genre,
            composer: p.composer,
            trackNumber: p.trackNumber, coverArtData: coverArtData,
            syncedLyrics: p.syncedLyrics,
            musicBrainzRecordingID: p.musicBrainzRecordingID,
            musicBrainzReleaseID: p.musicBrainzReleaseID,
            durationSeconds: p.durationSeconds, rating: p.rating,
            isFavorite: p.isFavorite ?? false, discNumber: p.discNumber)
    }

    /// D-228: catalogos guardados ANTES de este cambio persistian
    /// `MediaCategory.rawValue` (p.ej. "images", "homeVideos") -- ahora
    /// `category` es un string de display libre (colecciones de foto
    /// editables, o el nombre fijo de una categoria de video). Traduce
    /// los valores viejos conocidos a su nombre nuevo; cualquier otro
    /// valor (un string de display ya nuevo, o una coleccion de foto
    /// personalizada que el usuario ya haya creado) pasa tal cual.
    static let legacyCategoryDisplayNames: [String: String] = [
        "images": "Imágenes",
        "photos": "Fotos",
        "aiGenerated": "IA",
        "homeVideos": "Series",
        "videos": "Videos",
        "movies": "Películas",
    ]

    static func liveCategory(_ raw: String) -> String {
        legacyCategoryDisplayNames[raw] ?? raw
    }
}
