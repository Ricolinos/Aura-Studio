import XCTest
@testable import AuraStudio

/// ST-265: el barrido de basura AppleDouble (`._*`) y `.DS_Store` del
/// iPod -- limpia las carpetas de contenido, no toca nada legitimo y
/// reporta cuantos archivos y bytes libero.
final class AppleDoubleJunkSweepTests: XCTestCase {
    private var fakeIPod: URL!

    override func setUpWithError() throws {
        fakeIPod = FileManager.default.temporaryDirectory
            .appendingPathComponent("FakeIPodJunk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeIPod, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fakeIPod)
    }

    private func seed(_ relativePath: String, bytes: Int = 100) throws -> URL {
        let url = fakeIPod.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: 0x07, count: bytes).write(to: url)
        return url
    }

    func testSweepRemovesAppleDoubleAndDSStoreKeepingRealFiles() throws {
        let junk1 = try seed("Music/Queen/._Bohemian Rhapsody.mp3", bytes: 4_096)
        let junk2 = try seed("Music/Queen/.DS_Store", bytes: 6_148)
        let junk3 = try seed("Videos/.DS_Store", bytes: 100)
        let real1 = try seed("Music/Queen/Bohemian Rhapsody.mp3", bytes: 9_000_000)
        let real2 = try seed("Music/Queen/cover.jpg", bytes: 50_000)

        let sync = LibrarySync(volumeRoot: fakeIPod)
        let result = sync.sweepAppleDoubleJunk()

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.bytes, 4_096 + 6_148 + 100)
        for url in [junk1, junk2, junk3] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                           "\(url.lastPathComponent) tenia que salir")
        }
        for url in [real1, real2] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                          "\(url.lastPathComponent) NO se toca")
        }
    }

    func testSweepNeverTouchesRockboxOrTheVolumeRoot() throws {
        // Un `._*` FUERA de las carpetas de contenido no es asunto de
        // este barrido (la raiz y .rockbox no son de contenido).
        let outside = try seed(".rockbox/._config.cfg")
        let atRoot = try seed("._algo.cfg")

        let sync = LibrarySync(volumeRoot: fakeIPod)
        let result = sync.sweepAppleDoubleJunk()

        XCTAssertEqual(result.count, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: atRoot.path))
    }

    func testSyncReportsTheJunkItCleaned() throws {
        _ = try seed("Music/Artista/._cancion.mp3", bytes: 2_048)
        var item = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/source-\(UUID().uuidString).mp3"))
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent("staged-\(UUID().uuidString).mp3")
        try Data("fake mp3 bytes".utf8).write(to: staged)
        addTeardownBlock { try? FileManager.default.removeItem(at: staged) }
        item.metadata = TrackMetadata(title: "Cancion", artist: "Artista", album: "Album")
        item.preparedURL = staged
        item.status = .ready

        let sync = LibrarySync(volumeRoot: fakeIPod)
        let result = try sync.sync(items: [item])

        XCTAssertEqual(result.junkFilesRemoved, 1)
        XCTAssertEqual(result.junkBytesRemoved, 2_048)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fakeIPod.appendingPathComponent("Music/Artista/._cancion.mp3").path))
    }
}
