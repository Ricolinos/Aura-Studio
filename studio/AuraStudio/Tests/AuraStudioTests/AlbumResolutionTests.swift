import XCTest
@testable import AuraStudio

/// ST-263: resolucion a nivel de ALBUM -- una sola edicion de
/// MusicBrainz para todo el grupo, elegida por puntaje y numero de
/// pistas, aplicada llenando solo huecos.
final class AlbumResolutionTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func release(id: String, title: String = "Album", date: String? = "2001-05-01",
                         trackCount: Int? = nil, score: Int? = nil,
                         groupID: String? = nil) -> MusicBrainzClient.Release {
        MusicBrainzClient.Release(id: id, title: title, date: date, status: nil,
                                  country: nil, trackCount: trackCount, score: score,
                                  releaseGroup: groupID.map { MusicBrainzClient.ReleaseGroup(id: $0) })
    }

    // MARK: - pickBestRelease

    func testPickBestReleaseKeepsTheHighestScore() {
        let releases = [release(id: "baja", score: 75), release(id: "alta", score: 98)]
        XCTAssertEqual(LibraryEnricher.pickBestRelease(releases, trackCount: 10)?.id, "alta")
    }

    func testPickBestReleaseRejectsBelowTheThreshold() {
        let releases = [release(id: "baja", score: 40)]
        XCTAssertNil(LibraryEnricher.pickBestRelease(releases, trackCount: 10),
                     "score 40 < umbral (70): mejor sin album que inventado")
    }

    func testPickBestReleaseTreatsMissingScoreAsZero() {
        XCTAssertNil(LibraryEnricher.pickBestRelease([release(id: "sin", score: nil)], trackCount: 10))
    }

    func testPickBestReleaseBreaksTiesWithTheTrackCount() {
        let releases = [release(id: "sencillo", trackCount: 2, score: 90),
                        release(id: "album", trackCount: 12, score: 90)]
        XCTAssertEqual(LibraryEnricher.pickBestRelease(releases, trackCount: 12)?.id, "album",
                       "a igual puntaje gana la edicion con el numero de pistas del grupo")
    }

    // MARK: - Release decodifica score

    func testReleaseSearchDecodesTheScore() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = """
            {"releases": [{"id": "rel-1", "title": "Album", "date": "2001-05-01",
                            "score": 95, "track-count": 12,
                            "release-group": {"id": "grupo-1"}}]}
            """
            return (response, json.data(using: .utf8)!)
        }
        let client = MusicBrainzClient(session: mockSession(),
                                       rateLimiter: MusicBrainzRateLimiter(minimumInterval: 0))
        let releases = try await client.searchReleases(album: "Album", artist: "Artista")
        XCTAssertEqual(releases.first?.score, 95)
        XCTAssertEqual(releases.first?.trackCount, 12)
        XCTAssertEqual(releases.first?.releaseGroup?.id, "grupo-1")
    }

    // MARK: - resolveAlbum

    private func enricherReturning(json: String) -> LibraryEnricher {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json.data(using: .utf8)!)
        }
        let client = MusicBrainzClient(session: mockSession(),
                                       rateLimiter: MusicBrainzRateLimiter(minimumInterval: 0))
        return LibraryEnricher(musicBrainz: client)
    }

    func testResolveAlbumReturnsTheBestRelease() async throws {
        let json = """
        {"releases": [{"id": "rel-baja", "title": "Album (edicion rara)", "score": 72},
                      {"id": "rel-buena", "title": "Album", "date": "2001-05-01",
                       "score": 96, "track-count": 12, "release-group": {"id": "grupo-1"}}]}
        """
        let resolution = try await enricherReturning(json: json)
            .resolveAlbum(album: "Album", artist: "Artista", trackCount: 12, fetchCover: false)

        XCTAssertEqual(resolution?.albumTitle, "Album")
        XCTAssertEqual(resolution?.year, "2001")
        XCTAssertEqual(resolution?.releaseID, "rel-buena")
        XCTAssertEqual(resolution?.releaseGroupID, "grupo-1")
        XCTAssertNil(resolution?.coverData, "fetchCover=false: no se descarga nada")
    }

    func testResolveAlbumReturnsNilWhenNothingPassesTheThreshold() async throws {
        let json = #"{"releases": [{"id": "rel-1", "title": "Otra cosa", "score": 30}]}"#
        let resolution = try await enricherReturning(json: json)
            .resolveAlbum(album: "Album", artist: "Artista", trackCount: 12, fetchCover: false)
        XCTAssertNil(resolution)
    }

    // MARK: - applyingAlbum

    func testApplyingAlbumFillsOnlyTheGaps() {
        let resolution = LibraryEnricher.AlbumResolution(
            albumTitle: "Album remoto", year: "2001", releaseID: "rel-1",
            releaseGroupID: "grupo-1", coverData: Data([0x01, 0x02]))

        var completo = TrackMetadata(title: "Cancion", artist: "Artista",
                                     album: "Album corregido a mano", year: "1999",
                                     coverURL: URL(fileURLWithPath: "/tmp/caratula.jpg"))
        completo.musicBrainzReleaseID = "rel-vieja"
        let intacto = LibraryEnricher.applyingAlbum(resolution, to: completo)
        XCTAssertEqual(intacto.album, "Album corregido a mano", "nunca pisa un valor existente")
        XCTAssertEqual(intacto.year, "1999")
        XCTAssertEqual(intacto.musicBrainzReleaseID, "rel-vieja")
        XCTAssertEqual(intacto.coverURL?.lastPathComponent, "caratula.jpg")

        let hueco = LibraryEnricher.applyingAlbum(resolution, to: TrackMetadata(title: "Cancion"))
        XCTAssertEqual(hueco.album, "Album remoto")
        XCTAssertEqual(hueco.year, "2001")
        XCTAssertEqual(hueco.musicBrainzReleaseID, "rel-1")
        XCTAssertTrue(hueco.hasCover, "la caratula del grupo se aplica a quien no tiene")
    }
}
