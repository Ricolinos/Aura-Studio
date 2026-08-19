import Foundation

enum LibraryItemKind: Equatable {
    case music
    case video
    case photo
    case unsupported

    static func classify(url: URL) -> LibraryItemKind {
        switch url.pathExtension.lowercased() {
        case "flac", "mp3", "m4a", "wav", "aiff", "aif":
            return .music
        case "mp4", "mov", "m4v", "avi", "mkv", "mpg", "mpeg":
            return .video
        case "jpg", "jpeg", "png", "gif", "bmp", "heic", "tiff":
            return .photo
        default:
            return .unsupported
        }
    }
}

enum LibraryItemStatus: Equatable {
    case queued
    case enriching
    case transcoding(progress: Double)
    case ready
    case needsReview
    case failed(String)
}

/// Un archivo que el usuario solto en Aura Studio, en algun punto de su
/// camino hacia el iPod: musica nativa que solo necesita metadata,
/// video que hay que transcodificar, o una foto que hay que
/// redimensionar. `sourceURL` es el archivo original del usuario;
/// `preparedURL` es el resultado final listo para copiar al dispositivo
/// (el mismo archivo para musica nativa, o la salida de ffmpeg/resize).
struct LibraryItem: Identifiable, Equatable {
    let id: UUID
    /// D-228: ya no es `let`. Con "copiar medios a la biblioteca"
    /// activo, el archivo se copia recien en
    /// `LibraryViewModel.process(itemAt:)` -- cuando ya se conoce
    /// artista/album/categoria, no al soltarlo (`addDroppedFiles`) --
    /// y esta propiedad se actualiza para apuntar a esa copia.
    var sourceURL: URL
    let kind: LibraryItemKind
    var status: LibraryItemStatus
    var metadata: TrackMetadata?
    var preparedURL: URL?
    /// Solo para `.photo`/`.video`: categoria/coleccion dentro de la
    /// biblioteca de Aura Studio. Para video es uno de los 3 nombres
    /// fijos de `MediaCategory` (Videos/Series/Películas, guardado como
    /// su `displayName`); para foto es un nombre libre de
    /// `AppPreferences.photoCollections` (D-228: antes ambos tipos
    /// compartian el enum `MediaCategory`, ahora solo video lo sigue
    /// usando puertas adentro). Se sugiere sola al procesar el item y
    /// el usuario la puede corregir a mano.
    var category: String?
    /// PLAN-biblioteca-medios-v2.md §3.4: solo para `.video` en la
    /// categoría Series -- nombre de la serie, temporada y episodio,
    /// poblados al importar con `VideoTitleParser` o editables a mano
    /// desde el inspector. Determinan el nombre de destino en el iPod
    /// (` SxxEyy`, que `parse_sxxeyy()` del firmware agrupa) y el
    /// póster de temporada. `nil` para todo lo que no sea un episodio
    /// (película suelta, videoclip, música, foto).
    var seriesName: String?
    var season: Int?
    var episode: Int?
    /// PLAN-biblioteca-medios-v2.md §3.3: solo para `.photo` -- álbum
    /// LOCAL dentro de Aura Studio (nunca viaja al iPod, `/Photos`
    /// sigue plano, D-192). `nil` = sin álbum.
    var photoAlbum: String?
    /// Se pone en `true` la primera vez que el usuario corrige metadata
    /// a mano (revision, renombrar, edicion en lote, quitar caratula) --
    /// nunca por `LibraryEnricher`/`LocalTagReader`, que solo llenan
    /// huecos. Protege esas correcciones de la relectura masiva que
    /// ofrece el banner de "Aura Studio ahora lee mejor las etiquetas"
    /// (ver `LibraryViewModel.rereadLocalTags`, PLAN-studio-ux.md §2/P2)
    /// -- la accion explicita del menu contextual, en cambio, siempre
    /// pisa, sea cual sea este valor.
    var metadataEditedByUser: Bool
    /// Cuando se agrego a la biblioteca (ST-030). nil solo para items
    /// restaurados de un catalogo anterior a este campo.
    var addedAt: Date?

    init(sourceURL: URL, addedAt: Date? = Date()) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.kind = LibraryItemKind.classify(url: sourceURL)
        self.status = .queued
        self.metadata = nil
        self.preparedURL = nil
        self.category = nil
        self.seriesName = nil
        self.season = nil
        self.episode = nil
        self.photoAlbum = nil
        self.metadataEditedByUser = false
        self.addedAt = addedAt
    }

    /// Restauracion desde el catalogo persistido de la biblioteca
    /// (`biblioteca.json`, D-180) -- conserva el id original para que
    /// las playlists (que referencian por id) sigan validas entre
    /// sesiones.
    init(id: UUID, sourceURL: URL, kind: LibraryItemKind,
         status: LibraryItemStatus, metadata: TrackMetadata?, preparedURL: URL?,
         category: String? = nil, seriesName: String? = nil, season: Int? = nil,
         episode: Int? = nil, photoAlbum: String? = nil, metadataEditedByUser: Bool = false,
         addedAt: Date? = nil) {
        self.id = id
        self.sourceURL = sourceURL
        self.kind = kind
        self.status = status
        self.metadata = metadata
        self.preparedURL = preparedURL
        self.category = category
        self.seriesName = seriesName
        self.season = season
        self.episode = episode
        self.photoAlbum = photoAlbum
        self.metadataEditedByUser = metadataEditedByUser
        self.addedAt = addedAt
    }
}
