import XCTest
@testable import AuraStudio

/// ST-069 / contrato v15: forzar la reconstruccion de la base borra
/// `database_*.tcd` + `db_stamp.txt` en `/.aura/tagcache/` (compartida),
/// en `/.rockbox/` y en cada `/.firmware-*/` (firmwares anteriores a
/// v15), y deja `/.aura/thumbs/` intacto. Todo sobre carpetas temporales.
final class FirmwareDBRebuildTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("FakeIPod-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    private func write(_ relative: String, _ text: String = "x") throws {
        let url = root.appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func exists(_ relative: String) -> Bool {
        fm.fileExists(atPath: root.appendingPathComponent(relative).path)
    }

    func testForcedRebuildClearsSharedTagcacheAndKeepsThumbs() throws {
        try write(".aura/tagcache/database_idx.tcd")
        try write(".aura/tagcache/database_0.tcd")
        try write(".aura/tagcache/database_6.tcd")
        try write(".aura/tagcache/db_stamp.txt", "sello")
        try write(".aura/thumbs/albums/a.jpg")
        try write(".aura/thumbs/artists/b.jpg")
        try write(".aura/thumbs/photos/c.jpg")
        try write(".aura/library-stamp", "sello")
        try write(".aura/sync-pending.json", "{}")
        // Firmwares anteriores a v15: base por arbol.
        try write(".rockbox/database_idx.tcd")
        try write(".rockbox/aura/db_stamp.txt", "sello")
        try write(".rockbox/aura/aura.cfg", "theme: 1\n")
        try write(".firmware-metro/database_idx.tcd")
        try write(".firmware-metro/aura/db_stamp.txt", "sello")
        try write(".firmware-metro/aura/aura.cfg", "firmware_family: metro\n")

        LibrarySync.clearFirmwareDatabases(volumeRoot: root)

        for gone in [".aura/tagcache/database_idx.tcd", ".aura/tagcache/database_0.tcd",
                     ".aura/tagcache/database_6.tcd", ".aura/tagcache/db_stamp.txt",
                     ".rockbox/database_idx.tcd", ".rockbox/aura/db_stamp.txt",
                     ".firmware-metro/database_idx.tcd", ".firmware-metro/aura/db_stamp.txt"] {
            XCTAssertFalse(exists(gone), "\(gone) debe borrarse al forzar la reconstruccion")
        }
        for kept in [".aura/tagcache", ".aura/thumbs/albums/a.jpg", ".aura/thumbs/artists/b.jpg",
                     ".aura/thumbs/photos/c.jpg", ".aura/library-stamp", ".aura/sync-pending.json",
                     ".rockbox/aura/aura.cfg", ".firmware-metro/aura/aura.cfg"] {
            XCTAssertTrue(exists(kept), "\(kept) debe quedar intacto")
        }
    }

    func testForcedRebuildToleratesMissingSharedDirectory() throws {
        try write(".rockbox/database_idx.tcd")
        LibrarySync.clearFirmwareDatabases(volumeRoot: root)
        XCTAssertFalse(exists(".rockbox/database_idx.tcd"))
        XCTAssertFalse(exists(".aura/tagcache"), "no se crea nada: el directorio es del firmware")
    }

    /// El camino real: un sync con firmware sin `sync_marker_supported`
    /// dispara la reconstruccion forzada; con marcador soportado no toca
    /// la base compartida.
    func testSyncWithLegacyFirmwareClearsSharedTagcache() throws {
        try write(".aura/tagcache/database_idx.tcd")
        try write(".aura/thumbs/albums/a.jpg")
        try write(".rockbox/aura/aura.cfg", "theme: 1\n")
        let staging = root.appendingPathComponent("staging.mp3")
        try Data("mp3".utf8).write(to: staging)
        var item = LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/source-\(UUID().uuidString).mp3"))
        item.metadata = TrackMetadata(title: "T", artist: "A", album: "B", trackNumber: 1)
        item.preparedURL = staging
        item.status = .ready

        _ = try LibrarySync(volumeRoot: root).sync(items: [item])
        XCTAssertFalse(exists(".aura/tagcache/database_idx.tcd"))
        XCTAssertTrue(exists(".aura/thumbs/albums/a.jpg"))
        XCTAssertTrue(exists(".aura/library-stamp"), "el sync con musica sigue renovando el sello")
        XCTAssertTrue(exists(".aura/sync-pending.json"))

        try write(".aura/tagcache/database_idx.tcd")
        try write(".rockbox/aura/aura.cfg", "theme: 1\nsync_marker_supported: 1\n")
        _ = try LibrarySync(volumeRoot: root).sync(items: [item])
        XCTAssertTrue(exists(".aura/tagcache/database_idx.tcd"),
                      "con marcador soportado la base compartida sigue usable")
    }
}
