import XCTest
@testable import AuraStudio

/// Cubre dos piezas de §2 (PLAN-studio-ux.md) que no tienen test propio
/// todavia: que `enrich()` ahora usa `LocalTagReader` para TODOS los
/// formatos (no solo mp3), y el umbral minimo de `score` de MusicBrainz
/// que evita rellenar album/año con un resultado de baja confianza. Usa
/// `MockURLProtocol` (mismo patron que `GitHubReleaseCheckerFetchTests`)
/// para no depender de la red real -- `LiveEnrichmentIntegrationTests`
/// ya cubre el camino contra la API real.
final class LibraryEnricherTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func enricher(musicBrainzJSON: String) -> LibraryEnricher {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, musicBrainzJSON.data(using: .utf8)!)
        }
        let client = MusicBrainzClient(session: mockSession(), rateLimiter: MusicBrainzRateLimiter(minimumInterval: 0))
        return LibraryEnricher(musicBrainz: client)
    }

    private func makeItem(named name: String) throws -> AuraStudio.LibraryItem {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LibraryEnricherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(name)
        try Data().write(to: url)
        return AuraStudio.LibraryItem(sourceURL: url)
    }

    private func recordingJSON(score: Int?) -> String {
        let scoreField = score.map { "\"score\": \($0)," } ?? ""
        return """
        {"recordings": [{"id": "rec-1", "title": "Titulo remoto", \(scoreField)
          "artist-credit": [{"name": "Artista remoto"}],
          "releases": [{"id": "rel-1", "title": "Album remoto", "date": "2021-01-01"}]}]}
        """
    }

    func testLowScoreRecordingDoesNotFillAlbum() async throws {
        let item = try makeItem(named: "Artista Bajo Score - Cancion.mp3")
        let enricher = enricher(musicBrainzJSON: recordingJSON(score: 40))

        let metadata = await enricher.enrich(item: item, lyrics: false, coverArtOrder: [])

        XCTAssertNil(metadata.album, "score 40 < umbral (70): no deberia rellenar album con un resultado de baja confianza")
        XCTAssertNil(metadata.year)
        XCTAssertEqual(metadata.artist, "Artista Bajo Score", "el titulo/artista adivinados del nombre de archivo no dependen del score")
    }

    func testMissingScoreIsTreatedAsZero() async throws {
        let item = try makeItem(named: "Artista Sin Score - Cancion.mp3")
        let enricher = enricher(musicBrainzJSON: recordingJSON(score: nil))

        let metadata = await enricher.enrich(item: item, lyrics: false, coverArtOrder: [])

        XCTAssertNil(metadata.album, "score ausente se trata como 0, por debajo del umbral")
    }

    func testHighScoreRecordingFillsAlbum() async throws {
        let item = try makeItem(named: "Artista Alto Score - Cancion.mp3")
        let enricher = enricher(musicBrainzJSON: recordingJSON(score: 95))

        let metadata = await enricher.enrich(item: item, lyrics: false, coverArtOrder: [])

        XCTAssertEqual(metadata.album, "Album remoto")
        XCTAssertEqual(metadata.year, "2021")
    }

    func testEnrichReadsLocalTagsForFLACNotJustMP3() async throws {
        // Sin handler de red configurado (la llamada a MusicBrainz falla
        // y `enrich()` la traga con `try?`, como siempre) -- si esto
        // devuelve la metadata completa igual es porque vino de
        // `LocalTagReader`. Antes de este cambio `enrich()` solo leia
        // tags locales para `.mp3` (via `ID3Writer.readTag`): un FLAC
        // llegaba aca con todo `nil`.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LibraryEnricherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }

        guard let ffmpeg = FFmpegLocator.locate() else {
            throw XCTSkip("ffmpeg no esta instalado")
        }
        let url = dir.appendingPathComponent("test.flac")
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = [
            "-y", "-loglevel", "error",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
            "-metadata", "title=Ya Tiene Todo", "-metadata", "artist=Artista Local",
            "-metadata", "album=Album Local",
            url.path,
        ]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw XCTSkip("ffmpeg no pudo generar el fixture")
        }

        let item = AuraStudio.LibraryItem(sourceURL: url)
        let metadata = await LibraryEnricher(musicBrainz: MusicBrainzClient(session: mockSession())).enrich(item: item, lyrics: false, coverArtOrder: [])

        XCTAssertEqual(metadata.title, "Ya Tiene Todo")
        XCTAssertEqual(metadata.artist, "Artista Local")
        XCTAssertEqual(metadata.album, "Album Local")
    }
}
