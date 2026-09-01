import Foundation

/// Un álbum tal como lo ve la vista "Álbumes" (PLAN-studio-ux.md §2.3,
/// ST-031): un grupo de canciones de la biblioteca, no un directorio.
/// Nada de esto crea carpetas -- la organización en disco la sigue
/// decidiendo `AppPreferences.musicOrganization`.
struct AlbumGroup: Identifiable, Equatable {
    /// Clave estable (album + artista de album, normalizados) -- sirve
    /// para seleccionar el mismo grupo tras un cambio de metadata que
    /// no toque esos dos campos.
    let id: String
    let title: String
    let artist: String
    let items: [LibraryItem]
    /// Portada del grupo: la primera canción que tenga carátula.
    let coverArtData: Data?
    let year: String?
    let genre: String?
    /// `true` para el grupo especial "Sin álbum".
    let isUnknown: Bool

    var trackCount: Int { items.count }
    var isFavorite: Bool { items.contains { $0.metadata?.isFavorite == true } }
    var totalDurationSeconds: Double { items.reduce(0) { $0 + ($1.metadata?.durationSeconds ?? 0) } }
}

/// Un artista para la vista "Artistas": sus álbumes (agrupados por
/// `albumArtist ?? artist`, P4 del plan) y el total de canciones.
struct ArtistGroup: Identifiable, Equatable {
    let id: String
    let name: String
    let albums: [AlbumGroup]
    let isUnknown: Bool

    var trackCount: Int { albums.reduce(0) { $0 + $1.trackCount } }
    var items: [LibraryItem] { albums.flatMap(\.items) }
    /// Imagen representativa cuando no hay foto de artista: la portada
    /// del primer álbum con carátula.
    var fallbackCoverArtData: Data? { albums.compactMap(\.coverArtData).first }
}

enum LibraryGrouping {
    static let unknownAlbumTitle = "Sin álbum"
    static let unknownArtistName = "Artista desconocido"

    /// Normalización para agrupar: sin espacios sobrantes, sin
    /// distinguir mayúsculas ni acentos ("Álbum" == "album ").
    static func normalize(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Artista con el que se agrupa un álbum: `albumArtist ?? artist`,
    /// y desde R2-4 (ST-116) recortado a su **artista principal** --
    /// "Gorillaz feat. De La Soul" agrupa bajo "Gorillaz". Ver
    /// `ArtistNameNormalizer` y `docs/normalizacion-artistas.md`.
    ///
    /// **Solo agrupa.** El `artist` de la pista no se toca, y las rutas
    /// en disco tampoco: tanto la carpeta local
    /// (`LibrarySync.localLibraryRelativePath`) como la del iPod arman
    /// su nombre con el valor CRUDO (`albumArtist ?? artist`), no con
    /// esto. Es deliberado -- mover carpetas en el iPod es una
    /// operación destructiva sobre archivos ya sincronizados, y R2-4
    /// pidió agrupación, no reorganización. La consecuencia (una
    /// carpeta "Gorillaz feat. De La Soul" en el iPod para un álbum que
    /// Studio muestra bajo "Gorillaz") está anotada en
    /// `docs/normalizacion-artistas.md` § Alcance.
    static func albumArtist(of item: LibraryItem,
                            options: ArtistGroupingOptions = .default) -> String? {
        let candidate = item.metadata?.albumArtist ?? item.metadata?.artist
        let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return ArtistNameNormalizer.principalArtist(trimmed, options: options)
    }

    static func albumKey(of item: LibraryItem,
                         options: ArtistGroupingOptions = .default) -> String {
        "\(normalize(item.metadata?.album))\u{1F}\(normalize(albumArtist(of: item, options: options)))"
    }

    static func artistKey(of item: LibraryItem,
                          options: ArtistGroupingOptions = .default) -> String {
        normalize(albumArtist(of: item, options: options))
    }

    /// Álbumes: conocidos por título (orden natural, ignora artículo
    /// inicial), luego año; dentro, por disco, pista y título. "Sin
    /// álbum" (uno por artista) siempre al final.
    static func albums(from items: [LibraryItem],
                       options: ArtistGroupingOptions = .default) -> [AlbumGroup] {
        let music = items.filter { $0.kind == .music }
        var buckets: [String: [LibraryItem]] = [:]
        var order: [String] = []
        for item in music {
            let key = albumKey(of: item, options: options)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(item)
        }
        var groups = order.map { key -> AlbumGroup in
            // La grafia que se muestra es la de la primera pista que
            // entro al grupo (orden de la biblioteca), no la de la
            // pista 1 -- asi un " re " colado no le cambia el nombre.
            let first = buckets[key]![0]
            let bucket = sortedTracks(buckets[key]!)
            let albumTitle = first.metadata?.album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let isUnknown = albumTitle.isEmpty
            return AlbumGroup(
                id: key,
                title: isUnknown ? unknownAlbumTitle : albumTitle,
                artist: albumArtist(of: first, options: options) ?? unknownArtistName,
                items: bucket,
                coverArtData: bucket.compactMap { $0.metadata?.coverArtData }.first,
                year: bucket.compactMap { $0.metadata?.year }.first,
                genre: bucket.compactMap { $0.metadata?.genre }.first,
                isUnknown: isUnknown
            )
        }
        groups.sort(by: albumOrder)
        return groups
    }

    /// Artistas por nombre; "Artista desconocido" al final. Cada uno con
    /// sus álbumes en el orden de `albums(from:)`.
    static func artists(from items: [LibraryItem],
                        options: ArtistGroupingOptions = .default) -> [ArtistGroup] {
        let albums = albums(from: items, options: options)
        var buckets: [String: [AlbumGroup]] = [:]
        var order: [String] = []
        for album in albums {
            let key = normalize(album.isUnknownArtist ? nil : album.artist)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(album)
        }
        var groups = order.map { key -> ArtistGroup in
            let bucket = buckets[key]!
            let isUnknown = key.isEmpty
            return ArtistGroup(
                id: key,
                name: isUnknown ? unknownArtistName : bucket[0].artist,
                albums: bucket,
                isUnknown: isUnknown
            )
        }
        groups.sort { a, b in
            if a.isUnknown != b.isUnknown { return !a.isUnknown }
            return sortName(a.name).localizedStandardCompare(sortName(b.name)) == .orderedAscending
        }
        return groups
    }

    // MARK: - Orden

    static func sortedTracks(_ items: [LibraryItem]) -> [LibraryItem] {
        items.sorted { a, b in
            // Sin numero de disco = disco 1 (como Music.app): una pista
            // sin TPOS no va antes que todo el disco 1.
            let da = a.metadata?.discNumber ?? 1, db = b.metadata?.discNumber ?? 1
            if da != db { return da < db }
            let ta = a.metadata?.trackNumber ?? Int.max, tb = b.metadata?.trackNumber ?? Int.max
            if ta != tb { return ta < tb }
            return displayTitle(a).localizedStandardCompare(displayTitle(b)) == .orderedAscending
        }
    }

    static func displayTitle(_ item: LibraryItem) -> String {
        item.metadata?.title ?? item.sourceURL.deletingPathExtension().lastPathComponent
    }

    private static func albumOrder(_ a: AlbumGroup, _ b: AlbumGroup) -> Bool {
        if a.isUnknown != b.isUnknown { return !a.isUnknown }
        if a.isUnknown {
            // Dos "Sin álbum" de artistas distintos: por artista.
            return sortName(a.artist).localizedStandardCompare(sortName(b.artist)) == .orderedAscending
        }
        let byTitle = sortName(a.title).localizedStandardCompare(sortName(b.title))
        if byTitle != .orderedSame { return byTitle == .orderedAscending }
        return (a.year ?? "") < (b.year ?? "")
    }

    /// Ignora el artículo inicial (El/La/Los/Las/The/Un/Una/A/An) para
    /// ordenar, como hace Music.app.
    static func sortName(_ name: String) -> String {
        // Puntuacion inicial ("…Little Broken Hearts", "'Plastic Beach'",
        // "(What's the Story)") no cuenta para ordenar, como en Music.app.
        var trimmed = String(name.drop { !$0.isLetter && !$0.isNumber })
        if trimmed.isEmpty { trimmed = name }
        let lower = trimmed.lowercased()
        for article in ["the ", "los ", "las ", "el ", "la ", "una ", "un ", "an ", "a "] where lower.hasPrefix(article) {
            let rest = trimmed.dropFirst(article.count).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? trimmed : rest
        }
        return trimmed
    }
}

extension AlbumGroup {
    var isUnknownArtist: Bool { artist == LibraryGrouping.unknownArtistName }

    /// "3 canciones · 2019" para la tarjeta.
    var subtitleDetail: String {
        var parts = ["\(trackCount) \(trackCount == 1 ? "canción" : "canciones")"]
        if let year, !year.isEmpty { parts.append(year) }
        return parts.joined(separator: " · ")
    }
}

extension ArtistGroup {
    /// "31 álbumes, 321 canciones" como en la cabecera de Music.app.
    var summary: String {
        let albumCount = albums.filter { !$0.isUnknown }.count
        let albumsText = albumCount == 1 ? "1 álbum" : "\(albumCount) álbumes"
        let songsText = trackCount == 1 ? "1 canción" : "\(trackCount) canciones"
        return albumCount == 0 ? songsText : "\(albumsText), \(songsText)"
    }
}

/// Ámbito de la tabla de Canciones/Video cuando se embebe en Álbumes/
/// Artistas/Películas/Series (ST-031, ampliado PLAN-biblioteca-medios-v2.md
/// §3.4 Tanda 4). El nombre quedó de cuando solo cubría Música -- el
/// plan permite no renombrarlo si solo hace falta sumar casos (§4.1.1);
/// se documenta acá en vez de tocar cada sitio que ya lo usa. Las claves
/// son las de `LibraryGrouping.albumKey(of:)` / `artistKey(of:)` /
/// `videoCollectionKey(of:)`.
enum MusicScope: Equatable {
    case all
    case album(String)
    case artist(String)
    /// Todos los items de una película/serie (`VideoCollectionGroup.id`).
    case videoCollection(String)
    /// Solo los episodios de una temporada dentro de esa serie.
    case season(String, Int)
    /// Todas las fotos de un álbum dentro de una colección
    /// (`PhotoAlbumGroup.id`, incluye la categoría -- dos colecciones
    /// distintas pueden tener un álbum con el mismo nombre).
    case photoAlbum(String)
}

/// Un álbum de fotos DENTRO de una colección (Fotos/Imágenes/IA) --
/// PLAN-biblioteca-medios-v2.md §3.3, encargo adicional del dueño
/// (2026-08-18: "que sea muy similar en cuestión de uso a lo que
/// ofrecía el iPod Classic original" -- Álbumes/Rollos como carpetas,
/// mosaico de portada, clic para ver las fotos). Solo LOCAL: nunca
/// llega al iPod (D-192, `/Photos` sigue plano), ni crea carpetas por
/// sí solo -- es un grupo en memoria como `AlbumGroup`/`ArtistGroup`.
struct PhotoAlbumGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let category: String
    let items: [LibraryItem]
    /// `true` para el cajón "Sin álbum" -- fotos de la colección sin
    /// `photoAlbum` asignado, siempre al final de la cuadrícula.
    let isUnknown: Bool

    var count: Int { items.count }
    /// Hasta 4, para el mosaico 2×2 de la tarjeta (una sola foto si hay
    /// menos de 4). A diferencia de música/video, una foto NUNCA
    /// completa `item.metadata` (`LibraryViewModel.process(itemAt:)`,
    /// caso `.photo`) -- la imagen en sí es el contenido, se lee del
    /// archivo preparado (o el original si todavía no se procesó).
    var previewImages: [Data] {
        items.prefix(4).compactMap { item in
            try? Data(contentsOf: item.preparedURL ?? item.sourceURL)
        }
    }
}

/// Una temporada dentro de una serie: sus episodios, ordenados por
/// número (los sin número, al final). `number == VideoCollectionGroup.
/// noSeasonNumber` es el cajón "Sin temporada".
struct SeasonGroup: Identifiable, Equatable {
    let number: Int
    let items: [LibraryItem]
    var id: Int { number }
}

/// Una película o serie para las vistas "Películas"/"Series"
/// (PLAN-biblioteca-medios-v2.md §3.4): grupo en memoria, igual que
/// `AlbumGroup`/`ArtistGroup` -- nada de esto crea carpetas ni cambia
/// la organización en disco.
struct VideoCollectionGroup: Identifiable, Equatable {
    static let noSeasonNumber = -1

    let id: String
    let title: String
    let year: String?
    let posterData: Data?
    let isSeries: Bool
    let items: [LibraryItem]
    /// Vacío para una película. Para una serie, una entrada por número
    /// de temporada presente (incluida `noSeasonNumber` si hay
    /// episodios sin ese campo poblado), ordenadas de menor a mayor con
    /// "Sin temporada" siempre al final.
    let seasons: [SeasonGroup]

    var episodeCount: Int { items.count }
}

extension LibraryGrouping {
    /// Clave de agrupación de un video de Películas/Series: por
    /// `seriesName` normalizado si es un episodio de Series (varios
    /// archivos, un solo grupo); por título normalizado si es una
    /// película (agrupa duplicados reales, p.ej. una reimportación) o,
    /// sin título, por su propio id (nunca se agrupa con nada más).
    static func videoCollectionKey(of item: LibraryItem) -> String {
        if LibrarySync.isSeriesCategory(item.category),
           let seriesName = item.seriesName?.trimmingCharacters(in: .whitespacesAndNewlines), !seriesName.isEmpty {
            return "series\u{1F}\(normalize(seriesName))"
        }
        let title = item.metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, !title.isEmpty {
            return "movie\u{1F}\(normalize(title))"
        }
        return "movie\u{1F}\(item.id.uuidString)"
    }

    /// Películas y Series (D-283: `item.category` guardado como
    /// displayName localizado, doble idioma) agrupadas en
    /// `VideoCollectionGroup` -- por nombre, "Sin temporada" al final
    /// dentro de cada serie, artículo inicial ignorado al ordenar el
    /// listado (mismo criterio que álbumes/artistas).
    static func videoCollections(from items: [LibraryItem]) -> [VideoCollectionGroup] {
        let videos = items.filter { item in
            item.kind == .video && (
                item.category == MediaCategory.movies.displayNameSpanish
                || item.category == MediaCategory.movies.displayNameEnglish
                || LibrarySync.isSeriesCategory(item.category)
            )
        }
        var buckets: [String: [LibraryItem]] = [:]
        var order: [String] = []
        for item in videos {
            let key = videoCollectionKey(of: item)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(item)
        }
        var groups = order.map { key -> VideoCollectionGroup in
            let bucket = buckets[key]!
            let first = bucket[0]
            let isSeries = LibrarySync.isSeriesCategory(first.category)
            let title: String = {
                if isSeries, let seriesName = first.seriesName?.trimmingCharacters(in: .whitespacesAndNewlines), !seriesName.isEmpty {
                    return seriesName
                }
                let metaTitle = first.metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                return (metaTitle?.isEmpty == false ? metaTitle : nil) ?? displayTitle(first)
            }()

            var seasons: [SeasonGroup] = []
            if isSeries {
                var seasonBuckets: [Int: [LibraryItem]] = [:]
                var seasonOrder: [Int] = []
                for episode in bucket {
                    let number = episode.season ?? VideoCollectionGroup.noSeasonNumber
                    if seasonBuckets[number] == nil { seasonOrder.append(number) }
                    seasonBuckets[number, default: []].append(episode)
                }
                seasons = seasonOrder
                    .sorted { a, b in
                        if a == VideoCollectionGroup.noSeasonNumber { return false }
                        if b == VideoCollectionGroup.noSeasonNumber { return true }
                        return a < b
                    }
                    .map { number in
                        let episodes = (seasonBuckets[number] ?? []).sorted { a, b in
                            let ea = a.episode ?? Int.max, eb = b.episode ?? Int.max
                            if ea != eb { return ea < eb }
                            return displayTitle(a).localizedStandardCompare(displayTitle(b)) == .orderedAscending
                        }
                        return SeasonGroup(number: number, items: episodes)
                    }
            }

            return VideoCollectionGroup(
                id: key, title: title,
                year: bucket.compactMap { $0.metadata?.year }.first,
                posterData: bucket.compactMap { $0.metadata?.coverArtData }.first,
                isSeries: isSeries, items: bucket, seasons: seasons
            )
        }
        groups.sort { sortName($0.title).localizedStandardCompare(sortName($1.title)) == .orderedAscending }
        return groups
    }

    static let unknownPhotoAlbumTitle = "Sin álbum"

    /// Clave de agrupación de un álbum de fotos: categoría + nombre de
    /// álbum normalizado -- la categoría entra a propósito, dos
    /// colecciones distintas (p.ej. "Fotos" e "Imágenes") pueden tener
    /// cada una un álbum llamado igual sin mezclarse.
    static func photoAlbumKey(of item: LibraryItem, category: String) -> String {
        "\(normalize(category))\u{1F}\(normalize(item.photoAlbum))"
    }

    /// Álbumes de fotos dentro de UNA colección (encargo del dueño,
    /// 2026-08-18: "similar en uso a lo que ofrecía el iPod Classic
    /// original" -- álbumes como carpetas, mosaico de portada). Solo
    /// items de `.photo` con esa `category` exacta; "Sin álbum" (fotos
    /// sin `photoAlbum` asignado) siempre al final.
    static func photoAlbums(from items: [LibraryItem], category: String) -> [PhotoAlbumGroup] {
        let photos = items.filter { $0.kind == .photo && $0.category == category }
        var buckets: [String: [LibraryItem]] = [:]
        var order: [String] = []
        for item in photos {
            let key = photoAlbumKey(of: item, category: category)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(item)
        }
        var groups = order.map { key -> PhotoAlbumGroup in
            let bucket = buckets[key]!
            let albumName = bucket[0].photoAlbum?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let isUnknown = albumName.isEmpty
            return PhotoAlbumGroup(
                id: key, title: isUnknown ? unknownPhotoAlbumTitle : albumName,
                category: category, items: bucket, isUnknown: isUnknown
            )
        }
        groups.sort { a, b in
            if a.isUnknown != b.isUnknown { return !a.isUnknown }
            return sortName(a.title).localizedStandardCompare(sortName(b.title)) == .orderedAscending
        }
        return groups
    }
}
