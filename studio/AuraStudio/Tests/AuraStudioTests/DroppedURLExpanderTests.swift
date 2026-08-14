import XCTest
@testable import AuraStudio

/// D-229 (encargo del dueño, 2026-08-14): soltar una carpeta en Aura
/// Studio -- `DroppedURLExpander.expand` es la logica pura que decide
/// que archivos salen de ahi, probada contra una carpeta temporal real
/// con estructura anidada (mismo patron de fixture que
/// `LibraryLegacyMigrationTests`).
final class DroppedURLExpanderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DroppedURLExpanderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func touch(_ relativePath: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    func testPlainFileURLPassesThroughUnchanged() throws {
        try touch("song.mp3")
        let fileURL = root.appendingPathComponent("song.mp3")

        let result = DroppedURLExpander.expand([fileURL])

        XCTAssertEqual(result, [fileURL])
    }

    func testFolderExpandsToFlatListAtAnyDepth() throws {
        try touch("Album/track1.mp3")
        try touch("Album/Disco 2/track2.flac")
        try touch("Album/cover.jpg")

        let result = Set(DroppedURLExpander.expand([root.appendingPathComponent("Album")])
            .map(\.standardizedFileURL.path))

        XCTAssertEqual(result, [
            root.appendingPathComponent("Album/track1.mp3").standardizedFileURL.path,
            root.appendingPathComponent("Album/Disco 2/track2.flac").standardizedFileURL.path,
            root.appendingPathComponent("Album/cover.jpg").standardizedFileURL.path,
        ])
    }

    func testHiddenFilesAreSkipped() throws {
        try touch("Album/track1.mp3")
        try touch("Album/.DS_Store")

        let result = DroppedURLExpander.expand([root.appendingPathComponent("Album")])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.lastPathComponent, "track1.mp3")
    }

    func testPackageDescendantsAreNotEnumerated() throws {
        try touch("Album/track1.mp3")
        // Un ".app" adentro de la carpeta soltada no deberia desarmarse
        // en sus archivos internos.
        try touch("Album/Weird.app/Contents/Info.plist")

        let result = DroppedURLExpander.expand([root.appendingPathComponent("Album")])
            .map(\.lastPathComponent)

        XCTAssertFalse(result.contains("Info.plist"))
    }

    func testMixOfFilesAndFoldersExpandsOnlyTheFolders() throws {
        try touch("standalone.mp3")
        try touch("Album/track1.mp3")
        try touch("Album/track2.mp3")

        let result = Set(DroppedURLExpander.expand([
            root.appendingPathComponent("standalone.mp3"),
            root.appendingPathComponent("Album"),
        ]).map(\.lastPathComponent))

        XCTAssertEqual(result, ["standalone.mp3", "track1.mp3", "track2.mp3"])
    }

    func testEmptyFolderExpandsToNoFiles() throws {
        let empty = root.appendingPathComponent("Empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        XCTAssertTrue(DroppedURLExpander.expand([empty]).isEmpty)
    }

    /// Una URL que ya no existe no es una carpeta (`isDirectory` da
    /// `false` para cualquier ruta que `fileExists` no reconozca), asi
    /// que pasa de largo tal cual -- exactamente lo mismo que ya pasaba
    /// ANTES de este cambio con un drop de un archivo suelto: nunca se
    /// valido existencia aca, eso lo termina descubriendo mas tarde el
    /// pipeline (`process(itemAt:)`, que falla prolijamente con
    /// `.failed(...)` sin crashear).
    func testNonexistentURLPassesThroughUnchangedWithoutCrashing() {
        let missing = root.appendingPathComponent("does-not-exist.mp3")
        XCTAssertEqual(DroppedURLExpander.expand([missing]), [missing])
    }

    func testIsDirectoryDistinguishesFilesFromFolders() throws {
        try touch("Album/track1.mp3")

        XCTAssertTrue(DroppedURLExpander.isDirectory(root.appendingPathComponent("Album")))
        XCTAssertFalse(DroppedURLExpander.isDirectory(root.appendingPathComponent("Album/track1.mp3")))
    }
}
