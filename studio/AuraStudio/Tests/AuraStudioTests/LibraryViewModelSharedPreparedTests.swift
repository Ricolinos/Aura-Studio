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

    /// ST-221 desarmó el problema en vez de resolverlo: con el derivado
    /// nombrado por el id del elemento, dos duplicados **ya no comparten
    /// preparado**, así que borrar uno no puede dejar al otro "Listo"
    /// sin archivo. Lo que se verifica ahora es justamente eso -- que
    /// cada uno tenga el suyo y que borrar uno no toque el del otro.
    func testDeletingOneDuplicateKeepsTheSurvivorsPreparedFile() async throws {
        let prefs = AppPreferences(defaults: makeIsolatedDefaults("SharedPrepared"))
        prefs.copyMediaIntoLibrary = false
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: prefs)
        viewModel.addDroppedFiles([sourceA, sourceB])
        let ids = viewModel.items.map(\.id)
        XCTAssertEqual(ids.count, 2)
        let metadata = TrackMetadata(title: "Ain't No Sunshine", artist: "Bill Withers", album: "Just As I Am")
        for id in ids { await viewModel.applyReview(id: id, metadata: metadata) }

        let preparedA = try XCTUnwrap(viewModel.items[0].preparedURL)
        let preparedB = try XCTUnwrap(viewModel.items[1].preparedURL)
        XCTAssertNotEqual(preparedA.path, preparedB.path, "ST-221: mismo nombre ya NO significa mismo preparado")
        XCTAssertEqual(preparedA.lastPathComponent, "\(ids[0].uuidString).mp3")
        XCTAssertEqual(preparedB.lastPathComponent, "\(ids[1].uuidString).mp3")
        XCTAssertTrue(FileManager.default.fileExists(atPath: preparedA.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: preparedB.path))

        viewModel.deleteItems(ids: [ids[0]])

        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: preparedB.path), "el preparado del sobreviviente sigue en disco")
        XCTAssertFalse(FileManager.default.fileExists(atPath: preparedA.path), "el del borrado sí se va")

        viewModel.deleteItems(ids: [ids[1]])
        XCTAssertFalse(FileManager.default.fileExists(atPath: preparedB.path))
    }
}
