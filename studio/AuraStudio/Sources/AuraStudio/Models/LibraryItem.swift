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

/// ST-221 (PLAN-studio-ajustes-3.md §2): cómo guarda la biblioteca este
/// archivo. **Es la única fuente de verdad del modo** -- hasta acá se
/// deducía mirando la forma de la ruta, cada vez y en cada sitio.
///
/// La asimetría entre los dos valores es lo que importa: `copy` autoriza
/// a **escribir etiquetas dentro del archivo**, `reference` no autoriza
/// nada. Por eso un valor desconocido en el catálogo (una versión más
/// nueva, un error de escritura) se lee como `reference`: ante la duda,
/// el modo que no toca nada del usuario.
enum LibraryStorageMode: String, Equatable, Sendable {
    /// El archivo vive dentro de la biblioteca y Aura lo controla: le
    /// escribe las etiquetas y lo sincroniza directo.
    case copy
    /// El archivo es del usuario y está donde él lo dejó. **Nunca se
    /// toca.** Lo que viaja al iPod es un derivado en `.preparados/`.
    case reference

    /// Lo que se lee del catálogo. `nil` = el campo no venía (catálogo
    /// anterior a 0.4.0): hay que inferirlo. Un valor desconocido NO es
    /// `nil` -- es `reference`, y no se vuelve a inferir.
    static func fromPersisted(_ raw: String?) -> LibraryStorageMode? {
        guard let raw else { return nil }
        return LibraryStorageMode(rawValue: raw) ?? .reference
    }

    /// ST-221: cómo se deduce el modo de un catálogo que no lo trae.
    /// Se hace **una sola vez**, al cargar, y el resultado se persiste.
    ///
    /// La regla no es "está dentro de la carpeta de biblioteca" sino
    /// "está dentro de una de las tres carpetas que la app CREA".
    /// La diferencia importa y es la que evita un daño real: alguien que
    /// haya apuntado la biblioteca a su propia carpeta de música y use
    /// modo referencia -- un caso razonable, que hoy funciona -- vería
    /// todos sus originales marcados como copias, y a partir de ahí la
    /// app se creería con permiso de escribirles etiquetas adentro.
    ///
    /// Y el segundo candado, que es el que de verdad protege: **inferir
    /// no autoriza a escribir nada**. Lo único que escribe etiquetas en
    /// copias ya existentes es la migración explícita de §0.3, con su
    /// botón. Si esta inferencia se equivocara, el peor efecto es una
    /// etiqueta de modo mal puesta -- visible y corregible -- y no un
    /// archivo del usuario modificado a sus espaldas.
    /// Las tres comparaciones van en NFC (ver
    /// `SharedCatalogPath.catalogNormalized`): macOS entrega los acentos
    /// descompuestos y `PersistedLibrary.musicDirName` es un literal
    /// compuesto, así que sin normalizar `Música/` **nunca** empareja y
    /// toda biblioteca copiada se leería como referenciada.
    static func infer(sourceURL: URL, libraryRoot: URL) -> LibraryStorageMode {
        let root = SharedCatalogPath.catalogNormalized(libraryRoot.standardizedFileURL.path)
        let path = SharedCatalogPath.catalogNormalized(sourceURL.standardizedFileURL.path)
        for managed in [PersistedLibrary.musicDirName,
                        PersistedLibrary.imagesDirName,
                        PersistedLibrary.videosDirName] {
            let prefix = SharedCatalogPath.catalogNormalized(root + "/" + managed + "/")
            if path.hasPrefix(prefix) { return .copy }
        }
        return .reference
    }
}

/// Un archivo que el usuario solto en Aura Studio, en algun punto de su
/// camino hacia el iPod: musica nativa que solo necesita metadata,
/// video que hay que transcodificar, o una foto que hay que
/// redimensionar. `sourceURL` es el archivo original del usuario;
/// `preparedURL` es **el archivo que viaja al iPod** (ST-221): con
/// `storage == .copy` en música es el archivo de la biblioteca mismo
/// (`preparedURL == sourceURL`); en video, foto y modo referencia es el
/// derivado de `.preparados/<ID>`.
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
    /// PLAN-studio-rendimiento-2.md Fase 6 (ST-186), punto 1.4 heredado
    /// de la ronda 1: tamaño del archivo de origen, en bytes.
    ///
    /// `nil` significa **hay que medirlo** (ítem recién agregado, o
    /// catálogo guardado antes de que el campo existiera), nunca "vacío".
    /// Se rellena en segundo plano por lotes y se guarda una vez.
    ///
    /// Existe porque medirlo en el momento sale caro donde más duele:
    /// `MediaTableRow.fileSizeBytes` hacía un `stat` **por fila y por
    /// acceso**, y esa propiedad es además la clave de orden de la
    /// columna "Tamaño" -- ordenar 12 000 canciones por tamaño eran
    /// decenas de miles de `stat`, y con la biblioteca en un disco de
    /// red (el caso del dueño en Windows) cada uno cuesta un viaje.
    ///
    /// Mismo nombre y misma semántica que en Windows (ST-201), fijados
    /// por la sesión maestra para las dos plataformas.
    var fileSizeBytes: Int?
    /// ST-221: copiado a la biblioteca o referenciado en su lugar. Ver
    /// `LibraryStorageMode`.
    var storage: LibraryStorageMode
    /// ST-221 (paridad con Windows): ¿existe el archivo de origen ahora
    /// mismo?
    ///
    /// **No se persiste**: se recalcula al cargar y al refrescar. Un
    /// original referenciado en un disco desconectado es un elemento
    /// *no disponible*, **no un elemento que haya que borrar** -- hasta
    /// acá `loadCatalog` lo omitía en silencio y el siguiente guardado
    /// lo perdía para siempre, que es exactamente lo que le pasaría al
    /// dueño por desconectar un disco externo con la app abierta.
    var isAvailable: Bool

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
        self.fileSizeBytes = nil
        // Lo que se acaba de soltar todavía no se copió a ningún lado:
        // el modo real lo fija `process(itemAt:)` según el ajuste.
        self.storage = .reference
        self.isAvailable = true
    }

    /// Restauracion desde el catalogo persistido de la biblioteca
    /// (`biblioteca.json`, D-180) -- conserva el id original para que
    /// las playlists (que referencian por id) sigan validas entre
    /// sesiones.
    init(id: UUID, sourceURL: URL, kind: LibraryItemKind,
         status: LibraryItemStatus, metadata: TrackMetadata?, preparedURL: URL?,
         category: String? = nil, seriesName: String? = nil, season: Int? = nil,
         episode: Int? = nil, photoAlbum: String? = nil, metadataEditedByUser: Bool = false,
         addedAt: Date? = nil, fileSizeBytes: Int? = nil,
         storage: LibraryStorageMode = .reference, isAvailable: Bool = true) {
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
        self.fileSizeBytes = fileSizeBytes
        self.storage = storage
        self.isAvailable = isAvailable
    }
}
