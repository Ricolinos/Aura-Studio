import XCTest
@testable import AuraStudio

/// ST-264: dedupe de `.portadas/` por contenido -- el plan puro, la
/// accion al quitar/eliminar, y el comportamiento de punta a punta
/// (persistencia, borrado y re-alojado) con una biblioteca temporal.
@MainActor
final class CoverDedupeTests: XCTestCase {
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoverDedupe-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    private func freshPreferences() -> AppPreferences {
        AppPreferences(defaults: makeIsolatedDefaults("CoverDedupeTests"))
    }

    private let coverBytes = Data(repeating: 0xCD, count: 2_048)

    private func makeReadyMusicItem(cover: Data?) throws -> AuraStudio.LibraryItem {
        let musicDir = libraryRoot.appendingPathComponent(PersistedLibrary.musicDirName, isDirectory: true)
        try FileManager.default.createDirectory(at: musicDir, withIntermediateDirectories: true)
        let fileURL = musicDir.appendingPathComponent("cancion-\(UUID().uuidString).mp3")
        try Data([0x01]).write(to: fileURL)
        var item = AuraStudio.LibraryItem(sourceURL: fileURL, addedAt: Date())
        item.status = .ready
        item.preparedURL = fileURL
        item.metadata = TrackMetadata(title: "Cancion", coverArtData: cover)
        return item
    }

    /// Un elemento con caratula YA en disco (archivo escrito a mano),
    /// para probar el plan sin pasar por la persistencia.
    private func makeItemWithCoverOnDisk(bytes: Data) throws -> AuraStudio.LibraryItem {
        var item = try makeReadyMusicItem(cover: nil)
        let url = CoverStore.url(forItem: item.id, in: libraryRoot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url)
        item.metadata = TrackMetadata(title: "Cancion", coverURL: url, coverHash: CoverStore.hash(bytes))
        return item
    }

    private func coverFileCount() -> Int {
        let dir = libraryRoot.appendingPathComponent(PersistedLibrary.coversDirName, isDirectory: true)
        return (try? FileManager.default.contentsOfDirectory(atPath: dir.path).count) ?? 0
    }

    // MARK: - Plan puro

    func testPlanGroupsIdenticalCoversIntoTheSmallestUUIDCanonical() throws {
        let itemA = try makeItemWithCoverOnDisk(bytes: coverBytes)
        let itemB = try makeItemWithCoverOnDisk(bytes: coverBytes)
        let (owner, sharer) = itemA.id.uuidString < itemB.id.uuidString ? (itemA, itemB) : (itemB, itemA)

        let plan = CoverDedupe.plan(items: [itemA, itemB], libraryRoot: libraryRoot)

        XCTAssertEqual(plan.reassignments[sharer.id], CoverStore.url(forItem: owner.id, in: libraryRoot))
        XCTAssertNil(plan.reassignments[owner.id], "el sobreviviente no se reapunta")
        XCTAssertEqual(plan.filesToDelete, [CoverStore.url(forItem: sharer.id, in: libraryRoot)])
    }

    func testPlanSkipsDifferentImagesMissingHashesAndMissingFiles() throws {
        let other = try makeItemWithCoverOnDisk(bytes: Data(repeating: 0x01, count: 100))
        let sameA = try makeItemWithCoverOnDisk(bytes: coverBytes)
        let sameB = try makeItemWithCoverOnDisk(bytes: coverBytes)
        var noHash = try makeItemWithCoverOnDisk(bytes: coverBytes)
        noHash.metadata?.coverHash = nil // "no se sabe": nunca es prueba
        var noFile = try makeItemWithCoverOnDisk(bytes: coverBytes)
        let gone = CoverStore.url(forItem: noFile.id, in: libraryRoot)
        try FileManager.default.removeItem(at: gone)
        noFile.metadata = TrackMetadata(title: "Cancion", coverURL: gone, coverHash: CoverStore.hash(coverBytes))

        let plan = CoverDedupe.plan(items: [other, sameA, sameB, noHash, noFile], libraryRoot: libraryRoot)

        XCTAssertEqual(plan.reassignments.count, 1, "solo el par identico con hash y archivo se agrupa")
        XCTAssertEqual(plan.filesToDelete.count, 1)
        XCTAssertFalse(plan.reassignments.keys.contains(other.id))
    }

    // MARK: - Accion al quitar/eliminar

    func testRemovedCoverIsDeletedWhenNobodySharesIt() throws {
        let item = try makeItemWithCoverOnDisk(bytes: coverBytes)
        let action = CoverDedupe.actionForRemovedCover(
            itemID: item.id, coverURL: item.metadata!.coverURL!,
            remaining: [], libraryRoot: libraryRoot)
        XCTAssertEqual(action, .deleteFile)
    }

    func testRemovedCoverIsKeptWhenNamedAfterASurvivor() throws {
        let owner = try makeItemWithCoverOnDisk(bytes: coverBytes)
        var sharer = try makeReadyMusicItem(cover: nil)
        // El que se va apuntaba a la canonica del que se queda.
        sharer.metadata = TrackMetadata(title: "Cancion",
                                        coverURL: CoverStore.url(forItem: owner.id, in: libraryRoot),
                                        coverHash: CoverStore.hash(coverBytes))
        let removed = try makeReadyMusicItem(cover: nil)
        let action = CoverDedupe.actionForRemovedCover(
            itemID: removed.id, coverURL: owner.metadata!.coverURL!,
            remaining: [owner, sharer], libraryRoot: libraryRoot)
        XCTAssertEqual(action, .keep)
    }

    func testRemovedCoverIsRehomedWhenNamedAfterTheRemovedItem() throws {
        let owner = try makeItemWithCoverOnDisk(bytes: coverBytes)
        var sharer = try makeReadyMusicItem(cover: nil)
        sharer.metadata = TrackMetadata(title: "Cancion",
                                        coverURL: owner.metadata!.coverURL!,
                                        coverHash: CoverStore.hash(coverBytes))
        let action = CoverDedupe.actionForRemovedCover(
            itemID: owner.id, coverURL: owner.metadata!.coverURL!,
            remaining: [sharer], libraryRoot: libraryRoot)
        XCTAssertEqual(action, .rehome(toItem: sharer.id, sharerIDs: [sharer.id]))
    }

    // MARK: - Punta a punta: persistencia

    /// Dos canciones con la MISMA imagen pendiente escriben UN solo
    /// archivo, y las dos quedan apuntando a el -- tambien tras
    /// recargar el catalogo.
    func testWriteTimeDedupeStoresOneFileForIdenticalCovers() throws {
        let itemA = try makeReadyMusicItem(cover: coverBytes)
        let itemB = try makeReadyMusicItem(cover: coverBytes)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.replaceItemsForPerformanceTesting([itemA, itemB])

        viewModel.persistCatalog()

        XCTAssertEqual(coverFileCount(), 1, "dos portadas identicas = un archivo")
        let reloaded = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        XCTAssertEqual(reloaded.items.count, 2)
        XCTAssertEqual(reloaded.items.compactMap { $0.metadata?.coverURL }.count, 2)
        XCTAssertEqual(Set(reloaded.items.compactMap { $0.metadata?.coverURL }), [CoverStore.url(forItem: itemA.id, in: libraryRoot)],
                       "las dos apuntan al archivo del primero")
        XCTAssertEqual(reloaded.items.first?.metadata?.loadCoverData(), coverBytes)
    }

    /// La ruta anotada (compartida) sobrevive a guardados posteriores:
    /// antes se re-derivaba del id y el catalogo volvia a apuntar a un
    /// archivo inexistente.
    func testSharedCoverPathSurvivesLaterSaves() throws {
        let itemA = try makeReadyMusicItem(cover: coverBytes)
        let itemB = try makeReadyMusicItem(cover: coverBytes)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.replaceItemsForPerformanceTesting([itemA, itemB])
        viewModel.persistCatalog()
        viewModel.persistCatalog() // el segundo guardado no deshace el dedupe

        let reloaded = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        let urls = Set(reloaded.items.compactMap { $0.metadata?.coverURL })
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(reloaded.items.first { $0.id == itemB.id }?.metadata?.loadCoverData(), coverBytes)
    }

    // MARK: - Punta a punta: re-alojado

    /// Eliminar al dueño del archivo compartido lo re-aloja: el archivo
    /// pasa a la canonica del sobreviviente y este no pierde la tapa.
    func testDeletingTheCoverOwnerRehomesTheSharedFile() throws {
        let owner = try makeReadyMusicItem(cover: coverBytes)
        let sharer = try makeReadyMusicItem(cover: coverBytes)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.replaceItemsForPerformanceTesting([owner, sharer])
        viewModel.persistCatalog()
        XCTAssertEqual(coverFileCount(), 1)

        viewModel.performDeletion(ids: [owner.id])

        XCTAssertEqual(coverFileCount(), 1, "la caratula compartida sobrevive al dueño del nombre")
        let survivorURL = CoverStore.url(forItem: sharer.id, in: libraryRoot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: survivorURL.path),
                      "el archivo quedo con el nombre del sobreviviente")
        XCTAssertEqual(viewModel.items.first { $0.id == sharer.id }?.metadata?.coverURL, survivorURL)

        let reloaded = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        XCTAssertEqual(reloaded.items.first?.metadata?.loadCoverData(), coverBytes)
    }

    /// "Quitar caratula" del dueño del archivo compartido tambien lo
    /// re-aloja: el otro elemento conserva su tapa.
    func testClearingCoverOnTheOwnerRehomesTheSharedFile() async throws {
        let owner = try makeReadyMusicItem(cover: coverBytes)
        let sharer = try makeReadyMusicItem(cover: coverBytes)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.replaceItemsForPerformanceTesting([owner, sharer])
        viewModel.persistCatalog()

        await viewModel.clearCoverArt(ids: [owner.id])

        let survivorURL = CoverStore.url(forItem: sharer.id, in: libraryRoot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: survivorURL.path))
        XCTAssertEqual(viewModel.items.first { $0.id == sharer.id }?.metadata?.coverURL, survivorURL)
        XCTAssertEqual(coverFileCount(), 1)
    }

    /// La pasada de arranque agrupa copias que ya estaban en disco
    /// (escritas por una version vieja, una por elemento).
    func testStartupDedupeMergesExistingDuplicateFiles() throws {
        let itemA = try makeItemWithCoverOnDisk(bytes: coverBytes)
        let itemB = try makeItemWithCoverOnDisk(bytes: coverBytes)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.replaceItemsForPerformanceTesting([itemA, itemB])
        XCTAssertEqual(coverFileCount(), 2)

        viewModel.dedupeCoversIfNeeded()

        XCTAssertEqual(coverFileCount(), 1)
        let urls = Set(viewModel.items.compactMap { $0.metadata?.coverURL })
        XCTAssertEqual(urls.count, 1, "los dos elementos comparten archivo")
        let reloaded = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        XCTAssertEqual(reloaded.items.first?.metadata?.loadCoverData(), coverBytes)
    }
}
