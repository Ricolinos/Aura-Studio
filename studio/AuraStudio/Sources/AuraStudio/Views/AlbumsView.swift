import SwiftUI

/// Sección "Álbumes" (ST-020, PLAN-studio-ux.md §2.3): cuadrícula de
/// tarjetas de álbum como la de Music.app; clic en una → la misma tabla
/// de Canciones acotada a ese álbum (`MediaSectionView(scope: .album)`),
/// con cabecera de portada grande y botón para volver. Los álbumes son
/// grupos en memoria (`LibraryGrouping`), no carpetas.
struct AlbumsView: View {
    @ObservedObject var viewModel: LibraryViewModel
    let device: AuraDevice?
    @ObservedObject var preferences: AppPreferences

    @State private var albums: [AlbumGroup] = []
    @State private var searchText = ""
    @State private var selectedAlbumID: String?
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

    private var visibleAlbums: [AlbumGroup] {
        var result = albums.filter { LibrarySearch.album($0, matches: searchText) }
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
        Group {
            if let album = selectedAlbum {
                albumDetail(album)
            } else {
                grid
            }
        }
        .navigationTitle("Álbumes")
        .onAppear(perform: rebuild)
        .onReceive(viewModel.$items) { _ in rebuild() }
    }

    private func rebuild() {
        albums = LibraryGrouping.albums(from: viewModel.items)
        if let selectedAlbumID, !albums.contains(where: { $0.id == selectedAlbumID }) {
            self.selectedAlbumID = nil
        }
    }

    // MARK: - Cuadrícula

    private var grid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Álbumes")
                    .font(.title2.bold())
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
            .padding(.vertical, 12)

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
                            AlbumCardView(album: album)
                                .onTapGesture { selectedAlbumID = album.id }
                                .contextMenu { albumContextMenu(album) }
                                .help("\(album.title) — \(album.artist)")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
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
                    }
                }
                Spacer()
            }
            .padding(20)

            Divider()

            MediaSectionView(kind: .music, viewModel: viewModel, device: device,
                             preferences: preferences, scope: .album(album.id))
        }
    }

    private func albumStats(_ album: AlbumGroup) -> String {
        let minutes = Int((album.totalDurationSeconds / 60).rounded())
        let songs = album.trackCount == 1 ? "1 canción" : "\(album.trackCount) canciones"
        return minutes > 0 ? "\(songs), \(minutes) min" : songs
    }

    @ViewBuilder
    private func albumContextMenu(_ album: AlbumGroup) -> some View {
        Button("Abrir") { selectedAlbumID = album.id }
        Divider()
        Button(album.isFavorite ? "Quitar favorito del álbum" : "Marcar álbum como favorito") {
            viewModel.setFavorite(!album.isFavorite, forItems: Set(album.items.map(\.id)))
        }
        Button("Buscar información en línea") {
            Task { await viewModel.reenrichOnline(ids: Set(album.items.map(\.id)), fetchAlbumInfo: true, fetchLyrics: false) }
        }
        Divider()
        Button("Mostrar en Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(album.items.map(\.sourceURL))
        }
    }
}
