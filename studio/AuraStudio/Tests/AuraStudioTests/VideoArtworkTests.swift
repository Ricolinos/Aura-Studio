import XCTest
@testable import AuraStudio

/// ST-033: pósters de películas/series -- parser de títulos, cliente de
/// TMDB y resolvedor TMDB → fanart.tv → TMDB. Red simulada.
final class VideoArtworkTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func http(_ status: Int, _ url: URL) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    // MARK: - VideoTitleParser

    func testParserStripsSceneNoiseAndYear() {
        let parsed = VideoTitleParser.parse("The.Matrix.1999.1080p.BluRay.x264-GRP")
        XCTAssertEqual(parsed.title, "The Matrix")
        XCTAssertEqual(parsed.year, "1999")
        XCTAssertNil(parsed.seriesName)
    }

    func testParserKeepsYearOnlyTitles() {
        let parsed = VideoTitleParser.parse("2012")
        XCTAssertEqual(parsed.title, "2012")
        XCTAssertNil(parsed.year)
    }

    func testParserTakesLastYear() {
        let parsed = VideoTitleParser.parse("1917 (2019)")
        XCTAssertEqual(parsed.title, "1917")
        XCTAssertEqual(parsed.year, "2019")
    }

    func testParserDetectsEpisodes() {
        let parsed = VideoTitleParser.parse("Breaking Bad - S01E02 - Cat's in the Bag [720p]")
        XCTAssertEqual(parsed.seriesName, "Breaking Bad")
        XCTAssertEqual(parsed.season, 1)
        XCTAssertEqual(parsed.episode, 2)
        XCTAssertTrue(parsed.isEpisode)
        let alt = VideoTitleParser.parse("los_simpson_3x07_hdtv")
        XCTAssertEqual(alt.seriesName, "los simpson")
        XCTAssertEqual(alt.season, 3)
        XCTAssertEqual(alt.episode, 7)
    }

    func testParserLeavesCleanTitlesAlone() {
        XCTAssertEqual(VideoTitleParser.parse("Amores perros").title, "Amores perros")
    }

    // MARK: - TMDBClient

    func testSearchMovieSendsQueryYearLanguageAndKey() async throws {
        MockURLProtocol.handler = { request in
            let url = request.url!
            XCTAssertTrue(url.path.hasSuffix("/3/search/movie"))
            let query = url.query ?? ""
            XCTAssertTrue(query.contains("query=Matrix"))
            XCTAssertTrue(query.contains("year=1999"))
            XCTAssertTrue(query.contains("language=es-MX"))
            XCTAssertTrue(query.contains("api_key=t"))
            let json = #"{"results":[{"id":603,"title":"Matrix","release_date":"1999-03-30","poster_path":"/m.jpg"}]}"#
            return (self.http(200, url), Data(json.utf8))
        }
        let client = TMDBClient(session: mockSession(), apiKeyProvider: { "t" })
        let movie = try await client.searchMovie(title: "Matrix", year: "1999")
        XCTAssertEqual(movie?.id, 603)
        XCTAssertEqual(movie?.year, "1999")
        XCTAssertEqual(movie?.posterPath, "/m.jpg")
    }

    func testTMDBWithoutKeyReturnsNilWithoutNetwork() async throws {
        MockURLProtocol.handler = { _ in XCTFail("sin key no hay red"); throw URLError(.badURL) }
        let client = TMDBClient(session: mockSession(), apiKeyProvider: { nil })
        XCTAssertFalse(client.hasAPIKey)
        let movie = try await client.searchMovie(title: "x")
        XCTAssertNil(movie)
    }

    func testTVDBIDComesFromExternalIDs() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertTrue(request.url!.path.hasSuffix("/3/tv/1396/external_ids"))
            return (self.http(200, request.url!), Data(#"{"tvdb_id":81189,"imdb_id":"tt0903747"}"#.utf8))
        }
        let client = TMDBClient(session: mockSession(), apiKeyProvider: { "t" })
        let id = try await client.tvdbID(forTVShow: 1396)
        XCTAssertEqual(id, 81189)
    }

    func testDownloadPosterUsesImageBase() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url!.absoluteString, "https://image.tmdb.org/t/p/w780/m.jpg")
            return (self.http(200, request.url!), Data([1, 2]))
        }
        let client = TMDBClient(session: mockSession(), apiKeyProvider: { "t" })
        let data = try await client.downloadPoster(path: "/m.jpg")
        XCTAssertEqual(data, Data([1, 2]))
        let none = try await client.downloadPoster(path: nil)
        XCTAssertNil(none)
    }

    // MARK: - VideoArtworkResolver

    private func resolver(fanartKey: Bool, fanartHasIt: Bool) -> VideoArtworkResolver {
        MockURLProtocol.handler = { request in
            let url = request.url!
            switch url.host {
            case "api.themoviedb.org":
                if url.path.contains("/search/movie") {
                    return (self.http(200, url), Data(#"{"results":[{"id":603,"title":"Matrix","release_date":"1999-03-30","poster_path":"/m.jpg"}]}"#.utf8))
                }
                if url.path.contains("/search/tv") {
                    return (self.http(200, url), Data(#"{"results":[{"id":1396,"name":"Breaking Bad","first_air_date":"2008-01-20","poster_path":"/bb.jpg"}]}"#.utf8))
                }
                if url.path.contains("/external_ids") {
                    return (self.http(200, url), Data(#"{"tvdb_id":81189}"#.utf8))
                }
                return (self.http(404, url), Data())
            case "image.tmdb.org":
                return (self.http(200, url), Data([0x74])) // 't'
            case "webservice.fanart.tv":
                guard fanartHasIt else { return (self.http(404, url), Data()) }
                let key = url.path.contains("/movies/") ? "movieposter" : "tvposter"
                return (self.http(200, url), Data(#"{"\#(key)":[{"url":"https://assets.fanart.tv/f.jpg"}]}"#.utf8))
            case "assets.fanart.tv":
                return (self.http(200, url), Data([0x66])) // 'f'
            default:
                return (self.http(404, url), Data())
            }
        }
        let session = mockSession()
        return VideoArtworkResolver(
            tmdb: TMDBClient(session: session, apiKeyProvider: { "t" }),
            fanart: FanartTVClient(session: session, apiKeyProvider: { fanartKey ? "k" : nil }),
            hasFanartKey: { fanartKey })
    }

    func testMoviePrefersFanartWhenAvailable() async {
        let result = await resolver(fanartKey: true, fanartHasIt: true).resolve(rawTitle: "The.Matrix.1999.1080p", kind: .movie)
        guard case .success(let poster) = result else { return XCTFail("esperaba poster") }
        XCTAssertEqual(poster.source, .fanartTV)
        XCTAssertEqual(poster.data, Data([0x66]))
        XCTAssertEqual(poster.matchedTitle, "Matrix")
        XCTAssertEqual(poster.year, "1999")
    }

    func testMovieFallsBackToTMDBPoster() async {
        let result = await resolver(fanartKey: true, fanartHasIt: false).resolve(rawTitle: "Matrix", kind: .movie)
        guard case .success(let poster) = result else { return XCTFail("esperaba poster") }
        XCTAssertEqual(poster.source, .tmdb)
        XCTAssertEqual(poster.data, Data([0x74]))
    }

    func testSeriesGoesThroughTVDBIDForFanart() async {
        let result = await resolver(fanartKey: true, fanartHasIt: true).resolve(rawTitle: "Breaking Bad - S01E02", kind: .series)
        guard case .success(let poster) = result else { return XCTFail("esperaba poster") }
        XCTAssertEqual(poster.source, .fanartTV)
        XCTAssertEqual(poster.matchedTitle, "Breaking Bad")
    }

    func testUnknownKindWithEpisodeMarkerTriesSeriesFirst() async {
        let result = await resolver(fanartKey: false, fanartHasIt: false).resolve(rawTitle: "Breaking Bad S01E01", kind: .unknown)
        guard case .success(let poster) = result else { return XCTFail("esperaba poster") }
        XCTAssertEqual(poster.matchedTitle, "Breaking Bad")
        XCTAssertEqual(poster.source, .tmdb)
    }

    func testMissingTMDBKeyIsExplicitFailure() async {
        MockURLProtocol.handler = { _ in XCTFail("sin key no hay red"); throw URLError(.badURL) }
        let session = mockSession()
        let resolver = VideoArtworkResolver(
            tmdb: TMDBClient(session: session, apiKeyProvider: { nil }),
            fanart: FanartTVClient(session: session, apiKeyProvider: { "k" }),
            hasFanartKey: { true })
        let result = await resolver.resolve(rawTitle: "Matrix", kind: .movie)
        XCTAssertEqual(result, .failure(.missingTMDBKey))
    }

    func testNoMatchIsReported() async {
        MockURLProtocol.handler = { request in (self.http(200, request.url!), Data(#"{"results":[]}"#.utf8)) }
        let session = mockSession()
        let resolver = VideoArtworkResolver(
            tmdb: TMDBClient(session: session, apiKeyProvider: { "t" }),
            fanart: FanartTVClient(session: session, apiKeyProvider: { nil }),
            hasFanartKey: { false })
        let result = await resolver.resolve(rawTitle: "Nada de nada", kind: .movie)
        XCTAssertEqual(result, .failure(.noMatch))
    }
}
