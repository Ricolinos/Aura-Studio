import XCTest
@testable import AuraStudio

/// D-229 (encargo del dueño, 2026-08-14): soltar una CARPETA sobre Aura
/// Studio -- `LibraryViewModel.addDroppedFiles` la expande (via
/// `DroppedURLExpander`, probado aparte) y, si "copiar medios" esta
/// apagado, ademas registra la carpeta como "biblioteca vinculada" en
/// `AppPreferences.linkedLibraryFolders`. No se llama `processAll()` en
/// esta suite -- eso ejercitaria el pipeline de enriquecimiento/copia
/// D-228 completo (ya cubierto por `LibraryPipelineIntegrationTests`),
/// esta suite solo verifica el paso nuevo: que un folder-drop entra a la
/// biblioteca por el MISMO camino (`LibraryItem` por archivo reconocido)
/// que un drop de archivos sueltos.
@MainActor
final class LibraryFolderDropTests: XCTestCase {
    private var externalFolder: URL!
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        externalFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibraryFolderDropExternal-\(UUID().uuidString)", isDirectory: true)
        libraryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibraryFolderDropRoot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: externalFolder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: externalFolder)
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    /// `Album/track1.mp3`, `Album/Disco 2/track2.flac` (anidado),
    /// `Album/cover.jpg`, y `Album/notas.txt` (sin extension reconocida
    /// -- debe quedar afuera, igual que hoy con un archivo suelto sin
    /// extension conocida).
    @discardableResult
    private func writeFixtureFolder() throws -> URL {
        let album = externalFolder.appendingPathComponent("Album", isDirectory: true)
        let disco2 = album.appendingPathComponent("Disco 2", isDirectory: true)
        try FileManager.default.createDirectory(at: disco2, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: album.appendingPathComponent("track1.mp3"))
        try Data("x".utf8).write(to: disco2.appendingPathComponent("track2.flac"))
        try Data("x".utf8).write(to: album.appendingPathComponent("cover.jpg"))
        try Data("x".utf8).write(to: album.appendingPathComponent("notas.txt"))
        return album
    }

    private func freshPreferences(copyMediaIntoLibrary: Bool) -> AppPreferences {
        let suiteName = "LibraryFolderDropTests-\(UUID().uuidString)"
        let prefs = AppPreferences(defaults: UserDefaults(suiteName: suiteName)!)
        prefs.copyMediaIntoLibrary = copyMediaIntoLibrary
        return prefs
    }

    func testCopyOnFolderDropAddsOnlyRecognizedMediaAsItems() throws {
        let album = try writeFixtureFolder()
        let prefs = freshPreferences(copyMediaIntoLibrary: true)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: prefs)

        viewModel.addDroppedFiles([album])

        XCTAssertEqual(viewModel.items.count, 3, "mp3 + flac + jpg -- notas.txt no tiene extension reconocida")
        XCTAssertEqual(viewModel.items.filter { $0.kind == .music }.count, 2)
        XCTAssertEqual(viewModel.items.filter { $0.kind == .photo }.count, 1)
        XCTAssertFalse(viewModel.items.contains { $0.sourceURL.lastPathComponent == "notas.txt" })
    }

    func testCopyOnFolderDropDoesNotRegisterLinkedFolder() throws {
        let album = try writeFixtureFolder()
        let prefs = freshPreferences(copyMediaIntoLibrary: true)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: prefs)

        viewModel.addDroppedFiles([album])

        XCTAssertTrue(prefs.linkedLibraryFolders.isEmpty,
                       "con copia activa no hace falta recordar la carpeta externa -- los archivos ya van a terminar copiados adentro de la biblioteca")
    }

    func testCopyOffFolderDropReferencesOriginalsAndRegistersLinkedFolder() throws {
        let album = try writeFixtureFolder()
        let prefs = freshPreferences(copyMediaIntoLibrary: false)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: prefs)

        viewModel.addDroppedFiles([album])

        XCTAssertEqual(viewModel.items.count, 3)
        // Sin copiar: cada item sigue apuntando al archivo original,
        // fuera de la biblioteca. `resolvingSymlinksInPath()` porque
        // `FileManager.enumerator` devuelve rutas ya resueltas
        // (/private/var/... en macOS) mientras que `externalFolder` no
        // paso por ese mismo resolver -- son la misma carpeta, distinta
        // sola en representacion de texto.
        let externalPrefix = externalFolder.resolvingSymlinksInPath().path
        for item in viewModel.items {
            XCTAssertTrue(item.sourceURL.resolvingSymlinksInPath().path.hasPrefix(externalPrefix))
        }
        XCTAssertEqual(prefs.linkedLibraryFolders, [album.standardizedFileURL.path])
    }

    func testDroppingSameFolderTwiceWithCopyOffDoesNotDuplicateLinkedEntry() throws {
        let album = try writeFixtureFolder()
        let prefs = freshPreferences(copyMediaIntoLibrary: false)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: prefs)

        viewModel.addDroppedFiles([album])
        viewModel.addDroppedFiles([album])

        XCTAssertEqual(prefs.linkedLibraryFolders, [album.standardizedFileURL.path])
        XCTAssertEqual(viewModel.items.count, 6, "los items SI se vuelven a agregar -- el dedup es solo de la carpeta vinculada")
    }

    func testDroppingAPlainFileWithCopyOffDoesNotRegisterAnyLinkedFolder() throws {
        let file = externalFolder.appendingPathComponent("solo.mp3")
        try Data("x".utf8).write(to: file)
        let prefs = freshPreferences(copyMediaIntoLibrary: false)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: prefs)

        viewModel.addDroppedFiles([file])

        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertTrue(prefs.linkedLibraryFolders.isEmpty)
    }
}
