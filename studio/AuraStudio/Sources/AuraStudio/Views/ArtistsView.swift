import SwiftUI

/// Sección "Artistas" (ST-031, PLAN-studio-ux.md §2.3, captura de
/// referencia del dueño): maestro-detalle. Izquierda, la lista de
/// artistas con avatar (foto de artista si hay -- ST-032 --, si no la
/// portada de un álbum, si no un micrófono); derecha, la ficha del
/// artista con sus álbumes uno debajo del otro, cada uno con portada,
/// título, género · año y sus canciones. Agrupa por
/// `albumArtist ?? artist` (P4 del plan).
struct ArtistsView: View {
    @ObservedObject var viewModel: LibraryViewModel
    let device: AuraDevice?
    @ObservedObject var preferences: AppPreferences
    /// PLAN-studio-rendimiento-2.md Fase 1 (ST-181): la selección de
    /// artistas también llega a `SelectionStore` ("sincronizar solo la
    /// selección" con dos artistas marcados sincronizaba nada).
    /// ST-182: `let`, no `@ObservedObject` -- esta vista solo PUBLICA
    /// acá; observarlo le costaría una pasada de `body` extra por clic
    /// como eco de su propia publicación.
    let selectionStore: SelectionStore
    /// ST-032: acción "Buscar fotos de artistas" (nil = sin proveedor).
    var onFetchArtistImages: (([ArtistGroup]) -> Void)?

    @State private var artists: [ArtistGroup] = []
    @State private var searchText = ""
    /// PLAN-studio-rendimiento-2.md Fase 1 (ST-181): lo visible, una
    /// sola vez por cambio real de entrada -- ver `GridModel`.
    @StateObject private var listModel = GridModel<ArtistGroup>()
    /// El resumen de la barra de estado, memoizado -- `GridStatusModel`.
    /// En `@State` y no en `@StateObject` a propósito -- ver la nota
    /// larga en `AlbumsView.statusModel`: observarlo costaría una
    /// segunda pasada de `body` por clic.
    @State private var statusModel = GridStatusModel()
    /// Identidad de esta vista como publicadora de `selectionStore`.
    @State private var publisherID = UUID()
    /// `List(selection:)` con `Set` da multi-selección Cmd/Shift-clic
    /// nativa de Finder sin código propio (encargo del dueño,
    /// 2026-08-19) -- a diferencia de las cuadrículas (Álbumes,
    /// Películas...) que sí necesitan `GridSelection` a mano.
    @State private var selectedArtistIDs: Set<String> = []
    @State private var reviewingItem: LibraryItem?

    private var visibleArtists: [ArtistGroup] { listModel.visible }

    /// El cálculo en sí -- lo llama `GridModel.recompute`, nunca el `body`.
    private func computeVisible(_ groups: [ArtistGroup]) -> [ArtistGroup] {
        groups.filter { LibrarySearch.artist($0, matches: searchText) }
    }

    /// Detalle de un solo artista -- `nil` cuando hay 0 o >1
    /// seleccionados (ese caso lo cubre `selectionSummary`).
    private var selectedArtist: ArtistGroup? {
        guard selectedArtistIDs.count == 1, let id = selectedArtistIDs.first else { return nil }
        return artists.first { $0.id == id }
    }

    private var selectedArtists: [ArtistGroup] {
        artists.filter { selectedArtistIDs.contains($0.id) }
    }

    /// Artistas a los que aplica una acción disparada desde `artist`: su
    /// selección completa si ya estaba seleccionado, o solo él si no
    /// (mismo criterio Finder que `GridSelection.effectiveIDs`).
    private func effectiveArtists(for artist: ArtistGroup) -> [ArtistGroup] {
        let ids = selectedArtistIDs.contains(artist.id) ? selectedArtistIDs : [artist.id]
        return artists.filter { ids.contains($0.id) }
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
        // ST-063: barra de estado -- artistas/álbumes/canciones y la
        // selección. PLAN-studio-rendimiento-2.md Fase 1 (ST-181): ya no
        // se calcula en el `body` (era `LibraryStats.artists` crudo, con
        // el `flatMap` de todos los ítems y una normalización de álbum
        // por ítem, en cada clic).
        .background(LibraryStatusRelay(model: statusModel))
        .onAppear(perform: rebuild)
        .onReceive(viewModel.$items) { _ in rebuild() }
        .onChange(of: searchText) { refreshList() }
        .onChange(of: preferences.artistGrouping) { rebuild() }
        .onChange(of: selectedArtistIDs) { _, _ in
            refreshStatusSelection()
            publishSelection()
        }
        .onDisappear { selectionStore.clear(from: publisherID) }
        // ST-184: la lista de Artistas es un `List(selection:)` nativo,
        // así que "seleccionar todo" es asignar el conjunto visible.
        .focusedSceneValue(\.auraSelectionCommand, SelectionCommandContext(
            selectAll: { selectedArtistIDs = Set(listModel.visible.map(\.id)) },
            deselectAll: { selectedArtistIDs = [] },
            hasSelection: !selectedArtistIDs.isEmpty))
        .sheet(item: $reviewingItem) { item in
            MediaInfoView(item: item, availableCategories: nil) { _ in
            } onRatingChanged: { rating in
                Task { await viewModel.setRating(rating, forItem: item.id) }
            } onSave: { metadata in
                Task { await viewModel.applyReview(id: item.id, metadata: metadata) }
                reviewingItem = nil
            } onCancel: {
                reviewingItem = nil
            }
        }
    }

    private func rebuild() {
        let groups = LibraryGrouping.artists(from: viewModel.items, options: preferences.artistGrouping)
        artists = groups
        let validIDs = Set(groups.map(\.id))
        selectedArtistIDs.formIntersection(validIDs)
        if selectedArtistIDs.isEmpty, let first = groups.first {
            selectedArtistIDs = [first.id]
        }
        refreshList(groups)
    }

    private func refreshList(_ groups: [ArtistGroup]? = nil) {
        let source = groups ?? artists
        listModel.recompute { computeVisible(source) }
        let visible = listModel.visible
        statusModel.recomputeTotal { LibraryStats.artistsTotal(visible) }
        refreshStatusSelection()
        publishSelection()
    }

    private func refreshStatusSelection() {
        let visible = listModel.visible
        let selected = artists.filter { selectedArtistIDs.contains($0.id) }
        let totalCount = visible.count
        statusModel.recomputeSelection(cost: selected.reduce(0) { $0 + $1.trackCount }) {
            LibraryStats.artistsSelectionText(selected: selected, totalCount: totalCount)
        }
    }

    /// ST-181: lo seleccionado llega a `selectionStore`.
    private func publishSelection() {
        let ids = artists
            .filter { selectedArtistIDs.contains($0.id) }
            .flatMap { $0.items.map(\.id) }
        selectionStore.replace(with: Set(ids), from: publisherID)
    }

    // MARK: - Maestro

    private var master: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                LibrarySearchField(scopeTitle: "Artistas", text: $searchText)
                    .frame(maxWidth: .infinity)
                if let onFetchArtistImages {
                    Button {
                        onFetchArtistImages(artists)
                    } label: {
                        if viewModel.isFetchingArtistImages {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "person.crop.circle.badge.plus")
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isFetchingArtistImages)
                    .help("Buscar fotos de los artistas en línea (fanart.tv / Deezer)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
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
                List(visibleArtists, selection: $selectedArtistIDs) { artist in
                    HStack(spacing: 12) {
                        ArtistAvatarView(artistID: artist.id,
                                         imageData: viewModel.artistImages.image(forArtistKey: artist.id),
                                         fallbackCoverURL: artist.fallbackCoverURL,
                                         fallbackCoverHash: artist.fallbackCoverHash,
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
        } else if selectedArtistIDs.count > 1 {
            selectionSummary(selectedArtists)
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

    /// Detalle cuando hay más de un artista seleccionado (encargo del
    /// dueño, 2026-08-19: "organizar de una forma más cómoda la
    /// biblioteca") -- mismas acciones masivas que el menú contextual,
    /// visibles sin tener que abrir el menú.
    private func selectionSummary(_ artists: [ArtistGroup]) -> some View {
        let items = artists.flatMap(\.items)
        let allFavorite = items.allSatisfy { $0.metadata?.isFavorite == true }
        return VStack(spacing: 16) {
            Image(systemName: "music.mic")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("\(artists.count) artistas seleccionados")
                .font(.title3.bold())
            HStack(spacing: 10) {
                Button(allFavorite ? "Quitar favorito" : "Marcar como favorito") {
                    viewModel.setFavorite(!allFavorite, forItems: Set(items.map(\.id)))
                }
                Button("Buscar información en línea") {
                    Task { await viewModel.reenrichOnline(ids: Set(items.map(\.id)), fetchAlbumInfo: true, fetchLyrics: false) }
                }
                if let onFetchArtistImages {
                    Button("Buscar fotos") { onFetchArtistImages(artists) }
                }
                Button("Mostrar en Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(items.map(\.sourceURL))
                }
                Button("Eliminar", role: .destructive) {
                    viewModel.deleteItems(ids: Set(items.map(\.id)))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func artistHeader(_ artist: ArtistGroup) -> some View {
        HStack(alignment: .center, spacing: 20) {
            ArtistAvatarView(artistID: artist.id,
                             imageData: viewModel.artistImages.image(forArtistKey: artist.id),
                             fallbackCoverURL: artist.fallbackCoverURL,
                             fallbackCoverHash: artist.fallbackCoverHash,
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
                CoverArtView(coverHash: album.coverHash, coverURL: album.coverURL, side: 128)
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

    /// Menú contextual: si `artist` forma parte de una selección
    /// múltiple, actúa sobre toda la selección (encargo del dueño,
    /// 2026-08-19); si no, solo sobre `artist`.
    @ViewBuilder
    private func artistContextMenu(_ artist: ArtistGroup) -> some View {
        let targets = effectiveArtists(for: artist)
        let items = targets.flatMap(\.items)
        let allFavorite = items.allSatisfy { $0.metadata?.isFavorite == true }
        let plural = targets.count > 1

        Button(allFavorite ? "Quitar favorito" : "Marcar como favorito") {
            viewModel.setFavorite(!allFavorite, forItems: Set(items.map(\.id)))
        }
        Button("Buscar información en línea") {
            Task { await viewModel.reenrichOnline(ids: Set(items.map(\.id)), fetchAlbumInfo: true, fetchLyrics: false) }
        }
        if let onFetchArtistImages {
            Button(plural ? "Buscar fotos de los artistas" : "Buscar foto del artista") { onFetchArtistImages(targets) }
        }
        // R2-2: quitar la foto tiene sentido plural -- se quitan las de
        // todos los artistas alcanzados que tengan una. Antes solo se
        // ofrecía con uno, sin más razón que no haberlo pensado.
        let withImage = targets.filter { viewModel.artistImages.hasImage(forArtistKey: $0.id) }
        if !withImage.isEmpty {
            Button(withImage.count > 1 ? "Quitar fotos de los artistas" : "Quitar foto del artista") {
                for target in withImage { viewModel.artistImages.remove(forArtistKey: target.id) }
                viewModel.objectWillChange.send()
            }
        }
        Divider()
        Button("Mostrar en Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(plural ? items.map(\.sourceURL) : Array(items.prefix(1).map(\.sourceURL)))
        }
        Button(plural ? "Eliminar artistas" : "Eliminar artista", role: .destructive) {
            viewModel.deleteItems(ids: Set(items.map(\.id)))
        }
    }
}
