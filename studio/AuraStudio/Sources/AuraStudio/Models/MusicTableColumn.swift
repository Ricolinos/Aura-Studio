import Foundation

/// Columnas de la tabla de Canciones (ST-019). Antes la tabla tenia 7
/// columnas fijas + 3 opcionales por el limite de 10 slots de
/// `TableColumnBuilder` (D-199); con `TableColumnForEach` (macOS 14.4,
/// el deployment target del proyecto) las columnas se declaran a partir
/// de esta lista, en el orden y con la visibilidad que el usuario elija
/// en "Opciones de visualización" -- persistido en
/// `AppPreferences.musicVisibleColumns`. "Título" no esta aca: es la
/// columna fija que siempre va primero (como en Music.app).
///
/// Cada caso sabe su rotulo, a que grupo pertenece en la ventana de
/// opciones, si tiene sentido como criterio de orden y con que
/// comparador se ordena -- asi la vista no tiene un `switch` gigante
/// duplicado por cada uso.
enum MusicTableColumn: String, CaseIterable, Identifiable, Codable {
    // Musica
    case album
    case albumArtist
    case artist
    case composer
    case discNumber
    case duration
    case genre
    case trackNumber
    case year
    // Personal
    case favorite
    case rating
    // Estadisticas
    case dateAdded
    // Archivo
    case fileFormat
    case fileSize
    // Otros
    case status

    var id: String { rawValue }

    enum Group: String, CaseIterable, Identifiable {
        case music, personal, statistics, file, other
        var id: String { rawValue }
        var title: String {
            switch self {
            case .music: return "Música"
            case .personal: return "Personal"
            case .statistics: return "Estadísticas"
            case .file: return "Archivo"
            case .other: return "Otros"
            }
        }
        var columns: [MusicTableColumn] { MusicTableColumn.allCases.filter { $0.group == self } }
    }

    var group: Group {
        switch self {
        case .album, .albumArtist, .artist, .composer, .discNumber, .duration, .genre, .trackNumber, .year:
            return .music
        case .favorite, .rating:
            return .personal
        case .dateAdded:
            return .statistics
        case .fileFormat, .fileSize:
            return .file
        case .status:
            return .other
        }
    }

    var title: String {
        switch self {
        case .album: return "Álbum"
        case .albumArtist: return "Artista del álbum"
        case .artist: return "Artista"
        case .composer: return "Compositor"
        case .discNumber: return "Número de disco"
        case .duration: return "Duración"
        case .genre: return "Género"
        case .trackNumber: return "Número de pista"
        case .year: return "Año"
        case .favorite: return "Favorito"
        case .rating: return "Calificación"
        case .dateAdded: return "Fecha en que se agregó"
        case .fileFormat: return "Formato"
        case .fileSize: return "Tamaño"
        case .status: return "Estado"
        }
    }

    /// Encabezado corto para la tabla (la ventana de opciones usa
    /// `title`, que puede ser mas largo).
    var headerTitle: String {
        switch self {
        case .discNumber: return "Disco"
        case .trackNumber: return "N.º"
        case .dateAdded: return "Agregado"
        default: return title
        }
    }

    var minWidth: CGFloat {
        switch self {
        case .album, .artist, .albumArtist, .composer: return 90
        case .genre: return 60
        case .duration: return 50
        case .discNumber, .trackNumber: return 36
        case .year: return 44
        case .favorite: return 30
        case .rating: return 70
        case .dateAdded: return 90
        case .fileFormat: return 50
        case .fileSize: return 60
        case .status: return 90
        }
    }

    var idealWidth: CGFloat {
        switch self {
        case .album: return 160
        case .artist, .albumArtist, .composer: return 140
        case .genre: return 100
        case .duration: return 64
        case .discNumber, .trackNumber: return 44
        case .year: return 56
        case .favorite: return 34
        case .rating: return 90
        case .dateAdded: return 110
        case .fileFormat: return 60
        case .fileSize: return 70
        case .status: return 120
        }
    }

    /// Columnas que aparecen en la tabla recien instalada -- las mismas
    /// que la tabla fija anterior mostraba (Título va aparte), mas
    /// "Favorito" que es nueva y es el motivo del filtro "Solo
    /// favoritos".
    static let defaultVisible: [MusicTableColumn] = [.artist, .album, .genre, .duration, .favorite, .status]

    /// Criterios que ofrece el submenu "Opciones para ordenar" (Título
    /// se agrega aparte, como `MusicSortField.title`). El orden es
    /// alfabetico, como en Music.app.
    static let sortMenuColumns: [MusicTableColumn] = [.album, .artist, .duration, .favorite, .genre, .rating, .year, .dateAdded]

    /// Migracion desde el menu "+" viejo (D-199, `aura.visibleColumns.
    /// music`, valores de `ExtraColumn`): lo que el usuario ya habia
    /// activado ahi se conserva como columnas visibles.
    static func migratingLegacyExtraColumns(_ raw: String?) -> [MusicTableColumn] {
        var columns = defaultVisible
        for token in raw?.split(separator: ",") ?? [] {
            switch token {
            case "rating": columns.append(.rating)
            case "trackNumber": columns.append(.trackNumber)
            case "year": columns.append(.year)
            default: break
            }
        }
        return columns
    }
}

/// Criterio de orden de la tabla de Canciones: cualquier columna
/// ordenable, o Título (que no es columna configurable). Persistido
/// junto con el sentido en `AppPreferences`.
enum MusicSortField: Hashable, Codable {
    case title
    case column(MusicTableColumn)

    var title: String {
        switch self {
        case .title: return "Título"
        case .column(let column): return column.title
        }
    }

    /// Los criterios del submenu de orden y del picker de la ventana
    /// de opciones, alfabeticos, con Título en su lugar.
    static let menuFields: [MusicSortField] = {
        var fields: [MusicSortField] = MusicTableColumn.sortMenuColumns.map { .column($0) } + [.title]
        fields.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        return fields
    }()

    var rawValue: String {
        switch self {
        case .title: return "title"
        case .column(let column): return column.rawValue
        }
    }

    init?(rawValue: String) {
        if rawValue == "title" {
            self = .title
        } else if let column = MusicTableColumn(rawValue: rawValue) {
            self = .column(column)
        } else {
            return nil
        }
    }
}
