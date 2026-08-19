import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
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

        // ST-012: el cover.jpg que viene DENTRO del album es la caratula
        // del album (asset asociado, ver LocalTagReader), no una foto --
        // ya no entra a Imagenes. Antes de ST-012 este test afirmaba
        // "mp3 + flac + jpg = 3", el bug de contaminacion de Imagenes.
        XCTAssertEqual(viewModel.items.count, 2, "mp3 + flac -- cover.jpg es caratula, notas.txt no tiene extension reconocida")
        XCTAssertEqual(viewModel.items.filter { $0.kind == .music }.count, 2)
        XCTAssertEqual(viewModel.items.filter { $0.kind == .photo }.count, 0)
        XCTAssertFalse(viewModel.items.contains { $0.sourceURL.lastPathComponent == "notas.txt" })
        XCTAssertFalse(viewModel.items.contains { $0.sourceURL.lastPathComponent == "cover.jpg" })
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

        XCTAssertEqual(viewModel.items.count, 2, "mp3 + flac (ST-012: cover.jpg es caratula del album, no foto)")
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
        XCTAssertEqual(viewModel.items.count, 4, "los items SI se vuelven a agregar (2 + 2; ST-012: cover.jpg ya no cuenta) -- el dedup es solo de la carpeta vinculada")
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

    // MARK: - PLAN-biblioteca-medios-v2.md §3.2/§3.3: category/photoAlbum preasignados

    func testDroppedFilesCarryPresetCategoryAndAlbum() throws {
        let file = externalFolder.appendingPathComponent("foto.jpg")
        try Data("x".utf8).write(to: file)
        let prefs = freshPreferences(copyMediaIntoLibrary: true)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: prefs)

        viewModel.addDroppedFiles([file], into: .photo, category: "IA", photoAlbum: "Vacaciones 2026")

        XCTAssertEqual(viewModel.items.first?.category, "IA")
        XCTAssertEqual(viewModel.items.first?.photoAlbum, "Vacaciones 2026")
    }

    func testDroppedFilesWithoutPresetCategoryStayNil() throws {
        let file = externalFolder.appendingPathComponent("foto.jpg")
        try Data("x".utf8).write(to: file)
        let prefs = freshPreferences(copyMediaIntoLibrary: true)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: prefs)

        viewModel.addDroppedFiles([file], into: .photo)

        XCTAssertNil(viewModel.items.first?.category)
        XCTAssertNil(viewModel.items.first?.photoAlbum)
    }

    /// La categoría preasignada tiene que sobrevivir el pipeline
    /// completo -- `process(itemAt:)` solo clasifica sola cuando
    /// `category == nil` (ver `LibraryViewModel.swift`, caso `.photo`).
    /// JPEG sintético (D-303): sin tocar la biblioteca real del dueño.
    func testPresetCategorySurvivesFullPipelineProcessing() async throws {
        let photoURL = externalFolder.appendingPathComponent("foto.jpg")
        let data = try XCTUnwrap(makeFakeJPEGData())
        try data.write(to: photoURL)
        let prefs = freshPreferences(copyMediaIntoLibrary: false)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: prefs)

        viewModel.addDroppedFiles([photoURL], into: .photo, category: "IA")
        await viewModel.processAll()

        XCTAssertEqual(viewModel.items.first?.category, "IA", "la categoría preasignada por la subsección no debe ser pisada por la heurística automática")
    }

    private func makeFakeJPEGData() -> Data? {
        let size = CGSize(width: 4, height: 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                       bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))
        guard let cgImage = context.makeImage() else { return nil }
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }
}
