import SwiftUI

/// Sección "Películas" (PLAN-biblioteca-medios-v2.md §3.4, Tanda 4):
/// cuadrícula de pósters (proporción 2:3 real, no cuadrada) -- mismo
/// patrón de `AlbumsView`, cambiando la tarjeta cuadrada por
/// `MediaCardView(aspect: .poster)`. Clic en una tarjeta abre el
/// detalle: póster grande, año, acciones, y la tabla de Video acotada a
/// esa película sola (`MediaSectionView(scope: .videoCollection)`).
struct MoviesView: View {
    @ObservedObject var viewModel: LibraryViewModel
    let device: AuraDevice?
    @ObservedObject var preferences: AppPreferences

    @State private var movies: [VideoCollectionGroup] = []
    @State private var searchText = ""
    @State private var selectedMovieID: String?
    /// Selección múltiple estilo Finder (encargo del dueño, 2026-08-19).
    @State private var selection = GridSelection<String>()
    @State private var reviewingItem: LibraryItem?
    @AppStorage("aura.moviesSort") private var sortRaw = MovieSort.title.rawValue

    enum MovieSort: String, CaseIterable, Identifiable {
        case title, year, recentlyAdded
        var id: String { rawValue }
        var title: String {
            switch self {
            case .title: return "Título"
            case .year: return "Año"
            case .recentlyAdded: return "Agregado recientemente"
            }
        }
    }

    private var sort: MovieSort { MovieSort(rawValue: sortRaw) ?? .title }

    private var visibleMovies: [VideoCollectionGroup] {
        var result = movies.filter { matches($0, searchText) }
        switch sort {
        case .title:
            break // orden natural de LibraryGrouping (título, artículo inicial ignorado)
        case .year:
            result.sort { a, b in
                let ya = a.year ?? "", yb = b.year ?? ""
                if ya != yb { return ya > yb } // más reciente primero; sin año al final
                return LibraryGrouping.sortName(a.title).localizedStandardCompare(LibraryGrouping.sortName(b.title)) == .orderedAscending
            }
        case .recentlyAdded:
            result.sort { a, b in
                let da = a.items.compactMap(\.addedAt).max() ?? .distantPast
                let db = b.items.compactMap(\.addedAt).max() ?? .distantPast
                return da > db
            }
        }
        return result
    }

    private func matches(_ movie: VideoCollectionGroup, _ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        return LibrarySearch.matches(movie.title, needle) || LibrarySearch.matches(movie.year, needle)
    }

    private var selectedMovie: VideoCollectionGroup? {
        guard let selectedMovieID else { return nil }
        return movies.first { $0.id == selectedMovieID }
    }

    var body: some View {
        Group {
            if let movie = selectedMovie {
                movieDetail(movie)
            } else {
                grid
            }
        }
        .navigationTitle("Películas")
        .libraryStatus(statusSummary)
        .onAppear(perform: rebuild)
        .onReceive(viewModel.$items) { _ in rebuild() }
        .sheet(item: $reviewingItem) { item in
            MediaInfoView(item: item, availableCategories: MediaCategory.videoCategories.map(\.displayName)) { category in
                viewModel.setCategory(category, forItem: item.id)
            } onVideoInfoChanged: { title, seriesName, season, episode in
                viewModel.updateVideoInfo(id: item.id, title: title, seriesName: seriesName, season: season, episode: episode)
                reviewingItem = nil
            } onSave: { _ in
            } onCancel: {
                reviewingItem = nil
            }
        }
    }

    /// ST-063: barra de estado. Con una película abierta, sus archivos
    /// (la selección de la tabla embebida llega por `selectionForSync`).
    private var statusSummary: LibraryStatusSummary {
        if let movie = selectedMovie {
            let selected = movie.items.filter { viewModel.selectionForSync.contains($0.id) }
            var summary = LibraryStats.videos(items: movie.items, selected: selected, breakdown: false)
            summary.total = "«\(movie.title)» · " + summary.total
            return summary
        }
        return LibraryStats.movies(visibleMovies, selected: visibleMovies.filter { selection.isSelected($0.id) })
    }

    private func rebuild() {
        movies = LibraryGrouping.videoCollections(from: viewModel.items).filter { !$0.isSeries }
        if let selectedMovieID, !movies.contains(where: { $0.id == selectedMovieID }) {
            self.selectedMovieID = nil
        }
        selection.pruneMissing(from: Set(movies.map(\.id)))
    }

    /// Películas a las que aplica una acción disparada desde `movie`:
    /// su selección completa si ya estaba seleccionada, o solo ella si
    /// no (criterio Finder, ver `GridSelection.effectiveIDs`).
    private func effectiveMovies(for movie: VideoCollectionGroup) -> [VideoCollectionGroup] {
        let ids = selection.effectiveIDs(for: movie.id)
        return movies.filter { ids.contains($0.id) }
    }

    // MARK: - Cuadrícula

    private var grid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Spacer()
                Menu {
                    Picker("Ordenar por", selection: $sortRaw) {
                        ForEach(MovieSort.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Ordenar las películas")
                LibrarySearchField(scopeTitle: "Películas", text: $searchText)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if movies.isEmpty {
                emptyState("Todavía no hay películas en la biblioteca.",
                           detail: "Arrastra videos a \"Películas\" en la barra lateral y aquí aparecerán con su póster.")
            } else if visibleMovies.isEmpty {
                emptyState("Sin resultados para \"\(searchText)\".", detail: nil)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 24, alignment: .top)],
                              alignment: .leading, spacing: 28) {
                        ForEach(visibleMovies) { movie in
                            MediaCardView(imageData: movie.posterData, title: movie.title, subtitle: movie.year,
                                          aspect: .poster(width: 140), placeholderSymbol: "film")
                                .librarySelectionCheckbox(selection.isSelected(movie.id),
                                                          anySelected: !selection.selected.isEmpty) {
                                    selection.toggle(movie.id)
                                }
                                .onTapGesture(count: 2) { selectedMovieID = movie.id }
                                .onTapGesture { selection.handleTap(movie.id, orderedIDs: visibleMovies.map(\.id)) }
                                .contextMenu { movieContextMenu(movie) }
                                .draggable(LibrarySelectionTransfer(itemIDs: effectiveMovies(for: movie).flatMap(\.items).map(\.id)))
                                .help(movie.title)
                        }
                    }
                    // R2-1: mismo margen superior que la cuadrícula de
                    // Fotos. Sin él la primera fila arranca pegada al
                    // borde del ScrollView y su casilla -- que va a 6 pt
                    // del borde de la tarjeta -- queda cortada apenas se
                    // desplaza un poco, que es exactamente el síntoma que
                    // reportó el dueño ("la primera fila no pinta los
                    // círculos y las demás sí").
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private func emptyState(_ title: String, detail: String?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "film")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).foregroundStyle(.secondary)
            if let detail {
                Text(detail).font(.callout).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Detalle

    private func movieDetail(_ movie: VideoCollectionGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    selectedMovieID = nil
                } label: {
                    Label("Películas", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(AuraColors.light.accent)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            HStack(alignment: .top, spacing: 20) {
                CoverArtView(data: movie.posterData, width: 180, height: 270, placeholderSymbol: "film")
                VStack(alignment: .leading, spacing: 6) {
                    Text(movie.title)
                        .font(.title.bold())
                        .lineLimit(2)
                    if let year = movie.year, !year.isEmpty {
                        Text(year)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    if let item = movie.items.first {
                        Text(movieStats(item))
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                    HStack {
                        Button("Buscar póster en línea") {
                            Task { await viewModel.fetchVideoPosters(ids: Set(movie.items.map(\.id))) }
                        }
                        Button("Más información...") {
                            if let item = movie.items.first { reviewingItem = item }
                        }
                    }
                }
                Spacer()
            }
            .padding(20)

            Divider()

            MediaSectionView(kind: .video, viewModel: viewModel, device: device,
                             preferences: preferences, scope: .videoCollection(movie.id))
        }
    }

    private func movieStats(_ item: LibraryItem) -> String {
        let row = MediaTableRow(item: item)
        let parts = [row.durationText, item.sourceURL.pathExtension.uppercased()].filter { !$0.isEmpty && $0 != "--" }
        return parts.joined(separator: " · ")
    }

    /// Menú contextual: si se dispara sobre una película que forma
    /// parte de una selección múltiple, actúa sobre TODA la selección
    /// (encargo del dueño, 2026-08-19); si no, solo sobre `movie`.
    @ViewBuilder
    private func movieContextMenu(_ movie: VideoCollectionGroup) -> some View {
        let targets = effectiveMovies(for: movie)
        let items = targets.flatMap(\.items)
        let allFavorite = items.allSatisfy { $0.metadata?.isFavorite == true }
        let plural = targets.count > 1

        if !plural {
            Button("Abrir") { selectedMovieID = movie.id }
            Divider()
        }
        Button(allFavorite ? "Quitar favorito" : "Marcar como favorito") {
            viewModel.setFavorite(!allFavorite, forItems: Set(items.map(\.id)))
        }
        Button("Buscar póster en línea") {
            Task { await viewModel.fetchVideoPosters(ids: Set(items.map(\.id))) }
        }
        Menu("Cambiar categoría") {
            ForEach(MediaCategory.videoCategories) { category in
                Button(category.displayName) {
                    viewModel.setCategory(category.displayName, forItems: Set(items.map(\.id)))
                }
            }
        }
        Divider()
        Button("Mostrar en Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(items.map(\.sourceURL))
        }
        Button(plural ? "Eliminar películas" : "Eliminar película", role: .destructive) {
            viewModel.deleteItems(ids: Set(items.map(\.id)))
        }
    }
}
