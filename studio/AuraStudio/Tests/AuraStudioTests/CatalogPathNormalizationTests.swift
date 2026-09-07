import XCTest
@testable import AuraStudio

/// ST-221 (añadido tras el hallazgo de Windows en B1): las rutas
/// relativas del catálogo se **escriben en NFC**, y toda comparación de
/// rutas normaliza los dos lados antes de comparar.
///
/// macOS entrega los acentos descompuestos (NFD: `u` + acento
/// combinante) y Windows los escribe compuestos (NFC). En pantalla los
/// dos dicen "Música" y ninguna de las dos apps nota la diferencia --
/// hasta que algo COMPARA las cadenas, que es justo lo que ST-221 vino
/// a agregar con `LibraryStorageMode.infer`. Sin normalizar, una
/// biblioteca copiada escrita por la Mac se leería entera como
/// referenciada del lado de Windows, en silencio, y la app se creería
/// sin permiso para escribir etiquetas en archivos que sí son suyos.
@MainActor
final class CatalogPathNormalizationTests: XCTestCase {
    /// "Música" con el acento como carácter combinante (NFD), que es la
    /// forma en que macOS entrega los nombres de archivo.
    private let musicNFD = "M\u{0075}\u{0301}sica"

    private var libraryRoot: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CatalogPathNFC-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    func testTheFixtureIsReallyDecomposed() {
        XCTAssertNotEqual(Array(musicNFD.utf8), Array(PersistedLibrary.musicDirName.utf8),
                          "el fixture debe diferir byte a byte del literal del código, o esta prueba no prueba nada")
        XCTAssertEqual(musicNFD.precomposedStringWithCanonicalMapping, PersistedLibrary.musicDirName)
    }

    /// El caso que motivó la regla: la ruta llega descompuesta y el
    /// nombre de carpeta del código está compuesto.
    func testStorageIsInferredAsCopyEvenWhenThePathArrivesDecomposed() {
        let decomposed = libraryRoot
            .appendingPathComponent(musicNFD, isDirectory: true)
            .appendingPathComponent("Soda Stereo/Signos/01 Prófugos.mp3")

        XCTAssertEqual(LibraryStorageMode.infer(sourceURL: decomposed, libraryRoot: libraryRoot), .copy,
                       "una copia dentro de Música/ es una copia, venga el acento como venga")
    }

    /// Y la raíz también puede venir descompuesta (biblioteca elegida
    /// desde el Finder), con la ruta compuesta.
    func testStorageInferenceNormalizesBothSidesNotOnlyOne() {
        let rootDecomposed = FileManager.default.temporaryDirectory
            .appendingPathComponent("Biblioteca de M\u{0075}\u{0301}sica", isDirectory: true)
        let rootComposed = FileManager.default.temporaryDirectory
            .appendingPathComponent("Biblioteca de Música", isDirectory: true)
        let file = rootComposed
            .appendingPathComponent(PersistedLibrary.musicDirName, isDirectory: true)
            .appendingPathComponent("x.mp3")

        XCTAssertEqual(LibraryStorageMode.infer(sourceURL: file, libraryRoot: rootDecomposed), .copy)
    }

    func testAFileOutsideTheThreeManagedFoldersIsStillAReference() {
        let insideRootButNotManaged = libraryRoot
            .appendingPathComponent("Mis cosas", isDirectory: true)
            .appendingPathComponent("x.mp3")

        XCTAssertEqual(LibraryStorageMode.infer(sourceURL: insideRootButNotManaged, libraryRoot: libraryRoot), .reference,
                       "dentro de la raíz pero fuera de las tres carpetas que la app crea: referencia")
    }

    // MARK: - Escritura

    func testRelativePathIsWrittenPrecomposed() {
        let decomposed = libraryRoot
            .appendingPathComponent(musicNFD, isDirectory: true)
            .appendingPathComponent("01 Pr\u{006F}\u{0301}fugos.mp3")

        let relative = SharedCatalogPath.relativePath(of: decomposed, in: libraryRoot)

        XCTAssertEqual(relative, "Música/01 Prófugos.mp3")
        XCTAssertEqual(Array(relative.utf8), Array("Música/01 Prófugos.mp3".precomposedStringWithCanonicalMapping.utf8),
                       "al catálogo va en NFC, que es lo que Windows escribe y lee")
    }

    func testRelativePathRecognizesTheRootEvenWhenTheFormsDiffer() {
        let rootDecomposed = FileManager.default.temporaryDirectory
            .appendingPathComponent("Ra\u{0069}\u{0301}z", isDirectory: true)
        let fileComposed = FileManager.default.temporaryDirectory
            .appendingPathComponent("Raíz", isDirectory: true)
            .appendingPathComponent("Música/x.mp3")

        // Sin normalizar, `hasPrefix` fallaría y se guardaría la ruta
        // ABSOLUTA -- que es peor que el bug de Windows: convierte una
        // biblioteca portátil en una atada a esta Mac.
        XCTAssertEqual(SharedCatalogPath.relativePath(of: fileComposed, in: rootDecomposed), "Música/x.mp3")
    }

    func testIsInsideNormalizesBothSides() {
        let rootDecomposed = FileManager.default.temporaryDirectory
            .appendingPathComponent("Ra\u{0069}\u{0301}z", isDirectory: true)
        let fileComposed = FileManager.default.temporaryDirectory
            .appendingPathComponent("Raíz/Música/x.mp3")

        XCTAssertTrue(SharedCatalogPath.isInside(fileComposed, root: rootDecomposed))
        XCTAssertFalse(SharedCatalogPath.isInside(FileManager.default.temporaryDirectory.appendingPathComponent("Otra/x.mp3"),
                                                  root: rootDecomposed))
    }

    // MARK: - Lo que queda ESCRITO en el catálogo

    /// La prueba que de verdad protege a Windows: mira **los bytes del
    /// JSON persistido**, no lo que devuelve la carga.
    ///
    /// La distinción no es un tecnicismo. Una normalización aplicada al
    /// LEER dejaría esta prueba en verde y el defecto intacto: la otra
    /// app seguiría recibiendo la forma descompuesta, porque lo que
    /// viaja entre las dos es el archivo, no nuestra carga.
    func testTheThreeRelativePathsAreWrittenPrecomposedInTheCatalogJSON() throws {
        let musicDirNFD = libraryRoot.appendingPathComponent(musicNFD, isDirectory: true)
        let artistDir = musicDirNFD.appendingPathComponent("Soda Ste\u{0301}reo/Signos", isDirectory: true)
        try FileManager.default.createDirectory(at: artistDir, withIntermediateDirectories: true)
        let audioURL = artistDir.appendingPathComponent("01 Pr\u{006F}\u{0301}fugos.mp3")
        try Data("audio".utf8).write(to: audioURL)

        let preparedDir = libraryRoot.appendingPathComponent(PersistedLibrary.preparedDirName, isDirectory: true)
        try FileManager.default.createDirectory(at: preparedDir, withIntermediateDirectories: true)

        var item = AuraStudio.LibraryItem(sourceURL: audioURL)
        let preparedURL = preparedDir.appendingPathComponent("\(item.id.uuidString).mp3")
        try Data("preparado".utf8).write(to: preparedURL)
        item.preparedURL = preparedURL
        item.status = .ready
        item.storage = .copy
        item.metadata = TrackMetadata(title: "Prófugos", artist: "Soda Stéreo", album: "Signos",
                                      coverArtData: Data([0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: 0x42, count: 64)))

        let viewModel = LibraryViewModel(libraryRoot: libraryRoot,
                                         preferences: AppPreferences(defaults: makeIsolatedDefaults("CatalogPathNFC")))
        viewModel.replaceItemsForPerformanceTesting([item])
        viewModel.persistCatalog()

        let data = try Data(contentsOf: libraryRoot.appendingPathComponent(PersistedLibrary.catalogFileName))
        let saved = try XCTUnwrap(try JSONDecoder().decode(PersistedLibrary.self, from: data).items.first)

        for (label, path) in [("fuente", saved.sourceRelativePath),
                              ("preparado", try XCTUnwrap(saved.preparedRelativePath)),
                              ("carátula", try XCTUnwrap(saved.coverRelativePath))] {
            XCTAssertEqual(Array(path.utf8), Array(path.precomposedStringWithCanonicalMapping.utf8),
                           "la ruta de \(label) debe quedar escrita en NFC: \(path)")
        }
        XCTAssertEqual(saved.sourceRelativePath, "Música/Soda Stéreo/Signos/01 Prófugos.mp3")

        // Y el JSON en crudo, por si alguien cambia el decodificador:
        // los bytes de la forma descompuesta no pueden estar ahí.
        let nfdBytes = Data("Soda Ste\u{0301}reo".utf8)
        XCTAssertNil(data.range(of: nfdBytes), "no debe quedar ninguna ruta descompuesta en el catálogo")
    }

    /// La otra mitad del contrato: una ruta **absoluta** (modo
    /// referencia, el archivo vive fuera de la biblioteca) se escribe
    /// **tal como viene**. Es un dato del sistema donde está el archivo,
    /// no parte del formato: se compara normalizada, no se reescribe.
    func testAnAbsolutePathIsWrittenAsItComes() throws {
        let outsideDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Fuera-\(UUID().uuidString)/M\u{0075}\u{0301}sica del usuario", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        let audioURL = outsideDir.appendingPathComponent("x.mp3")
        try Data("audio".utf8).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: outsideDir.deletingLastPathComponent()) }

        var item = AuraStudio.LibraryItem(sourceURL: audioURL)
        item.status = .ready

        let viewModel = LibraryViewModel(libraryRoot: libraryRoot,
                                         preferences: AppPreferences(defaults: makeIsolatedDefaults("CatalogPathNFC")))
        viewModel.replaceItemsForPerformanceTesting([item])
        viewModel.persistCatalog()

        let data = try Data(contentsOf: libraryRoot.appendingPathComponent(PersistedLibrary.catalogFileName))
        let saved = try XCTUnwrap(try JSONDecoder().decode(PersistedLibrary.self, from: data).items.first)

        XCTAssertTrue(saved.sourceRelativePath.hasPrefix("/"), "debe haber quedado absoluta")
        XCTAssertEqual(Array(saved.sourceRelativePath.utf8), Array(audioURL.standardizedFileURL.path.utf8),
                       "una ruta absoluta se escribe como viene, sin normalizar")
    }

    // MARK: - `storage` al guardar (addendum ST-241)

    /// Un elemento recién importado **nunca pasa por una carga**, así
    /// que la inferencia tiene que ocurrir también al guardar: si no, la
    /// Mac escribiría al catálogo compartido un archivo que está dentro
    /// de sus propias carpetas marcado como referenciado, y Windows lo
    /// leería así.
    func testStorageIsResolvedWhenSavingNotOnlyWhenLoading() throws {
        let musicDirNFD = libraryRoot.appendingPathComponent(musicNFD, isDirectory: true)
        try FileManager.default.createDirectory(at: musicDirNFD, withIntermediateDirectories: true)
        let audioURL = musicDirNFD.appendingPathComponent("x.mp3")
        try Data("audio".utf8).write(to: audioURL)

        var item = AuraStudio.LibraryItem(sourceURL: audioURL)
        item.status = .ready
        XCTAssertEqual(item.storage, .reference, "control: recién creado, todavía nadie lo copió")

        let viewModel = LibraryViewModel(libraryRoot: libraryRoot,
                                         preferences: AppPreferences(defaults: makeIsolatedDefaults("CatalogPathNFC")))
        viewModel.replaceItemsForPerformanceTesting([item])
        viewModel.persistCatalog()

        let data = try Data(contentsOf: libraryRoot.appendingPathComponent(PersistedLibrary.catalogFileName))
        let saved = try XCTUnwrap(try JSONDecoder().decode(PersistedLibrary.self, from: data).items.first)

        XCTAssertEqual(saved.storage, "copy", "está bajo Música/: se guarda como copia, aunque el ítem en memoria dijera otra cosa")
    }

    /// Y el candado que impide que eso se vuelva "todo lo que esté cerca
    /// de la biblioteca es una copia".
    func testAnItemInsideTheRootButOutsideTheThreeFoldersIsSavedAsReference() throws {
        let otherDir = libraryRoot.appendingPathComponent("Mis cosas", isDirectory: true)
        try FileManager.default.createDirectory(at: otherDir, withIntermediateDirectories: true)
        let audioURL = otherDir.appendingPathComponent("x.mp3")
        try Data("audio".utf8).write(to: audioURL)

        var item = AuraStudio.LibraryItem(sourceURL: audioURL)
        item.status = .ready

        let viewModel = LibraryViewModel(libraryRoot: libraryRoot,
                                         preferences: AppPreferences(defaults: makeIsolatedDefaults("CatalogPathNFC")))
        viewModel.replaceItemsForPerformanceTesting([item])
        viewModel.persistCatalog()

        let data = try Data(contentsOf: libraryRoot.appendingPathComponent(PersistedLibrary.catalogFileName))
        let saved = try XCTUnwrap(try JSONDecoder().decode(PersistedLibrary.self, from: data).items.first)

        XCTAssertEqual(saved.storage, "reference")
    }

    // MARK: - Carpetas gestionadas

    /// Si en disco ya está `Música` descompuesta, la app **reusa esa** y
    /// no crea una segunda al lado. En APFS da igual; en exFAT o en red
    /// es la diferencia entre una biblioteca y dos que se ven iguales.
    func testManagedDirectoryReusesAnExistingDecomposedFolder() throws {
        let existing = libraryRoot.appendingPathComponent(musicNFD, isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)

        let resolved = SharedCatalogPath.managedDirectory(PersistedLibrary.musicDirName, in: libraryRoot)

        XCTAssertEqual(Array(resolved.lastPathComponent.utf8), Array(musicNFD.utf8),
                       "debe devolver la carpeta que YA existe, con el nombre que tiene en disco")
    }

    /// Sin carpeta previa se crea la que toca -- y su nombre EN DISCO
    /// queda descompuesto, se pida como se pida.
    ///
    /// Eso no es un defecto que se pueda arreglar acá: en macOS,
    /// Foundation descompone al bajar al sistema de archivos
    /// (`createDirectory`, `appendingPathComponent` y hasta
    /// `URL(fileURLWithPath:)` con una cadena compuesta). Comprobado en
    /// esta misma prueba, para que nadie vuelva a intentarlo.
    ///
    /// Por eso el contrato normaliza **las cadenas del catálogo** y no
    /// los nombres de archivo: lo primero está en nuestras manos, lo
    /// segundo no. Y por eso la mitad que sí importa es la de arriba --
    /// reusar la carpeta que ya exista, comparando en NFC.
    func testManagedDirectoryCreatesTheFolderAndMacOSStoresItDecomposed() throws {
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)

        let resolved = SharedCatalogPath.managedDirectory(PersistedLibrary.musicDirName, in: libraryRoot)
        try FileManager.default.createDirectory(at: resolved, withIntermediateDirectories: true)

        let entries = try FileManager.default.contentsOfDirectory(atPath: libraryRoot.path)
        XCTAssertEqual(entries, [musicNFD], "macOS guarda el nombre descompuesto, pida lo que pida la app")
        XCTAssertEqual(SharedCatalogPath.catalogNormalized(try XCTUnwrap(entries.first)),
                       PersistedLibrary.musicDirName,
                       "y normalizado es la carpeta que la app quería")

        // Lo que de verdad protege el contrato: lo que se escribiría en
        // el catálogo para un archivo de esa carpeta va en NFC.
        let file = resolved.appendingPathComponent("x.mp3")
        XCTAssertEqual(SharedCatalogPath.relativePath(of: file, in: libraryRoot), "Música/x.mp3")
    }

    // MARK: - Lectura

    /// La tolerancia de lectura NO cambia: contra el disco se siguen
    /// probando las dos formas, porque ahí manda lo que el sistema de
    /// archivos conserve (APFS guarda la forma con que se creó).
    func testResolveStillFindsAFileWhoseNameOnDiskIsDecomposed() throws {
        let dir = libraryRoot.appendingPathComponent(musicNFD, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("x.mp3")
        try Data("audio".utf8).write(to: fileURL)

        let composedRelative = "Música/x.mp3".precomposedStringWithCanonicalMapping
        XCTAssertNotNil(SharedCatalogPath.resolve(composedRelative, in: libraryRoot),
                        "una ruta compuesta (la que escribe Windows) tiene que encontrar el archivo creado descompuesto")
    }

    /// El viaje completo del elemento **no disponible**: se guardó
    /// descompuesto, se conserva con `recordedURL` (que no toca disco) y
    /// se vuelve a escribir. Lo que se afirma es lo único que importa
    /// del otro lado: que **lo que vuelve al catálogo esté en NFC**.
    ///
    /// Y no se afirma sobre el `URL`: `appendingPathComponent` vuelve a
    /// descomponer lo que se le pase, así que la forma interna de un
    /// `URL` no es algo sobre lo que se pueda tener contrato. Por eso la
    /// normalización va en la CADENA al escribir (`relativePath`), que
    /// es donde sí se sostiene.
    func testAnUnavailableItemIsRewrittenPrecomposed() throws {
        let url = try XCTUnwrap(SharedCatalogPath.recordedURL("M\u{0075}\u{0301}sica/x.mp3", in: libraryRoot))
        XCTAssertEqual(url.lastPathComponent, "x.mp3")

        let rewritten = SharedCatalogPath.relativePath(of: url, in: libraryRoot)
        XCTAssertEqual(rewritten, "Música/x.mp3")
        XCTAssertEqual(Array(rewritten.utf8), Array("Música/x.mp3".precomposedStringWithCanonicalMapping.utf8),
                       "un elemento no disponible no puede degradar la forma de su ruta al reescribirse")
    }
}
