import XCTest
@testable import AuraStudio

/// ST-064: dos elementos con el mismo nombre de archivo comparten el
/// preparado en `.preparados/` (carpeta plana). Eliminar uno no debe
/// dejar al otro "Listo" sin archivo (era lo que rompía el sync con
/// "no se encuentra" tras quitar duplicados desde "Elementos similares").
@MainActor
final class LibraryViewModelSharedPreparedTests: XCTestCase {
    private var libraryRoot: URL!
    private var sourceA: URL!
    private var sourceB: URL!

    override func setUpWithError() throws {
        let tmp = FileManager.default.temporaryDirectory
        libraryRoot = tmp.appendingPathComponent("SharedPrepared-\(UUID().uuidString)")
        let dirA = tmp.appendingPathComponent("SharedPreparedA-\(UUID().uuidString)")
        let dirB = tmp.appendingPathComponent("SharedPreparedB-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        sourceA = dirA.appendingPathComponent("01 - Ain't No Sunshine.mp3")
        sourceB = dirB.appendingPathComponent("01 - Ain't No Sunshine.mp3")
        try Data("a".utf8).write(to: sourceA)
        try Data("b".utf8).write(to: sourceB)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
        try? FileManager.default.removeItem(at: sourceA.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: sourceB.deletingLastPathComponent())
    }

    func testDeletingOneDuplicateKeepsTheSurvivorsPreparedFile() async throws {
        let prefs = AppPreferences(defaults: UserDefaults(suiteName: "SharedPrepared-\(UUID().uuidString)")!)
        prefs.copyMediaIntoLibrary = false
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: prefs)
        viewModel.addDroppedFiles([sourceA, sourceB])
        let ids = viewModel.items.map(\.id)
        XCTAssertEqual(ids.count, 2)
        let metadata = TrackMetadata(title: "Ain't No Sunshine", artist: "Bill Withers", album: "Just As I Am")
        for id in ids { await viewModel.applyReview(id: id, metadata: metadata) }

        let prepared = try XCTUnwrap(viewModel.items[1].preparedURL)
        XCTAssertEqual(viewModel.items[0].preparedURL?.path, prepared.path, "mismo nombre => mismo preparado")
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.path))

        viewModel.deleteItems(ids: [ids[0]])

        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.path), "el preparado del sobreviviente sigue en disco")

        // Sin sobrevivientes que lo compartan, sí se borra.
        viewModel.deleteItems(ids: [ids[1]])
        XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.path))
    }
}
