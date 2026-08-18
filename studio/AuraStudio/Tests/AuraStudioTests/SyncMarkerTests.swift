import XCTest
@testable import AuraStudio

/// ST-012 / `docs/contracts/library-layout-v1.md` SS4: el marcador
/// `/.aura/sync-pending.json` que LibrarySync deja para que el firmware
/// reconstruya sus indices al arrancar, y la capacidad
/// `sync_marker_supported` de aura.cfg que decide si ademas se borra la
/// base de tagcache (firmware viejo) o no (firmware nuevo).
final class SyncMarkerTests: XCTestCase {
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

    private func writeAuraConfig(_ text: String) throws {
        let dir = fakeIPod.appendingPathComponent(".rockbox/aura")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try text.write(to: dir.appendingPathComponent("aura.cfg"), atomically: true, encoding: .utf8)
    }

    private func plantTagcacheFiles() throws {
        let dir = fakeIPod.appendingPathComponent(".rockbox")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in LibrarySync.tagcacheFilesToClear {
            try Data("db".utf8).write(to: fakeIPod.appendingPathComponent(name))
        }
    }

    private var markerURL: URL { fakeIPod.appendingPathComponent(SyncPendingMarker.relativePath) }

    // MARK: - Modelo

    func testMarkerRoundTripsAndMatchesContractShape() throws {
        let marker = SyncPendingMarker(changes: .init(music: true, video: false, images: true),
                                       date: Date(timeIntervalSince1970: 1_787_000_000))
        try marker.write(to: fakeIPod)

        let text = try String(contentsOf: markerURL, encoding: .utf8)
        // Claves exactas del contrato SS4.1, en el nivel que corresponde.
        XCTAssertTrue(text.contains("\"version\" : 1"))
        XCTAssertTrue(text.contains("\"attempts\" : 0"))
        XCTAssertTrue(text.contains("\"changes\""))
        XCTAssertTrue(text.contains("\"music\" : true"))
        XCTAssertTrue(text.contains("\"images\" : true"))
        XCTAssertTrue(text.contains("\"timestamp\" : \"2026-08-17T"))

        XCTAssertEqual(SyncPendingMarker.read(from: fakeIPod), marker)
    }

    func testReadReturnsNilWhenAbsentOrMalformed() throws {
        XCTAssertNil(SyncPendingMarker.read(from: fakeIPod))
        try FileManager.default.createDirectory(at: markerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "no es json".write(to: markerURL, atomically: true, encoding: .utf8)
        XCTAssertNil(SyncPendingMarker.read(from: fakeIPod))
    }

    func testFirmwareCapabilityParsesAuraConfig() throws {
        XCTAssertNil(FirmwareCapabilities.supportedSyncMarkerVersion(volumeRoot: fakeIPod))
        try writeAuraConfig("theme: 1\ntheme_format_supported: 1\n")
        XCTAssertNil(FirmwareCapabilities.supportedSyncMarkerVersion(volumeRoot: fakeIPod),
                     "firmware anterior a D-293: sin la clave")
        try writeAuraConfig("theme: 1\nsync_marker_supported: 1\n")
        XCTAssertEqual(FirmwareCapabilities.supportedSyncMarkerVersion(volumeRoot: fakeIPod), 1)
    }

    // MARK: - LibrarySync

    func testSyncThatCopiesMusicWritesMarkerWithOnlyMusicMarked() throws {
        let sync = LibrarySync(volumeRoot: fakeIPod)
        let result = try sync.sync(items: [musicItem()])

        XCTAssertEqual(result.filesCopied, 1)
        XCTAssertTrue(result.syncMarkerWritten)
        let marker = try XCTUnwrap(SyncPendingMarker.read(from: fakeIPod))
        XCTAssertEqual(marker.version, SyncPendingMarker.currentVersion)
        XCTAssertEqual(marker.attempts, 0)
        XCTAssertTrue(marker.changes.music)
        XCTAssertFalse(marker.changes.video)
        XCTAssertFalse(marker.changes.images)
    }

    func testSyncWithNothingToCopyWritesNoMarker() throws {
        let sync = LibrarySync(volumeRoot: fakeIPod)
        let empty = try sync.sync(items: [])
        XCTAssertFalse(empty.syncMarkerWritten)
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))

        // Segunda pasada con la misma biblioteca: el diferencial no copia
        // nada -> tampoco hay marcador nuevo.
        let item = musicItem()
        _ = try sync.sync(items: [item])
        try FileManager.default.removeItem(at: markerURL)
        let again = try sync.sync(items: [item])
        XCTAssertEqual(again.filesCopied, 0)
        XCTAssertFalse(again.syncMarkerWritten)
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
    }

    func testMarkerAccumulatesPreviousUnprocessedSections() throws {
        // El firmware no alcanzo a procesar un marcador anterior con
        // Fotos: el nuevo sync (solo musica) debe conservar images=true.
        try SyncPendingMarker(changes: .init(music: false, video: false, images: true)).write(to: fakeIPod)
        let sync = LibrarySync(volumeRoot: fakeIPod)
        _ = try sync.sync(items: [musicItem()])

        let marker = try XCTUnwrap(SyncPendingMarker.read(from: fakeIPod))
        XCTAssertTrue(marker.changes.music)
        XCTAssertTrue(marker.changes.images)
        XCTAssertFalse(marker.changes.video)
        XCTAssertEqual(marker.attempts, 0, "marcador nuevo: el contador vuelve a cero")
    }

    func testOldFirmwareStillGetsTagcacheCleared() throws {
        try plantTagcacheFiles()
        // aura.cfg sin sync_marker_supported = firmware anterior a D-293
        try writeAuraConfig("theme: 1\n")
        _ = try LibrarySync(volumeRoot: fakeIPod).sync(items: [musicItem()])

        for name in LibrarySync.tagcacheFilesToClear {
            XCTAssertFalse(FileManager.default.fileExists(atPath: fakeIPod.appendingPathComponent(name).path),
                           "\(name) deberia haberse borrado (mecanismo previo)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path),
                      "el marcador se escribe igual: inofensivo para el firmware viejo")
    }

    func testNewFirmwareKeepsTagcacheAndGetsMarker() throws {
        try plantTagcacheFiles()
        try writeAuraConfig("theme: 1\nsync_marker_supported: 1\n")
        _ = try LibrarySync(volumeRoot: fakeIPod).sync(items: [musicItem()])

        for name in LibrarySync.tagcacheFilesToClear {
            XCTAssertTrue(FileManager.default.fileExists(atPath: fakeIPod.appendingPathComponent(name).path),
                          "\(name) NO debe borrarse: el firmware nuevo reconstruye por el marcador y la base vieja sigue usable")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path))
    }

    func testRemovingOrphanMarksItsSection() throws {
        let item = musicItem()
        let sync = LibrarySync(volumeRoot: fakeIPod)
        _ = try sync.sync(items: [item])
        try FileManager.default.removeItem(at: markerURL)

        // Se borra del iPod (eleccion explicita del usuario) sin copiar
        // nada nuevo: la seccion Musica igual cambio.
        let result = try sync.sync(items: [], removeOrphanedSourcePaths: [item.sourceURL.path])
        XCTAssertEqual(result.filesCopied, 0)
        XCTAssertTrue(result.syncMarkerWritten)
        let marker = try XCTUnwrap(SyncPendingMarker.read(from: fakeIPod))
        XCTAssertTrue(marker.changes.music)
    }
}
