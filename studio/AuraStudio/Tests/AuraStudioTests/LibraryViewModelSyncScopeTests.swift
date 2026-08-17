import XCTest
@testable import AuraStudio

/// PLAN-general-sync.md §6: "Sincronizar solo la selección" con nada
/// seleccionado nunca debe fallar -- se resuelve como un no-op seguro,
/// sin tocar el dispositivo en absoluto.
@MainActor
final class LibraryViewModelSyncScopeTests: XCTestCase {
    private var libraryRoot: URL!
    private var fakeIPod: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("SyncScopeLibrary-\(UUID().uuidString)")
        fakeIPod = FileManager.default.temporaryDirectory.appendingPathComponent("SyncScopeIPod-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeIPod, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
        try? FileManager.default.removeItem(at: fakeIPod)
    }

    private func freshPreferences() -> AppPreferences {
        AppPreferences(defaults: UserDefaults(suiteName: "SyncScopeTests-\(UUID().uuidString)")!)
    }

    func testEmptySelectionScopeDoesNotTouchTheDevice() async throws {
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())

        await viewModel.sync(toVolumeAt: fakeIPod, scope: .selection([]))

        XCTAssertEqual(viewModel.lastSyncSummary, "No hay ningún elemento seleccionado para sincronizar.")
        XCTAssertNil(viewModel.lastError)
        let manifestURL = fakeIPod.appendingPathComponent(LibrarySync.manifestRelativePath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: manifestURL.path), "no debe haber escrito absolutamente nada en el dispositivo")
        let markerURL = fakeIPod.appendingPathComponent(LibrarySync.inProgressMarkerRelativePath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
    }

    func testSelectionScopeWithIDsThatAreNotReadyIsAlsoASafeNoOp() async throws {
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("not-ready-\(UUID().uuidString).mp3")
        try Data("x".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        viewModel.addDroppedFiles([sourceURL]) // queda en .queued, nunca llega a .ready
        let id = try XCTUnwrap(viewModel.items.first?.id)

        await viewModel.sync(toVolumeAt: fakeIPod, scope: .selection([id]))

        XCTAssertEqual(viewModel.lastSyncSummary, "Los elementos seleccionados todavía no están listos para sincronizar.")
        let manifestURL = fakeIPod.appendingPathComponent(LibrarySync.manifestRelativePath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: manifestURL.path))
    }

    func testCancelSyncWithNoActiveSyncDoesNothing() {
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.cancelSync() // no debe fallar ni tener efecto observable
        XCTAssertNil(viewModel.syncProgress)
    }
}
