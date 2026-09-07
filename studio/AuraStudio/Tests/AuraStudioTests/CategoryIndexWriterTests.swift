import XCTest
@testable import AuraStudio

/// PLAN-biblioteca-medios-v2.md §3.5 / CONTRATO-firmware-studio.md §D.2:
/// `LibrarySync.writeCategoryIndexes` (privado, se verifica a través de
/// `sync()`, mismo patrón que `LibrarySyncTests`/`LibrarySyncDeleteAllContentTests`).
final class CategoryIndexWriterTests: XCTestCase {
    private var fakeIPod: URL!
    private var stagedFiles: [URL] = []

    override func setUpWithError() throws {
        fakeIPod = FileManager.default.temporaryDirectory.appendingPathComponent("FakeIPod-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeIPod, withIntermediateDirectories: true)
        stagedFiles = []
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fakeIPod)
        for url in stagedFiles { try? FileManager.default.removeItem(at: url) }
    }

    /// ST-221 dio vuelta de dónde sale el nombre de destino: la BASE es
    /// la de `sourceURL` (el archivo que soltó el usuario) y solo la
    /// EXTENSIÓN es la del preparado. Por eso `videoItem`/`photoItem`
    /// arman el origen a partir del nombre pedido -- el índice tiene que
    /// nombrar el archivo **tal como queda en el iPod**, que es lo único
    /// que el firmware puede emparejar.
    ///
    /// Cada ítem necesita igual su propio archivo preparado en disco:
    /// `sync()` lo lee para el tamaño y la fecha.
    private func stage(named name: String, contents: String = "fake bytes") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try Data(contents.utf8).write(to: url)
        stagedFiles.append(url)
        return url
    }

    private func videoItem(category: String?, preparedName: String) throws -> AuraStudio.LibraryItem {
        let base = (preparedName as NSString).deletingPathExtension
        var item = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/\(base).mkv"))
        item.category = category
        item.preparedURL = try stage(named: preparedName)
        item.status = .ready
        return item
    }

    private func photoItem(category: String?, preparedName: String) throws -> AuraStudio.LibraryItem {
        let base = (preparedName as NSString).deletingPathExtension
        var item = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/\(base).jpg"))
        item.category = category
        item.preparedURL = try stage(named: preparedName)
        item.status = .ready
        return item
    }

    private var videoCategoriesURL: URL { fakeIPod.appendingPathComponent(LibrarySync.videoCategoriesRelativePath) }
    private var photoCategoriesURL: URL { fakeIPod.appendingPathComponent(LibrarySync.photoCategoriesRelativePath) }

    func testVideoCategoriesMapMoviesSeriesAndDefaultToClip() throws {
        let movie = try videoItem(category: "Películas", preparedName: "movie.mpg")
        let series = try videoItem(category: "Series", preparedName: "series.mpg")
        let clip = try videoItem(category: "Videos", preparedName: "clip.mpg")
        let sync = LibrarySync(volumeRoot: fakeIPod)

        _ = try sync.sync(items: [movie, series, clip])

        let text = try String(contentsOf: videoCategoriesURL, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("# aura-video-categories v1\n"))
        XCTAssertTrue(text.contains("movie.mpg: movie"))
        XCTAssertTrue(text.contains("series.mpg: series"))
        XCTAssertTrue(text.contains("clip.mpg: clip"))
    }

    func testVideoCategoryAcceptsEnglishDisplayName() throws {
        // D-283: item.category se guarda como el displayName LOCALIZADO
        // -- "Movies"/"Series" en inglés deben mapear igual que su
        // contraparte en español.
        let movie = try videoItem(category: MediaCategory.movies.displayNameEnglish, preparedName: "movie-en.mpg")
        let series = try videoItem(category: MediaCategory.series.displayNameEnglish, preparedName: "series-en.mpg")
        let sync = LibrarySync(volumeRoot: fakeIPod)

        _ = try sync.sync(items: [movie, series])

        let text = try String(contentsOf: videoCategoriesURL, encoding: .utf8)
        XCTAssertTrue(text.contains("movie-en.mpg: movie"))
        XCTAssertTrue(text.contains("series-en.mpg: series"))
    }

    func testPhotoCategoriesMapPhotosImagesAIAndCustomCollectionToImage() throws {
        let photo = try photoItem(category: "Fotos", preparedName: "photo.jpg")
        let ai = try photoItem(category: "IA", preparedName: "ai.jpg")
        let custom = try photoItem(category: "Recuerdos de viaje", preparedName: "custom.jpg") // colección personalizada
        let sync = LibrarySync(volumeRoot: fakeIPod)

        _ = try sync.sync(items: [photo, ai, custom])

        let text = try String(contentsOf: photoCategoriesURL, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("# aura-photo-categories v1\n"))
        XCTAssertTrue(text.contains("photo.jpg: photo"))
        XCTAssertTrue(text.contains("ai.jpg: ai"))
        XCTAssertTrue(text.contains("custom.jpg: image"),
                      "una colección personalizada (ni Fotos ni IA) exporta como 'image'")
    }

    func testNoVideosMeansIndexFileIsDeletedNotLeftStale() throws {
        let sync = LibrarySync(volumeRoot: fakeIPod)
        // Primer sync con un video deja el índice escrito.
        _ = try sync.sync(items: [try videoItem(category: "Películas", preparedName: "solo.mpg")])
        XCTAssertTrue(FileManager.default.fileExists(atPath: videoCategoriesURL.path))

        // Un sync posterior sin ningún video no debe dejar el índice
        // viejo apuntando a un archivo que ya no está.
        _ = try sync.sync(items: [try photoItem(category: "Fotos", preparedName: "solo.jpg")])
        XCTAssertFalse(FileManager.default.fileExists(atPath: videoCategoriesURL.path))
    }

    func testIndexEntriesAreWrittenPrecomposedNFC() throws {
        // ST-062: macOS reporta los nombres DESCOMPUESTOS (NFD) pero el
        // driver msdosfs los GUARDA precompuestos (NFC) en el LFN de
        // FAT32, que es lo que el firmware lee y compara byte a byte.
        // Un nombre con acento debe serializarse en NFC o el firmware
        // no lo empareja jamás (bug real: "Avatar Aang el último
        // maestro del aire.mpg" invisible en Películas).
        let nfdName = "Avatar Aang el \u{0075}\u{0301}ltimo maestro del aire.mpg"
        let nfcName = nfdName.precomposedStringWithCanonicalMapping
        XCTAssertNotEqual(Array(nfdName.utf8), Array(nfcName.utf8), "el fixture debe ser NFD de verdad")

        let movie = try videoItem(category: "Películas", preparedName: nfdName)
        let sync = LibrarySync(volumeRoot: fakeIPod)

        _ = try sync.sync(items: [movie])

        let data = try Data(contentsOf: videoCategoriesURL)
        let expectedLine = Data("\(nfcName): movie".utf8)
        let forbiddenLine = Data("\(nfdName): movie".utf8)
        XCTAssertNotNil(data.range(of: expectedLine), "la línea debe ir en NFC (precompuesta)")
        // Nota: si expected == forbidden el nombre no era NFD; ya se
        // afirmó arriba que difieren.
        XCTAssertNil(data.range(of: forbiddenLine), "no debe quedar la forma NFD")
    }
}
