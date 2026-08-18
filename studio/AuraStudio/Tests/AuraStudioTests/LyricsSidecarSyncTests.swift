import XCTest
@testable import AuraStudio

/// ST-012 / `docs/contracts/library-layout-v1.md` SS3: letras `.lrc` junto
/// al audio en el iPod, mismo nombre base -- la unica ruta que el
/// firmware busca (`aura_nowplaying.c`, `derive_sibling_path()`).
final class LyricsSidecarSyncTests: XCTestCase {
    private var fakeIPod: URL!
    private var stagingFile: URL!

    override func setUpWithError() throws {
        fakeIPod = FileManager.default.temporaryDirectory.appendingPathComponent("FakeIPod-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeIPod, withIntermediateDirectories: true)
        stagingFile = FileManager.default.temporaryDirectory.appendingPathComponent("staged-\(UUID().uuidString).mp3")
        try Data("fake mp3 bytes".utf8).write(to: stagingFile)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fakeIPod)
        try? FileManager.default.removeItem(at: stagingFile)
    }

    private let syncedLyrics = "[00:01.00]Is this the real life\n[00:04.50]Is this just fantasy"

    private func musicItem(lyrics: String?, sourcePath: String? = nil) -> AuraStudio.LibraryItem {
        var item = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: sourcePath ?? "/tmp/source-\(UUID().uuidString).mp3"))
        item.metadata = TrackMetadata(title: "Bohemian Rhapsody", artist: "Queen", album: "A Night at the Opera",
                                      trackNumber: 11, syncedLyrics: lyrics)
        item.preparedURL = stagingFile
        item.status = .ready
        return item
    }

    private var expectedAudio: URL { fakeIPod.appendingPathComponent("Music/Queen/A Night at the Opera/Bohemian Rhapsody.mp3") }
    private var expectedLRC: URL { fakeIPod.appendingPathComponent("Music/Queen/A Night at the Opera/Bohemian Rhapsody.lrc") }

    func testSidecarPathIsSiblingWithSameBaseName() {
        XCTAssertEqual(LibrarySync.lyricsSidecarRelativePath(forDeviceRelativePath: "Music/A/B/01 Song.mp3"),
                       "Music/A/B/01 Song.lrc")
        XCTAssertEqual(LibrarySync.lyricsSidecarRelativePath(forDeviceRelativePath: "Music/A/B/Song.alac.m4a"),
                       "Music/A/B/Song.alac.lrc",
                       "solo se reemplaza la ULTIMA extension, igual que derive_sibling_path() en el firmware")
    }

    func testSyncWritesLRCNextToAudioAsUTF8() throws {
        _ = try LibrarySync(volumeRoot: fakeIPod).sync(items: [musicItem(lyrics: syncedLyrics)])

        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedAudio.path))
        let written = try String(contentsOf: expectedLRC, encoding: .utf8)
        XCTAssertEqual(written, syncedLyrics + "\n")
    }

    func testPlainLyricsAreWrittenToo() throws {
        // Sin marcas de tiempo: el firmware decide (hoy las ignora); Studio
        // las escribe igual (contrato SS3).
        _ = try LibrarySync(volumeRoot: fakeIPod).sync(items: [musicItem(lyrics: "Solo letra plana\nsegunda linea")])
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedLRC.path))
    }

    func testNoLyricsMeansNoFile() throws {
        _ = try LibrarySync(volumeRoot: fakeIPod).sync(items: [musicItem(lyrics: nil)])
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedAudio.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: expectedLRC.path))

        _ = try LibrarySync(volumeRoot: fakeIPod).sync(items: [musicItem(lyrics: "   \n")])
        XCTAssertFalse(FileManager.default.fileExists(atPath: expectedLRC.path), "solo espacios = sin letra")
    }

    func testLyricsArrivingAfterTheSongWasSyncedStillLand() throws {
        // La cancion se sincronizo sin letra; el enriquecimiento la trajo
        // despues. El diferencial no recopia el audio -- el .lrc tiene
        // que llegar igual.
        let sourcePath = "/tmp/source-\(UUID().uuidString).mp3"
        let sync = LibrarySync(volumeRoot: fakeIPod)
        let first = try sync.sync(items: [musicItem(lyrics: nil, sourcePath: sourcePath)])
        XCTAssertEqual(first.filesCopied, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: expectedLRC.path))

        let second = try sync.sync(items: [musicItem(lyrics: syncedLyrics, sourcePath: sourcePath)])
        XCTAssertEqual(second.filesCopied, 0, "el audio no cambio: no se recopia")
        XCTAssertEqual(try String(contentsOf: expectedLRC, encoding: .utf8), syncedLyrics + "\n")
    }

    func testClearingLyricsInStudioRemovesTheSidecar() throws {
        let sourcePath = "/tmp/source-\(UUID().uuidString).mp3"
        let sync = LibrarySync(volumeRoot: fakeIPod)
        _ = try sync.sync(items: [musicItem(lyrics: syncedLyrics, sourcePath: sourcePath)])
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedLRC.path))

        _ = try sync.sync(items: [musicItem(lyrics: nil, sourcePath: sourcePath)])
        XCTAssertFalse(FileManager.default.fileExists(atPath: expectedLRC.path), "nunca huerfanos")
    }

    func testRemovingTheSongRemovesItsSidecar() throws {
        let item = musicItem(lyrics: syncedLyrics)
        let sync = LibrarySync(volumeRoot: fakeIPod)
        _ = try sync.sync(items: [item])
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedLRC.path))

        _ = try sync.sync(items: [], removeOrphanedSourcePaths: [item.sourceURL.path])
        XCTAssertFalse(FileManager.default.fileExists(atPath: expectedAudio.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: expectedLRC.path))
    }

    func testRelocatingTheSongMovesItsSidecar() throws {
        // Cambia el layout de Music/ (Artista/Album -> Album): la cancion se
        // reubica y el .lrc viejo no debe quedar huerfano en la carpeta
        // anterior.
        let sourcePath = "/tmp/source-\(UUID().uuidString).mp3"
        let sync = LibrarySync(volumeRoot: fakeIPod)
        _ = try sync.sync(items: [musicItem(lyrics: syncedLyrics, sourcePath: sourcePath)], musicOrganization: .artistAlbum)
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedLRC.path))

        _ = try sync.sync(items: [musicItem(lyrics: syncedLyrics, sourcePath: sourcePath)], musicOrganization: .album)
        XCTAssertFalse(FileManager.default.fileExists(atPath: expectedLRC.path), "el .lrc viejo se fue con la cancion")
        let relocated = fakeIPod.appendingPathComponent("Music/A Night at the Opera/Bohemian Rhapsody.lrc")
        XCTAssertTrue(FileManager.default.fileExists(atPath: relocated.path))
    }

    func testSidecarIsOwnedByStudioInTheDeviceIndex() throws {
        let item = musicItem(lyrics: syncedLyrics)
        let sync = LibrarySync(volumeRoot: fakeIPod)
        _ = try sync.sync(items: [item])

        let index = DeviceSyncIndexBuilder.scan(volumeRoot: fakeIPod, currentFiles: [], manifest: sync.loadManifest())
        XCTAssertTrue(index.foreignPaths.isEmpty, "el .lrc no debe aparecer como 'Solo en el iPod': \(index.foreignPaths)")
    }
}
