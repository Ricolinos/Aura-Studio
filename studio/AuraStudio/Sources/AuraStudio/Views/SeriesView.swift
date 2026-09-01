import SwiftUI

/// Sección "Series" (PLAN-biblioteca-medios-v2.md §3.4, Tanda 4): misma
/// cuadrícula de pósters que `MoviesView`; el detalle, en vez de una
/// sola tabla, agrupa los episodios por temporada (patrón
/// `ArtistsView.albumSection`) -- "Sin temporada" siempre al final para
/// los episodios que no traían `SxxEyy` en el nombre.
struct SeriesView: View {
    @ObservedObject var viewModel: LibraryViewModel
    let device: AuraDevice?
    @ObservedObject var preferences: AppPreferences

    @State private var series: [VideoCollectionGroup] = []
    @State private var searchText = ""
    @State private var selectedSeriesID: String?
    /// Selección múltiple de series en la cuadrícula (encargo del
    /// dueño, 2026-08-19).
    @State private var selection = GridSelection<String>()
    /// Selección múltiple de episodios dentro de una serie abierta --
    /// se limpia al volver a la cuadrícula (`selectedSeriesID = nil`).
    @State private var episodeSelection = GridSelection<UUID>()
    /// R2-1: la casilla de un episodio aparece al pasar el cursor por su
    /// FILA (la casilla oculta no recibe eventos, así que no puede
    /// detectar su propio hover).
    @State private var hoveredEpisodeID: UUID?
    @State private var reviewingItem: LibraryItem?

    private var visibleSeries: [VideoCollectionGroup] {
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return series }
        return series.filter { LibrarySearch.matches($0.title, needle) }
    }

    private var selectedSeries: VideoCollectionGroup? {
        guard let selectedSeriesID else { return nil }
        return series.first { $0.id == selectedSeriesID }
    }

    var body: some View {
        Group {
            if let show = selectedSeries {
                seriesDetail(show)
            } else {
                grid
            }
        }
        .navigationTitle("Series")
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

    /// ST-063: barra de estado -- series/temporadas/episodios en la
    /// cuadrícula; con una serie abierta, sus episodios y los seleccionados.
    private var statusSummary: LibraryStatusSummary {
        if let show = selectedSeries {
            return LibraryStats.episodes(of: show, selected: show.items.filter { episodeSelection.isSelected($0.id) })
        }
        return LibraryStats.series(visibleSeries, selected: visibleSeries.filter { selection.isSelected($0.id) })
    }

    private func rebuild() {
        series = LibraryGrouping.videoCollections(from: viewModel.items).filter(\.isSeries)
        if let selectedSeriesID, !series.contains(where: { $0.id == selectedSeriesID }) {
            self.selectedSeriesID = nil
        }
        selection.pruneMissing(from: Set(series.map(\.id)))
        if let show = selectedSeries {
            episodeSelection.pruneMissing(from: Set(show.items.map(\.id)))
        } else {
            episodeSelection.clear()
        }
    }

    /// Series a las que aplica una acción disparada desde `show`: su
    /// selección completa si ya estaba seleccionada, o solo ella si no
    /// (criterio Finder, ver `GridSelection.effectiveIDs`).
    private func effectiveSeries(for show: VideoCollectionGroup) -> [VideoCollectionGroup] {
        let ids = selection.effectiveIDs(for: show.id)
        return series.filter { ids.contains($0.id) }
    }

    private func effectiveEpisodes(for item: LibraryItem, in show: VideoCollectionGroup) -> [LibraryItem] {
        let ids = episodeSelection.effectiveIDs(for: item.id)
        return show.items.filter { ids.contains($0.id) }
    }

    // MARK: - Cuadrícula

    private var grid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Spacer()
                LibrarySearchField(scopeTitle: "Series", text: $searchText)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if series.isEmpty {
                emptyState("Todavía no hay series en la biblioteca.",
                           detail: "Arrastra episodios a \"Series\" en la barra lateral -- si el nombre trae SxxEyy se agrupan solos.")
            } else if visibleSeries.isEmpty {
                emptyState("Sin resultados para \"\(searchText)\".", detail: nil)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 24, alignment: .top)],
                              alignment: .leading, spacing: 28) {
                        ForEach(visibleSeries) { show in
                            MediaCardView(imageData: show.posterData, title: show.title,
                                          subtitle: episodeCountText(show), aspect: .poster(width: 140), placeholderSymbol: "tv")
                                .librarySelectionCheckbox(selection.isSelected(show.id),
                                                          anySelected: !selection.selected.isEmpty) {
                                    selection.toggle(show.id)
                                }
                                .onTapGesture(count: 2) { selectedSeriesID = show.id }
                                .onTapGesture { selection.handleTap(show.id, orderedIDs: visibleSeries.map(\.id)) }
                                .contextMenu { seriesContextMenu(show) }
                                .draggable(LibrarySelectionTransfer(itemIDs: effectiveSeries(for: show).flatMap(\.items).map(\.id)))
                                .help(show.title)
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

    private func episodeCountText(_ show: VideoCollectionGroup) -> String {
        show.episodeCount == 1 ? "1 episodio" : "\(show.episodeCount) episodios"
    }

    private func emptyState(_ title: String, detail: String?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "tv")
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

    private func seriesDetail(_ show: VideoCollectionGroup) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button {
                        selectedSeriesID = nil
                        episodeSelection.clear()
                    } label: {
                        Label("Series", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AuraColors.light.accent)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)

                seriesHeader(show)
                    .padding(.horizontal, 20)

                Divider().padding(.vertical, 16)

                VStack(alignment: .leading, spacing: 28) {
                    ForEach(show.seasons) { season in
                        seasonSection(season, show: show)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private func seriesHeader(_ show: VideoCollectionGroup) -> some View {
        HStack(alignment: .top, spacing: 20) {
            CoverArtView(data: show.posterData, width: 180, height: 270, placeholderSymbol: "tv")
            VStack(alignment: .leading, spacing: 6) {
                Text(show.title)
                    .font(.title.bold())
                    .lineLimit(2)
                if let year = show.year, !year.isEmpty {
                    Text(year)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Text("\(show.seasons.count == 1 ? "1 temporada" : "\(show.seasons.count) temporadas"), \(episodeCountText(show))")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                Button("Buscar póster en línea") {
                    Task { await viewModel.fetchVideoPosters(ids: Set(show.items.map(\.id))) }
                }
            }
            Spacer()
        }
    }

    private func seasonSection(_ season: SeasonGroup, show: VideoCollectionGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(seasonTitle(season))
                .font(.title2.bold())
            VStack(spacing: 0) {
                ForEach(Array(season.items.enumerated()), id: \.element.id) { index, item in
                    episodeRow(item, show: show)
                    if index < season.items.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private func seasonTitle(_ season: SeasonGroup) -> String {
        season.number == VideoCollectionGroup.noSeasonNumber ? "Sin temporada" : "Temporada \(season.number)"
    }

    private func episodeRow(_ item: LibraryItem, show: VideoCollectionGroup) -> some View {
        let title = LibraryGrouping.displayTitle(item)
        let syncState = viewModel.deviceSyncIndex?.state(forSourcePath: item.sourceURL.path)
        let isSelected = episodeSelection.isSelected(item.id)
        return HStack(spacing: 12) {
            // ST-103: los episodios son filas, no tarjetas -- la casilla
            // va al principio de la fila en vez de sobre una portada,
            // pero hace exactamente lo mismo.
            LibraryRowSelectionCheckbox(isSelected: isSelected,
                                        anySelected: !episodeSelection.selected.isEmpty,
                                        isRowHovered: hoveredEpisodeID == item.id,
                                        toggle: { episodeSelection.toggle(item.id) })
            Text(item.episode.map { "\($0)" } ?? "--")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
            Text(title).lineLimit(1)
            Spacer()
            Text(MediaTableRow(item: item, syncState: syncState).durationText)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(isSelected ? AuraColors.light.accent.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hoveredEpisodeID = $0 ? item.id : (hoveredEpisodeID == item.id ? nil : hoveredEpisodeID) }
        .onTapGesture {
            episodeSelection.handleTap(item.id, orderedIDs: show.seasons.flatMap(\.items).map(\.id))
        }
        .draggable(LibrarySelectionTransfer(itemIDs: effectiveEpisodes(for: item, in: show).map(\.id)))
        .contextMenu { episodeContextMenu(item, show: show) }
    }

    /// Menú contextual: si `item` forma parte de una selección múltiple
    /// de episodios, actúa sobre TODA la selección (encargo del dueño,
    /// 2026-08-19); si no, solo sobre `item`.
    @ViewBuilder
    private func episodeContextMenu(_ item: LibraryItem, show: VideoCollectionGroup) -> some View {
        let targets = effectiveEpisodes(for: item, in: show)
        let allFavorite = targets.allSatisfy { $0.metadata?.isFavorite == true }
        let plural = targets.count > 1

        if !plural {
            Button("Más información...") { reviewingItem = item }
            Divider()
        }
        Button(allFavorite ? "Quitar favorito" : "Marcar como favorito") {
            viewModel.setFavorite(!allFavorite, forItems: Set(targets.map(\.id)))
        }
        Menu("Cambiar categoría") {
            ForEach(MediaCategory.videoCategories) { category in
                Button(category.displayName) {
                    viewModel.setCategory(category.displayName, forItems: Set(targets.map(\.id)))
                }
            }
        }
        Divider()
        Button("Mostrar en Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(targets.map(\.sourceURL))
        }
        Button(plural ? "Eliminar episodios" : "Eliminar episodio", role: .destructive) {
            viewModel.deleteItems(ids: Set(targets.map(\.id)))
        }
    }

    /// Menú contextual de la cuadrícula de series: mismo criterio que
    /// `episodeContextMenu` -- toda la selección si `show` ya estaba
    /// seleccionada, o solo ella si no.
    @ViewBuilder
    private func seriesContextMenu(_ show: VideoCollectionGroup) -> some View {
        let targets = effectiveSeries(for: show)
        let items = targets.flatMap(\.items)
        let allFavorite = items.allSatisfy { $0.metadata?.isFavorite == true }
        let plural = targets.count > 1

        if !plural {
            Button("Abrir") { selectedSeriesID = show.id }
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
        Button(plural ? "Eliminar series" : "Eliminar serie", role: .destructive) {
            viewModel.deleteItems(ids: Set(items.map(\.id)))
        }
    }
}
