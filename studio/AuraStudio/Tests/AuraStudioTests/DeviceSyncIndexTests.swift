import XCTest
@testable import AuraStudio

/// PLAN-general-sync.md §4: los 5 estados por elemento
/// (`DeviceSyncIndexBuilder.build`, lógica pura -- sin disco, mismo
/// criterio que `SyncPlannerTests`) más huérfanos y "solo en el iPod".
final class DeviceSyncIndexTests: XCTestCase {
    private typealias CurrentFile = DeviceSyncIndexBuilder.CurrentFile
    private typealias DeviceFileStat = DeviceSyncIndexBuilder.DeviceFileStat

    private func record(sourcePath: String, sourceSize: Int64 = 100, sourceModifiedAt: TimeInterval = 1000,
                         destination: String, destSize: Int64? = 200, destModifiedAt: TimeInterval? = 2000,
                         writtenBy: String? = "mac-1") -> SyncRecord {
        SyncRecord(sourcePath: sourcePath, sourceSize: sourceSize, sourceModifiedAt: sourceModifiedAt,
                   destinationRelativePath: destination, destinationSize: destSize,
                   destinationModifiedAt: destModifiedAt, writtenBy: writtenBy, syncedAt: 3000)
    }

    func testSyncedWhenPreparedAndDestinationFingerprintsBothMatch() {
        let manifest = SyncManifest(records: [
            "/a.mp3": record(sourcePath: "/a.mp3", destination: "Music/A/Al/a.mp3"),
        ])
        let index = DeviceSyncIndexBuilder.build(
            currentFiles: [CurrentFile(sourcePath: "/a.mp3", size: 100, modifiedAt: 1000)],
            manifest: manifest,
            deviceFiles: ["Music/A/Al/a.mp3": DeviceFileStat(size: 200, modifiedAt: 2000)]
        )
        XCTAssertEqual(index.state(forSourcePath: "/a.mp3"), .synced)
    }

    func testPendingWhenNoRecordExists() {
        let index = DeviceSyncIndexBuilder.build(
            currentFiles: [CurrentFile(sourcePath: "/new.mp3", size: 1, modifiedAt: 1)],
            manifest: .empty,
            deviceFiles: [:]
        )
        XCTAssertEqual(index.state(forSourcePath: "/new.mp3"), .pending)
    }

    func testChangedLocallyWhenPreparedFingerprintNoLongerMatchesRecord() {
        let manifest = SyncManifest(records: [
            "/a.mp3": record(sourcePath: "/a.mp3", sourceSize: 100, sourceModifiedAt: 1000, destination: "Music/A/Al/a.mp3"),
        ])
        // El archivo preparado cambio de tamaño (se re-etiqueto, se
        // volvio a leer del disco, etc.) -- el registro quedo viejo.
        let index = DeviceSyncIndexBuilder.build(
            currentFiles: [CurrentFile(sourcePath: "/a.mp3", size: 999, modifiedAt: 1000)],
            manifest: manifest,
            deviceFiles: ["Music/A/Al/a.mp3": DeviceFileStat(size: 200, modifiedAt: 2000)]
        )
        XCTAssertEqual(index.state(forSourcePath: "/a.mp3"), .changedLocally)
    }

    func testChangedLocallyWhenRecordIsLegacyWithoutDestinationFingerprint() {
        // Manifiesto v1 (PLAN-general-sync.md §9): sin destinationSize/
        // destinationModifiedAt -- no verificable, se trata como "con
        // cambios" una vez para que el proximo sync la complete.
        let manifest = SyncManifest(records: [
            "/a.mp3": record(sourcePath: "/a.mp3", destination: "Music/A/Al/a.mp3", destSize: nil, destModifiedAt: nil),
        ])
        let index = DeviceSyncIndexBuilder.build(
            currentFiles: [CurrentFile(sourcePath: "/a.mp3", size: 100, modifiedAt: 1000)],
            manifest: manifest,
            deviceFiles: ["Music/A/Al/a.mp3": DeviceFileStat(size: 200, modifiedAt: 2000)]
        )
        XCTAssertEqual(index.state(forSourcePath: "/a.mp3"), .changedLocally)
    }

    func testModifiedOnDeviceWhenDestinationFingerprintDiffersFromRecord() {
        let manifest = SyncManifest(records: [
            "/a.mp3": record(sourcePath: "/a.mp3", destination: "Music/A/Al/a.mp3", destSize: 200, destModifiedAt: 2000),
        ])
        // Alguien reemplazo el archivo en el iPod por fuera de Aura
        // Studio -- el tamaño real ya no es el que se registro al copiar.
        let index = DeviceSyncIndexBuilder.build(
            currentFiles: [CurrentFile(sourcePath: "/a.mp3", size: 100, modifiedAt: 1000)],
            manifest: manifest,
            deviceFiles: ["Music/A/Al/a.mp3": DeviceFileStat(size: 555, modifiedAt: 2000)]
        )
        XCTAssertEqual(index.state(forSourcePath: "/a.mp3"), .modifiedOnDevice)
    }

    func testRemovedFromDeviceWhenDestinationFileIsGone() {
        let manifest = SyncManifest(records: [
            "/a.mp3": record(sourcePath: "/a.mp3", destination: "Music/A/Al/a.mp3"),
        ])
        let index = DeviceSyncIndexBuilder.build(
            currentFiles: [CurrentFile(sourcePath: "/a.mp3", size: 100, modifiedAt: 1000)],
            manifest: manifest,
            deviceFiles: [:] // el destino ya no esta en el dispositivo
        )
        XCTAssertEqual(index.state(forSourcePath: "/a.mp3"), .removedFromDevice)
    }

    func testOrphanedRecordsAreItemsWhoseSourceLeftTheLibrary() {
        let manifest = SyncManifest(records: [
            "/a.mp3": record(sourcePath: "/a.mp3", destination: "Music/A/Al/a.mp3"),
            "/gone.mp3": record(sourcePath: "/gone.mp3", destination: "Music/B/Bl/gone.mp3"),
        ])
        let index = DeviceSyncIndexBuilder.build(
            currentFiles: [CurrentFile(sourcePath: "/a.mp3", size: 100, modifiedAt: 1000)], // "/gone.mp3" ya no esta en la biblioteca
            manifest: manifest,
            deviceFiles: [
                "Music/A/Al/a.mp3": DeviceFileStat(size: 200, modifiedAt: 2000),
                "Music/B/Bl/gone.mp3": DeviceFileStat(size: 50, modifiedAt: 500),
            ]
        )
        XCTAssertEqual(index.orphanedRecords.map(\.sourcePath), ["/gone.mp3"])
    }

    func testForeignPathIsAFileAuraStudioNeverWrote() {
        let manifest = SyncManifest(records: [
            "/a.mp3": record(sourcePath: "/a.mp3", destination: "Music/A/Al/a.mp3"),
        ])
        let index = DeviceSyncIndexBuilder.build(
            currentFiles: [CurrentFile(sourcePath: "/a.mp3", size: 100, modifiedAt: 1000)],
            manifest: manifest,
            deviceFiles: [
                "Music/A/Al/a.mp3": DeviceFileStat(size: 200, modifiedAt: 2000),
                "Music/Otro Artista/Copiado a mano.mp3": DeviceFileStat(size: 10, modifiedAt: 10),
            ]
        )
        XCTAssertEqual(index.foreignPaths, ["Music/Otro Artista/Copiado a mano.mp3"])
    }

    func testOwnedConventionsAreNeverFlaggedForeign() {
        let manifest = SyncManifest(records: [
            "/a.mp3": record(sourcePath: "/a.mp3", destination: "Music/A/Al/a.mp3"),
            "/v.mov": record(sourcePath: "/v.mov", destination: "Videos/v.mpg"),
        ])
        let index = DeviceSyncIndexBuilder.build(
            currentFiles: [
                CurrentFile(sourcePath: "/a.mp3", size: 100, modifiedAt: 1000),
                CurrentFile(sourcePath: "/v.mov", size: 100, modifiedAt: 1000),
            ],
            manifest: manifest,
            deviceFiles: [
                "Music/A/Al/a.mp3": DeviceFileStat(size: 200, modifiedAt: 2000),
                "Music/A/Al/cover.jpg": DeviceFileStat(size: 9, modifiedAt: 9), // caratula de album, sin registro propio
                "Videos/v.mpg": DeviceFileStat(size: 200, modifiedAt: 2000),
                "Videos/v.jpg": DeviceFileStat(size: 9, modifiedAt: 9), // poster, sin registro propio
                "Playlists/Favoritas.m3u8": DeviceFileStat(size: 9, modifiedAt: 9),
                "Playlists/Favoritas.jpg": DeviceFileStat(size: 9, modifiedAt: 9),
            ]
        )
        XCTAssertTrue(index.foreignPaths.isEmpty, "cover.jpg, poster y todo Playlists/ son propios de Aura Studio, aunque no tengan registro individual en el manifiesto")
    }

    func testHasConflictsReflectsModifiedOnDeviceAndOrphans() {
        var index = DeviceSyncIndex.empty
        XCTAssertFalse(index.hasConflicts)
        index.states["/a.mp3"] = .modifiedOnDevice
        XCTAssertTrue(index.hasConflicts)
    }

    // MARK: - scan() contra un filesystem real (fakeIPod)

    func testScanReflectsARealFilesystemEndToEnd() throws {
        let fakeIPod = FileManager.default.temporaryDirectory.appendingPathComponent("DeviceSyncIndexScan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeIPod, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fakeIPod) }

        let syncedDest = fakeIPod.appendingPathComponent("Music/Queen/Opera/Bohemian Rhapsody.mp3")
        try FileManager.default.createDirectory(at: syncedDest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("synced".utf8).write(to: syncedDest)
        let syncedAttrs = try FileManager.default.attributesOfItem(atPath: syncedDest.path)

        let foreignFile = fakeIPod.appendingPathComponent("Music/Copiado a mano.mp3")
        try Data("ajeno".utf8).write(to: foreignFile)

        let manifest = SyncManifest(records: [
            "/bohemian.mp3": record(
                sourcePath: "/bohemian.mp3", destination: "Music/Queen/Opera/Bohemian Rhapsody.mp3",
                destSize: (syncedAttrs[.size] as? Int64) ?? 0,
                destModifiedAt: (syncedAttrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            ),
        ])

        let index = DeviceSyncIndexBuilder.scan(
            volumeRoot: fakeIPod,
            currentFiles: [CurrentFile(sourcePath: "/bohemian.mp3", size: 100, modifiedAt: 1000)],
            manifest: manifest
        )

        XCTAssertEqual(index.state(forSourcePath: "/bohemian.mp3"), .synced)
        XCTAssertEqual(index.foreignPaths, ["Music/Copiado a mano.mp3"])
    }
}
