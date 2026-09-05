import XCTest
@testable import AuraStudio

/// PLAN-studio-rendimiento.md Fase 3: `persistCatalog()` deja de
/// reescribir todas las carátulas en cada guardado (punto 2) y las
/// acciones sobre selección múltiple persisten una sola vez (punto 4).
@MainActor
final class PersistCatalogCoalescedTests: XCTestCase {
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("PersistCoalesced-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    private func freshPreferences() -> AppPreferences {
        AppPreferences(defaults: UserDefaults(suiteName: "PersistCoalescedTests-\(UUID().uuidString)")!)
    }

    private func makeReadyMusicItem(cover: Data?) throws -> AuraStudio.LibraryItem {
        let musicDir = libraryRoot.appendingPathComponent(PersistedLibrary.musicDirName, isDirectory: true)
        try FileManager.default.createDirectory(at: musicDir, withIntermediateDirectories: true)
        let fileURL = musicDir.appendingPathComponent("cancion-\(UUID().uuidString).mp3")
        try Data([0x01]).write(to: fileURL)
        var item = AuraStudio.LibraryItem(sourceURL: fileURL, addedAt: Date())
        item.status = .ready
        item.preparedURL = fileURL
        item.metadata = TrackMetadata(title: "Canción", coverArtData: cover)
        return item
    }

    /// Una carátula sin cambios entre dos guardados NO se vuelve a
    /// escribir -- pero el catálogo persistido sigue declarando su ruta
    /// correctamente (el archivo ya está en disco de un guardado
    /// anterior). Es la propiedad crítica: "no reescribir" nunca debe
    /// significar "olvidarse de que existe".
    func testUnchangedCoverKeepsItsRecordedPathAcrossSaves() throws {
        let cover = Data(repeating: 0xAB, count: 4_096)
        let item = try makeReadyMusicItem(cover: cover)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.replaceItemsForPerformanceTesting([item])

        viewModel.persistCatalog()
        let coverURL = libraryRoot
            .appendingPathComponent(PersistedLibrary.coversDirName)
            .appendingPathComponent("\(item.id.uuidString).jpg")
        let firstWriteDate = try FileManager.default.attributesOfItem(atPath: coverURL.path)[.modificationDate] as? Date

        // Segundo guardado, misma carátula: el archivo no debería
        // tocarse (mismo mtime), pero el catálogo debe seguir
        // declarando la ruta.
        Thread.sleep(forTimeInterval: 0.05)
        viewModel.persistCatalog()
        let secondWriteDate = try FileManager.default.attributesOfItem(atPath: coverURL.path)[.modificationDate] as? Date
        XCTAssertEqual(firstWriteDate, secondWriteDate, "una carátula sin cambios no debería reescribirse")

        let reloaded = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        XCTAssertEqual(reloaded.items.first?.metadata?.coverArtData, cover,
                       "el catálogo debe seguir sabiendo dónde está la carátula aunque no se haya reescrito")
    }

    /// Si la carátula SÍ cambia, se reescribe (no se queda pegada al
    /// hash viejo para siempre).
    func testChangedCoverIsRewritten() throws {
        let item = try makeReadyMusicItem(cover: Data(repeating: 0x01, count: 100))
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.replaceItemsForPerformanceTesting([item])
        viewModel.persistCatalog()

        var changed = item
        changed.metadata?.coverArtData = Data(repeating: 0x02, count: 100)
        viewModel.replaceItemsForPerformanceTesting([changed])
        viewModel.persistCatalog()

        let reloaded = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        XCTAssertEqual(reloaded.items.first?.metadata?.coverArtData, Data(repeating: 0x02, count: 100))
    }

    /// PLAN-studio-rendimiento.md Fase 3 punto 4: `clearCoverArt(ids:)`
    /// sobre varios ítems a la vez limpia todos y persiste -- el catálogo
    /// recargado no debe declarar ninguna carátula para ninguno.
    func testClearCoverArtBatchClearsAllSelectedItems() throws {
        let itemA = try makeReadyMusicItem(cover: Data(repeating: 0x01, count: 50))
        let itemB = try makeReadyMusicItem(cover: Data(repeating: 0x02, count: 50))
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.replaceItemsForPerformanceTesting([itemA, itemB])
        viewModel.persistCatalog()

        viewModel.clearCoverArt(ids: [itemA.id, itemB.id])

        XCTAssertNil(viewModel.items.first { $0.id == itemA.id }?.metadata?.coverArtData)
        XCTAssertNil(viewModel.items.first { $0.id == itemB.id }?.metadata?.coverArtData)

        let reloaded = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        XCTAssertEqual(reloaded.items.count, 2)
        XCTAssertTrue(reloaded.items.allSatisfy { $0.metadata?.coverArtData == nil })
    }

    /// `clearCoverArt(id:)` (un solo ítem) sigue funcionando igual que
    /// antes -- ahora delega a `clearCoverArt(ids:)`.
    func testClearCoverArtSingleItemStillWorks() throws {
        let item = try makeReadyMusicItem(cover: Data(repeating: 0x01, count: 50))
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.replaceItemsForPerformanceTesting([item])
        viewModel.persistCatalog()

        viewModel.clearCoverArt(id: item.id)

        XCTAssertNil(viewModel.items.first?.metadata?.coverArtData)
    }
}
