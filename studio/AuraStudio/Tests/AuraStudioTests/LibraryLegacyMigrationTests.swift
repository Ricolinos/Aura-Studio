import XCTest
@testable import AuraStudio

/// D-228: `LibraryViewModel.migrateLegacyLibraryLayoutIfNeeded()` es
/// privada -- se prueba indirectamente por su unico punto de entrada
/// real, `LibraryViewModel.init(libraryRoot:)`, contra una carpeta
/// temporal armada a mano con el esquema VIEJO (`Originales/`/
/// `Preparados/`/`Portadas/` + `biblioteca.json` con esas rutas).
@MainActor
final class LibraryLegacyMigrationTests: XCTestCase {
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuraLegacyMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    /// Arma una biblioteca vieja con UN item de musica: archivo en
    /// `Originales/`, preparado en `Preparados/`, portada en
    /// `Portadas/`, y el catalogo apuntando a las tres.
    @discardableResult
    private func writeLegacyFixture(itemID: UUID = UUID()) throws -> UUID {
        let fm = FileManager.default
        let originals = libraryRoot.appendingPathComponent("Originales")
        let prepared = libraryRoot.appendingPathComponent("Preparados")
        let covers = libraryRoot.appendingPathComponent("Portadas")
        try fm.createDirectory(at: originals, withIntermediateDirectories: true)
        try fm.createDirectory(at: prepared, withIntermediateDirectories: true)
        try fm.createDirectory(at: covers, withIntermediateDirectories: true)

        try Data("fake original bytes".utf8).write(to: originals.appendingPathComponent("song.mp3"))
        try Data("fake prepared bytes".utf8).write(to: prepared.appendingPathComponent("song.mp3"))
        try Data("fake cover bytes".utf8).write(to: covers.appendingPathComponent("\(itemID.uuidString).jpg"))

        let persisted = PersistedLibrary(items: [
            PersistedLibraryItem(
                id: itemID,
                sourceRelativePath: "Originales/song.mp3",
                kind: "music",
                status: "ready",
                metadata: PersistedTrackMetadata(title: "Track", artist: "Queen", album: "A Night at the Opera"),
                preparedRelativePath: "Preparados/song.mp3",
                coverRelativePath: "Portadas/\(itemID.uuidString).jpg",
                category: nil
            ),
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(persisted).write(to: libraryRoot.appendingPathComponent("biblioteca.json"))
        return itemID
    }

    func testMigratesFilesToNewSchemeAndRewritesCatalog() throws {
        let itemID = try writeLegacyFixture()
        let fm = FileManager.default

        let viewModel = LibraryViewModel(libraryRoot: libraryRoot)

        XCTAssertEqual(viewModel.items.count, 1)
        let item = try XCTUnwrap(viewModel.items.first)
        XCTAssertEqual(item.id, itemID)

        let expectedSource = libraryRoot.appendingPathComponent("Música/Queen/A Night at the Opera/song.mp3")
        XCTAssertEqual(item.sourceURL.standardizedFileURL.path, expectedSource.standardizedFileURL.path)
        XCTAssertTrue(fm.fileExists(atPath: expectedSource.path), "el original deberia haberse movido a Música/Queen/A Night at the Opera/")

        let expectedPrepared = libraryRoot.appendingPathComponent(".preparados/song.mp3")
        XCTAssertTrue(fm.fileExists(atPath: expectedPrepared.path), "lo preparado deberia haberse movido a .preparados/")

        let expectedCover = libraryRoot.appendingPathComponent(".portadas/\(itemID.uuidString).jpg")
        XCTAssertTrue(fm.fileExists(atPath: expectedCover.path), "la portada deberia haberse movido a .portadas/")

        // Las carpetas viejas, ahora vacias, se limpian solas.
        XCTAssertFalse(fm.fileExists(atPath: libraryRoot.appendingPathComponent("Originales").path))
        XCTAssertFalse(fm.fileExists(atPath: libraryRoot.appendingPathComponent("Preparados").path))
        XCTAssertFalse(fm.fileExists(atPath: libraryRoot.appendingPathComponent("Portadas").path))

        // El catalogo en disco quedo reescrito -- no solo el modelo en
        // memoria -- para que una relectura futura ya vea las rutas
        // nuevas sin tener que volver a migrar.
        let data = try Data(contentsOf: libraryRoot.appendingPathComponent("biblioteca.json"))
        let reloaded = try JSONDecoder().decode(PersistedLibrary.self, from: data)
        XCTAssertEqual(reloaded.items.first?.sourceRelativePath, "Música/Queen/A Night at the Opera/song.mp3")
        XCTAssertEqual(reloaded.items.first?.preparedRelativePath, ".preparados/song.mp3")
        XCTAssertEqual(reloaded.items.first?.coverRelativePath, ".portadas/\(itemID.uuidString).jpg")
    }

    func testIdempotentSecondRunIsANoOp() throws {
        try writeLegacyFixture()
        _ = LibraryViewModel(libraryRoot: libraryRoot)

        // Segunda vez: ni `Originales/` ni las demas carpetas viejas
        // existen mas, asi que el chequeo inicial de
        // `migrateLegacyLibraryLayoutIfNeeded` tiene que salir de
        // inmediato sin tocar nada ni crashear.
        let secondRun = LibraryViewModel(libraryRoot: libraryRoot)
        XCTAssertEqual(secondRun.items.count, 1)
    }

    func testLeftoverFileBlocksDirectoryRemovalButDoesNotFailMigration() throws {
        try writeLegacyFixture()
        // Un archivo suelto que Finder pudo haber dejado caer (p.ej.
        // .DS_Store) en la carpeta vieja de preparados -- no deberia
        // impedir que el item se migre, solo que esa carpeta puntual
        // sobreviva (no es un `rm -rf`, ver removeLegacyDirectoryIfEmpty).
        try Data().write(to: libraryRoot.appendingPathComponent("Preparados/.DS_Store"))

        let viewModel = LibraryViewModel(libraryRoot: libraryRoot)

        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: libraryRoot.appendingPathComponent("Preparados").path),
                       "la carpeta vieja no deberia borrarse si le queda algo adentro")
        XCTAssertTrue(FileManager.default.fileExists(atPath: libraryRoot.appendingPathComponent(".preparados/song.mp3").path))
    }

    func testFreshLibraryWithoutLegacyFoldersIsUntouched() throws {
        // Sin ninguna carpeta vieja: el guard de entrada de
        // `migrateLegacyLibraryLayoutIfNeeded` sale de inmediato -- no
        // deberia crear `biblioteca.json` ni ninguna carpeta legacy de
        // la nada.
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot)
        XCTAssertEqual(viewModel.items.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: libraryRoot.appendingPathComponent("Originales").path))
    }
}
