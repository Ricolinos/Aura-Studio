import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import AuraStudio

/// PLAN-biblioteca-medios-v2.md §3.5 (Tanda 5) / CONTRATO-firmware-studio.md
/// §D.3: `LibrarySync.writeArtistImages` -- fotos de artista reales al
/// iPod, junto al índice `archivo: artista` (formato invertido a
/// propósito, ver aura_artist_images_parse.h del firmware).
final class ArtistImageExportTests: XCTestCase {
    private var fakeIPod: URL!
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        fakeIPod = FileManager.default.temporaryDirectory.appendingPathComponent("FakeIPod-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeIPod, withIntermediateDirectories: true)
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("AuraLib-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fakeIPod)
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    private func musicItem(title: String, artist: String, albumArtist: String, album: String) -> AuraStudio.LibraryItem {
        var item = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).mp3"))
        item.metadata = TrackMetadata(title: title, artist: artist, album: album, albumArtist: albumArtist)
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp3")
        try? Data("fake mp3 bytes".utf8).write(to: staging)
        item.preparedURL = staging
        item.status = .ready
        return item
    }

    /// JPEG cuadrado sintético (D-303): nunca datos reales.
    private func makeFakeJPEGData(size: Int = 200) -> Data? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                       space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 0.7, green: 0.2, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        guard let image = context.makeImage() else { return nil }
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }

    private var artistsDirURL: URL { fakeIPod.appendingPathComponent(LibrarySync.artistImagesDirRelativePath) }
    private var indexURL: URL { fakeIPod.appendingPathComponent(LibrarySync.artistImagesIndexRelativePath) }

    func testTwoRawArtistTagVariantsShareOneImageAndTwoIndexLines() throws {
        let e1 = musicItem(title: "Uno", artist: "Queen", albumArtist: "Queen", album: "A")
        let e2 = musicItem(title: "Dos", artist: "Queen feat. David Bowie", albumArtist: "Queen", album: "A")
        let key = LibraryGrouping.artistKey(of: e1)
        let store = ArtistImageStore(libraryRoot: libraryRoot)
        try store.save(try XCTUnwrap(makeFakeJPEGData()), forArtistKey: key)

        let sync = LibrarySync(volumeRoot: fakeIPod)
        _ = try sync.sync(items: [e1, e2], libraryRoot: libraryRoot)

        let fileName = ArtistImageStore.fileName(forArtistKey: key)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artistsDirURL.appendingPathComponent(fileName).path))

        let index = try String(contentsOf: indexURL, encoding: .utf8)
        XCTAssertTrue(index.hasPrefix("# aura-artist-images v1\n"))
        XCTAssertTrue(index.contains("\(fileName): Queen\n") || index.hasSuffix("\(fileName): Queen"))
        XCTAssertTrue(index.contains("\(fileName): Queen feat. David Bowie"))
        // Un solo archivo compartido -- no dos copias de la misma foto.
        let jpgCount = (try? FileManager.default.contentsOfDirectory(atPath: artistsDirURL.path))?.count ?? 0
        XCTAssertEqual(jpgCount, 1)
    }

    func testNoSavedArtistImagesMeansNoFileAndNoIndex() throws {
        let e1 = musicItem(title: "Uno", artist: "Sin Foto", albumArtist: "Sin Foto", album: "A")
        let sync = LibrarySync(volumeRoot: fakeIPod)

        _ = try sync.sync(items: [e1], libraryRoot: libraryRoot)

        XCTAssertFalse(FileManager.default.fileExists(atPath: indexURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: artistsDirURL.path))
    }

    func testArtistNameWithColonIsPreservedWholeAsTheValue() throws {
        let e1 = musicItem(title: "Live", artist: "Panic! At The Disco: Live", albumArtist: "Panic! At The Disco: Live", album: "A")
        let key = LibraryGrouping.artistKey(of: e1)
        let store = ArtistImageStore(libraryRoot: libraryRoot)
        try store.save(try XCTUnwrap(makeFakeJPEGData()), forArtistKey: key)

        let sync = LibrarySync(volumeRoot: fakeIPod)
        _ = try sync.sync(items: [e1], libraryRoot: libraryRoot)

        let fileName = ArtistImageStore.fileName(forArtistKey: key)
        let index = try String(contentsOf: indexURL, encoding: .utf8)
        // El nombre de archivo va PRIMERO (FAT-seguro); el ':' del
        // nombre de artista queda intacto como parte del valor -- el
        // parser del firmware separa en el PRIMER ':' de la línea.
        XCTAssertTrue(index.contains("\(fileName): Panic! At The Disco: Live"))
    }

    /// Contrato v20 (ST-159): la foto de artista que llega al iPod es de
    /// `LibrarySync.deviceArtistSide` (320×320 desde v20, antes 128) --
    /// se compara contra la constante, no un número de más, para que
    /// esta prueba no quede desactualizada la próxima vez que cambie.
    func testExportedImageIsResizedToDeviceArtistSide() throws {
        let e1 = musicItem(title: "Uno", artist: "Grande", albumArtist: "Grande", album: "A")
        let key = LibraryGrouping.artistKey(of: e1)
        let store = ArtistImageStore(libraryRoot: libraryRoot)
        try store.save(try XCTUnwrap(makeFakeJPEGData(size: 800)), forArtistKey: key)

        let sync = LibrarySync(volumeRoot: fakeIPod)
        _ = try sync.sync(items: [e1], libraryRoot: libraryRoot)

        let fileName = ArtistImageStore.fileName(forArtistKey: key)
        let outputURL = artistsDirURL.appendingPathComponent(fileName)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(outputURL as CFURL, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try XCTUnwrap(props[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(props[kCGImagePropertyPixelHeight] as? Int)
        XCTAssertEqual(width, LibrarySync.deviceArtistSide)
        XCTAssertEqual(height, LibrarySync.deviceArtistSide)
    }

    func testDeletingAllMusicRemovesArtistImagesAndIndex() throws {
        let e1 = musicItem(title: "Uno", artist: "Queen", albumArtist: "Queen", album: "A")
        let key = LibraryGrouping.artistKey(of: e1)
        let store = ArtistImageStore(libraryRoot: libraryRoot)
        try store.save(try XCTUnwrap(makeFakeJPEGData()), forArtistKey: key)

        let sync = LibrarySync(volumeRoot: fakeIPod)
        _ = try sync.sync(items: [e1], libraryRoot: libraryRoot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexURL.path))

        _ = try sync.deleteAllDeviceContent(kinds: [.music])

        XCTAssertFalse(FileManager.default.fileExists(atPath: indexURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: artistsDirURL.path))
    }
}
