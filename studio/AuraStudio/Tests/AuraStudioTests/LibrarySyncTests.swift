import XCTest
@testable import AuraStudio

/// Fase 24: LibrarySync.sync() contra una carpeta temporal en vez de un
/// iPod de verdad (mismo patron que LibraryPipelineIntegrationTests,
/// pero sin ffmpeg de por medio -- solo musica, asi que corre rapido y
/// sin fixtures externos).
final class LibrarySyncTests: XCTestCase {
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

    private func musicItem() -> AuraStudio.LibraryItem {
        var item = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/source-\(UUID().uuidString).mp3"))
        item.metadata = TrackMetadata(title: "Bohemian Rhapsody", artist: "Queen", album: "A Night at the Opera", trackNumber: 11)
        item.preparedURL = stagingFile
        item.status = .ready
        return item
    }

    func testSyncWritesMusicAtHierarchicalPath() throws {
        let item = musicItem()
        let sync = LibrarySync(volumeRoot: fakeIPod)

        let result = try sync.sync(items: [item])

        XCTAssertEqual(result.filesCopied, 1)
        let expected = fakeIPod.appendingPathComponent("Music/Queen/A Night at the Opera/Bohemian Rhapsody.mp3")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expected.path))
    }

    func testMigrationDeletesStaleFlatFile() throws {
        let item = musicItem()
        let sync = LibrarySync(volumeRoot: fakeIPod)

        // Simula un dispositivo sincronizado antes de esta fase: el
        // manifiesto apunta a la ruta plana vieja y el archivo ya esta
        // ahi.
        let staleRelative = "Music/\(item.sourceURL.lastPathComponent)"
        let staleURL = fakeIPod.appendingPathComponent(staleRelative)
        try FileManager.default.createDirectory(at: staleURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old flat copy".utf8).write(to: staleURL)

        let attrs = try FileManager.default.attributesOfItem(atPath: stagingFile.path)
        let manifest = SyncManifest(records: [
            item.sourceURL.path: SyncRecord(
                sourcePath: item.sourceURL.path,
                sourceSize: (attrs[.size] as? Int64) ?? 0,
                sourceModifiedAt: (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0,
                destinationRelativePath: staleRelative
            ),
        ])
        try sync.saveManifest(manifest)

        let result = try sync.sync(items: [item])

        XCTAssertEqual(result.filesCopied, 1, "el destino cambio, debe recopiarse aunque tamano/fecha sean iguales")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleURL.path), "el archivo en la ruta plana vieja debe borrarse")
        let newURL = fakeIPod.appendingPathComponent("Music/Queen/A Night at the Opera/Bohemian Rhapsody.mp3")
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
    }

    func testPlaylistIsWrittenAsM3U8WithResolvedPaths() throws {
        let item = musicItem()
        let playlist = Playlist(name: "Roadtrip", trackItemIDs: [item.id])
        let sync = LibrarySync(volumeRoot: fakeIPod)

        let result = try sync.sync(items: [item], playlists: [playlist])

        XCTAssertEqual(result.playlistsWritten, 1)
        let playlistURL = fakeIPod.appendingPathComponent("Playlists/Roadtrip.m3u8")
        let contents = try String(contentsOf: playlistURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("#EXTM3U"))
        XCTAssertTrue(contents.contains("/Music/Queen/A Night at the Opera/Bohemian Rhapsody.mp3"))
    }

    func testPlaylistWithNoResolvableTracksIsNotWritten() throws {
        let playlist = Playlist(name: "Vacio", trackItemIDs: [UUID()])
        let sync = LibrarySync(volumeRoot: fakeIPod)

        let result = try sync.sync(items: [], playlists: [playlist])

        XCTAssertEqual(result.playlistsWritten, 0)
        let playlistURL = fakeIPod.appendingPathComponent("Playlists/Vacio.m3u8")
        XCTAssertFalse(FileManager.default.fileExists(atPath: playlistURL.path))
    }

    // MARK: - Progreso (D-217)

    func testOnProgressReportsEachCopiedFileAgainstFilesActuallyCopied() throws {
        let item = musicItem()
        let sync = LibrarySync(volumeRoot: fakeIPod)
        var calls: [(copied: Int, total: Int)] = []

        _ = try sync.sync(items: [item]) { copied, total in
            calls.append((copied, total))
        }

        XCTAssertEqual(calls.count, 1, "un solo archivo por copiar -- un solo tick de progreso")
        XCTAssertEqual(calls.first?.copied, 1)
        XCTAssertEqual(calls.first?.total, 1)
    }

    func testOnProgressNotCalledWhenNothingNeedsCopying() throws {
        let item = musicItem()
        let sync = LibrarySync(volumeRoot: fakeIPod)
        _ = try sync.sync(items: [item])

        var calls = 0
        _ = try sync.sync(items: [item]) { _, _ in calls += 1 }

        XCTAssertEqual(calls, 0, "el segundo sync no copia nada (mismo tamaño/fecha) -- sin tick de progreso")
    }

    // MARK: - Calificaciones (D-200)

    func testRatedItemWritesNativeScaleRatingToSidecar() throws {
        var item = musicItem()
        item.metadata?.rating = 4
        let sync = LibrarySync(volumeRoot: fakeIPod)

        _ = try sync.sync(items: [item])

        let url = fakeIPod.appendingPathComponent(LibrarySync.ratingsRelativePath)
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("/Music/Queen/A Night at the Opera/Bohemian Rhapsody.mp3: 8"),
                      "4 estrellas de Aura Studio deben llegar como 8 en la escala nativa 0-10 de Rockbox")
    }

    func testUnratedItemsProduceNoSidecar() throws {
        let item = musicItem()
        let sync = LibrarySync(volumeRoot: fakeIPod)

        _ = try sync.sync(items: [item])

        let url = fakeIPod.appendingPathComponent(LibrarySync.ratingsRelativePath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testClearingRatingRemovesAnExistingSidecar() throws {
        var item = musicItem()
        item.metadata?.rating = 5
        let sync = LibrarySync(volumeRoot: fakeIPod)
        _ = try sync.sync(items: [item])
        let url = fakeIPod.appendingPathComponent(LibrarySync.ratingsRelativePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        item.metadata?.rating = nil
        _ = try sync.sync(items: [item])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testSummaryFileReflectsSyncedCounts() throws {
        let item = musicItem()
        let sync = LibrarySync(volumeRoot: fakeIPod)

        _ = try sync.sync(items: [item])

        let summaryURL = fakeIPod.appendingPathComponent(LibrarySync.summaryRelativePath)
        let contents = try String(contentsOf: summaryURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("music_count: 1"))
        XCTAssertTrue(contents.contains("video_count: 0"))
        XCTAssertTrue(contents.contains("playlist_count: 0"))
    }
}
