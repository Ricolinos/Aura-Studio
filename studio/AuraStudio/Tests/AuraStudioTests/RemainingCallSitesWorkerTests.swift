import XCTest
@testable import AuraStudio

/// PLAN-studio-rendimiento.md Fase 4 paso 5: los últimos llamadores
/// síncronos de `prepareMusic` -- importar (`process(itemAt:)`,
/// `processAll()`), `applyReview`, `renameItem`, `reenrichOnline` y
/// `rereadLocalTags` (estas dos últimas ya tenían pruebas de
/// corrección propias en otros archivos; acá solo lo nuevo: que
/// pasan por `fileWorker` en lotes, y el criterio de cierre).
/// Alcance deliberado: solo la rama MÚSICA de `process(itemAt:)`. Las
/// ramas video/foto de esa misma función también hacen trabajo pesado
/// síncrono (transcodificación completa, `ImageResizer`) pero eso es
/// un problema aparte de `LibraryFileWorker` (pensado para
/// `prepareMusic`, no para todo el pipeline de importación) -- fuera
/// de esta ronda.
@MainActor
final class RemainingCallSitesWorkerTests: XCTestCase {
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("RemainingCallSites-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
        MainThreadWatchdog.onHangDetectedForTesting = nil
    }

    /// `enrichOnline` es `true` por default (D-...): sin apagarlo acá,
    /// `processAll()` intentaría pegarle a MusicBrainz/Deezer de
    /// verdad con estas pistas sintéticas.
    private func offlinePreferences() -> AppPreferences {
        let prefs = AppPreferences(defaults: makeIsolatedDefaults("RemainingCallSitesTests"))
        prefs.enrichOnline = false
        prefs.copyMediaIntoLibrary = false
        return prefs
    }

    private func makeQueuedTracks(count: Int, musicDir: URL) throws -> [AuraStudio.LibraryItem] {
        try FileManager.default.createDirectory(at: musicDir, withIntermediateDirectories: true)
        var items: [AuraStudio.LibraryItem] = []
        for i in 0..<count {
            let fileURL = musicDir.appendingPathComponent("pista-\(i).mp3")
            try (Data([0xFF, 0xFB, 0x90, 0x00]) + Data(repeating: UInt8(i % 256), count: 200)).write(to: fileURL)
            var item = AuraStudio.LibraryItem(sourceURL: fileURL, addedAt: Date())
            item.status = .queued
            items.append(item)
        }
        return items
    }

    private func makeReadyTracks(count: Int, musicDir: URL) throws -> [AuraStudio.LibraryItem] {
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

    // MARK: - Importar (processAll)

    func testImportRoutesMusicPrepareThroughFileWorker() async throws {
        let musicDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        let tracks = try makeQueuedTracks(count: 5, musicDir: musicDir)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: offlinePreferences())
        viewModel.replaceItemsForPerformanceTesting(tracks)
        viewModel.makePersistenceSynchronousForTesting()

        await viewModel.processAll()

        XCTAssertEqual(viewModel.items.count, 5)
        for item in viewModel.items {
            XCTAssertNotNil(item.preparedURL)
            if case .failed = item.status {
                XCTFail("no debería fallar preparando una pista sintética válida: \(item.status)")
            }
        }
    }

    /// Criterio de cierre del paso: importar 300 pistas SEGUIDAS (el
    /// camino de más impacto -- son todas las canciones nuevas, una
    /// por una) con el vigilante real activado -- cero bloqueos > 250 ms.
    func testBulkImportNeverBlocksTheMainThreadOverTheWatchdogThreshold() async throws {
        setenv("AURA_WATCHDOG", "1", 1)
        let hangs = HangCollector()
        MainThreadWatchdog.onHangDetectedForTesting = { durationMs in hangs.add(durationMs) }
        MainThreadWatchdog.startIfRequested()

        let musicDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        let tracks = try makeQueuedTracks(count: 300, musicDir: musicDir)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: offlinePreferences())
        viewModel.replaceItemsForPerformanceTesting(tracks)
        viewModel.makePersistenceSynchronousForTesting()

        await viewModel.processAll()

        XCTAssertTrue(hangs.values.isEmpty, "bloqueos del hilo principal > 250 ms importando 300 pistas: \(hangs.values)")
    }

    // MARK: - applyReview / renameItem (un solo ítem)

    func testApplyReviewUpdatesMetadataAndPreparedFile() async throws {
        let musicDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        let tracks = try makeReadyTracks(count: 1, musicDir: musicDir)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: offlinePreferences())
        viewModel.replaceItemsForPerformanceTesting(tracks)
        viewModel.makePersistenceSynchronousForTesting()

        var corrected = TrackMetadata(title: "Título corregido", artist: "Artista", album: "Álbum")
        corrected.genre = "Rock"
        await viewModel.applyReview(id: tracks[0].id, metadata: corrected)

        let updated = viewModel.items.first { $0.id == tracks[0].id }
        XCTAssertEqual(updated?.metadata?.title, "Título corregido")
        XCTAssertTrue(updated?.metadataEditedByUser ?? false)
        XCTAssertNotNil(updated?.preparedURL)
    }

    func testRenameItemUpdatesTitleForMusicOnly() async throws {
        let musicDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        let tracks = try makeReadyTracks(count: 1, musicDir: musicDir)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: offlinePreferences())
        viewModel.replaceItemsForPerformanceTesting(tracks)
        viewModel.makePersistenceSynchronousForTesting()

        await viewModel.renameItem(id: tracks[0].id, title: "Nuevo título")

        let updated = viewModel.items.first { $0.id == tracks[0].id }
        XCTAssertEqual(updated?.metadata?.title, "Nuevo título")
        XCTAssertNotNil(updated?.preparedURL)
    }

    // MARK: - reenrichOnline / rereadLocalTags (lotes)

    /// `fetchAlbumInfo`/`fetchLyrics` en `false`: `LibraryEnricher.
    /// reenrich` no hace ninguna llamada de red con ambos apagados
    /// (ver su cuerpo) -- prueba determinística, sin mocks de red.
    func testReenrichOnlineWithNoFetchesStillRoutesPrepareThroughFileWorker() async throws {
        let musicDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        let tracks = try makeReadyTracks(count: 3, musicDir: musicDir)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: offlinePreferences())
        viewModel.replaceItemsForPerformanceTesting(tracks)
        viewModel.makePersistenceSynchronousForTesting()

        await viewModel.reenrichOnline(ids: Set(tracks.map(\.id)), fetchAlbumInfo: false, fetchLyrics: false)

        for item in viewModel.items {
            XCTAssertNotNil(item.preparedURL)
        }
        XCTAssertTrue(viewModel.taskCenter.isEmpty)
    }

    /// Criterio de cierre: 300 pistas por `reenrichOnline` (sin red) y
    /// otras 300 por `rereadLocalTags` -- cero bloqueos > 250 ms.
    func testReenrichAndRereadNeverBlockTheMainThreadOverTheWatchdogThreshold() async throws {
        setenv("AURA_WATCHDOG", "1", 1)
        let hangs = HangCollector()
        MainThreadWatchdog.onHangDetectedForTesting = { durationMs in hangs.add(durationMs) }
        MainThreadWatchdog.startIfRequested()

        let musicDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        let tracks = try makeReadyTracks(count: 300, musicDir: musicDir)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: offlinePreferences())
        viewModel.replaceItemsForPerformanceTesting(tracks)
        viewModel.makePersistenceSynchronousForTesting()

        await viewModel.reenrichOnline(ids: Set(tracks.map(\.id)), fetchAlbumInfo: false, fetchLyrics: false)
        await viewModel.rereadLocalTags(ids: Set(tracks.map(\.id)))

        XCTAssertTrue(hangs.values.isEmpty, "bloqueos del hilo principal > 250 ms en reenrichOnline/rereadLocalTags: \(hangs.values)")
    }
}
