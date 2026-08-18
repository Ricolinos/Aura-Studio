import Foundation

/// Un álbum tal como lo ve la vista "Álbumes" (PLAN-studio-ux.md §2.3,
/// ST-020): un grupo de canciones de la biblioteca, no un directorio.
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

    /// Artista con el que se agrupa un álbum: la misma precedencia que
    /// la ruta de sync (`LibrarySync`: `albumArtist ?? artist`), para
    /// que lo que se ve en Studio coincida con las carpetas del iPod.
    static func albumArtist(of item: LibraryItem) -> String? {
        let candidate = item.metadata?.albumArtist ?? item.metadata?.artist
        let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func albumKey(of item: LibraryItem) -> String {
        "\(normalize(item.metadata?.album))\u{1F}\(normalize(albumArtist(of: item)))"
    }

    static func artistKey(of item: LibraryItem) -> String {
        normalize(albumArtist(of: item))
    }

    /// Álbumes: conocidos por título (orden natural, ignora artículo
    /// inicial), luego año; dentro, por disco, pista y título. "Sin
    /// álbum" (uno por artista) siempre al final.
    static func albums(from items: [LibraryItem]) -> [AlbumGroup] {
        let music = items.filter { $0.kind == .music }
        var buckets: [String: [LibraryItem]] = [:]
        var order: [String] = []
        for item in music {
            let key = albumKey(of: item)
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
                artist: albumArtist(of: first) ?? unknownArtistName,
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
    static func artists(from items: [LibraryItem]) -> [ArtistGroup] {
        let albums = albums(from: items)
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

/// Ámbito de la tabla de Canciones cuando se embebe en Álbumes/Artistas
/// (ST-020). Las claves son las de `LibraryGrouping.albumKey(of:)` /
/// `artistKey(of:)`.
enum MusicScope: Equatable {
    case all
    case album(String)
    case artist(String)
}
