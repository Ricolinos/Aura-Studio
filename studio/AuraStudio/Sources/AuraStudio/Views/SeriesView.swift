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

    private func rebuild() {
        series = LibraryGrouping.videoCollections(from: viewModel.items).filter(\.isSeries)
        if let selectedSeriesID, !series.contains(where: { $0.id == selectedSeriesID }) {
            self.selectedSeriesID = nil
        }
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
                                .onTapGesture { selectedSeriesID = show.id }
                                .help(show.title)
                        }
                    }
                    .padding(.horizontal, 20)
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
                        seasonSection(season)
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

    private func seasonSection(_ season: SeasonGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(seasonTitle(season))
                .font(.title2.bold())
            VStack(spacing: 0) {
                ForEach(Array(season.items.enumerated()), id: \.element.id) { index, item in
                    episodeRow(item)
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

    private func episodeRow(_ item: LibraryItem) -> some View {
        let title = LibraryGrouping.displayTitle(item)
        let syncState = viewModel.deviceSyncIndex?.state(forSourcePath: item.sourceURL.path)
        return HStack(spacing: 12) {
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
        .contentShape(Rectangle())
        .contextMenu {
            Button("Más información...") { reviewingItem = item }
            Divider()
            Button("Mostrar en Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.sourceURL])
            }
        }
    }
}
