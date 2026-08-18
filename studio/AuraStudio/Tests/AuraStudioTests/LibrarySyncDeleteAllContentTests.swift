import XCTest
@testable import AuraStudio

/// Encargo del dueño (General → "Eliminar todos los archivos, o por
/// tipos de medios"): `LibrarySync.deleteAllDeviceContent(kinds:)`
/// borra contenido sincronizado directo del disco, fuera del flujo
/// normal de `sync()`. Mismo patrón de fixtures que `LibrarySyncTests`.
final class LibrarySyncDeleteAllContentTests: XCTestCase {
    private var fakeIPod: URL!
    private var musicStaging: URL!
    private var photoStaging: URL!

    override func setUpWithError() throws {
        fakeIPod = FileManager.default.temporaryDirectory.appendingPathComponent("FakeIPod-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeIPod, withIntermediateDirectories: true)
        musicStaging = FileManager.default.temporaryDirectory.appendingPathComponent("staged-\(UUID().uuidString).mp3")
        try Data("fake mp3 bytes".utf8).write(to: musicStaging)
        photoStaging = FileManager.default.temporaryDirectory.appendingPathComponent("staged-\(UUID().uuidString).jpg")
        try Data("fake jpg bytes".utf8).write(to: photoStaging)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fakeIPod)
        try? FileManager.default.removeItem(at: musicStaging)
        try? FileManager.default.removeItem(at: photoStaging)
    }

    private func musicItem() -> AuraStudio.LibraryItem {
        var item = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/source-\(UUID().uuidString).mp3"))
        item.metadata = TrackMetadata(title: "Song", artist: "Artist", album: "Album", trackNumber: 1)
        item.preparedURL = musicStaging
        item.status = .ready
        return item
    }

    private func photoItem() -> AuraStudio.LibraryItem {
        var item = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/source-\(UUID().uuidString).jpg"))
        item.preparedURL = photoStaging
        item.status = .ready
        return item
    }

    func testDeletingOneKindLeavesOthersUntouched() throws {
        let music = musicItem()
        let photo = photoItem()
        let sync = LibrarySync(volumeRoot: fakeIPod)
        _ = try sync.sync(items: [music, photo])

        let musicDestination = fakeIPod.appendingPathComponent("Music/Artist/Album/Song.mp3")
        let photoDestination = fakeIPod.appendingPathComponent("Photos/\(photoStaging.lastPathComponent)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: musicDestination.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: photoDestination.path))

        let deleted = try sync.deleteAllDeviceContent(kinds: [.music])

        XCTAssertEqual(deleted, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: musicDestination.path), "la musica se borro")
        XCTAssertTrue(FileManager.default.fileExists(atPath: photoDestination.path), "las fotos NO se tocan si solo se pidio borrar musica")

        let manifest = sync.loadManifest()
        XCTAssertNil(manifest.records[music.sourceURL.path], "el registro de musica se limpia del manifiesto")
        XCTAssertNotNil(manifest.records[photo.sourceURL.path], "el registro de fotos sigue -- no se toco esa seccion")
    }

    func testDeletingAllKindsRemovesEverythingAndClearsManifest() throws {
        let music = musicItem()
        let photo = photoItem()
        let sync = LibrarySync(volumeRoot: fakeIPod)
        _ = try sync.sync(items: [music, photo])

        let deleted = try sync.deleteAllDeviceContent(kinds: [.music, .video, .photo])
        XCTAssertEqual(deleted, 2)

        let manifest = sync.loadManifest()
        XCTAssertTrue(manifest.records.isEmpty)
    }

    /// Sin esto, el proximo sync() vería el mismo sourcePath/tamaño/
    /// fecha del registro viejo (que ya no se borró, sigue igual) y
    /// decidiría `.skip` -- "ya está copiado" -- aunque el archivo real
    /// ya no exista en el disco.
    func testAfterDeletionNextSyncRecopiesInsteadOfSkipping() throws {
        let music = musicItem()
        let sync = LibrarySync(volumeRoot: fakeIPod)
        _ = try sync.sync(items: [music])
        _ = try sync.deleteAllDeviceContent(kinds: [.music])

        let result = try sync.sync(items: [music])

        XCTAssertEqual(result.filesCopied, 1, "el manifiesto limpio hace que se vuelva a copiar, no que se salte")
        let musicDestination = fakeIPod.appendingPathComponent("Music/Artist/Album/Song.mp3")
        XCTAssertTrue(FileManager.default.fileExists(atPath: musicDestination.path))
    }

    func testDeletionWritesSyncPendingMarkerForTheFirmware() throws {
        let music = musicItem()
        let sync = LibrarySync(volumeRoot: fakeIPod)
        _ = try sync.sync(items: [music])

        _ = try sync.deleteAllDeviceContent(kinds: [.music])

        let marker = SyncPendingMarker.read(from: fakeIPod, fileManager: .default)
        XCTAssertNotNil(marker)
        XCTAssertEqual(marker?.changes.music, true)
        XCTAssertEqual(marker?.changes.video, false)
        XCTAssertEqual(marker?.changes.images, false)
    }

    func testDeletingEmptyKindsDoesNothing() throws {
        let sync = LibrarySync(volumeRoot: fakeIPod)
        let deleted = try sync.deleteAllDeviceContent(kinds: [])
        XCTAssertEqual(deleted, 0)
    }
}
