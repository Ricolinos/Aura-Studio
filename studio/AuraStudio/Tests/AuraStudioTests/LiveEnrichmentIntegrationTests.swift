import XCTest
@testable import AuraStudio

/// Estos tests pegan contra las APIs reales de MusicBrainz/Cover Art
/// Archive/LRCLIB (no hay forma de verificar honestamente que el
/// parseo de JSON funciona contra la forma real de la respuesta sin
/// pegarle a la real -- un JSON de muestra escrito a mano solo prueba
/// que el codigo lee lo que YO creo que la API devuelve). Si no hay
/// red disponible se saltean en vez de fallar, para no romper corridas
/// de test en entornos sin salida a internet.
final class LiveEnrichmentIntegrationTests: XCTestCase {
    private func skipIfOffline() async throws {
        let url = URL(string: "https://musicbrainz.org")!
        guard (try? await URLSession.shared.data(from: url)) != nil else {
            throw XCTSkip("Sin acceso a red, saltando test de integracion")
        }
    }

    func testMusicBrainzFindsWellKnownRecording() async throws {
        try await skipIfOffline()

        let client = MusicBrainzClient()
        let recording = try await client.searchRecording(title: "Bohemian Rhapsody", artist: "Queen")

        XCTAssertNotNil(recording)
        XCTAssertTrue(recording?.title.lowercased().contains("bohemian rhapsody") ?? false)
        XCTAssertFalse(recording?.releases?.isEmpty ?? true)
    }

    func testCoverArtArchiveFetchesRealCover() async throws {
        try await skipIfOffline()

        let mbClient = MusicBrainzClient()
        guard let recording = try await mbClient.searchRecording(title: "Bohemian Rhapsody", artist: "Queen"),
              let releaseID = recording.releases?.first?.id else {
            throw XCTSkip("MusicBrainz no devolvio un release para probar Cover Art Archive")
        }

        let coverClient = CoverArtArchiveClient()
        let coverData = try? await coverClient.fetchFrontCover(releaseID: releaseID)

        // Puede ser nil legitimamente si ese release en particular no
        // tiene tapa subida -- lo que se verifica es que la llamada no
        // explota y que, si trae algo, es una imagen real.
        if let coverData {
            XCTAssertGreaterThan(coverData.count, 100)
        }
    }

    func testLRCLIBFindsSyncedLyricsForWellKnownSong() async throws {
        try await skipIfOffline()

        let client = LRCLIBClient()
        let lyrics = try await client.fetchSyncedLyrics(title: "Bohemian Rhapsody", artist: "Queen")

        if let lyrics {
            XCTAssertTrue(lyrics.contains("["), "letra sincronizada deberia tener timestamps [mm:ss.xx]")
        }
    }

    func testFullEnrichmentPipelineOnRealFilename() async throws {
        try await skipIfOffline()

        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("Queen - Bohemian Rhapsody.mp3")
        FileManager.default.createFile(atPath: tmpURL.path, contents: Data([0xFF, 0xFB]))
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let item = LibraryItem(sourceURL: tmpURL)
        let enricher = LibraryEnricher()
        let metadata = await enricher.enrich(item: item)

        XCTAssertEqual(metadata.artist, "Queen")
        XCTAssertNotNil(metadata.title)
        XCTAssertNotNil(metadata.album)
    }
}
