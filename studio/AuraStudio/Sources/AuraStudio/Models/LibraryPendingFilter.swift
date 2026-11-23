import Foundation

/// ST-262: filtros de "pendientes" -- que le falta a un album o a una
/// cancion (caratula, ano, genero, letra...). La idea es que encontrar
/// lo que necesita atencion no obligue a recorrer la biblioteca a ojo:
/// cada vista deja ver solo lo que tiene un hueco concreto.
///
/// Logica pura, sin SwiftUI, para probarla sin levantar vistas. Los
/// titulos salen del catalogo con claves literales (ver
/// `LocalizationCatalogTests`).

/// Que le falta a un ALBUM (grupo de `LibraryGrouping`).
enum AlbumPendingFilter: String, CaseIterable, Identifiable {
    case all, missingCover, missingYear, missingGenre
    var id: String { rawValue }

    func matches(_ group: AlbumGroup) -> Bool {
        switch self {
        case .all:
            return true
        case .missingCover:
            // El grupo "Sin album" se excluye a proposito: no es un
            // album y ninguna herramienta de albumes (busqueda de
            // caratulas, enriquecimiento) puede arreglarlo.
            guard !group.isUnknown else { return false }
            return group.coverHash == nil && group.coverPendingData == nil
        case .missingYear:
            guard !group.isUnknown else { return false }
            return Self.isBlank(group.year)
        case .missingGenre:
            guard !group.isUnknown else { return false }
            return Self.isBlank(group.genre)
        }
    }

    var title: String {
        switch self {
        case .all: return LS("pending-filter.todos")
        case .missingCover: return LS("pending-filter.sin-caratula")
        case .missingYear: return LS("pending-filter.sin-ano")
        case .missingGenre: return LS("pending-filter.sin-genero")
        }
    }

    static func isBlank(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespaces).isEmpty != false
    }
}

/// Que le falta a una CANCION.
enum SongPendingFilter: String, CaseIterable, Identifiable {
    case all, missingCover, missingArtist, missingAlbum, missingYear, missingLyrics
    var id: String { rawValue }

    func matches(_ item: LibraryItem) -> Bool {
        switch self {
        case .all: return true
        case .missingCover: return item.metadata?.hasCover != true
        case .missingArtist: return AlbumPendingFilter.isBlank(item.metadata?.artist)
        case .missingAlbum: return AlbumPendingFilter.isBlank(item.metadata?.album)
        case .missingYear: return AlbumPendingFilter.isBlank(item.metadata?.year)
        case .missingLyrics: return AlbumPendingFilter.isBlank(item.metadata?.syncedLyrics)
        }
    }

    var title: String {
        switch self {
        case .all: return LS("pending-filter.todos")
        case .missingCover: return LS("pending-filter.sin-caratula")
        case .missingArtist: return LS("pending-filter.sin-artista")
        case .missingAlbum: return LS("pending-filter.sin-album")
        case .missingYear: return LS("pending-filter.sin-ano")
        case .missingLyrics: return LS("pending-filter.sin-letra")
        }
    }
}
