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

    @State private var albums: [PhotoAlbumGroup] = []
    @State private var searchText = ""
    @State private var selectedAlbumID: String?
    @State private var selectedPhotoID: UUID?
    @State private var renamingAlbum: PhotoAlbumGroup?
    @State private var quickLook = QuickLookCoordinator()
    @State private var isTargeted = false
    /// Como en `MediaSectionView`: soltar ≥2 archivos (o una carpeta)
    /// sobre la cuadrícula de álbumes pregunta el nombre; un archivo
    /// suelto entra sin álbum. Soltar DENTRO de un álbum ya abierto no
    /// pregunta nada -- ya se sabe a cuál álbum va.
    @State private var pendingAlbumNameURLs: [URL]?

    private var visibleAlbums: [PhotoAlbumGroup] {
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return albums }
        return albums.filter { LibrarySearch.matches($0.title, needle) }
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
        .onAppear(perform: rebuild)
        .onReceive(viewModel.$items) { _ in rebuild() }
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

    private func rebuild() {
        albums = LibraryGrouping.photoAlbums(from: viewModel.items, category: category)
        if let selectedAlbumID, !albums.contains(where: { $0.id == selectedAlbumID }) {
            self.selectedAlbumID = nil
        }
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
                                    .onTapGesture { selectedAlbumID = album.id }
                                    .contextMenu { albumContextMenu(album) }
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

    @ViewBuilder
    private func albumContextMenu(_ album: PhotoAlbumGroup) -> some View {
        Button("Abrir") { selectedAlbumID = album.id }
        if !album.isUnknown {
            Divider()
            Button("Renombrar álbum...") { renamingAlbum = album }
            Button("Disolver álbum", role: .destructive) {
                viewModel.dissolvePhotoAlbum(items: Set(album.items.map(\.id)))
            }
        }
    }

    // MARK: - Detalle: cuadrícula de miniaturas (uso "a la iPod Classic")

    private func albumDetail(_ album: PhotoAlbumGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    selectedAlbumID = nil
                    selectedPhotoID = nil
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
                            photoThumb(item)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .onKeyPress(.space) {
            guard let selectedPhotoID, let item = album.items.first(where: { $0.id == selectedPhotoID }) else { return .ignored }
            quickLook.toggle(for: item.sourceURL)
            return .handled
        }
    }

    private func photoThumb(_ item: LibraryItem) -> some View {
        let isSelected = item.id == selectedPhotoID
        return CoverArtView(data: try? Data(contentsOf: item.preparedURL ?? item.sourceURL), side: 140,
                            cornerRadius: 6, placeholderSymbol: "photo")
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isSelected ? AuraColors.light.accent : .clear, lineWidth: 3)
            )
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { quickLook.toggle(for: item.sourceURL) }
            .onTapGesture { selectedPhotoID = item.id }
            .contextMenu {
                Button("Vista previa") { quickLook.toggle(for: item.sourceURL) }
                Divider()
                Button("Quitar del álbum") {
                    viewModel.dissolvePhotoAlbum(items: [item.id])
                }
                Button("Mostrar en Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([item.sourceURL])
                }
                Divider()
                Button("Eliminar de la biblioteca", role: .destructive) {
                    viewModel.deleteItems(ids: [item.id])
                }
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
