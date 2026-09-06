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
    /// PLAN-studio-rendimiento.md Fase 1: la selección de la tabla
    /// embebida (película expandida) llega por acá -- ver `SelectionStore`.
    /// PLAN-studio-rendimiento-2.md Fase 3 (ST-182): `let` y no
    /// `@ObservedObject` -- esta vista PUBLICA acá su selección, así que
    /// observarlo le devolvía el eco de su propia publicación y le
    /// costaba una segunda pasada de `body` por clic. Quien observa es
    /// `SelectionStoreObserver`.
    let selectionStore: SelectionStore

    @State private var movies: [VideoCollectionGroup] = []
    @State private var searchText = ""
    @State private var selectedMovieID: String?
    /// Selección múltiple estilo Finder (encargo del dueño, 2026-08-19).
    /// PLAN-studio-rendimiento-2.md Fase 4 (ST-184): la selección vive
    /// en un `GridSelectionModel` inyectable, como en Álbumes desde
    /// ST-181 -- es lo que guarda además los marcos de las tarjetas para
    /// el arrastre, y lo que deja probar los gestos sin mover un mouse.
    @StateObject private var selectionModel: GridSelectionModel<String>

    /// El espacio de coordenadas compartido entre los marcos de las
    /// tarjetas y el rectángulo del arrastre.
    private static let gridSpace = "peliculas.cuadricula"

    init(viewModel: LibraryViewModel, device: AuraDevice?, preferences: AppPreferences,
         selectionStore: SelectionStore,
         selectionModel: GridSelectionModel<String> = GridSelectionModel()) {
        self.viewModel = viewModel
        self.device = device
        self.preferences = preferences
        self.selectionStore = selectionStore
        _selectionModel = StateObject(wrappedValue: selectionModel)
    }

    private var selection: GridSelection<String> {
        get { selectionModel.selection }
        nonmutating set { selectionModel.selection = newValue }
    }
    /// PLAN-studio-rendimiento-2.md Fase 1 (ST-181): lo visible (filtro
    /// + orden) y su `GridOrder`, calculados una sola vez por cambio
    /// real de entrada -- ver `GridModel`. Antes era un computed var que
    /// el `body` evaluaba varias veces por pasada.
    @StateObject private var gridModel = GridModel<VideoCollectionGroup>()
    /// El resumen de la barra de estado, memoizado -- `GridStatusModel`.
    /// En `@State` y no en `@StateObject` a propósito -- ver la nota
    /// larga en `AlbumsView.statusModel`: observarlo costaría una
    /// segunda pasada de `body` por clic.
    @State private var statusModel = GridStatusModel()
    /// Identidad de esta vista como publicadora de `selectionStore`.
    @State private var publisherID = UUID()
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

    private var visibleMovies: [VideoCollectionGroup] { gridModel.visible }

    /// El cálculo en sí -- lo llama `GridModel.recompute`, nunca el `body`.
    private func computeVisible(_ groups: [VideoCollectionGroup]) -> [VideoCollectionGroup] {
        var result = groups.filter { matches($0, searchText) }
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
        .background(LibraryStatusRelay(model: statusModel))
        .onAppear(perform: rebuild)
        .onReceive(viewModel.$items) { _ in rebuild() }
        // PLAN-studio-rendimiento-2.md Fase 1 (ST-181): fuera del `body`.
        .onChange(of: searchText) { refreshGrid() }
        .onChange(of: sortRaw) { refreshGrid() }
        .onChange(of: selectedMovieID) { _, id in
            refreshStatusTotal()
            if id == nil { publishSelection() }
        }
        .onChange(of: selection) { _, _ in
            refreshStatusSelection()
            if selectedMovieID == nil { publishSelection() }
        }
        .onDisappear { selectionStore.clear(from: publisherID) }
        .background(SelectionStoreObserver(store: selectionStore) { _ in
            // Solo importa con un detalle ABIERTO: ahí la selección de
            // la barra de estado la publica la tabla embebida.
            if selectedMovieID != nil { refreshStatusSelection() }
        })
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
    /// (la selección de la tabla embebida llega por `selectionStore`).
    /// PLAN-studio-rendimiento-2.md Fase 1 (ST-181): se calcula fuera del
    /// `body`, con el total memoizado -- ver `GridStatusModel`.
    private func refreshStatusTotal() {
        if let movie = selectedMovie {
            let items = movie.items
            let title = movie.title
            statusModel.recomputeTotal {
                var summary = LibraryStats.videos(items: items, selected: [], breakdown: false)
                summary.total = "«\(title)» · " + summary.total
                return summary
            }
        } else {
            let visible = gridModel.visible
            statusModel.recomputeTotal { LibraryStats.moviesTotal(visible) }
        }
        refreshStatusSelection()
    }

    private func refreshStatusSelection() {
        if let movie = selectedMovie {
            let selected = movie.items.filter { selectionStore.selected.contains($0.id) }
            let totalCount = movie.items.count
            statusModel.recomputeSelection(cost: selected.count) {
                LibraryStats.videoSelectionText(selected: selected, totalCount: totalCount)
            }
        } else {
            let visible = gridModel.visible
            let selected = visible.filter { selection.isSelected($0.id) }
            let totalCount = visible.count
            statusModel.recomputeSelection(cost: selected.reduce(0) { $0 + $1.items.count }) {
                LibraryStats.moviesSelectionText(selected: selected, totalCount: totalCount)
            }
        }
    }

    /// ST-181: la selección de la cuadrícula también llega a
    /// `selectionStore` ("sincronizar solo la selección").
    private func publishSelection() {
        let ids = gridModel.visible
            .filter { selection.isSelected($0.id) }
            .flatMap { $0.items.map(\.id) }
        selectionStore.replace(with: Set(ids), from: publisherID)
    }

    private func rebuild() {
        let groups = LibraryGrouping.videoCollections(from: viewModel.items).filter { !$0.isSeries }
        movies = groups
        if let selectedMovieID, !groups.contains(where: { $0.id == selectedMovieID }) {
            self.selectedMovieID = nil
        }
        selection.pruneMissing(from: Set(groups.map(\.id)))
        refreshGrid(groups)
    }

    private func refreshGrid(_ groups: [VideoCollectionGroup]? = nil) {
        let source = groups ?? movies
        gridModel.recompute { computeVisible(source) }
        refreshStatusTotal()
        if selectedMovieID == nil { publishSelection() }
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
                            MediaCardView(imageID: "video:\(movie.id)", imageData: movie.posterData, title: movie.title, subtitle: movie.year,
                                          aspect: .poster(width: 140), placeholderSymbol: "film")
                                .librarySelectionCheckbox(selection.isSelected(movie.id),
                                                          anySelected: !selection.selected.isEmpty) {
                                    selection.toggle(movie.id)
                                }
                                .onTapGesture(count: 2) { selectedMovieID = movie.id }
                                .onTapGesture { selection.handleTap(movie.id, order: gridModel.order) }
                                .contextMenu { movieContextMenu(movie) }
                                .draggable(LibrarySelectionTransfer(itemIDs: effectiveMovies(for: movie).flatMap(\.items).map(\.id)))
                                .help(movie.title)
                                .gridMarqueeFrame(id: movie.id, in: Self.gridSpace, model: selectionModel)
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
                    // ST-184: el arrastre va DETRÁS de las tarjetas --
                    // arrastrar desde una tarjeta la mueve, desde un
                    // hueco dibuja el recuadro.
                    .background(
                        GridMarqueeCapture(
                            onBegin: { selectionModel.beginMarquee() },
                            onDrag: { rect, modifiers in
                                selectionModel.updateMarquee(rect: rect, modifiers: modifiers)
                            },
                            onEnd: { selectionModel.endMarquee() },
                            onClickAway: { _ in selection.clear() })
                    )
                    .overlay(alignment: .topLeading) {
                        if let rect = selectionModel.marqueeRect {
                            GridMarqueeRectangle(rect: rect)
                        }
                    }
                    .coordinateSpace(name: Self.gridSpace)
                }
            }
        }
        // PLAN-studio-rendimiento.md Fase 2: ver el comentario
        // equivalente en AlbumsView.grid -- mismo patrón. Pendiente de
        // verificar interactivo con el dueño.
        .onKeyPress(.escape) {
            guard !selection.selected.isEmpty else { return .ignored }
            selection.clear()
            return .handled
        }
        // ST-184: flechas mueven el foco, Shift+flechas extienden desde
        // el ancla. Las columnas por fila salen de los marcos que
        // reportan las tarjetas.
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            let direction: GridDirection
            switch press.key {
            case .leftArrow: direction = .left
            case .rightArrow: direction = .right
            case .upArrow: direction = .up
            default: direction = .down
            }
            selection.move(direction, order: gridModel.order,
                           columnsPerRow: selectionModel.columnsPerRow,
                           extending: press.modifiers.contains(.shift))
            return .handled
        }
        // ST-184: ⌘A / ⇧⌘A por el menú Edición. Con una película
        // abierta manda su tabla embebida, que publica el suyo.
        .focusedSceneValue(\.auraSelectionCommand, selectedMovieID == nil
            ? SelectionCommandContext(selectAll: { selection.selectAll(gridModel.order) },
                                      deselectAll: { selection.clear() },
                                      hasSelection: !selection.selected.isEmpty)
            : nil)
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
                CoverArtView(id: "video:\(movie.id)", data: movie.posterData, width: 180, height: 270, placeholderSymbol: "film")
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
                             preferences: preferences, selectionStore: selectionStore, scope: .videoCollection(movie.id))
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
