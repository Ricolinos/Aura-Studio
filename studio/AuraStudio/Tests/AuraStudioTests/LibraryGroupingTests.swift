import XCTest
@testable import AuraStudio

/// ST-031 (PLAN-studio-ux.md §2.3): agrupación por álbum y por artista
/// -- casos obligatorios del plan: vacíos, homónimos, normalización,
/// "Sin álbum"/"Artista desconocido" al final.
final class LibraryGroupingTests: XCTestCase {
    private func song(_ title: String, artist: String? = nil, albumArtist: String? = nil,
                      album: String? = nil, track: Int? = nil, disc: Int? = nil,
                      year: String? = nil, cover: Data? = nil, kind: String = "mp3") -> AuraStudio.LibraryItem {
        var item = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).\(kind)"))
        item.metadata = TrackMetadata(title: title, artist: artist, album: album, albumArtist: albumArtist,
                                      year: year, trackNumber: track, coverArtData: cover, discNumber: disc)
        return item
    }

    func testEmptyLibraryYieldsNoGroups() {
        XCTAssertTrue(LibraryGrouping.albums(from: []).isEmpty)
        XCTAssertTrue(LibraryGrouping.artists(from: []).isEmpty)
    }

    func testAlbumsIgnoreNonMusicItems() {
        let photo = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/x.jpg"))
        XCTAssertTrue(LibraryGrouping.albums(from: [photo]).isEmpty)
    }

    func testSameAlbumDifferentSpellingCollapsesIntoOneGroup() {
        let a = song("Uno", artist: "Café Tacvba", album: "Re")
        let b = song("Dos", artist: "Cafe Tacvba", album: " re ")
        let groups = LibraryGrouping.albums(from: [a, b])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].title, "Re", "se muestra la grafía de la primera pista")
        XCTAssertEqual(groups[0].trackCount, 2)
    }

    func testHomonymousAlbumsOfDifferentArtistsStaySeparate() {
        let a = song("x", artist: "A", album: "Greatest Hits")
        let b = song("y", artist: "B", album: "Greatest Hits")
        XCTAssertEqual(LibraryGrouping.albums(from: [a, b]).count, 2)
    }

    func testAlbumArtistTakesPrecedenceOverTrackArtist() {
        let a = song("Feat 1", artist: "Gorillaz feat. Daley", albumArtist: "Gorillaz", album: "Cracker Island")
        let b = song("Feat 2", artist: "Gorillaz", albumArtist: "Gorillaz", album: "Cracker Island")
        let albums = LibraryGrouping.albums(from: [a, b])
        XCTAssertEqual(albums.count, 1)
        XCTAssertEqual(albums[0].artist, "Gorillaz")
        let artists = LibraryGrouping.artists(from: [a, b])
        XCTAssertEqual(artists.map(\.name), ["Gorillaz"])
    }

    func testUnknownAlbumGoesLastAndUsesLabel() {
        let known = song("k", artist: "Zeta", album: "Zzz")
        let noAlbum = song("n", artist: "Alfa")
        let groups = LibraryGrouping.albums(from: [noAlbum, known])
        XCTAssertEqual(groups.map(\.title), ["Zzz", LibraryGrouping.unknownAlbumTitle])
        XCTAssertTrue(groups[1].isUnknown)
        XCTAssertEqual(groups[1].artist, "Alfa")
    }

    func testAllWithoutAlbumIsOneGroupPerArtist() {
        let a = song("1", artist: "Alfa"), b = song("2", artist: "Alfa"), c = song("3", artist: "Beta")
        let groups = LibraryGrouping.albums(from: [a, b, c])
        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.allSatisfy { $0.isUnknown })
        XCTAssertEqual(groups.map(\.artist), ["Alfa", "Beta"])
    }

    func testUnknownArtistGoesLast() {
        let a = song("1", album: "Solo")
        let b = song("2", artist: "Zzz", album: "Top")
        let artists = LibraryGrouping.artists(from: [a, b])
        XCTAssertEqual(artists.map(\.name), ["Zzz", LibraryGrouping.unknownArtistName])
        XCTAssertTrue(artists[1].isUnknown)
    }

    func testTracksSortByDiscThenTrackThenTitle() {
        let t3 = song("c", artist: "A", album: "X", track: 3, disc: 1)
        let d2 = song("a", artist: "A", album: "X", track: 1, disc: 2)
        let t1 = song("b", artist: "A", album: "X", track: 1, disc: 1)
        let noNum = song("zz", artist: "A", album: "X")
        let items = LibraryGrouping.albums(from: [noNum, d2, t3, t1])[0].items
        XCTAssertEqual(items.map { $0.metadata?.title }, ["b", "c", "zz", "a"].map(Optional.init))
    }

    func testAlbumsSortIgnoringLeadingArticleThenYear() {
        let the = song("1", artist: "A", album: "The Bends", year: "1995")
        let abc = song("2", artist: "A", album: "Amnesiac", year: "2001")
        let z = song("3", artist: "A", album: "Zeta")
        XCTAssertEqual(LibraryGrouping.albums(from: [z, the, abc]).map(\.title), ["Amnesiac", "The Bends", "Zeta"])
    }

    func testAlbumCoverIsFirstAvailable() {
        let cover = Data([0xFF, 0xD8])
        let noCover = song("1", artist: "A", album: "X", track: 1)
        let withCover = song("2", artist: "A", album: "X", track: 2, cover: cover)
        XCTAssertEqual(LibraryGrouping.albums(from: [noCover, withCover])[0].coverArtData, cover)
    }

    func testArtistSummaryCounts() {
        let a = song("1", artist: "G", album: "A1"), b = song("2", artist: "G", album: "A2"), c = song("3", artist: "G")
        let artist = LibraryGrouping.artists(from: [a, b, c])[0]
        XCTAssertEqual(artist.summary, "2 álbumes, 3 canciones")
        XCTAssertEqual(artist.albums.map(\.title), ["A1", "A2", LibraryGrouping.unknownAlbumTitle])
    }

    func testSortNameStripsArticles() {
        XCTAssertEqual(LibraryGrouping.sortName("The Beatles"), "Beatles")
        XCTAssertEqual(LibraryGrouping.sortName("Los Fabulosos Cadillacs"), "Fabulosos Cadillacs")
        XCTAssertEqual(LibraryGrouping.sortName("Alaska"), "Alaska", "no confunde 'A' con artículo dentro de la palabra")
        XCTAssertEqual(LibraryGrouping.sortName("The"), "The")
        XCTAssertEqual(LibraryGrouping.sortName("…Little Broken Hearts"), "Little Broken Hearts")
        XCTAssertEqual(LibraryGrouping.sortName("'Plastic Beach' Instrumentals"), "Plastic Beach' Instrumentals")
        XCTAssertEqual(LibraryGrouping.sortName("(What's the Story) Morning Glory?"), "What's the Story) Morning Glory?")
        XCTAssertEqual(LibraryGrouping.sortName("..."), "...")
    }

    // MARK: - videoCollections (PLAN-biblioteca-medios-v2.md §3.4, Tanda 4)

    private func video(_ title: String, category: String, seriesName: String? = nil,
                        season: Int? = nil, episode: Int? = nil, year: String? = nil,
                        cover: Data? = nil) -> AuraStudio.LibraryItem {
        var item = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).mkv"))
        item.metadata = TrackMetadata(title: title, year: year, coverArtData: cover)
        item.category = category
        item.seriesName = seriesName
        item.season = season
        item.episode = episode
        return item
    }

    func testVideoCollectionsIgnoresNonMovieNonSeriesCategories() {
        let clip = video("Clip", category: "Videos")
        let photo = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/x.jpg"))
        XCTAssertTrue(LibraryGrouping.videoCollections(from: [clip, photo]).isEmpty)
    }

    func testStandaloneMovieBecomesItsOwnGroup() {
        let movie = video("Little Amelie", category: "Películas", year: "2025")
        let groups = LibraryGrouping.videoCollections(from: [movie])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].title, "Little Amelie")
        XCTAssertEqual(groups[0].year, "2025")
        XCTAssertFalse(groups[0].isSeries)
        XCTAssertTrue(groups[0].seasons.isEmpty)
        XCTAssertEqual(groups[0].episodeCount, 1)
    }

    func testSeriesWithTwoSeasonsGroupsByNormalizedSeriesName() {
        let e1 = video("Piloto", category: "Series", seriesName: "Mi Serie", season: 1, episode: 1)
        let e2 = video("Segundo", category: "Series", seriesName: "mi serie", season: 1, episode: 2)
        let e3 = video("Estreno T2", category: "Series", seriesName: "Mi Serie", season: 2, episode: 1)
        let groups = LibraryGrouping.videoCollections(from: [e1, e2, e3])
        XCTAssertEqual(groups.count, 1, "misma serie, aunque la grafía del tag difiera en mayúsculas")
        let show = groups[0]
        XCTAssertTrue(show.isSeries)
        XCTAssertEqual(show.episodeCount, 3)
        XCTAssertEqual(show.seasons.map(\.number), [1, 2])
        XCTAssertEqual(show.seasons[0].items.map { $0.episode }, [1, 2], "episodios ordenados dentro de la temporada")
    }

    func testEpisodeWithoutSeasonNumberGoesLast() {
        let withSeason = video("Ep 1", category: "Series", seriesName: "Serie X", season: 1, episode: 1)
        let withoutSeason = video("Extra", category: "Series", seriesName: "Serie X", season: nil, episode: nil)
        let show = LibraryGrouping.videoCollections(from: [withSeason, withoutSeason])[0]
        XCTAssertEqual(show.seasons.map(\.number), [1, VideoCollectionGroup.noSeasonNumber],
                       "el cajón 'Sin temporada' siempre va al final, sin importar el orden de entrada")
    }

    func testMovieTitlesIgnoreLeadingArticleWhenSorting() {
        let a = video("The Matrix", category: "Películas")
        let b = video("Amelie", category: "Películas")
        let groups = LibraryGrouping.videoCollections(from: [a, b])
        XCTAssertEqual(groups.map(\.title), ["Amelie", "The Matrix"], "'The' no cuenta para el orden alfabético")
    }

    func testSeriesEnglishCategoryDisplayNameAlsoGroups() {
        // D-283: item.category se guarda como el displayName LOCALIZADO
        // -- "Series" en inglés (coincide con el español acá, pero
        // MediaCategory.series.displayNameEnglish es la fuente real).
        let e = video("Ep", category: MediaCategory.series.displayNameEnglish, seriesName: "Show", season: 1, episode: 1)
        let groups = LibraryGrouping.videoCollections(from: [e])
        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(groups[0].isSeries)
    }

    func testMoviePosterComesFromCoverArtData() {
        let data = Data("poster".utf8)
        let movie = video("X", category: "Películas", cover: data)
        XCTAssertEqual(LibraryGrouping.videoCollections(from: [movie])[0].posterData, data)
    }
}
