import Foundation

/// PLAN-studio-rendimiento.md Fase 1, punto 3: la parte de
/// `LibraryStatusSummary` que NO depende de la selección (`total`,
/// `trailing` -- conteos de artistas/álbumes, duración, tamaño de TODO
/// el catálogo filtrado) memoizada, igual que `RowsModel` memoiza
/// `rows`: recalculada solo cuando cambian `items`, nunca por
/// selección. La parte de `selection` sí depende de la selección y se
/// recalcula en el sitio (`MediaSectionView.statusSummary`) con
/// `LibraryStats.musicSelectionText`/`videoSelectionText`/
/// `photoSelectionText` -- barata, proporcional a lo seleccionado, no
/// al catálogo entero.
@MainActor
final class StatusSummaryModel: ObservableObject {
    @Published private(set) var total: LibraryStatusSummary?

    func recompute(items: [LibraryItem], kind: LibraryItemKind,
                   options: ArtistGroupingOptions, presetCategory: String?,
                   photoCollections: [String]) {
        guard !items.isEmpty || total != nil else { return }
        switch kind {
        case .music:
            total = LibraryStats.music(items: items, selected: [], options: options)
        case .video:
            total = LibraryStats.videos(items: items, selected: [], breakdown: presetCategory == nil)
        case .photo:
            total = LibraryStats.photos(items: items, selected: [],
                                        collections: presetCategory == nil ? photoCollections : nil)
        case .unsupported:
            total = nil
        }
    }
}
