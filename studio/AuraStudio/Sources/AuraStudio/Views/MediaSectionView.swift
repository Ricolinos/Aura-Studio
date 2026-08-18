import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// Una seccion de contenido del dispositivo (Musica, Video o Fotos).
/// Las tres comparten exactamente el mismo flujo -- soltar archivos, que
/// el pipeline los prepare, revisar lo que quedo incompleto -- asi que
/// son la misma vista parametrizada por `kind` en vez de tres copias.
///
/// Fase 1B/D-193: esto es una interfaz de GESTION, no un reproductor --
/// para escuchar/ver algo, se selecciona y se aprieta espacio, exacto
/// el gesto de Vista Previa de Finder (`QuickLookCoordinator`), nunca
/// hay play/pause propio de la app.
///
/// D-198 (encargo del dueno, referencia visual de una tabla tipo
/// Finder/Musica.app): tabla con columnas de verdad (anchos ajustables
/// nativos de `Table`, encabezados que ordenan), casillas de
/// verificacion para editar en conjunto, y menu contextual con las
/// acciones de biblioteca (buscar info/letra, quitar caratula, elegir
/// canciones relacionadas, renombrar, borrar). Se dejaron afuera a
/// proposito "Reproducciones" y una calificacion con estrella del
/// mockup de referencia -- Aura Studio no reproduce nada (no hay
/// conteo de reproducciones que llevar) y una calificacion nueva
/// hubiera sido un campo decorativo sin ningun dato real detras.
struct MediaSectionView: View {
    let kind: LibraryItemKind
    @ObservedObject var viewModel: LibraryViewModel
    /// El iPod conectado (D-202, encargo del dueño) -- de aca sale el
    /// volumen contra el que se compara `LibrarySync.loadManifest()`
    /// para saber que elementos ya llegaron al dispositivo. `nil` sin
    /// iPod conectado, y entonces nada se marca como sincronizado.
    let device: AuraDevice?
    /// D-228: de aca salen las colecciones de fotos editables
    /// (`photoCollections`) que arma el picker/filtro para `.photo` --
    /// video sigue usando el conjunto fijo de `MediaCategory`.
    @ObservedObject var preferences: AppPreferences
    /// ST-031: la misma tabla, acotada a un álbum o a un artista, cuando
    /// se embebe en Álbumes/Artistas. Con `.all` es la sección Canciones
    /// completa (zona de arrastre, banners, título de navegación).
    var scope: MusicScope = .all

    @State private var isTargeted = false
    /// ST-031: búsqueda contextual ("Buscar en Canciones/Video/Fotos").
    @State private var searchText = ""
    @State private var reviewingItem: LibraryItem?
    @State private var renamingItem: LibraryItem?
    @State private var selection: Set<UUID> = []
    @State private var sortOrder: [KeyPathComparator<MediaTableRow>] = [.init(\.title, order: .forward)]
    @State private var quickLook = QuickLookCoordinator()
    @State private var categoryFilter: String?
    /// Columnas extra visibles (D-199, boton "+" de la barra de
    /// herramientas) -- persiste por tipo de medio en UserDefaults, asi
    /// que Musica/Video/Fotos recuerdan su propia eleccion.
    @State private var visibleColumns: Set<ExtraColumn> = []
    /// D-203: MusicBrainz limita a 1 pedido/segundo, asi que "Buscar
    /// información en línea" sobre varias canciones tarda -- sin esto no
    /// habia NINGUN indicio de que algo estaba pasando, asi que un
    /// pedido que tardaba unos segundos se veia igual que uno que no
    /// hacia nada.
    @State private var isEnriching = false
    @State private var enrichmentBusyText = "Buscando información en línea..."
    /// D-218: IDs pendientes de mostrar el aviso "¿Quieres editar
    /// varios elementos?" antes de abrir la edicion en lote -- se salta
    /// directo a `batchEditingIDs` si el usuario ya marco "No volver a
    /// mostrar" (persistido en UserDefaults, ver `batchWarningSuppressedKey`).
    @State private var pendingBatchEditIDs: Set<UUID>?
    /// ST-012: hoja de revision de caratulas que cayeron a Imagenes.
    @State private var reviewingCoverContamination = false
    @State private var batchEditingIDs: Set<UUID>?
    /// ST-030: hoja "Opciones de visualización" (solo musica).
    @State private var showingViewOptions = false

    private var allItemsOfKind: [LibraryItem] {
        viewModel.items.filter { $0.kind == kind }
    }

    private var items: [LibraryItem] {
        var result = allItemsOfKind
        switch scope {
        case .all: break
        case .album(let key): result = result.filter { LibraryGrouping.albumKey(of: $0) == key }
        case .artist(let key): result = result.filter { LibraryGrouping.artistKey(of: $0) == key }
        }
        if let categoryFilter {
            result = result.filter { $0.category == categoryFilter }
        }
        if kind == .music && preferences.musicShowOnlyFavorites {
            result = result.filter { $0.metadata?.isFavorite == true }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter { LibrarySearch.item($0, matches: query) }
        }
        return result
    }

    private var isEmbedded: Bool { scope != .all }

    /// Nombre del ámbito para el campo de búsqueda.
    private var searchScopeTitle: String {
        switch kind {
        case .music: return "Canciones"
        case .video: return "Video"
        case .photo: return "Fotos"
        case .unsupported: return "Biblioteca"
        }
    }

    private var rows: [MediaTableRow] {
        let index = viewModel.deviceSyncIndex
        return items
            .map { MediaTableRow(item: $0, syncState: index?.state(forSourcePath: $0.sourceURL.path)) }
            .sorted(using: sortOrder)
    }

    /// Solo fotos y video se organizan por categoria (D-192) -- musica
    /// usa carpetas de artista/album, y eso ya se elige en Ajustes, no
    /// aca por elemento. Foto usa la lista libre de `preferences.
    /// photoCollections` (D-228: editable por el usuario); video sigue
    /// el conjunto fijo de `MediaCategory` (nunca cambia, asi que se
    /// convierte a `displayName` aca mismo para que ambos casos
    /// devuelvan `[String]`).
    private var availableCategories: [String]? {
        switch kind {
        case .photo: return preferences.photoCollections
        case .video: return MediaCategory.videoCategories.map(\.displayName)
        default: return nil
        }
    }

    private var selectedItem: LibraryItem? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return items.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let availableCategories {
                categoryFilterBar(availableCategories)
            }
            if items.isEmpty && !isEmbedded && searchText.isEmpty && !preferences.musicShowOnlyFavorites {
                dropZone
                    .padding(24)
                    .frame(maxHeight: .infinity)
            } else {
                if !isEmbedded {
                    dropZone
                        .frame(height: 96)
                        .padding([.horizontal, .top], 16)
                }
                if kind == .music && !isEmbedded { legacyMetadataRereadBanner }
                if kind == .photo { coverContaminationBanner }
                if kind == .video { ffmpegMissingBanner }
                // D-202 (encargo del dueño): el "+" de columnas va PEGADO
                // a los encabezados de la tabla, no en la barra de
                // herramientas de la ventana -- `Table` no deja insertar
                // contenido propio dentro de su fila de encabezados (los
                // titulos de columna solo aceptan texto), asi que esta
                // franja angosta encima de la tabla, alineada a la
                // derecha, es lo mas cerca que se puede quedar.
                if kind == .music || kind == .video { enrichmentBanner }
                if kind == .music { musicHeaderMenuBar } else { columnsBar }
                if items.isEmpty {
                    emptyFilteredState
                }
                table
                    .onKeyPress(.space) {
                        guard let selectedItem else { return .ignored }
                        quickLook.toggle(for: selectedItem.sourceURL)
                        return .handled
                    }
            }
        }
        .navigationTitle(isEmbedded ? "" : title)
        .sheet(isPresented: $showingViewOptions) {
            MusicViewOptionsView(preferences: preferences) { showingViewOptions = false }
        }
        .onChange(of: sortOrder) { storeSortOrderInPreferences() }
        .onChange(of: preferences.musicSortField) { applySortOrderFromPreferences() }
        .onChange(of: preferences.musicSortAscending) { applySortOrderFromPreferences() }
        .toolbar {
            if kind == .music {
                ToolbarItem {
                    Button {
                        guard let selectedItem else { return }
                        reviewingItem = selectedItem
                    } label: {
                        Label("Editar", systemImage: "pencil")
                    }
                    .disabled(selectedItem == nil)
                    .help("Editar metadata y letra de la canción seleccionada")
                }
            }
        }
        .onAppear {
            loadVisibleColumns()
            applySortOrderFromPreferences()
            viewModel.selectionForSync = selection
        }
        // PLAN-general-sync.md §6: "Solo la selección" en
        // `DeviceActivityBar` -- la vista de biblioteca activa publica
        // su seleccion; se limpia al salir para que otra sección no
        // herede una selección que ya no es la que el usuario ve.
        .onChange(of: selection) { viewModel.selectionForSync = $0 }
        .onDisappear { viewModel.selectionForSync = [] }
        .sheet(item: $reviewingItem) { item in
            MediaInfoView(item: item, availableCategories: availableCategories) { category in
                viewModel.setCategory(category, forItem: item.id)
            } onRatingChanged: { rating in
                viewModel.setRating(rating, forItem: item.id)
            } onSave: { metadata in
                viewModel.applyReview(id: item.id, metadata: metadata)
                reviewingItem = nil
            } onCancel: {
                reviewingItem = nil
            }
        }
        .sheet(item: $renamingItem) { item in
            RenameSheet(currentTitle: item.metadata?.title ?? item.sourceURL.deletingPathExtension().lastPathComponent) { newTitle in
                viewModel.renameItem(id: item.id, title: newTitle)
                renamingItem = nil
            } onCancel: {
                renamingItem = nil
            }
        }
        .sheet(isPresented: Binding(
            get: { pendingBatchEditIDs != nil },
            set: { if !$0 { pendingBatchEditIDs = nil } }
        )) {
            if let ids = pendingBatchEditIDs {
                BatchEditWarningSheet(count: ids.count) {
                    pendingBatchEditIDs = nil
                } onConfirm: { suppress in
                    if suppress {
                        UserDefaults.standard.set(true, forKey: Self.batchWarningSuppressedKey)
                    }
                    pendingBatchEditIDs = nil
                    batchEditingIDs = ids
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { batchEditingIDs != nil },
            set: { if !$0 { batchEditingIDs = nil } }
        )) {
            if let ids = batchEditingIDs {
                BatchMediaInfoView(items: items.filter { ids.contains($0.id) }) { changes in
                    viewModel.applyBatchEdit(ids: ids, changes: changes)
                    batchEditingIDs = nil
                } onCancel: {
                    batchEditingIDs = nil
                }
            }
        }
    }

    // MARK: - Columnas extra (D-199)

    private var columnsStorageKey: String { "aura.visibleColumns.\(kindKey)" }

    private var kindKey: String {
        switch kind {
        case .music: return "music"
        case .video: return "video"
        case .photo: return "photo"
        case .unsupported: return "unsupported"
        }
    }

    private func loadVisibleColumns() {
        guard let raw = UserDefaults.standard.string(forKey: columnsStorageKey) else { return }
        visibleColumns = Set(raw.split(separator: ",").compactMap { ExtraColumn(rawValue: String($0)) })
    }

    private func toggleColumn(_ column: ExtraColumn) {
        if visibleColumns.contains(column) {
            visibleColumns.remove(column)
        } else {
            visibleColumns.insert(column)
        }
        UserDefaults.standard.set(visibleColumns.map(\.rawValue).joined(separator: ","), forKey: columnsStorageKey)
    }

    private var columnsBar: some View {
        HStack {
            LibrarySearchField(scopeTitle: searchScopeTitle, text: $searchText)
            Spacer()
            Menu {
                ForEach(ExtraColumn.allCases.filter { $0.isApplicable(to: kind) }) { column in
                    Button {
                        toggleColumn(column)
                    } label: {
                        if visibleColumns.contains(column) {
                            Label(column.displayName, systemImage: "checkmark")
                        } else {
                            Text(column.displayName)
                        }
                    }
                }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Elegir qué columnas mostrar")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    // MARK: - Edicion en lote (D-218)

    private static let batchWarningSuppressedKey = "aura.batchEditWarningSuppressed"

    private func startBatchEdit(ids: Set<UUID>) {
        if UserDefaults.standard.bool(forKey: Self.batchWarningSuppressedKey) {
            batchEditingIDs = ids
        } else {
            pendingBatchEditIDs = ids
        }
    }

    // MARK: - Oferta de relectura de etiquetas (PLAN-studio-ux.md §2/P1)

    /// Se ofrece UNA sola vez (`AppPreferences.legacyMetadataBannerShown`)
    /// la primera vez que se carga una biblioteca con musica despues de
    /// este cambio -- "Ahora no" no vuelve a preguntar, la accion sigue
    /// disponible a mano en el menu contextual ("Volver a leer etiquetas
    /// del archivo").
    @ViewBuilder
    private var legacyMetadataRereadBanner: some View {
        if let count = viewModel.legacyMetadataRereadOfferCount, !isEnriching {
            HStack(spacing: 12) {
                Text("Aura Studio ahora lee mejor las etiquetas de tus archivos. ¿Quieres volver a leer las \(count) canción(es) de tu biblioteca?")
                    .font(.callout)
                Spacer()
                Button("Ahora no") {
                    viewModel.dismissLegacyMetadataRereadOffer()
                }
                Button("Volver a leer") {
                    runEnrichment(busyText: "Leyendo etiquetas del archivo...") {
                        await viewModel.acceptLegacyMetadataRereadOffer()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    /// PLAN-sync-media-hardening.md PARTE 3A: un solo banner persistente
    /// en vez del mismo párrafo largo repetido por cada fila de video en
    /// cola sin ffmpeg instalado -- ver `hasVideosWaitingOnFFmpeg`/
    /// `retryVideosWaitingOnFFmpeg` en `LibraryViewModel`.
    @ViewBuilder
    private var ffmpegMissingBanner: some View {
        if viewModel.hasVideosWaitingOnFFmpeg {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Para convertir videos al formato del iPod hace falta ffmpeg. Instálalo con Homebrew (\"brew install ffmpeg\") y vuelve a intentar.")
                    .font(.callout)
                Spacer()
                Button("Volver a intentar") {
                    Task { await viewModel.retryVideosWaitingOnFFmpeg() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    /// ST-012: una vez por instalacion, si hay entradas de Imagenes que
    /// parecen caratulas (`coverContaminationCandidates`), se ofrece
    /// revisarlas -- nunca se quita nada sin pasar por la hoja.
    @ViewBuilder
    private var coverContaminationBanner: some View {
        if let count = viewModel.coverContaminationOfferCount {
            HStack(spacing: 12) {
                Text("\(count) imagen(es) de tu biblioteca parecen carátulas de álbum, no fotos. ¿Quieres revisarlas?")
                    .font(.callout)
                Spacer()
                Button("Ahora no") {
                    viewModel.dismissCoverContaminationOffer()
                }
                Button("Revisar") {
                    reviewingCoverContamination = true
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .sheet(isPresented: $reviewingCoverContamination) {
                CoverContaminationSheet(library: viewModel) {
                    reviewingCoverContamination = false
                }
            }
        }
    }

    // MARK: - Busqueda de informacion en linea (D-203)

    private func runEnrichment(busyText: String = "Buscando información en línea...", _ action: @escaping () async -> Void) {
        guard !isEnriching else { return }
        enrichmentBusyText = busyText
        isEnriching = true
        Task {
            await action()
            isEnriching = false
        }
    }

    @ViewBuilder
    private var enrichmentBanner: some View {
        if isEnriching {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(enrichmentBusyText)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 8)
        } else if let summary = viewModel.lastEnrichmentSummary {
            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
    }

    // MARK: - Tabla

    @ViewBuilder
    private var table: some View {
        switch kind {
        case .music: musicTable
        case .video: mediaTable(showsArtistAlbumGenre: false)
        case .photo, .unsupported: mediaTable(showsArtistAlbumGenre: false)
        }
    }

    /// ST-030: columnas de musica dinamicas. `TableColumnForEach`
    /// (macOS 14.4) declara una columna por cada entrada de
    /// `preferences.musicVisibleColumns`, en ese orden -- ya no rige el
    /// limite de 10 slots de `TableColumnBuilder` (D-199), que era lo
    /// que dejaba "Artista del álbum" y compañia fuera del menu "+".
    /// Título sigue fija y primera; el resto lo decide el usuario en
    /// "Opciones de visualización". Cada columna ordena con el
    /// comparador que define `MusicTableColumn.comparator(order:)`.
    private var musicTable: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("") { row in checkboxCell(row) }
                .width(22)
            TableColumn("Título", value: \.title) { row in Text(row.title) }
                // D-202 (encargo del dueño): `Table` nativo no soporta
                // columnas "congeladas" al hacer scroll horizontal --
                // en vez de una reescritura grande y riesgosa, se le da
                // un minimo generoso para que casi nunca haga falta
                // encogerla, y la barra de scroll horizontal (ya
                // automatica en NSScrollView) se encarga del resto.
                .width(min: 180, ideal: 220)
            TableColumnForEach(preferences.musicVisibleColumns) { column in
                TableColumn(column.headerTitle, sortUsing: column.comparator(order: .forward)) { row in
                    musicCell(column, row)
                }
                .width(min: column.minWidth, ideal: column.idealWidth)
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in contextMenuContent(for: ids) }
        // Clic derecho sobre los encabezados: mismo menu que el boton
        // de la barra (`musicHeaderMenuBar`).
        .overlay(alignment: .topLeading) {
            TableHeaderMenuInstaller(entries: { headerMenuEntries })
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func musicCell(_ column: MusicTableColumn, _ row: MediaTableRow) -> some View {
        switch column {
        case .album: Text(row.album)
        case .albumArtist: Text(row.albumArtist)
        case .artist: Text(row.artist)
        case .composer: Text(row.composer)
        case .discNumber: Text(row.discNumberText)
        case .duration: Text(row.durationText)
        case .genre: Text(row.genre)
        case .trackNumber: Text(row.trackNumberText)
        case .year: Text(row.year)
        case .favorite: favoriteCell(row)
        case .rating: Text(row.ratingText)
        case .dateAdded: Text(row.addedAtText)
        case .fileFormat: Text(row.fileFormat)
        case .fileSize: Text(row.fileSizeText)
        case .status: statusCell(row.item)
        }
    }

    /// Estrella como en Music.app: llena si es favorito, vacia y tenue
    /// si no; un clic alterna sin abrir nada.
    private func favoriteCell(_ row: MediaTableRow) -> some View {
        Button {
            viewModel.toggleFavorite(id: row.id)
        } label: {
            Image(systemName: row.isFavorite ? "star.fill" : "star")
                .foregroundStyle(row.isFavorite ? AuraColors.light.accent : Color.secondary.opacity(0.35))
        }
        .buttonStyle(.plain)
        .help(row.isFavorite ? "Quitar de favoritos" : "Marcar como favorito")
    }

    // MARK: - Menu de encabezado (ST-030)

    /// Las entradas del menu de clic derecho sobre los encabezados y del
    /// boton de la barra: filtro (Todas / Solo favoritos), submenu de
    /// orden con el sentido, y la ventana de opciones.
    private var headerMenuEntries: [TableHeaderMenuEntry] {
        let onlyFavorites = preferences.musicShowOnlyFavorites
        var sortEntries: [TableHeaderMenuEntry] = MusicSortField.menuFields.map { field in
            .item(title: field.title, checked: preferences.musicSortField == field) {
                preferences.musicSortField = field
            }
        }
        sortEntries.append(.separator)
        sortEntries.append(.item(title: "Ascendente", checked: preferences.musicSortAscending) {
            preferences.musicSortAscending = true
        })
        sortEntries.append(.item(title: "Descendente", checked: !preferences.musicSortAscending) {
            preferences.musicSortAscending = false
        })
        return [
            .item(title: "Todas las canciones", checked: !onlyFavorites) {
                preferences.musicShowOnlyFavorites = false
            },
            .item(title: "Solo favoritos", checked: onlyFavorites) {
                preferences.musicShowOnlyFavorites = true
            },
            .separator,
            .submenu(title: "Opciones para ordenar", symbol: "arrow.up.arrow.down", entries: sortEntries),
            .separator,
            .item(title: "Mostrar opciones de visualización", symbol: "gearshape") {
                showingViewOptions = true
            },
        ]
    }

    /// Cuando un filtro (búsqueda, "Solo favoritos") no deja nada, se
    /// dice -- una tabla vacía sin explicación parece un bug.
    private var emptyFilteredState: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "No hay favoritos todavía." : "Sin resultados para \"\(searchText)\".")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var musicHeaderMenuBar: some View {
        HStack(spacing: 8) {
            LibrarySearchField(scopeTitle: searchScopeTitle, text: $searchText)
            if preferences.musicShowOnlyFavorites {
                Label("Solo favoritos", systemImage: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                TableHeaderMenuContent(entries: headerMenuEntries)
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Filtrar, ordenar y elegir columnas (también con clic derecho sobre los encabezados)")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    /// El orden que se muestra vive en `sortOrder` (lo que `Table`
    /// entiende); el que se persiste vive en `AppPreferences`. Los dos
    /// se mantienen iguales sin ciclos: solo se escribe cuando difieren.
    private func applySortOrderFromPreferences() {
        guard kind == .music else { return }
        let wanted = preferences.musicSortField.comparator(order: preferences.musicSortAscending ? .forward : .reverse)
        if let current = sortOrder.first, current.keyPath == wanted.keyPath, current.order == wanted.order { return }
        sortOrder = [wanted]
    }

    private func storeSortOrderInPreferences() {
        guard kind == .music, let first = sortOrder.first,
              let field = MusicSortField(keyPath: first.keyPath) else { return }
        if preferences.musicSortField != field { preferences.musicSortField = field }
        let ascending = first.order == .forward
        if preferences.musicSortAscending != ascending { preferences.musicSortAscending = ascending }
    }

    /// Video y fotos comparten forma (Categoría en vez de Artista/Álbum/
    /// Género) -- `showsArtistAlbumGenre` queda como parametro por si
    /// alguno de los dos necesita divergir despues, aunque hoy ambos lo
    /// pasan en `false`. Con 5 columnas fijas quedan 5 slots libres
    /// (mismo limite de 10 explicado arriba) -- hoy solo se ofrecen
    /// Formato/Tamaño, con espacio de sobra para agregar mas despues.
    private func mediaTable(showsArtistAlbumGenre: Bool) -> some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("") { row in checkboxCell(row) }
                .width(22)
            TableColumn("Título", value: \.title) { row in Text(row.title) }
                .width(min: 180, ideal: 280)
            TableColumn("Categoría", value: \.category) { row in Text(row.category.isEmpty ? "Sin categoría" : row.category) }
                .width(min: 90, ideal: 130)
            TableColumn("Duración", value: \.durationSeconds) { row in Text(row.durationText) }
                .width(min: 50, ideal: 64)
            if visibleColumns.contains(.fileFormat) {
                TableColumn("Formato", value: \.fileFormat) { row in Text(row.fileFormat) }
                    .width(min: 50, ideal: 60)
            }
            if visibleColumns.contains(.fileSize) {
                TableColumn("Tamaño", value: \.fileSizeBytes) { row in Text(row.fileSizeText) }
                    .width(min: 60, ideal: 70)
            }
            TableColumn("Estado", value: \.statusRank) { row in statusCell(row.item) }
                // D-215: "Sincronizado" no entraba comodo en el ancho
                // viejo (pensado solo para el icono + un check).
                .width(min: 90, ideal: 120)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in contextMenuContent(for: ids) }
    }

    private func checkboxCell(_ row: MediaTableRow) -> some View {
        Toggle("", isOn: Binding(
            get: { selection.contains(row.id) },
            set: { checked in
                if checked { selection.insert(row.id) } else { selection.remove(row.id) }
            }
        ))
        .labelsHidden()
    }

    @ViewBuilder
    private func statusCell(_ item: LibraryItem) -> some View {
        switch item.status {
        case .queued:
            Text("En cola").foregroundStyle(.secondary)
        case .enriching:
            ProgressView().controlSize(.small)
        case .transcoding(let progress):
            ProgressView(value: progress).frame(width: 60)
        case .ready:
            // PLAN-general-sync.md §1.6: con `deviceSyncIndex` listo
            // (iPod conectado y ya verificado), la columna muestra los
            // 5 estados reales en vez del "Listo"/"Sincronizado" viejo
            // (D-202/D-215, que solo miraba el manifiesto -- no
            // distinguía "con cambios" de "modificado en el iPod").
            // Sin dispositivo, o mientras `verifyDevice` todavía corre
            // (`deviceSyncIndex == nil`), se queda en "Listo".
            if let index = viewModel.deviceSyncIndex {
                syncStateCell(index.state(forSourcePath: item.sourceURL.path))
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Listo").foregroundStyle(.secondary)
                }
            }
        case .needsReview:
            Button {
                reviewingItem = item
            } label: {
                Label("Revisar", systemImage: "exclamationmark.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.orange)
        case .failed(let message):
            Label(message, systemImage: "xmark.circle")
                .foregroundStyle(.red)
                .help(message)
        }
    }

    /// Los 5 estados de `SyncItemState` (PLAN-general-sync.md §4.1) --
    /// plano, símbolo + texto, sin fondo ni translucidez (§1.6, mismo
    /// criterio que el resto de la tabla).
    @ViewBuilder
    private func syncStateCell(_ state: SyncItemState) -> some View {
        switch state {
        case .synced:
            Label("Sincronizado", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        case .pending:
            Label("Pendiente", systemImage: "arrow.up.circle")
                .foregroundStyle(AuraColors.light.accent)
        case .changedLocally:
            Label("Con cambios", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(AuraColors.light.accent)
        case .modifiedOnDevice:
            Label("Modificado en el iPod", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .help("Este archivo cambió en el iPod fuera de Aura Studio. La próxima vez que sincronices podrás elegir si lo conservas o lo reemplazas con la versión de tu biblioteca.")
        case .removedFromDevice:
            Label("Quitado del iPod", systemImage: "minus.circle")
                .foregroundStyle(.secondary)
                .help("Se quitó del iPod fuera de Aura Studio -- no se vuelve a copiar solo. Usa \"Sincronizar la selección\" en el menú contextual para volver a copiarlo.")
        }
    }

    // MARK: - Menu contextual (D-198)

    @ViewBuilder
    private func contextMenuContent(for ids: Set<UUID>) -> some View {
        let targetIDs = ids.isEmpty ? selection : ids
        let targetItems = items.filter { targetIDs.contains($0.id) }

        if kind == .music, !targetItems.isEmpty {
            Button("Buscar información en línea") {
                runEnrichment { await viewModel.reenrichOnline(ids: targetIDs, fetchAlbumInfo: true, fetchLyrics: false) }
            }
            Button("Buscar letra") {
                runEnrichment { await viewModel.reenrichOnline(ids: targetIDs, fetchAlbumInfo: false, fetchLyrics: true) }
            }
            Button("Volver a leer etiquetas del archivo") {
                runEnrichment(busyText: "Leyendo etiquetas del archivo...") {
                    await viewModel.rereadLocalTags(ids: targetIDs)
                }
            }
            .help("Vuelve a leer título, artista, álbum, año, género, autor, N.º de pista y carátula directamente del archivo original")
            Button("Eliminar carátula") {
                for item in targetItems { viewModel.clearCoverArt(id: item.id) }
            }
            .disabled(!targetItems.contains { $0.metadata?.coverArtData != nil })

            Divider()

            // ST-030: favorito. Si en la seleccion hay alguna que no lo
            // es, la accion marca todas; si todas lo son, las quita.
            if targetItems.contains(where: { $0.metadata?.isFavorite != true }) {
                Button("Marcar como favorito") {
                    viewModel.setFavorite(true, forItems: Set(targetItems.map(\.id)))
                }
            } else {
                Button("Quitar de favoritos") {
                    viewModel.setFavorite(false, forItems: Set(targetItems.map(\.id)))
                }
            }

            Divider()

            if let reference = targetItems.first {
                if let album = reference.metadata?.album {
                    Button("Seleccionar canciones del mismo álbum") {
                        selection = Set(allItemsOfKind.filter { $0.metadata?.album == album }.map(\.id))
                    }
                }
                if let artist = reference.metadata?.artist {
                    Button("Seleccionar canciones del mismo artista") {
                        selection = Set(allItemsOfKind.filter { $0.metadata?.artist == artist }.map(\.id))
                    }
                }
            }

            Divider()
        }

        if kind == .video, !targetItems.isEmpty {
            // ST-033: posters de peliculas/series (TMDB + fanart.tv).
            Button("Buscar póster en línea") {
                runEnrichment(busyText: "Buscando pósters en línea...") {
                    await viewModel.fetchVideoPosters(ids: Set(targetItems.map(\.id)))
                }
            }
            .help("Busca el póster en TMDB y fanart.tv (necesita la API key de TMDB en Ajustes › Servicios) y lo copia junto al video en el iPod")
            Button("Quitar póster") {
                for item in targetItems { viewModel.clearVideoPoster(id: item.id) }
            }
            .disabled(!targetItems.contains { $0.metadata?.coverArtData != nil })
            Divider()
        }

        if let availableCategories, !targetItems.isEmpty {
            Menu("Cambiar categoría") {
                ForEach(availableCategories, id: \.self) { category in
                    Button(category) {
                        for item in targetItems { viewModel.setCategory(category, forItem: item.id) }
                    }
                }
            }
            Divider()
        }

        if targetItems.count == 1, let single = targetItems.first {
            Button("Cambiar nombre...") {
                renamingItem = single
            }
            Button("Más información...") {
                reviewingItem = single
            }
            Divider()
        } else if kind == .music, targetItems.count > 1 {
            // D-218: mismo lugar del menu que "Más información...",
            // pero para varias canciones -- dispara el aviso previo (o
            // se lo salta si el usuario ya dijo "No volver a mostrar").
            Button("Obtener información...") {
                startBatchEdit(ids: targetIDs)
            }
            Divider()
        }

        // PLAN-general-sync.md §6: atajo directo desde la tabla, sin ir
        // a General -- mismo camino que el boton de ahi (alcance
        // ".selection"), solo con los elementos LISTOS de esta seleccion
        // puntual (no toda `viewModel.selectionForSync`, que puede
        // arrastrar seleccion vieja de otra vista si el usuario no volvio
        // a tocar nada aca desde que cambio de sección).
        if let device, device.isAura, !targetItems.isEmpty {
            Button("Sincronizar la selección") {
                Task {
                    await viewModel.sync(toVolumeAt: URL(fileURLWithPath: device.mountPath),
                                         scope: .selection(targetIDs))
                }
            }
            .disabled(!targetItems.contains { $0.status == .ready })
            Divider()
        }

        if !targetItems.isEmpty {
            Button("Mostrar en Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(targetItems.map(\.sourceURL))
            }
            Divider()
        }

        Button("Eliminar", role: .destructive) {
            viewModel.deleteItems(ids: targetIDs)
            selection.subtract(targetIDs)
        }
        .disabled(targetItems.isEmpty)
    }

    private func categoryFilterBar(_ categories: [String]) -> some View {
        HStack(spacing: 8) {
            filterChip(label: "Todas", isSelected: categoryFilter == nil) { categoryFilter = nil }
            ForEach(categories, id: \.self) { category in
                filterChip(label: category, isSelected: categoryFilter == category) {
                    categoryFilter = category
                }
            }
            Spacer()
        }
        .padding([.horizontal, .top], 16)
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .background(Capsule().fill(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1)))
        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
    }

    private var title: String {
        switch kind {
        case .music: return "Musica"
        case .video: return "Video"
        case .photo: return "Fotos"
        case .unsupported: return "Otros"
        }
    }

    private var prompt: String {
        switch kind {
        case .music: return "Suelta canciones aqui"
        case .video: return "Suelta videos aqui"
        case .photo: return "Suelta fotos aqui"
        case .unsupported: return "Suelta archivos aqui"
        }
    }

    private var dropZone: some View {
        DropZone(isTargeted: $isTargeted, prompt: prompt, symbol: symbolName) { urls in
            // ST-012: cada seccion ingiere solo su tipo -- un cover.jpg
            // dentro de un album soltado en Musica es caratula, no foto.
            viewModel.addDroppedFiles(urls, into: kind)
            Task { await viewModel.processAll() }
        }
    }

    private var symbolName: String {
        switch kind {
        case .music: return "music.note"
        case .video: return "play.rectangle"
        case .photo: return "photo"
        case .unsupported: return "questionmark"
        }
    }
}

/// Fila plana para `Table` (D-198): campos NO opcionales (vacio/0 en
/// vez de nil) porque `KeyPathComparator` necesita `Comparable` real
/// para ordenar por encabezado -- Optional no lo es. Envuelve el
/// `LibraryItem` original para las acciones que si necesitan el modelo
/// completo (`row.item`).
struct MediaTableRow: Identifiable {
    let item: LibraryItem
    /// Estado contra el iPod conectado (nil sin dispositivo o mientras
    /// se verifica) -- se resuelve al armar la fila para que la columna
    /// "Estado" tenga una clave ordenable (ST-030).
    var syncState: SyncItemState? = nil
    var id: UUID { item.id }

    /// Clave de orden de la columna "Estado" (ST-030): lo que ya esta
    /// en el iPod primero, despues lo que falta por hacer, y al final
    /// lo que necesita atencion -- asi "ordenar por Estado" agrupa lo
    /// pendiente y lo problematico en vez de mezclarlo. El texto que
    /// se muestra sigue saliendo de `statusCell`; esto es solo el rango.
    var statusRank: Int {
        switch item.status {
        case .ready:
            switch syncState {
            case .synced: return 0
            case .none: return 1              // "Listo" (sin iPod)
            case .pending: return 2
            case .changedLocally: return 3
            case .modifiedOnDevice: return 4
            case .removedFromDevice: return 5
            }
        case .queued: return 6
        case .enriching: return 7
        case .transcoding: return 8
        case .needsReview: return 9
        case .failed: return 10
        }
    }
    var title: String { item.metadata?.title ?? item.sourceURL.deletingPathExtension().lastPathComponent }
    var artist: String { item.metadata?.artist ?? "" }
    var album: String { item.metadata?.album ?? "" }
    var genre: String { item.metadata?.genre ?? "" }
    var category: String { item.category ?? "" }
    var durationSeconds: Double { item.metadata?.durationSeconds ?? 0 }

    var durationText: String {
        guard let seconds = item.metadata?.durationSeconds, seconds > 0 else { return "--" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Columnas de musica (ST-030)

    var albumArtist: String { item.metadata?.albumArtist ?? "" }
    var composer: String { item.metadata?.composer ?? "" }
    var discNumberSort: Int { item.metadata?.discNumber ?? 0 }
    var discNumberText: String { item.metadata?.discNumber.map(String.init) ?? "" }
    var isFavorite: Bool { item.metadata?.isFavorite ?? false }
    /// Ascendente = favoritos primero (0 antes que 1).
    var favoriteRank: Int { isFavorite ? 0 : 1 }
    var addedAtSort: Date { item.addedAt ?? .distantPast }
    var addedAtText: String {
        guard let date = item.addedAt else { return "" }
        return Self.addedAtFormatter.string(from: date)
    }
    private static let addedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    // MARK: - Columnas extra (D-199)

    var trackNumberSort: Int { item.metadata?.trackNumber ?? 0 }
    var trackNumberText: String { item.metadata?.trackNumber.map(String.init) ?? "" }
    var year: String { item.metadata?.year ?? "" }
    var ratingValue: Int { item.metadata?.rating ?? 0 }
    var ratingText: String {
        guard let rating = item.metadata?.rating, rating > 0 else { return "" }
        return String(repeating: "★", count: rating)
    }
    var fileFormat: String { item.sourceURL.pathExtension.uppercased() }
    var fileSizeBytes: Int64 {
        (try? FileManager.default.attributesOfItem(atPath: item.sourceURL.path)[.size] as? Int64) ?? 0
    }
    var fileSizeText: String {
        let bytes = fileSizeBytes
        guard bytes > 0 else { return "--" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Columnas opcionales que el boton "+" de la barra de herramientas
/// deja agregar/quitar en Video y Fotos (D-199) -- persisten por tipo de
/// medio en UserDefaults (`MediaSectionView.columnsStorageKey`). Musica
/// ya no pasa por aca: sus columnas son `MusicTableColumn` (ST-030).
enum ExtraColumn: String, CaseIterable, Identifiable {
    case fileFormat, fileSize

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fileFormat: return "Formato"
        case .fileSize: return "Tamaño"
        }
    }

    func isApplicable(to kind: LibraryItemKind) -> Bool {
        kind != .music
    }
}

private struct RenameSheet: View {
    let currentTitle: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String

    init(currentTitle: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.currentTitle = currentTitle
        self.onSave = onSave
        self.onCancel = onCancel
        _text = State(initialValue: currentTitle)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cambiar nombre").font(.title3.bold())
            TextField("Nombre", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if !trimmed.isEmpty { onSave(trimmed) } }
            HStack {
                Spacer()
                Button("Cancelar", action: onCancel)
                Button("Guardar") { onSave(trimmed) }
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

private struct DropZone: View {
    @Binding var isTargeted: Bool
    let prompt: String
    let symbol: String
    let onDrop: ([URL]) -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
            .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: symbol).font(.largeTitle)
                    Text(prompt)
                }
                .foregroundStyle(.secondary)
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                loadURLs(from: providers)
                return true
            }
    }

    /// Los items del drop se resuelven de forma asincronica, cada uno en
    /// su propio hilo y en cualquier orden. Antes esto acumulaba en un
    /// `var urls` capturado por todos los callbacks a la vez: carrera de
    /// datos real (soltar varios archivos podia perder alguno o corromper
    /// el array) que solo denuncia `xcodebuild` con la concurrencia
    /// estricta de Swift 6, no `swift build` -- mismo caso que D-034.
    ///
    /// `DropCollector` serializa la escritura con un lock y ademas guarda
    /// cada URL en la posicion de SU provider, asi el orden en que el
    /// usuario solto los archivos se respeta aunque los callbacks
    /// vuelvan desordenados (importa al soltar un album entero).
    private func loadURLs(from providers: [NSItemProvider]) {
        let collector = DropCollector(count: providers.count)
        let group = DispatchGroup()
        for (index, provider) in providers.enumerated() {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { collector.set(url, at: index) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            onDrop(collector.ordered())
        }
    }
}

private final class DropCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var slots: [URL?]

    init(count: Int) {
        slots = Array(repeating: nil, count: count)
    }

    func set(_ url: URL, at index: Int) {
        lock.lock(); defer { lock.unlock() }
        guard slots.indices.contains(index) else { return }
        slots[index] = url
    }

    func ordered() -> [URL] {
        lock.lock(); defer { lock.unlock() }
        return slots.compactMap { $0 }
    }
}

// MARK: - Comparadores por columna (ST-030)

extension MusicTableColumn {
    /// Clave con la que ordena esta columna. `Table` compara comparadores
    /// por `keyPath`, asi que sirve tanto para construir el comparador
    /// como para reconocer, cuando el usuario hace clic en un
    /// encabezado, que columna eligio (`MusicSortField(keyPath:)`).
    var sortKeyPath: PartialKeyPath<MediaTableRow> {
        switch self {
        case .album: return \MediaTableRow.album
        case .albumArtist: return \MediaTableRow.albumArtist
        case .artist: return \MediaTableRow.artist
        case .composer: return \MediaTableRow.composer
        case .discNumber: return \MediaTableRow.discNumberSort
        case .duration: return \MediaTableRow.durationSeconds
        case .genre: return \MediaTableRow.genre
        case .trackNumber: return \MediaTableRow.trackNumberSort
        case .year: return \MediaTableRow.year
        case .favorite: return \MediaTableRow.favoriteRank
        case .rating: return \MediaTableRow.ratingValue
        case .dateAdded: return \MediaTableRow.addedAtSort
        case .fileFormat: return \MediaTableRow.fileFormat
        case .fileSize: return \MediaTableRow.fileSizeBytes
        case .status: return \MediaTableRow.statusRank
        }
    }

    func comparator(order: SortOrder) -> KeyPathComparator<MediaTableRow> {
        switch self {
        case .album: return KeyPathComparator(\.album, comparator: .localizedStandard, order: order)
        case .albumArtist: return KeyPathComparator(\.albumArtist, comparator: .localizedStandard, order: order)
        case .artist: return KeyPathComparator(\.artist, comparator: .localizedStandard, order: order)
        case .composer: return KeyPathComparator(\.composer, comparator: .localizedStandard, order: order)
        case .discNumber: return KeyPathComparator(\.discNumberSort, order: order)
        case .duration: return KeyPathComparator(\.durationSeconds, order: order)
        case .genre: return KeyPathComparator(\.genre, comparator: .localizedStandard, order: order)
        case .trackNumber: return KeyPathComparator(\.trackNumberSort, order: order)
        case .year: return KeyPathComparator(\.year, order: order)
        case .favorite: return KeyPathComparator(\.favoriteRank, order: order)
        case .rating: return KeyPathComparator(\.ratingValue, order: order)
        case .dateAdded: return KeyPathComparator(\.addedAtSort, order: order)
        case .fileFormat: return KeyPathComparator(\.fileFormat, order: order)
        case .fileSize: return KeyPathComparator(\.fileSizeBytes, order: order)
        case .status: return KeyPathComparator(\.statusRank, order: order)
        }
    }
}

extension MusicSortField {
    var sortKeyPath: PartialKeyPath<MediaTableRow> {
        switch self {
        case .title: return \MediaTableRow.title
        case .column(let column): return column.sortKeyPath
        }
    }

    func comparator(order: SortOrder) -> KeyPathComparator<MediaTableRow> {
        switch self {
        case .title: return KeyPathComparator(\.title, comparator: .localizedStandard, order: order)
        case .column(let column): return column.comparator(order: order)
        }
    }

    /// Reconoce el criterio a partir del comparador que `Table` deja en
    /// `sortOrder` tras un clic en un encabezado. nil para columnas que
    /// no son criterio persistible (no deberia pasar: todas lo son).
    init?(keyPath: PartialKeyPath<MediaTableRow>) {
        if keyPath == \MediaTableRow.title { self = .title; return }
        if let column = MusicTableColumn.allCases.first(where: { $0.sortKeyPath == keyPath }) {
            self = .column(column)
            return
        }
        return nil
    }
}
