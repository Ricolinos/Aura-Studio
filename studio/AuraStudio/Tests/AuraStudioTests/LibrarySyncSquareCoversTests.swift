import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import AuraStudio

/// ST-142 / ST-159, contrato v20: lo que llega al iPod es cuadrado y del
/// tamaño exacto que fija el contrato -- `cover.jpg` de 320×320 y, desde
/// v20, `.rockbox/aura/artists/*.jpg` también de 320×320 (antes 128×128).
/// Se comprueba sobre un volumen de prueba, midiendo los archivos que
/// quedaron escritos, no el código que los escribe.
final class LibrarySyncSquareCoversTests: XCTestCase {
    private var fakeIPod: URL!
    private var libraryRoot: URL!
    private var stagingFile: URL!

    override func setUpWithError() throws {
        let temp = FileManager.default.temporaryDirectory
        fakeIPod = temp.appendingPathComponent("FakeIPod-\(UUID().uuidString)")
        libraryRoot = temp.appendingPathComponent("Biblioteca-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeIPod, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        stagingFile = temp.appendingPathComponent("staged-\(UUID().uuidString).mp3")
        try Data("fake mp3 bytes".utf8).write(to: stagingFile)
    }

    override func tearDownWithError() throws {
        for url in [fakeIPod, libraryRoot, stagingFile] {
            try? FileManager.default.removeItem(at: url!)
        }
    }

    /// Un JPEG liso de verdad: las carátulas de mentira ("unos bytes")
    /// ya no sirven acá, porque el recorte tiene que poder decodificarlas.
    private func jpeg(width: Int, height: Int, red: UInt8 = 200) throws -> Data {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = red; pixels[i + 1] = 60; pixels[i + 2] = 90; pixels[i + 3] = 255
        }
        guard let context = pixels.withUnsafeMutableBytes({ buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }), let image = context.makeImage() else {
            throw XCTSkip("no se pudo generar la imagen de prueba")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw XCTSkip("no se pudo codificar el JPEG de prueba")
        }
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func size(ofFileAt url: URL) throws -> (width: Int, height: Int) {
        guard let size = ImageResizer.orientedPixelSize(ofFileAt: url) else {
            throw XCTSkip("no se pudo leer el tamaño de \(url.lastPathComponent)")
        }
        return size
    }

    private func musicItem(cover: Data?) -> AuraStudio.LibraryItem {
        var item = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/source-\(UUID().uuidString).mp3"))
        item.metadata = TrackMetadata(title: "Persiana Americana", artist: "Soda Stereo",
                                       album: "Signos", trackNumber: 3, coverArtData: cover)
        item.preparedURL = stagingFile
        item.status = .ready
        return item
    }

    private var coverURL: URL {
        fakeIPod.appendingPathComponent("Music/Soda Stereo/Signos/cover.jpg")
    }

    func testTheAlbumCoverArrivesAtThreeHundredAndTwenty() throws {
        // 4:3 de 1600×1200 en la biblioteca -> 320×320 en el iPod.
        let item = musicItem(cover: try jpeg(width: 1600, height: 1200))
        _ = try LibrarySync(volumeRoot: fakeIPod).sync(items: [item], coverArtPolicy: .albumOnly)

        let size = try size(ofFileAt: coverURL)
        XCTAssertEqual(size.width, LibrarySync.deviceCoverSide)
        XCTAssertEqual(size.height, LibrarySync.deviceCoverSide)
    }

    func testASixteenNineCoverAlsoArrivesSquare() throws {
        let item = musicItem(cover: try jpeg(width: 1920, height: 1080))
        _ = try LibrarySync(volumeRoot: fakeIPod).sync(items: [item], coverArtPolicy: .albumOnly)

        let size = try size(ofFileAt: coverURL)
        XCTAssertEqual(size.width, 320)
        XCTAssertEqual(size.height, 320)
    }

    func testACoverSmallerThanTheContractSizeIsNotBlownUp() throws {
        // Una carátula chica no se agranda a 320: se manda como está,
        // cuadrada. El firmware la escala si la necesita más grande.
        let item = musicItem(cover: try jpeg(width: 200, height: 200))
        _ = try LibrarySync(volumeRoot: fakeIPod).sync(items: [item], coverArtPolicy: .albumOnly)

        let size = try size(ofFileAt: coverURL)
        XCTAssertEqual(size.width, 200)
        XCTAssertEqual(size.height, 200)
    }

    func testAnUnchangedCoverIsNotRewritten() throws {
        // Desde v18 el mtime de `cover.jpg` es parte de la clave de la
        // caché maestra del firmware: reescribirla igual en cada sync le
        // tiraría toda su caché de carátulas sin que nada cambiara.
        let item = musicItem(cover: try jpeg(width: 1000, height: 1000))
        let sync = LibrarySync(volumeRoot: fakeIPod)

        _ = try sync.sync(items: [item], coverArtPolicy: .albumOnly)
        let first = try FileManager.default.attributesOfItem(atPath: coverURL.path)[.modificationDate] as? Date

        _ = try sync.sync(items: [item], coverArtPolicy: .albumOnly)
        let second = try FileManager.default.attributesOfItem(atPath: coverURL.path)[.modificationDate] as? Date

        XCTAssertNotNil(first)
        XCTAssertEqual(first, second, "una carátula idéntica no debe reescribirse")
    }

    func testACoverThatChangedDoesTravelAgain() throws {
        var item = musicItem(cover: try jpeg(width: 1000, height: 1000))
        let sync = LibrarySync(volumeRoot: fakeIPod)
        _ = try sync.sync(items: [item], coverArtPolicy: .albumOnly)
        let before = try Data(contentsOf: coverURL)

        // Otro COLOR, no solo otro tamaño: dos imágenes lisas del mismo
        // color dan el mismo JPEG de 320 y la prueba no probaría nada.
        item.metadata?.coverArtData = try jpeg(width: 600, height: 600, red: 20)
        _ = try sync.sync(items: [item], coverArtPolicy: .albumOnly)

        XCTAssertNotEqual(try Data(contentsOf: coverURL), before)
    }

    func testACoverThatCannotBeDecodedDoesNotTravelAtAll() throws {
        // Antes que dejar en el iPod algo que incumple el contrato (o que
        // ni siquiera es una imagen), no se escribe nada.
        let item = musicItem(cover: Data("esto no es una imagen".utf8))
        _ = try LibrarySync(volumeRoot: fakeIPod).sync(items: [item], coverArtPolicy: .albumOnly)

        XCTAssertFalse(FileManager.default.fileExists(atPath: coverURL.path))
    }

    func testASyncThatOnlyChangedTheCoverStillMarksMusic() throws {
        // Desde v18 el firmware rehace su caché maestra por una clave que
        // incluye el mtime de `cover.jpg`: un sync que no copió ni una
        // canción pero cambió la carátula SÍ tocó Música, y el marcador
        // tiene que decirlo.
        var item = musicItem(cover: try jpeg(width: 1000, height: 1000))
        let sync = LibrarySync(volumeRoot: fakeIPod)
        _ = try sync.sync(items: [item], coverArtPolicy: .albumOnly)

        let marker = fakeIPod.appendingPathComponent(SyncPendingMarker.relativePath)
        try? FileManager.default.removeItem(at: marker)

        item.metadata?.coverArtData = try jpeg(width: 900, height: 900, red: 30)
        _ = try sync.sync(items: [item], coverArtPolicy: .albumOnly)

        let data = try XCTUnwrap(try? Data(contentsOf: marker), "el sync debió dejar el marcador")
        let decoded = try JSONDecoder().decode(SyncPendingMarker.self, from: data)
        XCTAssertTrue(decoded.changes.music)
    }

    func testTheArtistPhotoArrivesSquareAtDeviceArtistSide() throws {
        // §D.3 las exige cuadradas desde v6; hasta v18 Studio mandaba el
        // lado mayor a 128 con la proporción original.
        let item = musicItem(cover: nil)
        let store = ArtistImageStore(libraryRoot: libraryRoot)
        let key = LibraryGrouping.artistKey(of: item)
        // Se guarda saltándose `save` a propósito: así entra una foto
        // rectangular, como las que dejó cualquier versión anterior.
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try (try jpeg(width: 900, height: 600)).write(to: store.url(forArtistKey: key))

        _ = try LibrarySync(volumeRoot: fakeIPod).sync(items: [item], libraryRoot: libraryRoot)

        let photo = fakeIPod
            .appendingPathComponent(LibrarySync.artistImagesDirRelativePath)
            .appendingPathComponent(ArtistImageStore.fileName(forArtistKey: key))
        let size = try size(ofFileAt: photo)
        XCTAssertEqual(size.width, LibrarySync.deviceArtistSide)
        XCTAssertEqual(size.height, LibrarySync.deviceArtistSide)
    }

    func testAnUnchangedArtistPhotoIsNotRewrittenEither() throws {
        let item = musicItem(cover: nil)
        let store = ArtistImageStore(libraryRoot: libraryRoot)
        let key = LibraryGrouping.artistKey(of: item)
        try store.save(try jpeg(width: 500, height: 500), forArtistKey: key)

        let sync = LibrarySync(volumeRoot: fakeIPod)
        let photo = fakeIPod
            .appendingPathComponent(LibrarySync.artistImagesDirRelativePath)
            .appendingPathComponent(ArtistImageStore.fileName(forArtistKey: key))

        _ = try sync.sync(items: [item], libraryRoot: libraryRoot)
        let first = try FileManager.default.attributesOfItem(atPath: photo.path)[.modificationDate] as? Date

        _ = try sync.sync(items: [item], libraryRoot: libraryRoot)
        let second = try FileManager.default.attributesOfItem(atPath: photo.path)[.modificationDate] as? Date

        XCTAssertNotNil(first)
        XCTAssertEqual(first, second)
    }
}
