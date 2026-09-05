import XCTest
@testable import AuraStudio

/// Colector thread-safe para `MainThreadWatchdog.onHangDetectedForTesting`
/// -- el gancho es `@Sendable` porque el manejador de señal corre en el
/// hilo principal REAL (interrumpido), nunca en el actor de la prueba;
/// una `var` local capturada por la clausura no compila bajo
/// concurrencia estricta.
final class HangCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int] = []

    func add(_ value: Int) {
        lock.lock(); storage.append(value); lock.unlock()
    }

    var values: [Int] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}

/// PLAN-studio-rendimiento.md Fase 4 paso 2: `applyBatchEdit` corre
/// `prepareMusic` en `fileWorker` (fuera del actor principal) y aplica
/// los resultados a `items` en lotes, no uno por ítem.
@MainActor
final class ApplyBatchEditWorkerTests: XCTestCase {
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("BatchEditWorker-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
        MainThreadWatchdog.onHangDetectedForTesting = nil
    }

    private func freshPreferences() -> AppPreferences {
        AppPreferences(defaults: UserDefaults(suiteName: "BatchEditWorkerTests-\(UUID().uuidString)")!)
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
            item.metadata = TrackMetadata(title: "Canción \(i)", artist: "Artista viejo", album: "Álbum \(i % 10)")
            items.append(item)
        }
        return items
    }

    func testAppliesTheChangeToEveryTargetedItem() async throws {
        let musicDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        let tracks = try makeTracks(count: 30, musicDir: musicDir)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.replaceItemsForPerformanceTesting(tracks)
        viewModel.makePersistenceSynchronousForTesting()

        let ids = Set(tracks.prefix(10).map(\.id))
        await viewModel.applyBatchEdit(ids: ids, changes: BatchMetadataChanges(artist: "Artista nuevo"))

        for item in viewModel.items where ids.contains(item.id) {
            XCTAssertEqual(item.metadata?.artist, "Artista nuevo")
            XCTAssertTrue(item.metadataEditedByUser)
        }
        for item in viewModel.items where !ids.contains(item.id) {
            XCTAssertEqual(item.metadata?.artist, "Artista viejo", "no debe tocar ítems fuera de la selección")
        }
    }

    func testReportsProgressToTheTaskCenterAndFinishesWhenDone() async throws {
        let musicDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        let tracks = try makeTracks(count: 5, musicDir: musicDir)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.replaceItemsForPerformanceTesting(tracks)
        viewModel.makePersistenceSynchronousForTesting()

        XCTAssertTrue(viewModel.taskCenter.isEmpty)
        await viewModel.applyBatchEdit(ids: Set(tracks.map(\.id)), changes: BatchMetadataChanges(genre: "Jazz"))
        XCTAssertTrue(viewModel.taskCenter.isEmpty, "la tarea debe desregistrarse sola al terminar")
    }

    /// PLAN-studio-rendimiento.md Fase 4, criterio de cierre del paso 2:
    /// cero bloqueos > 250 ms con 500 ítems. `AURA_WATCHDOG` se activa
    /// EN LA PRUEBA (nunca corrió antes en este proceso -- las pruebas
    /// no pasan por `AuraStudioApp.init()`), y se verifica con un gancho
    /// en vez de leer la salida de consola.
    func testFiveHundredItemsNeverBlockTheMainThreadOverTheWatchdogThreshold() async throws {
        setenv("AURA_WATCHDOG", "1", 1)
        let hangs = HangCollector()
        MainThreadWatchdog.onHangDetectedForTesting = { durationMs in hangs.add(durationMs) }
        MainThreadWatchdog.startIfRequested()

        let musicDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        let tracks = try makeTracks(count: 500, musicDir: musicDir)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.replaceItemsForPerformanceTesting(tracks)
        viewModel.makePersistenceSynchronousForTesting()

        await viewModel.applyBatchEdit(ids: Set(tracks.map(\.id)), changes: BatchMetadataChanges(year: "2000"))

        XCTAssertTrue(hangs.values.isEmpty, "bloqueos del hilo principal > 250 ms durante la edición en lote: \(hangs.values)")
    }
}
