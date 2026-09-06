import SwiftUI

/// Sección "Álbumes" (ST-031, PLAN-studio-ux.md §2.3): cuadrícula de
/// tarjetas de álbum como la de Music.app; clic en una → la misma tabla
/// de Canciones acotada a ese álbum (`MediaSectionView(scope: .album)`),
/// con cabecera de portada grande y botón para volver. Los álbumes son
/// grupos en memoria (`LibraryGrouping`), no carpetas.
struct AlbumsView: View {
    @ObservedObject var viewModel: LibraryViewModel
    let device: AuraDevice?
    @ObservedObject var preferences: AppPreferences
    /// PLAN-studio-rendimiento.md Fase 1: la selección de la tabla
    /// embebida (álbum expandido) llega por acá -- ver `SelectionStore`.
    /// PLAN-studio-rendimiento-2.md Fase 3 (ST-182): `let` y no
    /// `@ObservedObject` -- esta vista PUBLICA acá su selección, así que
    /// observarlo le devolvía el eco de su propia publicación y le
    /// costaba una segunda pasada de `body` por clic. Quien observa es
    /// `SelectionStoreObserver`.
    let selectionStore: SelectionStore

    @State private var albums: [AlbumGroup] = []
    @State private var searchText = ""
    @State private var selectedAlbumID: String?
    /// PLAN-studio-rendimiento-2.md Fase 1 (ST-181): lo VISIBLE (filtro
    /// de búsqueda + orden) y su `GridOrder`, calculados una sola vez
    /// por cambio real de entrada. Antes era un computed var que el
    /// `body` evaluaba cinco veces por pasada -- ver `GridModel`.
    @StateObject private var gridModel = GridModel<AlbumGroup>()
    /// El resumen de la barra de estado, memoizado -- ver
    /// `GridStatusModel`. En `@State` y no en `@StateObject` A
    /// PROPÓSITO (mismo criterio que `ContentView.statusCenter`):
    /// `@State` sostiene la referencia sin suscribir a esta vista. Si
    /// `AlbumsView` lo observara, cada clic costaría DOS pasadas de su
    /// `body` -- una por la selección y otra por el resumen nuevo. Quien
    /// lo observa es `LibraryStatusRelay`, una vista de tamaño cero.
    @State private var statusModel = GridStatusModel()
    /// Identidad de esta vista como publicadora de `selectionStore`.
    @State private var publisherID = UUID()
    /// Selección múltiple estilo Finder (encargo del dueño, 2026-08-19)
    /// -- clic simple selecciona/alterna, doble clic abre el detalle
    /// (como siempre lo hacía el tap único, ahora reservado al gesto de
    /// doble clic). PLAN-studio-rendimiento-2.md Fase 1 (ST-181): vive
    /// en un `GridSelectionModel` inyectable en vez de un `@State
    /// private` para que el arnés pueda cambiarla desde afuera y contar
    /// evaluaciones de `body` por clic -- mismo comportamiento.
    @StateObject private var selectionModel: GridSelectionModel<String>

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
    /// ST-104: álbum cuyo menú pidió "Buscar carátulas del álbum".
    /// PLAN-studio-rendimiento-2.md Fase 3 (ST-182): ahora es una COLA
    /// -- la acción plural deja acá los álbumes que no tuvieron una
    /// opción lo bastante segura, y el selector los recorre uno por uno
    /// con "Omitir". Un solo álbum es una cola de uno.
    @State private var coverQueue: [AlbumCoverRequest] = []
    @State private var coverQueueIndex = 0
    @AppStorage("aura.albumsSort") private var sortRaw = AlbumSort.title.rawValue

    enum AlbumSort: String, CaseIterable, Identifiable {
        case title, artist, year, recentlyAdded
        var id: String { rawValue }
        var title: String {
            switch self {
            case .title: return "Título"
            case .artist: return "Artista"
            case .year: return "Año"
            case .recentlyAdded: return "Agregado recientemente"
            }
        }
    }

    private var sort: AlbumSort { AlbumSort(rawValue: sortRaw) ?? .title }

    private var visibleAlbums: [AlbumGroup] { gridModel.visible }

    /// El cálculo en sí. Lo llama `GridModel.recompute`, nunca el
    /// `body`; `groups` viene por parámetro porque `rebuild()` lo usa
    /// con el valor recién calculado, antes de que el `@State` lo
    /// refleje.
    private func computeVisible(_ groups: [AlbumGroup]) -> [AlbumGroup] {
        var result = groups.filter { LibrarySearch.album($0, matches: searchText) }
        switch sort {
        case .title:
            break // orden natural de LibraryGrouping (título, año; "Sin álbum" al final)
        case .artist:
            result.sort { a, b in
                if a.isUnknown != b.isUnknown { return !a.isUnknown }
                let byArtist = LibraryGrouping.sortName(a.artist).localizedStandardCompare(LibraryGrouping.sortName(b.artist))
                if byArtist != .orderedSame { return byArtist == .orderedAscending }
                return (a.year ?? "") < (b.year ?? "")
            }
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

    private var selectedAlbum: AlbumGroup? {
        guard let selectedAlbumID else { return nil }
        return albums.first { $0.id == selectedAlbumID }
    }

    var body: some View {
        #if DEBUG
        let _ = BodyEvaluationCounter.record("AlbumsView")
        #endif
        Group {
            if let album = selectedAlbum {
                albumDetail(album)
            } else {
                grid
            }
        }
        .navigationTitle("Álbumes")
        .background(LibraryStatusRelay(model: statusModel))
        .onAppear(perform: rebuild)
        .onReceive(viewModel.$items) { _ in rebuild() }
        // PLAN-studio-rendimiento-2.md Fase 1 (ST-181): todo lo que
        // antes se recalculaba dentro del `body` se dispara acá, por la
        // entrada que de verdad cambió.
        .onChange(of: searchText) { refreshGrid() }
        .onChange(of: sortRaw) { refreshGrid() }
        .onChange(of: preferences.artistGrouping) { rebuild() }
        .onChange(of: selectedAlbumID) { _, id in
            refreshStatusTotal()
            // Al volver del detalle, la cuadrícula vuelve a ser quien
            // publica la selección; al entrar, la publica su tabla.
            if id == nil { publishSelection() }
        }
        .onChange(of: selection) { _, _ in
            refreshStatusSelection()
            if selectedAlbumID == nil { publishSelection() }
        }
        .onDisappear { selectionStore.clear(from: publisherID) }
        .background(SelectionStoreObserver(store: selectionStore) { _ in
            // Solo importa con un detalle ABIERTO: ahí la selección de
            // la barra de estado la publica la tabla embebida.
            if selectedAlbumID != nil { refreshStatusSelection() }
        })
        .sheet(isPresented: showingCoverPicker) { coverPicker }
    }

    /// ST-063: barra de estado. En la cuadrícula, álbumes/artistas/
    /// canciones y lo seleccionado; con un álbum abierto, sus canciones
    /// (la selección de la tabla embebida llega por `selectionStore`).
    /// PLAN-studio-rendimiento-2.md Fase 1 (ST-181): esto vivía en el
    /// `body` -- `LibraryStats.albums` crudo, o sea `flatMap` de los
    /// 12 000 ítems más una normalización de artista por ítem, en cada
    /// clic (diagnóstico §0.1). Ahora el total se recalcula con la
    /// cuadrícula y la selección aparte, fuera de main cuando es cara.
    private func refreshStatusTotal() {
        if let album = selectedAlbum {
            let items = album.items
            let title = album.title
            let options = preferences.artistGrouping
            statusModel.recomputeTotal {
                var summary = LibraryStats.music(items: items, selected: [], options: options)
                summary.total = "«\(title)» · " + summary.total
                return summary
            }
        } else {
            let visible = gridModel.visible
            statusModel.recomputeTotal { LibraryStats.albumsTotal(visible) }
        }
        refreshStatusSelection()
    }

    private func refreshStatusSelection() {
        if let album = selectedAlbum {
            let selectedTracks = album.items.filter { selectionStore.selected.contains($0.id) }
            let totalCount = album.items.count
            let options = preferences.artistGrouping
            statusModel.recomputeSelection(cost: selectedTracks.count) {
                LibraryStats.musicSelectionText(selected: selectedTracks, totalCount: totalCount, options: options)
            }
        } else {
            let visible = gridModel.visible
            let selected = visible.filter { selection.isSelected($0.id) }
            let totalCount = visible.count
            statusModel.recomputeSelection(cost: selected.reduce(0) { $0 + $1.trackCount }) {
                LibraryStats.albumsSelectionText(selected: selected, totalCount: totalCount)
            }
        }
    }

    /// PLAN-studio-rendimiento-2.md Fase 1 (ST-181): la selección de la
    /// CUADRÍCULA también llega a `selectionStore` -- seleccionar tres
    /// álbumes y pedir "sincronizar solo la selección" tenía que
    /// sincronizar esas canciones y no sincronizaba nada.
    private func publishSelection() {
        let ids = gridModel.visible
            .filter { selection.isSelected($0.id) }
            .flatMap { $0.items.map(\.id) }
        selectionStore.replace(with: Set(ids), from: publisherID)
    }

    private func rebuild() {
        let groups = LibraryGrouping.albums(from: viewModel.items, options: preferences.artistGrouping)
        albums = groups
        if let selectedAlbumID, !groups.contains(where: { $0.id == selectedAlbumID }) {
            self.selectedAlbumID = nil
        }
        selection.pruneMissing(from: Set(groups.map(\.id)))
        // ST-182: el índice de agrupación se arma en segundo plano al
        // cambiar el catálogo, para que el primer clic derecho no pague
        // los 12 000 cálculos de clave.
        viewModel.warmCatalogIndex()
        refreshGrid(groups)
    }

    /// Recalcula lo visible (y con ello la barra de estado). `groups`
    /// solo se pasa desde `rebuild()`, que tiene el valor nuevo antes
    /// que el `@State`.
    private func refreshGrid(_ groups: [AlbumGroup]? = nil) {
        let source = groups ?? albums
        gridModel.recompute { computeVisible(source) }
        refreshStatusTotal()
        if selectedAlbumID == nil { publishSelection() }
    }

    // MARK: - Carátulas (cola del selector)

    /// El pedido de carátulas de UN álbum, resuelto contra la biblioteca
    /// completa para que la tapa elegida se aplique al álbum ENTERO y no
    /// solo a lo que estaba seleccionado.
    /// PLAN-studio-rendimiento-2.md Fase 3 (ST-182): por el índice del
    /// catálogo, no recorriendo los 12 000 ítems por álbum.
    private func coverRequest(for album: AlbumGroup) -> AlbumCoverRequest? {
        AlbumCoverRequest.forAlbum(album, in: viewModel.catalogIndex)
    }

    /// Un pedido por cada álbum alcanzado que tenga sentido buscar. Con
    /// los 1 000 álbumes seleccionados esto eran 12 millones de claves
    /// normalizadas (81 s medidos en ST-180 (d)); ahora son 1 000
    /// búsquedas en un diccionario.
    private func coverRequests(for targets: [AlbumGroup]) -> [AlbumCoverRequest] {
        let index = viewModel.catalogIndex
        return targets.compactMap { AlbumCoverRequest.forAlbum($0, in: index) }
    }

    private var showingCoverPicker: Binding<Bool> {
        Binding(get: { coverQueue.indices.contains(coverQueueIndex) },
                set: { if !$0 { closeCoverQueue() } })
    }

    @ViewBuilder
    private var coverPicker: some View {
        if coverQueue.indices.contains(coverQueueIndex) {
            let request = coverQueue[coverQueueIndex]
            AlbumCoverPickerView(
                request: request,
                search: AlbumCoverSearch(deezerEnabled: preferences.deezerEnabled),
                queuePosition: coverQueue.count > 1 ? (coverQueueIndex + 1, coverQueue.count) : nil,
                onApply: { data in
                    Task { await viewModel.applyAlbumCover(data, toItems: request.trackIDs) }
                    advanceCoverQueue()
                },
                onSkip: coverQueue.count > 1 ? { advanceCoverQueue() } : nil,
                onCancel: { closeCoverQueue() })
                // La hoja no se cierra entre álbumes: cambia de
                // contenido. El `.id` es lo que hace que el siguiente
                // arranque su búsqueda en vez de mostrar las candidatas
                // del anterior.
                .id(request.id)
        }
    }

    private func startCoverQueue(_ requests: [AlbumCoverRequest]) {
        coverQueueIndex = 0
        coverQueue = requests
    }

    private func advanceCoverQueue() {
        if coverQueueIndex + 1 < coverQueue.count {
            coverQueueIndex += 1
        } else {
            closeCoverQueue()
        }
    }

    private func closeCoverQueue() {
        coverQueue = []
        coverQueueIndex = 0
    }

    /// R2-3: aplica la recomendada donde alcanza el umbral y deja lo
    /// dudoso al usuario.
    ///
    /// PLAN-studio-rendimiento-2.md Fase 3 (ST-182) cambia qué pasa con
    /// lo dudoso: antes, con EXACTAMENTE uno se abría su selector y con
    /// varios no se abría nada -- "una fila de pickers encadenados no se
    /// puede usar". Ahora sí se puede: los dudosos entran en una cola
    /// que el selector recorre de a uno, diciendo en cuál va ("Álbum 2
    /// de 7") y con "Omitir este álbum". Cancelar corta la cola entera.
    private func applyRecommended(_ requests: [AlbumCoverRequest]) {
        Task {
            let pending = await viewModel.applyRecommendedCovers(
                for: requests,
                search: AlbumCoverSearch(deezerEnabled: preferences.deezerEnabled))
            startCoverQueue(pending)
        }
    }

    /// Álbumes a los que aplica una acción disparada desde `album`: su
    /// selección completa si ya estaba seleccionado, o solo él si no
    /// (criterio Finder, ver `GridSelection.effectiveIDs`).
    private func effectiveAlbums(for album: AlbumGroup) -> [AlbumGroup] {
        let ids = selection.effectiveIDs(for: album.id)
        return albums.filter { ids.contains($0.id) }
    }

    // MARK: - Cuadrícula

    private var grid: some View {
        VStack(spacing: 0) {
            // Orden y busqueda como en Music.app: arriba a la derecha,
            // en la misma fila que el titulo de la ventana.
            HStack(spacing: 10) {
                Spacer()
                Menu {
                    Picker("Ordenar por", selection: $sortRaw) {
                        ForEach(AlbumSort.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Ordenar los álbumes")
                LibrarySearchField(scopeTitle: "Álbumes", text: $searchText)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if albums.isEmpty {
                emptyState("Todavía no hay música en la biblioteca.",
                           detail: "Suelta canciones en \"Canciones\" y aquí aparecerán agrupadas por álbum.")
            } else if visibleAlbums.isEmpty {
                emptyState("Sin resultados para \"\(searchText)\".", detail: nil)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 24, alignment: .top)],
                              alignment: .leading, spacing: 28) {
                        ForEach(visibleAlbums) { album in
                            AlbumGridCell(album: album,
                                          isSelected: selection.isSelected(album.id),
                                          anySelected: !selection.selected.isEmpty,
                                          onOpen: { selectedAlbumID = album.id },
                                          onTap: { selection.handleTap(album.id, order: gridModel.order) },
                                          onToggle: { selection.toggle(album.id) },
                                          menu: { albumContextMenu(album) })
                                .equatable()
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
        // PLAN-studio-rendimiento.md Fase 2: el orden visible se
        // reconstruye solo cuando cambia el conjunto/orden visible, no
        // en cada clic (punto 2) -- ahora sale del propio `GridModel`
        // (ST-181), sin el `onChange(of: visibleAlbums.map(\.id))` que
        // era, él solo, una de las cinco evaluaciones por pasada.
        // Cmd+A selecciona todo lo visible, Escape deselecciona.
        .onKeyPress(.escape) {
            guard !selection.selected.isEmpty else { return .ignored }
            selection.clear()
            return .handled
        }
        .onKeyPress(keys: ["a"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            selection.selectAll(gridModel.order)
            return .handled
        }
    }

    private func emptyState(_ title: String, detail: String?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).foregroundStyle(.secondary)
            if let detail {
                Text(detail).font(.callout).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Detalle de álbum

    private func albumDetail(_ album: AlbumGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    selectedAlbumID = nil
                } label: {
                    Label("Álbumes", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(AuraColors.light.accent)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            HStack(alignment: .top, spacing: 20) {
                CoverArtView(data: album.coverArtData, side: 180)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(album.title)
                            .font(.title.bold())
                            .lineLimit(2)
                        if album.isFavorite {
                            Image(systemName: "star.fill")
                                .foregroundStyle(AuraColors.light.accent)
                        }
                    }
                    Text(album.artist)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text([album.genre, album.year].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                    Text(albumStats(album))
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    HStack {
                        Button(album.isFavorite ? "Quitar favorito" : "Marcar como favorito") {
                            viewModel.setFavorite(!album.isFavorite, forItems: Set(album.items.map(\.id)))
                        }
                        Button("Buscar información en línea") {
                            Task { await viewModel.reenrichOnline(ids: Set(album.items.map(\.id)), fetchAlbumInfo: true, fetchLyrics: false) }
                        }
                        Button("Buscar carátulas del álbum...") {
                            if let request = coverRequest(for: album) { startCoverQueue([request]) }
                        }
                        .disabled(album.isUnknown)
                        .help("Busca varias carátulas en Cover Art Archive y Deezer y aplica la que elijas a todas las canciones del álbum")
                    }
                }
                Spacer()
            }
            .padding(20)

            Divider()

            MediaSectionView(kind: .music, viewModel: viewModel, device: device,
                             preferences: preferences, selectionStore: selectionStore, scope: .album(album.id))
        }
    }

    private func albumStats(_ album: AlbumGroup) -> String {
        let minutes = Int((album.totalDurationSeconds / 60).rounded())
        let songs = album.trackCount == 1 ? "1 canción" : "\(album.trackCount) canciones"
        return minutes > 0 ? "\(songs), \(minutes) min" : songs
    }

    /// Menú contextual: si se dispara sobre un álbum que forma parte de
    /// una selección múltiple, actúa sobre TODA la selección (encargo
    /// del dueño, 2026-08-19); si no, solo sobre `album`.
    @ViewBuilder
    private func albumContextMenu(_ album: AlbumGroup) -> some View {
        let targets = effectiveAlbums(for: album)
        // PLAN-studio-rendimiento-2.md Fase 3 (ST-182): el menú se
        // construye con lo que ya está agrupado, sin materializar las
        // canciones de la selección. Antes, un `flatMap` de los álbumes
        // alcanzados armaba un arreglo de 12 000 ítems solo para ABRIR
        // el menú, y los `coverRequests` recorrían el catálogo entero
        // una vez por álbum. Todo lo que necesita los ítems de verdad
        // (marcar favoritos, mostrar en Finder, eliminar) los pide
        // DENTRO de su closure, o sea al elegir la acción, no al abrir.
        let requests = coverRequests(for: targets)
        // `allSatisfy` corta en el primer elemento que no cumple, así
        // que esto es O(1) en el caso normal, no O(catálogo).
        let allFavorite = targets.allSatisfy { group in
            group.items.allSatisfy { $0.metadata?.isFavorite == true }
        }

        if targets.count == 1 {
            Button("Abrir") { selectedAlbumID = album.id }
            Divider()
        }
        Button(allFavorite ? "Quitar favorito" : "Marcar como favorito") {
            viewModel.setFavorite(!allFavorite, forItems: itemIDs(of: targets))
        }
        Button("Buscar información en línea") {
            Task { await viewModel.reenrichOnline(ids: itemIDs(of: targets), fetchAlbumInfo: true, fetchLyrics: false) }
        }
        if requests.count == 1 {
            // R2-2: la condición es que la selección RESUELVA a un solo
            // álbum, no que se haya hecho clic sobre una sola tarjeta --
            // `AlbumCoverRequest` es quien lo decide, y decide igual acá
            // que en la tabla de Canciones.
            Button("Buscar carátulas del álbum...") { startCoverQueue(requests) }
            // R2-3: la automática, sin preguntar, solo si supera el umbral.
            Button("Aplicar carátula recomendada") { applyRecommended(requests) }
                .disabled(viewModel.isApplyingRecommendedCovers)
                .help("Aplica sin preguntar solo la carátula que supere el umbral de confianza; si ninguna lo supera, se abre el selector")
        } else if requests.count > 1 {
            // F3: la acción plural que faltaba. Aplica la recomendada
            // donde alcanza el umbral y encola los dudosos en el
            // selector, uno por uno.
            Button("Buscar carátulas de \(requests.count) álbumes...") { applyRecommended(requests) }
                .disabled(viewModel.isApplyingRecommendedCovers)
                .help("Aplica sin preguntar la carátula que supere el umbral de confianza en cada álbum; los que no tengan una opción segura los eliges tú, uno por uno")
        }
        Divider()
        Button("Mostrar en Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(targets.flatMap(\.items).map(\.sourceURL))
        }
        Button(targets.count > 1 ? "Eliminar álbumes" : "Eliminar álbum", role: .destructive) {
            viewModel.deleteItems(ids: itemIDs(of: targets))
        }
    }

    private func itemIDs(of groups: [AlbumGroup]) -> Set<UUID> {
        var ids = Set<UUID>()
        for group in groups { for item in group.items { ids.insert(item.id) } }
        return ids
    }
}

/// PLAN-studio-rendimiento-2.md Fase 1, addendum (ST-181): la celda de
/// la cuadrícula, como vista **`Equatable`** aparte.
///
/// Sin esto, el criterio de cierre de F1 ("un clic reevalúa solo la
/// tarjeta tocada") no se puede cumplir por más que se saque trabajo del
/// `body` de `AlbumsView`: cada pasada reconstruye las cláusulas de
/// todas las celdas realizadas, y los closures de gesto y de menú no se
/// pueden comparar -- SwiftUI las da por distintas SIEMPRE y vuelve a
/// evaluar su `body`. Con `==` explícito y `.equatable()`, la celda se
/// redibuja solo si cambió algo que ella DIBUJA.
///
/// La comparación es O(1) a propósito: nunca `AlbumGroup` entero, que
/// arrastra los bytes de la carátula (`Equatable` sintetizado los
/// compararía byte a byte, 15 KB por tarjeta por pasada). Se comparan
/// los campos que se ven, más el tamaño del blob de la portada como
/// huella barata de "cambió la carátula".
///
/// Capturar `self` en los closures es seguro tras ST-181: la selección
/// y el orden viven en objetos (`GridSelectionModel`, `GridModel`), así
/// que un closure "viejo" igual lee el valor actual a través de la
/// referencia -- y `selectedAlbumID` es `@State`, cuya caja también es
/// estable.
private struct AlbumGridCell<Menu: View>: View, Equatable {
    let album: AlbumGroup
    let isSelected: Bool
    let anySelected: Bool
    let onOpen: () -> Void
    let onTap: () -> Void
    let onToggle: () -> Void
    @ViewBuilder let menu: () -> Menu

    var body: some View {
        AlbumCardView(album: album)
            .librarySelectionCheckbox(isSelected, anySelected: anySelected, toggle: onToggle)
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onOpen)
            .onTapGesture(perform: onTap)
            .contextMenu(menuItems: menu)
            .help("\(album.title) — \(album.artist)")
    }

    /// `nonisolated` obligatorio: `View` es `@MainActor`, así que la
    /// celda también lo es, y `Equatable.==` es un requisito sin
    /// aislamiento -- en modo Swift 6 (el que usa el proyecto de Xcode,
    /// `SWIFT_VERSION: "6.0"`; `swift build` del paquete es más
    /// permisivo y no lo señalaba) la conformidad no compila sin esto.
    /// Solo lee `let` de tipos `Sendable`, que es lo que lo hace seguro.
    nonisolated static func == (a: AlbumGridCell, b: AlbumGridCell) -> Bool {
        a.isSelected == b.isSelected
            && a.anySelected == b.anySelected
            && a.album.id == b.album.id
            && a.album.title == b.album.title
            && a.album.artist == b.album.artist
            && a.album.trackCount == b.album.trackCount
            && a.album.isFavorite == b.album.isFavorite
            && a.album.coverArtData?.count == b.album.coverArtData?.count
    }
}
