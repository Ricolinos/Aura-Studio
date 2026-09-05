import XCTest
@testable import AuraStudio

/// PLAN-studio-rendimiento.md Fase 4 paso 4: `setRating` deja el
/// `prepareMusic` (transcode/ID3) en `LibraryFileWorker`, fuera del
/// hilo principal. Sustituye a
/// `LibraryPerformanceBaselineTests.testSetRatingMainThreadCost`
/// (ST-155), que medía justo el costo síncrono que este paso elimina.
@MainActor
final class SetRatingWorkerTests: XCTestCase {
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("SetRating-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
        MainThreadWatchdog.onHangDetectedForTesting = nil
    }

    private func freshPreferences() -> AppPreferences {
        AppPreferences(defaults: UserDefaults(suiteName: "SetRatingTests-\(UUID().uuidString)")!)
    }

    private func makeTracks(count: Int, musicDir: URL) throws -> [AuraStudio.LibraryItem] {
        try FileManager.default.createDirectory(at: musicDir, withIntermediateDirectories: true)
        var items: [AuraStudio.LibraryItem] = []
        for i in 0..<count {
            let fileURL = musicDir.appendingPathComponent("pista-\(i).mp3")
            try (Data([0xFF, 0xFB, 0x90, 0x00]) + Data(repeating: UInt8(i % 256), count: 200)).write(to: fileURL)
            var item = AuraStudio.LibraryItem(sourceURL: fileURL, addedAt: Date())
            item.status = .ready
            item.preparedURL = fileURL
            item.metadata = TrackMetadata(title: "Pista \(i)", artist: "Artista", album: "Álbum")
            items.append(item)
        }
        return items
    }

    func testUpdatesRatingAndRepreparesTheFile() async throws {
        let musicDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        let tracks = try makeTracks(count: 1, musicDir: musicDir)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.replaceItemsForPerformanceTesting(tracks)
        viewModel.makePersistenceSynchronousForTesting()

        await viewModel.setRating(4, forItem: tracks[0].id)

        let updated = viewModel.items.first { $0.id == tracks[0].id }
        XCTAssertEqual(updated?.metadata?.rating, 4)
        XCTAssertNotNil(updated?.preparedURL)
    }

    /// Quitar la calificación (nil) es un caso real del inspector -- no
    /// debe dejar `preparedURL` en nil solo porque ya no hay estrellas.
    func testClearingRatingKeepsThePreparedFile() async throws {
        let musicDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        let tracks = try makeTracks(count: 1, musicDir: musicDir)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.replaceItemsForPerformanceTesting(tracks)
        viewModel.makePersistenceSynchronousForTesting()

        await viewModel.setRating(nil, forItem: tracks[0].id)

        let updated = viewModel.items.first { $0.id == tracks[0].id }
        XCTAssertNil(updated?.metadata?.rating)
        XCTAssertNotNil(updated?.preparedURL)
    }

    /// Fotos/video no tienen estrellas -- no debe intentar prepararlos.
    func testNonMusicItemsAreIgnored() async throws {
        let videoDir = libraryRoot.appendingPathComponent("Videos", isDirectory: true)
        try FileManager.default.createDirectory(at: videoDir, withIntermediateDirectories: true)
        let fileURL = videoDir.appendingPathComponent("clip.mp4")
        try Data([0x00, 0x01]).write(to: fileURL)
        var item = AuraStudio.LibraryItem(sourceURL: fileURL, addedAt: Date())
        item.status = .ready
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.replaceItemsForPerformanceTesting([item])
        viewModel.makePersistenceSynchronousForTesting()

        await viewModel.setRating(5, forItem: item.id)

        XCTAssertNil(viewModel.items.first?.metadata?.rating)
    }

    /// Criterio de cierre del paso (Fase 0 §0.4): calificar 300 pistas
    /// SEGUIDAS, una por una -- el escenario real que motivó este paso
    /// ("una estrella", no un lote explícito, ver ST-155) -- cero
    /// bloqueos > 250 ms.
    func testThreeHundredSequentialRatingsNeverBlockTheMainThreadOverTheWatchdogThreshold() async throws {
        setenv("AURA_WATCHDOG", "1", 1)
        let hangs = HangCollector()
        MainThreadWatchdog.onHangDetectedForTesting = { durationMs in hangs.add(durationMs) }
        MainThreadWatchdog.startIfRequested()

        let musicDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        let tracks = try makeTracks(count: 300, musicDir: musicDir)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.replaceItemsForPerformanceTesting(tracks)
        viewModel.makePersistenceSynchronousForTesting()

        for track in tracks {
            await viewModel.setRating(Int.random(in: 1...5), forItem: track.id)
        }

        XCTAssertTrue(hangs.values.isEmpty, "bloqueos del hilo principal > 250 ms calificando 300 pistas: \(hangs.values)")
    }
}
