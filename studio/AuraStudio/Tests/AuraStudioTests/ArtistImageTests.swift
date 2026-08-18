import XCTest
@testable import AuraStudio

/// ST-021: fotos de artista -- almacenamiento en la biblioteca, cliente
/// de artistas de MusicBrainz, endpoints nuevos de fanart.tv y el
/// resolvedor con respaldo de Deezer. Red simulada con `MockURLProtocol`.
final class ArtistImageTests: XCTestCase {
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

    private func tempLibrary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("artist-images-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // MARK: - ArtistImageStore

    func testStoreSavesUnderPortadasArtistasAndReadsBack() throws {
        let store = ArtistImageStore(libraryRoot: try tempLibrary())
        XCTAssertNil(store.image(forArtistKey: "gorillaz"))
        try store.save(Data([1, 2, 3]), forArtistKey: "gorillaz")
        XCTAssertEqual(store.image(forArtistKey: "gorillaz"), Data([1, 2, 3]))
        XCTAssertTrue(store.url(forArtistKey: "gorillaz").path.hasSuffix("/.portadas/artistas/gorillaz.jpg"))
        XCTAssertTrue(store.hasImage(forArtistKey: "gorillaz"))
        store.remove(forArtistKey: "gorillaz")
        XCTAssertNil(store.image(forArtistKey: "gorillaz"))
    }

    func testStoreFileNameIsSafeAndStable() {
        XCTAssertEqual(ArtistImageStore.fileName(forArtistKey: "cafe tacvba"), "cafe-tacvba.jpg")
        XCTAssertEqual(ArtistImageStore.fileName(forArtistKey: "ac/dc"), "ac_2fdc.jpg")
        XCTAssertEqual(ArtistImageStore.fileName(forArtistKey: ""), "artista.jpg")
        XCTAssertFalse(ArtistImageStore.fileName(forArtistKey: "../x").contains("/"))
    }

    func testStoreSurvivesRereadFromDisk() throws {
        let root = try tempLibrary()
        try ArtistImageStore(libraryRoot: root).save(Data([9]), forArtistKey: "x")
        XCTAssertEqual(ArtistImageStore(libraryRoot: root).image(forArtistKey: "x"), Data([9]))
    }

    // MARK: - MusicBrainz artistas

    func testSearchArtistReturnsBestAboveThreshold() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertTrue(request.url!.path.hasSuffix("/artist"))
            XCTAssertTrue(request.url!.query!.contains("artist:"))
            let json = #"{"artists":[{"id":"low","name":"Gorillaz Tribute","score":60},{"id":"e21857d5","name":"Gorillaz","score":100}]}"#
            return (self.http(200, request.url!), Data(json.utf8))
        }
        let client = MusicBrainzClient(session: mockSession(), rateLimiter: MusicBrainzRateLimiter(minimumInterval: 0))
        let artist = try await client.searchArtist(name: "Gorillaz")
        XCTAssertEqual(artist?.id, "e21857d5")
    }

    func testSearchArtistRejectsWeakMatches() async throws {
        MockURLProtocol.handler = { request in
            (self.http(200, request.url!), Data(#"{"artists":[{"id":"x","name":"Otro","score":40}]}"#.utf8))
        }
        let client = MusicBrainzClient(session: mockSession(), rateLimiter: MusicBrainzRateLimiter(minimumInterval: 0))
        let artist = try await client.searchArtist(name: "Gorillaz")
        XCTAssertNil(artist)
    }

    // MARK: - fanart.tv

    func testFanartArtistThumbDownloadsFirstImage() async throws {
        MockURLProtocol.handler = { request in
            let url = request.url!
            if url.host == "webservice.fanart.tv" {
                XCTAssertTrue(url.path.hasSuffix("/v3/music/mbid-1"))
                XCTAssertTrue(url.query!.contains("api_key=k"))
                return (self.http(200, url), Data(#"{"artistthumb":[{"url":"https://assets.fanart.tv/a.jpg"}]}"#.utf8))
            }
            XCTAssertEqual(url.absoluteString, "https://assets.fanart.tv/a.jpg")
            return (self.http(200, url), Data([0xFF, 0xD8, 0x01]))
        }
        let client = FanartTVClient(session: mockSession(), apiKeyProvider: { "k" })
        let data = try await client.fetchArtistThumb(musicBrainzArtistID: "mbid-1")
        XCTAssertEqual(data, Data([0xFF, 0xD8, 0x01]))
    }

    func testFanartWithoutKeyNeverTouchesNetwork() async throws {
        MockURLProtocol.handler = { _ in XCTFail("no debe pedir nada sin key"); throw URLError(.badURL) }
        let client = FanartTVClient(session: mockSession(), apiKeyProvider: { nil })
        let thumb = try await client.fetchArtistThumb(musicBrainzArtistID: "x")
        XCTAssertNil(thumb)
        let poster = try await client.fetchMoviePoster(tmdbOrIMDbID: "tt1")
        XCTAssertNil(poster)
    }

    func testFanart404IsNilNotError() async throws {
        MockURLProtocol.handler = { request in (self.http(404, request.url!), Data()) }
        let client = FanartTVClient(session: mockSession(), apiKeyProvider: { "k" })
        let poster = try await client.fetchTVPoster(tvdbID: "999")
        XCTAssertNil(poster)
    }

    func testFanartMovieAndTVPosterPaths() async throws {
        var paths: [String] = []
        MockURLProtocol.handler = { request in
            let url = request.url!
            if url.host == "webservice.fanart.tv" {
                paths.append(url.path)
                let key = url.path.contains("/movies/") ? "movieposter" : "tvposter"
                return (self.http(200, url), Data(#"{"\#(key)":[{"url":"https://assets.fanart.tv/p.jpg"}]}"#.utf8))
            }
            return (self.http(200, url), Data([7]))
        }
        let client = FanartTVClient(session: mockSession(), apiKeyProvider: { "k" })
        let movie = try await client.fetchMoviePoster(tmdbOrIMDbID: "603")
        XCTAssertEqual(movie, Data([7]))
        let tv = try await client.fetchTVPoster(tvdbID: "81189")
        XCTAssertEqual(tv, Data([7]))
        XCTAssertEqual(paths, ["/v3/movies/603", "/v3/tv/81189"])
    }

    // MARK: - Deezer

    func testDeezerArtistPictureRequiresExactNameMatch() async throws {
        MockURLProtocol.handler = { request in
            let url = request.url!
            if url.host == "api.deezer.com" {
                XCTAssertTrue(url.path.hasSuffix("/search/artist"))
                let json = #"{"data":[{"name":"Gorillaz Sound System","picture_xl":"https://cdn/wrong.jpg"},{"name":"Gorillaz","picture_xl":"https://cdn/right.jpg"}]}"#
                return (self.http(200, url), Data(json.utf8))
            }
            XCTAssertEqual(url.absoluteString, "https://cdn/right.jpg")
            return (self.http(200, url), Data([1]))
        }
        let client = DeezerClient(session: mockSession())
        let picture = try await client.fetchArtistPicture(name: "gorillaz")
        XCTAssertEqual(picture, Data([1]))
    }

    // MARK: - Resolver

    func testResolverPrefersFanartAndFallsBackToDeezer() async {
        MockURLProtocol.handler = { request in
            let url = request.url!
            switch url.host {
            case "musicbrainz.org":
                return (self.http(200, url), Data(#"{"artists":[{"id":"mb1","name":"A","score":100}]}"#.utf8))
            case "webservice.fanart.tv":
                return (self.http(404, url), Data()) // fanart no lo tiene
            case "api.deezer.com":
                return (self.http(200, url), Data(#"{"data":[{"name":"A","picture_xl":"https://cdn/a.jpg"}]}"#.utf8))
            default:
                return (self.http(200, url), Data([0xAA]))
            }
        }
        let session = mockSession()
        let resolver = ArtistImageResolver(
            musicBrainz: MusicBrainzClient(session: session, rateLimiter: MusicBrainzRateLimiter(minimumInterval: 0)),
            fanart: FanartTVClient(session: session, apiKeyProvider: { "k" }),
            deezer: DeezerClient(session: session),
            hasFanartKey: { true },
            deezerEnabled: true)
        let result = await resolver.resolve(artistName: "A")
        XCTAssertEqual(result?.source, .deezer)
        XCTAssertEqual(result?.data, Data([0xAA]))
    }

    func testResolverSkipsUnknownArtistAndDisabledSources() async {
        MockURLProtocol.handler = { _ in XCTFail("sin fuentes habilitadas no hay red"); throw URLError(.badURL) }
        let session = mockSession()
        let resolver = ArtistImageResolver(
            musicBrainz: MusicBrainzClient(session: session, rateLimiter: MusicBrainzRateLimiter(minimumInterval: 0)),
            fanart: FanartTVClient(session: session, apiKeyProvider: { nil }),
            deezer: DeezerClient(session: session),
            hasFanartKey: { false },
            deezerEnabled: false)
        let none = await resolver.resolve(artistName: "Alguien")
        XCTAssertNil(none)
        let unknown = await resolver.resolve(artistName: LibraryGrouping.unknownArtistName)
        XCTAssertNil(unknown)
    }
}
