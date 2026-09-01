import XCTest
@testable import AuraStudio

/// ST-102: la biblioteca es COMPARTIDA -- la misma carpeta se abre desde
/// Aura Studio en la Mac y desde Aura Studio en Windows, y las dos apps
/// escriben el mismo `biblioteca.json`.
///
/// El caso real que motiva estas pruebas: el catalogo del dueno tenia
/// 401 elementos escritos desde Windows y esta app mostraba la
/// biblioteca VACIA, sin un solo error. El JSON decodificaba perfecto
/// (los nombres de campo y los tipos ya estaban acordados, ver
/// `SwiftInteropTests` del lado de Windows); lo que fallaba era la
/// resolucion de las rutas, y `loadCatalog()` omite en silencio todo
/// item cuyo archivo no exista. "Vacia" y "no la pude leer" se ven
/// exactamente igual en pantalla.
final class SharedCatalogPathTests: XCTestCase {
    func testTheLiteralPathIsTriedFirst() {
        // En macOS `\` es un caracter valido en un nombre de archivo:
        // una biblioteca hecha aca con un archivo asi tiene que seguir
        // resolviendo a ESE archivo, no a una ruta reinterpretada.
        XCTAssertEqual(SharedCatalogPath.candidates(for: #"Música\x.mp3"#).first, #"Música\x.mp3"#)
    }

    func testWindowsSeparatorsBecomeACandidate() {
        XCTAssertTrue(SharedCatalogPath.candidates(for: #"Música\Soda\01 x.mp3"#).contains("Música/Soda/01 x.mp3"))
    }

    func testBothUnicodeNormalizationsAreCandidates() {
        // exFAT y los recursos compartidos por red SI distinguen NFC de
        // NFD (APFS y HFS+ no). Windows escribe precompuesto, macOS
        // descompuesto.
        let precomposed = "M\u{00FA}sica/x.mp3"
        let decomposed = "Mu\u{0301}sica/x.mp3"
        let candidates = SharedCatalogPath.candidates(for: precomposed)
        XCTAssertTrue(candidates.contains(precomposed))
        XCTAssertTrue(candidates.contains(decomposed))
    }

    func testThereAreNoRepeatedCandidates() {
        let candidates = SharedCatalogPath.candidates(for: "Videos/x.mp4")
        XCTAssertEqual(candidates.count, Set(candidates).count)
        XCTAssertEqual(candidates, ["Videos/x.mp4"])
    }

    func testAWindowsAbsolutePathIsNeverJoinedToTheLibraryRoot() {
        // Pegar `C:\Users\...` debajo de la raiz daria una ruta absurda
        // que ademas podria existir por casualidad. No se resuelve: el
        // item se omite, que es lo correcto.
        XCTAssertTrue(SharedCatalogPath.isForeignAbsolute(#"C:\Users\rick\x.mp3"#))
        XCTAssertTrue(SharedCatalogPath.isForeignAbsolute("V:/Media/x.mp3"))
        XCTAssertTrue(SharedCatalogPath.isForeignAbsolute(#"\\servidor\medios\x.mp3"#))
        XCTAssertFalse(SharedCatalogPath.isForeignAbsolute("/Users/rick/x.mp3"))
        XCTAssertFalse(SharedCatalogPath.isForeignAbsolute("Música/x.mp3"))
        XCTAssertNil(SharedCatalogPath.resolve(#"C:\Users\rick\x.mp3"#,
                                               in: URL(fileURLWithPath: "/tmp", isDirectory: true)))
    }

    func testAPathThatIsJustADriveLetterIsNotAbsolute() {
        XCTAssertFalse(SharedCatalogPath.isAbsolute("C:"))
        XCTAssertFalse(SharedCatalogPath.isAbsolute("Álbum: en vivo/x.mp3"))
    }
}

/// La prueba que de verdad importa: un `biblioteca.json` con la forma
/// EXACTA que escribe Aura Studio en Windows tiene que abrirse aca con
/// todos sus elementos.
@MainActor
final class SharedCatalogInteropTests: XCTestCase {
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuraSharedCatalog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    private func write(_ relative: String, _ contents: String) throws {
        let url = libraryRoot.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    /// Recorte fiel del catalogo real del dueno: separadores `\`, fecha
    /// como numero de segundos desde 2001, identificadores de
    /// MusicBrainz con "ID" en mayusculas, y la caratula nombrada con el
    /// `Guid` hexadecimal pelado que usa Windows (aca el archivo se
    /// llama `<UUID>.jpg`, que es como lo nombra esta app).
    private func writeWindowsCatalog(itemID: UUID) throws {
        let hexID = itemID.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let json = """
        {
          "items": [
            {
              "id": "\(itemID.uuidString)",
              "sourceRelativePath": "M\u{00FA}sica\\\\Fatboy Slim\\\\Signos\\\\01 Right Here.m4a",
              "kind": "music",
              "status": "ready",
              "metadata": {
                "title": "Right Here, Right Now",
                "artist": "Fatboy Slim",
                "album": "You've Come A Long Way, Baby",
                "musicBrainzRecordingID": "83c68fe1-9660-4e4a-ad7b-f27815730606",
                "musicBrainzReleaseID": "011a766d-162f-4f4b-919e-6b42a8a10cb4",
                "trackNumber": 1
              },
              "preparedRelativePath": ".preparados\\\\01 Right Here.m4a",
              "coverRelativePath": ".portadas\\\\\(hexID).jpg",
              "metadataEditedByUser": true,
              "addedAt": 808784218.004062
            }
          ],
          "playlists": []
        }
        """
        try Data(json.utf8).write(to: libraryRoot.appendingPathComponent(PersistedLibrary.catalogFileName))
    }

    func testACatalogWrittenOnWindowsIsNotAnEmptyLibrary() throws {
        let itemID = UUID()
        try write("Música/Fatboy Slim/Signos/01 Right Here.m4a", "audio")
        try write(".preparados/01 Right Here.m4a", "preparado")
        try write(".portadas/\(itemID.uuidString).jpg", "portada")
        try writeWindowsCatalog(itemID: itemID)

        let viewModel = LibraryViewModel(libraryRoot: libraryRoot)

        XCTAssertEqual(viewModel.items.count, 1,
                       "un catalogo escrito en Windows no puede verse igual que una biblioteca vacia")
        let item = try XCTUnwrap(viewModel.items.first)
        XCTAssertEqual(item.id, itemID)
        XCTAssertEqual(item.metadata?.title, "Right Here, Right Now")
        XCTAssertEqual(item.metadata?.musicBrainzRecordingID, "83c68fe1-9660-4e4a-ad7b-f27815730606")
        XCTAssertTrue(item.metadataEditedByUser)
        // La fecha viaja como Double de segundos desde 2001 -- es lo que
        // lee un `JSONDecoder()` por omision, y es lo que Windows escribe.
        XCTAssertEqual(item.addedAt?.timeIntervalSinceReferenceDate ?? 0, 808784218.004062, accuracy: 0.001)
    }

    func testTheSourceResolvesToTheRealFileAndKeepsItReady() throws {
        let itemID = UUID()
        try write("Música/Fatboy Slim/Signos/01 Right Here.m4a", "audio")
        try write(".preparados/01 Right Here.m4a", "preparado")
        try writeWindowsCatalog(itemID: itemID)

        let viewModel = LibraryViewModel(libraryRoot: libraryRoot)
        let item = try XCTUnwrap(viewModel.items.first)

        XCTAssertEqual(item.sourceURL.lastPathComponent, "01 Right Here.m4a")
        XCTAssertNotNil(item.preparedURL, "lo preparado tambien viene con `\\` y tiene que encontrarse")
        // "Listo" sin su archivo preparado se reencola; con el, no.
        // Si la ruta de `.preparados\` no se resolviera, esta biblioteca
        // se re-procesaria entera sin razon.
        XCTAssertEqual(item.status, .ready)
    }

    /// Las dos apps nombran distinto el MISMO archivo de caratula: esta
    /// usa `UUID.uuidString` (mayusculas con guiones) y Windows el
    /// hexadecimal pelado del `Guid`. Sin respaldo al nombre canonico,
    /// la cancion se ve sin caratula aunque la imagen este ahi.
    func testTheCoverIsFoundEvenWhenWindowsNamedItDifferently() throws {
        let itemID = UUID()
        try write("Música/Fatboy Slim/Signos/01 Right Here.m4a", "audio")
        try write(".preparados/01 Right Here.m4a", "preparado")
        try write(".portadas/\(itemID.uuidString).jpg", "portada")
        try writeWindowsCatalog(itemID: itemID)

        let viewModel = LibraryViewModel(libraryRoot: libraryRoot)
        let item = try XCTUnwrap(viewModel.items.first)

        XCTAssertEqual(item.metadata?.coverArtData, Data("portada".utf8))
    }

    /// La otra mitad del contrato: leer tolerante NO cambia como se
    /// escribe. Al guardar, esta app sigue dejando rutas relativas con
    /// `/` -- que es lo que Windows tambien sabe leer.
    func testSavingRewritesThePathsWithForwardSlashes() throws {
        let itemID = UUID()
        try write("Música/Fatboy Slim/Signos/01 Right Here.m4a", "audio")
        try write(".preparados/01 Right Here.m4a", "preparado")
        try writeWindowsCatalog(itemID: itemID)

        let viewModel = LibraryViewModel(libraryRoot: libraryRoot)
        // Cualquier mutacion persiste el catalogo completo.
        viewModel.setFavorite(true, forItems: [itemID])

        let data = try Data(contentsOf: libraryRoot.appendingPathComponent(PersistedLibrary.catalogFileName))
        let reloaded = try JSONDecoder().decode(PersistedLibrary.self, from: data)
        let saved = try XCTUnwrap(reloaded.items.first)

        XCTAssertFalse(saved.sourceRelativePath.contains("\\"))
        XCTAssertFalse(saved.preparedRelativePath?.contains("\\") ?? false)
        XCTAssertEqual(saved.sourceRelativePath, "Música/Fatboy Slim/Signos/01 Right Here.m4a")
        XCTAssertEqual(saved.preparedRelativePath, ".preparados/01 Right Here.m4a")
    }

    /// Un archivo que de verdad ya no esta sigue omitiendose -- la
    /// tolerancia no puede convertirse en "inventar rutas".
    func testAnItemWhoseFileIsGoneIsStillSkipped() throws {
        let itemID = UUID()
        try writeWindowsCatalog(itemID: itemID)

        let viewModel = LibraryViewModel(libraryRoot: libraryRoot)

        XCTAssertTrue(viewModel.items.isEmpty)
    }
}
