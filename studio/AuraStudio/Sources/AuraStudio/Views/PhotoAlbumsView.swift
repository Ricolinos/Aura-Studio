import SwiftUI

/// Álbumes de fotos dentro de UNA colección (Fotos/Imágenes/IA) --
/// encargo del dueño (2026-08-18): "que sea muy similar en cuestión de
/// uso a lo que ofrecía el iPod Classic original". El iPod Classic
/// mostraba los álbumes como carpetas con una portada, y adentro una
/// CUADRÍCULA de miniaturas (no una tabla) -- a diferencia de
/// Música/Video (D-193: interfaz de gestión, tabla + Vista Previa de
/// Finder), acá el detalle también es una cuadrícula de miniaturas
/// reales, tocar una la selecciona y espacio la abre en Vista Previa,
/// mismo gesto de siempre.
///
/// Solo LOCAL: los álbumes nunca llegan al iPod (D-192, `/Photos` sigue
/// plano) -- esto es organización de Aura Studio únicamente.
struct PhotoAlbumsView: View {
    @ObservedObject var viewModel: LibraryViewModel
    let device: AuraDevice?
    @ObservedObject var preferences: AppPreferences
    /// "Fotos" / "Imágenes" / "IA" -- la colección exacta que esta
    /// instancia muestra (una por subsección de la barra lateral).
    let category: String
    /// PLAN-studio-rendimiento-2.md Fase 1 (ST-181): las cuadrículas
    /// también publican su selección -- ver `SelectionStore`.
    @ObservedObject var selectionStore: SelectionStore

    @State private var albums: [PhotoAlbumGroup] = []
    @State private var searchText = ""
    @State private var selectedAlbumID: String?
    /// Selección múltiple de álbumes (encargo del dueño, 2026-08-19).
    @State private var selection = GridSelection<String>()
    /// Selección múltiple de fotos dentro de un álbum abierto -- se
    /// limpia al volver a la cuadrícula de álbumes. Espacio con
    /// exactamente 1 seleccionada abre Vista Previa (mismo gesto de
    /// siempre); con varias, no hace nada (no hay "vista previa
    /// múltiple" con este espacio de nombres de Quick Look).
    @State private var photoSelection = GridSelection<UUID>()
    /// PLAN-studio-rendimiento-2.md Fase 1 (ST-181): lo visible y su
    /// `GridOrder`, calculados una sola vez por cambio real de entrada.
    @StateObject private var gridModel = GridModel<PhotoAlbumGroup>()
    /// El resumen de la barra de estado, memoizado -- `GridStatusModel`.
    @StateObject private var statusModel = GridStatusModel()
    /// Identidad de esta vista como publicadora de `selectionStore`.
    @State private var publisherID = UUID()
    /// PLAN-studio-rendimiento.md Fase 2 punto 2: construido una vez
    /// por cambio del álbum visible, nunca en el gesto de tap.
    @State private var photoOrder = GridOrder<UUID>.empty
    @State private var renamingAlbum: PhotoAlbumGroup?
    @State private var quickLook = QuickLookCoordinator()
    @State private var isTargeted = false
    /// Como en `MediaSectionView`: soltar ≥2 archivos (o una carpeta)
    /// sobre la cuadrícula de álbumes pregunta el nombre; un archivo
    /// suelto entra sin álbum. Soltar DENTRO de un álbum ya abierto no
    /// pregunta nada -- ya se sabe a cuál álbum va.
    @State private var pendingAlbumNameURLs: [URL]?

    private var visibleAlbums: [PhotoAlbumGroup] { gridModel.visible }

    /// El cálculo en sí -- lo llama `GridModel.recompute`, nunca el `body`.
    private func computeVisible(_ groups: [PhotoAlbumGroup]) -> [PhotoAlbumGroup] {
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return groups }
        return groups.filter { LibrarySearch.matches($0.title, needle) }
    }

    private var selectedAlbum: PhotoAlbumGroup? {
        guard let selectedAlbumID else { return nil }
        return albums.first { $0.id == selectedAlbumID }
    }

    var body: some View {
        Group {
            if let album = selectedAlbum {
                albumDetail(album)
            } else {
                grid
            }
        }
        .navigationTitle(category)
        .libraryStatus(statusModel.summary)
        .onAppear(perform: rebuild)
        .onReceive(viewModel.$items) { _ in rebuild() }
        // PLAN-studio-rendimiento-2.md Fase 1 (ST-181): fuera del `body`.
        .onChange(of: searchText) { refreshGrid() }
        .onChange(of: selectedAlbumID) { refreshGrid() }
        .onChange(of: selection) { _, _ in
            refreshStatusSelection()
            publishSelection()
        }
        .onChange(of: photoSelection) { _, _ in
            refreshStatusSelection()
            publishSelection()
        }
        .onDisappear { selectionStore.clear(from: publisherID) }
        .sheet(item: $renamingAlbum) { album in
            AlbumRenameSheet(currentTitle: album.isUnknown ? "" : album.title) { newName in
                viewModel.renamePhotoAlbum(items: Set(album.items.map(\.id)), to: newName)
                renamingAlbum = nil
            } onCancel: {
                renamingAlbum = nil
            }
        }
        .sheet(isPresented: Binding(
            get: { pendingAlbumNameURLs != nil },
            set: { if !$0 { pendingAlbumNameURLs = nil } }
        )) {
            if let urls = pendingAlbumNameURLs {
                PhotoAlbumNameSheet(suggestedAlbumName: suggestedAlbumName(for: urls)) { albumName in
                    viewModel.addDroppedFiles(urls, into: .photo, category: category, photoAlbum: albumName)
                    Task { await viewModel.processAll() }
                    pendingAlbumNameURLs = nil
                }
            }
        }
    }

    /// Igual que `MediaSectionView.suggestedAlbumName(for:)`: una sola
    /// carpeta soltada sugiere su propio nombre.
    private func suggestedAlbumName(for urls: [URL]) -> String? {
        guard urls.count == 1, DroppedURLExpander.isDirectory(urls[0]) else { return nil }
        return urls[0].lastPathComponent
    }

    /// Soltar sobre la cuadrícula de álbumes: ≥2 archivos o una carpeta
    /// preguntan nombre; un archivo suelto entra sin álbum.
    private func handleGridDrop(_ urls: [URL]) {
        let expanded = DroppedURLExpander.expand(urls)
        let droppedAFolder = urls.contains { DroppedURLExpander.isDirectory($0) }
        if expanded.count >= 2 || droppedAFolder {
            pendingAlbumNameURLs = urls
        } else {
            viewModel.addDroppedFiles(urls, into: .photo, category: category)
            Task { await viewModel.processAll() }
        }
    }

    /// Soltar DENTRO de un álbum ya abierto: sin diálogo, va directo a
    /// ese álbum (o "Sin álbum" si `album.isUnknown`).
    private func handleDetailDrop(_ urls: [URL], album: PhotoAlbumGroup) {
        viewModel.addDroppedFiles(urls, into: .photo, category: category, photoAlbum: album.isUnknown ? nil : album.title)
        Task { await viewModel.processAll() }
    }

    /// ST-063: barra de estado -- álbumes/fotos en la cuadrícula; con
    /// un álbum abierto, sus fotos y las seleccionadas.
    /// PLAN-studio-rendimiento-2.md Fase 1 (ST-181): se calcula fuera
    /// del `body`, con el total memoizado -- ver `GridStatusModel`.
    private func refreshStatusTotal() {
        if let album = selectedAlbum {
            statusModel.recomputeTotal { LibraryStats.photoAlbumTotal(album) }
        } else {
            let visible = gridModel.visible
            statusModel.recomputeTotal { LibraryStats.photoAlbumsTotal(visible) }
        }
        refreshStatusSelection()
    }

    private func refreshStatusSelection() {
        if let album = selectedAlbum {
            let selected = album.items.filter { photoSelection.isSelected($0.id) }
            let totalCount = album.count
            statusModel.recomputeSelection(cost: selected.count) {
                LibraryStats.photoSelectionText(selected: selected, totalCount: totalCount)
            }
        } else {
            let visible = gridModel.visible
            let selected = visible.filter { selection.isSelected($0.id) }
            let totalCount = visible.count
            statusModel.recomputeSelection(cost: selected.reduce(0) { $0 + $1.count }) {
                LibraryStats.photoAlbumsSelectionText(selected: selected, totalCount: totalCount)
            }
        }
    }

    /// ST-181: lo seleccionado (álbumes completos, o fotos sueltas con
    /// un álbum abierto) llega a `selectionStore`.
    private func publishSelection() {
        let ids: [UUID]
        if let album = selectedAlbum {
            ids = album.items.filter { photoSelection.isSelected($0.id) }.map(\.id)
        } else {
            ids = gridModel.visible
                .filter { selection.isSelected($0.id) }
                .flatMap { $0.items.map(\.id) }
        }
        selectionStore.replace(with: Set(ids), from: publisherID)
    }

    private func rebuild() {
        let groups = LibraryGrouping.photoAlbums(from: viewModel.items, category: category)
        albums = groups
        if let selectedAlbumID, !groups.contains(where: { $0.id == selectedAlbumID }) {
            self.selectedAlbumID = nil
        }
        selection.pruneMissing(from: Set(groups.map(\.id)))
        if let id = selectedAlbumID, let album = groups.first(where: { $0.id == id }) {
            photoSelection.pruneMissing(from: Set(album.items.map(\.id)))
        } else {
            photoSelection.clear()
        }
        refreshGrid(groups)
    }

    private func refreshGrid(_ groups: [PhotoAlbumGroup]? = nil) {
        let source = groups ?? albums
        gridModel.recompute { computeVisible(source) }
        refreshStatusTotal()
        publishSelection()
    }

    /// Álbumes a los que aplica una acción disparada desde `album`: su
    /// selección completa si ya estaba seleccionado, o solo él si no
    /// (criterio Finder, ver `GridSelection.effectiveIDs`).
    private func effectiveAlbums(for album: PhotoAlbumGroup) -> [PhotoAlbumGroup] {
        let ids = selection.effectiveIDs(for: album.id)
        return albums.filter { ids.contains($0.id) }
    }

    private func effectivePhotos(for item: LibraryItem, in album: PhotoAlbumGroup) -> [LibraryItem] {
        let ids = photoSelection.effectiveIDs(for: item.id)
        return album.items.filter { ids.contains($0.id) }
    }

    // MARK: - Cuadrícula de álbumes

    private var grid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Spacer()
                LibrarySearchField(scopeTitle: category, text: $searchText)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if albums.isEmpty {
                DropZone(isTargeted: $isTargeted, prompt: "Suelta fotos aquí", symbol: "photo", onDrop: handleGridDrop)
                    .padding(24)
                    .frame(maxHeight: .infinity)
            } else {
                DropZone(isTargeted: $isTargeted, prompt: "Suelta fotos aquí", symbol: "photo", onDrop: handleGridDrop)
                    .frame(height: 80)
                    .padding([.horizontal, .top], 16)

                if visibleAlbums.isEmpty {
                    emptyState("Sin resultados para \"\(searchText)\".", detail: nil)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 24, alignment: .top)],
                                  alignment: .leading, spacing: 28) {
                            ForEach(visibleAlbums) { album in
                                PhotoAlbumCardView(album: album)
                                    .librarySelectionCheckbox(selection.isSelected(album.id)) {
                                        selection.toggle(album.id)
                                    }
                                    .onTapGesture(count: 2) { selectedAlbumID = album.id }
                                    .onTapGesture { selection.handleTap(album.id, order: gridModel.order) }
                                    .contextMenu { albumContextMenu(album) }
                                    .draggable(LibrarySelectionTransfer(itemIDs: effectiveAlbums(for: album).flatMap(\.items).map(\.id)))
                                    .help(album.title)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                    }
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
        .onKeyPress(keys: ["a"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            selection.selectAll(gridModel.order)
            return .handled
        }
    }

    private func emptyState(_ title: String, detail: String?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.stack")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).foregroundStyle(.secondary)
            if let detail {
                Text(detail).font(.callout).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    /// Menú contextual: si `album` forma parte de una selección
    /// múltiple, actúa sobre TODA la selección (encargo del dueño,
    /// 2026-08-19); si no, solo sobre `album`.
    @ViewBuilder
    private func albumContextMenu(_ album: PhotoAlbumGroup) -> some View {
        let targets = effectiveAlbums(for: album)
        let items = targets.flatMap(\.items)
        let plural = targets.count > 1
        let anyKnown = targets.contains { !$0.isUnknown }

        if !plural {
            Button("Abrir") { selectedAlbumID = album.id }
            Divider()
        }
        Menu("Cambiar categoría") {
            ForEach(preferences.photoCollections, id: \.self) { collection in
                Button(collection) {
                    viewModel.setCategory(collection, forItems: Set(items.map(\.id)))
                }
            }
        }
        .disabled(items.isEmpty)
        if anyKnown {
            Divider()
            if !plural {
                Button("Renombrar álbum...") { renamingAlbum = album }
            }
            Button(plural ? "Disolver álbumes" : "Disolver álbum", role: .destructive) {
                viewModel.dissolvePhotoAlbum(items: Set(items.map(\.id)))
            }
        }
        Divider()
        Button("Mostrar en Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(items.map(\.sourceURL))
        }
        Button("Eliminar fotos de la biblioteca", role: .destructive) {
            viewModel.deleteItems(ids: Set(items.map(\.id)))
        }
    }

    // MARK: - Detalle: cuadrícula de miniaturas (uso "a la iPod Classic")

    private func albumDetail(_ album: PhotoAlbumGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    selectedAlbumID = nil
                    photoSelection.clear()
                } label: {
                    Label(category, systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(AuraColors.light.accent)
                Spacer()
                if !album.isUnknown {
                    Menu {
                        albumContextMenu(album)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            HStack(spacing: 8) {
                Text(album.title)
                    .font(.title.bold())
                    .lineLimit(1)
                Text(album.count == 1 ? "1 foto" : "\(album.count) fotos")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 12)

            DropZone(isTargeted: $isTargeted, prompt: "Suelta fotos aquí para agregarlas a este álbum", symbol: "photo",
                     onDrop: { handleDetailDrop($0, album: album) })
                .frame(height: 70)
                .padding([.horizontal, .top], 16)

            if album.items.isEmpty {
                emptyState("Este álbum se quedó sin fotos.", detail: nil)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 12, alignment: .top)],
                              alignment: .leading, spacing: 12) {
                        ForEach(album.items) { item in
                            photoThumb(item, album: album)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .onKeyPress(.space) {
            guard photoSelection.selected.count == 1, let id = photoSelection.selected.first,
                  let item = album.items.first(where: { $0.id == id }) else { return .ignored }
            quickLook.toggle(for: item.sourceURL)
            return .handled
        }
        // PLAN-studio-rendimiento.md Fase 2: fotos de ESTE álbum
        // abierto. Pendiente de verificar interactivo con el dueño.
        .onAppear { photoOrder = GridOrder(album.items.map(\.id)) }
        .onChange(of: album.items.map(\.id)) { photoOrder = GridOrder($0) }
        .onKeyPress(.escape) {
            guard !photoSelection.selected.isEmpty else { return .ignored }
            photoSelection.clear()
            return .handled
        }
        .onKeyPress(keys: ["a"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            photoSelection.selectAll(photoOrder)
            return .handled
        }
    }

    private func photoThumb(_ item: LibraryItem, album: PhotoAlbumGroup) -> some View {
        let isSelected = photoSelection.isSelected(item.id)
        return CoverArtView(data: try? Data(contentsOf: item.preparedURL ?? item.sourceURL), side: 140,
                            cornerRadius: 6, placeholderSymbol: "photo")
            .librarySelectionCheckbox(isSelected, cornerRadius: 6) {
                photoSelection.toggle(item.id)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { quickLook.toggle(for: item.sourceURL) }
            .onTapGesture { photoSelection.handleTap(item.id, order: photoOrder) }
            .draggable(LibrarySelectionTransfer(itemIDs: effectivePhotos(for: item, in: album).map(\.id)))
            .contextMenu { photoContextMenu(item, album: album) }
    }

    /// Menú contextual: si `item` forma parte de una selección múltiple
    /// de fotos, actúa sobre TODA la selección (encargo del dueño,
    /// 2026-08-19); si no, solo sobre `item`.
    @ViewBuilder
    private func photoContextMenu(_ item: LibraryItem, album: PhotoAlbumGroup) -> some View {
        let targets = effectivePhotos(for: item, in: album)
        let plural = targets.count > 1

        if !plural {
            Button("Vista previa") { quickLook.toggle(for: item.sourceURL) }
            Divider()
        }
        Menu("Cambiar categoría") {
            ForEach(preferences.photoCollections, id: \.self) { collection in
                Button(collection) {
                    viewModel.setCategory(collection, forItems: Set(targets.map(\.id)))
                }
            }
        }
        Button("Quitar del álbum") {
            viewModel.dissolvePhotoAlbum(items: Set(targets.map(\.id)))
        }
        Button("Mostrar en Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(targets.map(\.sourceURL))
        }
        Divider()
        Button("Eliminar de la biblioteca", role: .destructive) {
            viewModel.deleteItems(ids: Set(targets.map(\.id)))
        }
    }
}

/// Hoja mínima para renombrar un álbum -- mismo patrón visual que
/// `RenameSheet` de `MediaSectionView.swift` (privada a ese archivo, de
/// ahí esta copia liviana en vez de exponerla).
private struct AlbumRenameSheet: View {
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String

    init(currentTitle: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onSave = onSave
        self.onCancel = onCancel
        _text = State(initialValue: currentTitle)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Renombrar álbum").font(.title3.bold())
            TextField("Nombre del álbum", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onSave(trimmed) }
            Text("Dejarlo vacío disuelve el álbum -- las fotos vuelven a \"Sin álbum\".")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancelar", action: onCancel)
                Button("Guardar") { onSave(trimmed) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}
