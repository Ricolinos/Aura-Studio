import SwiftUI

/// Sección "Artistas" (ST-020, PLAN-studio-ux.md §2.3, captura de
/// referencia del dueño): maestro-detalle. Izquierda, la lista de
/// artistas con avatar (foto de artista si hay -- ST-021 --, si no la
/// portada de un álbum, si no un micrófono); derecha, la ficha del
/// artista con sus álbumes uno debajo del otro, cada uno con portada,
/// título, género · año y sus canciones. Agrupa por
/// `albumArtist ?? artist` (P4 del plan).
struct ArtistsView: View {
    @ObservedObject var viewModel: LibraryViewModel
    let device: AuraDevice?
    @ObservedObject var preferences: AppPreferences
    /// ST-021: acción "Buscar fotos de artistas" (nil = sin proveedor).
    var onFetchArtistImages: (([ArtistGroup]) -> Void)?
    var isFetchingArtistImages = false

    @State private var artists: [ArtistGroup] = []
    @State private var searchText = ""
    @State private var selectedArtistID: String?
    @State private var reviewingItem: LibraryItem?

    private var visibleArtists: [ArtistGroup] {
        artists.filter { LibrarySearch.artist($0, matches: searchText) }
    }

    private var selectedArtist: ArtistGroup? {
        guard let selectedArtistID else { return nil }
        return artists.first { $0.id == selectedArtistID }
    }

    var body: some View {
        HStack(spacing: 0) {
            master
                .frame(width: 280)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Artistas")
        .onAppear(perform: rebuild)
        .onReceive(viewModel.$items) { _ in rebuild() }
        .sheet(item: $reviewingItem) { item in
            MediaInfoView(item: item, availableCategories: nil) { _ in
            } onRatingChanged: { rating in
                viewModel.setRating(rating, forItem: item.id)
            } onSave: { metadata in
                viewModel.applyReview(id: item.id, metadata: metadata)
                reviewingItem = nil
            } onCancel: {
                reviewingItem = nil
            }
        }
    }

    private func rebuild() {
        artists = LibraryGrouping.artists(from: viewModel.items)
        if selectedArtistID == nil || !artists.contains(where: { $0.id == selectedArtistID }) {
            selectedArtistID = artists.first?.id
        }
    }

    // MARK: - Maestro

    private var master: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Artistas")
                    .font(.title2.bold())
                Spacer()
                if let onFetchArtistImages {
                    Button {
                        onFetchArtistImages(artists)
                    } label: {
                        if isFetchingArtistImages {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "person.crop.circle.badge.plus")
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isFetchingArtistImages)
                    .help("Buscar fotos de los artistas en línea (fanart.tv / Deezer)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            LibrarySearchField(scopeTitle: "Artistas", text: $searchText)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            if artists.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "music.mic")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("Todavía no hay música en la biblioteca.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(visibleArtists, selection: $selectedArtistID) { artist in
                    HStack(spacing: 12) {
                        ArtistAvatarView(imageData: viewModel.artistImages.image(forArtistKey: artist.id),
                                         fallbackCoverData: artist.fallbackCoverArtData,
                                         side: 40)
                        Text(artist.name)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .tag(artist.id)
                    .contextMenu { artistContextMenu(artist) }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Detalle

    @ViewBuilder
    private var detail: some View {
        if let artist = selectedArtist {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    artistHeader(artist)
                    ForEach(artist.albums) { album in
                        albumSection(album, artist: artist)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "music.mic")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Elige un artista de la lista.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func artistHeader(_ artist: ArtistGroup) -> some View {
        HStack(alignment: .center, spacing: 20) {
            ArtistAvatarView(imageData: viewModel.artistImages.image(forArtistKey: artist.id),
                             fallbackCoverData: artist.fallbackCoverArtData,
                             side: 96)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(artist.name)
                        .font(.largeTitle.bold())
                        .lineLimit(2)
                    if artist.items.contains(where: { $0.metadata?.isFavorite == true }) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(AuraColors.light.accent)
                    }
                }
                Text(artist.summary)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Buscar información en línea") {
                        Task { await viewModel.reenrichOnline(ids: Set(artist.items.map(\.id)), fetchAlbumInfo: true, fetchLyrics: false) }
                    }
                    Menu {
                        artistContextMenu(artist)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(.top, 4)
            }
            Spacer()
        }
    }

    private func albumSection(_ album: AlbumGroup, artist: ArtistGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                CoverArtView(data: album.coverArtData, side: 128)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(album.title)
                            .font(.title2.bold())
                            .lineLimit(2)
                        if album.isFavorite {
                            Image(systemName: "star.fill")
                                .foregroundStyle(AuraColors.light.accent)
                        }
                    }
                    Text([album.genre, album.year].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                    Text(album.trackCount == 1 ? "1 canción" : "\(album.trackCount) canciones")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Menu {
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
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            VStack(spacing: 0) {
                ForEach(Array(album.items.enumerated()), id: \.element.id) { index, item in
                    trackRow(item, position: index + 1, artist: artist)
                    if index < album.items.count - 1 {
                        Divider().padding(.leading, 36)
                    }
                }
            }
        }
    }

    private func trackRow(_ item: LibraryItem, position: Int, artist: ArtistGroup) -> some View {
        let title = LibraryGrouping.displayTitle(item)
        let trackArtist = item.metadata?.artist
        let showsArtist = trackArtist != nil && LibraryGrouping.normalize(trackArtist) != artist.id
        let isFavorite = item.metadata?.isFavorite ?? false
        return HStack(spacing: 12) {
            Text(item.metadata?.trackNumber.map(String.init) ?? "\(position)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1)
                if showsArtist, let trackArtist {
                    Text(trackArtist)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(MediaTableRow(item: item).durationText)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Button {
                viewModel.toggleFavorite(id: item.id)
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? AuraColors.light.accent : Color.secondary.opacity(0.35))
            }
            .buttonStyle(.plain)
            .help(isFavorite ? "Quitar de favoritos" : "Marcar como favorito")
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Más información...") { reviewingItem = item }
            Button(isFavorite ? "Quitar de favoritos" : "Marcar como favorito") {
                viewModel.toggleFavorite(id: item.id)
            }
            Divider()
            Button("Mostrar en Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.sourceURL])
            }
        }
    }

    @ViewBuilder
    private func artistContextMenu(_ artist: ArtistGroup) -> some View {
        let allFavorite = artist.items.allSatisfy { $0.metadata?.isFavorite == true }
        Button(allFavorite ? "Quitar favorito del artista" : "Marcar artista como favorito") {
            viewModel.setFavorite(!allFavorite, forItems: Set(artist.items.map(\.id)))
        }
        Button("Buscar información en línea") {
            Task { await viewModel.reenrichOnline(ids: Set(artist.items.map(\.id)), fetchAlbumInfo: true, fetchLyrics: false) }
        }
        if let onFetchArtistImages {
            Button("Buscar foto del artista") { onFetchArtistImages([artist]) }
        }
        if viewModel.artistImages.hasImage(forArtistKey: artist.id) {
            Button("Quitar foto del artista") {
                viewModel.artistImages.remove(forArtistKey: artist.id)
                viewModel.objectWillChange.send()
            }
        }
        Divider()
        Button("Mostrar en Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(artist.items.prefix(1).map(\.sourceURL))
        }
    }
}
