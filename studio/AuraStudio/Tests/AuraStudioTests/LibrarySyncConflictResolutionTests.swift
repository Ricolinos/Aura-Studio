import XCTest
@testable import AuraStudio

/// PLAN-general-sync.md §0.1/§1.2: la hoja de conflictos previa a
/// sincronizar necesita que `LibrarySync.sync()` sepa forzar la
/// recopia de un archivo "modificado en el iPod" (el usuario eligió
/// "Reemplazar con la biblioteca") y borrar del dispositivo los
/// registros huérfanos que el usuario marcó explícitamente -- nunca
/// automático.
final class LibrarySyncConflictResolutionTests: XCTestCase {
    private var fakeIPod: URL!
    private var stagingFiles: [URL] = []

    override func setUpWithError() throws {
        fakeIPod = FileManager.default.temporaryDirectory.appendingPathComponent("FakeIPod-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeIPod, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fakeIPod)
        for file in stagingFiles { try? FileManager.default.removeItem(at: file) }
    }

    private func musicItem(title: String, artist: String = "Queen", album: String = "A Night at the Opera") throws -> AuraStudio.LibraryItem {
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("staged-\(UUID().uuidString).mp3")
        try Data("fake mp3 bytes for \(title)".utf8).write(to: staging)
        stagingFiles.append(staging)
        var item = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/source-\(UUID().uuidString).mp3"))
        item.metadata = TrackMetadata(title: title, artist: artist, album: album)
        item.preparedURL = staging
        item.status = .ready
        return item
    }

    func testForceRecopyOverridesAFileSyncPlannerWouldOtherwiseSkip() throws {
        let item = try musicItem(title: "Song A")
        let sync = LibrarySync(volumeRoot: fakeIPod)
        let first = try sync.sync(items: [item])
        XCTAssertEqual(first.filesCopied, 1)

        let destination = fakeIPod.appendingPathComponent("Music/Queen/A Night at the Opera/Song A.mp3")
        // Alguien reemplazo el archivo en el iPod por fuera de Aura
        // Studio -- sin nada que cambiara del lado de la biblioteca,
        // un sync normal lo saltearia (SyncPlanner nunca mira el
        // destino).
        try Data("contenido distinto puesto a mano en el iPod".utf8).write(to: destination)

        let withoutForce = try sync.sync(items: [item])
        XCTAssertEqual(withoutForce.filesCopied, 0, "sin forceRecopySourcePaths, \"conservar en el iPod\" es el default -- cero codigo especial, ya es lo que pasa")

        let withForce = try sync.sync(items: [item], forceRecopySourcePaths: [item.sourceURL.path])
        XCTAssertEqual(withForce.filesCopied, 1, "\"Reemplazar con la biblioteca\": el usuario eligio explicitamente recopiar")
        XCTAssertEqual(try Data(contentsOf: destination), try Data(contentsOf: item.preparedURL!))
    }

    func testRemoveOrphanedSourcePathsDeletesOnlyTheChosenOnesFromDeviceAndManifest() throws {
        let itemA = try musicItem(title: "Song A")
        let itemB = try musicItem(title: "Song B", artist: "Beatles", album: "Abbey Road")
        let sync = LibrarySync(volumeRoot: fakeIPod)
        _ = try sync.sync(items: [itemA, itemB])

        let destinationA = fakeIPod.appendingPathComponent("Music/Queen/A Night at the Opera/Song A.mp3")
        let destinationB = fakeIPod.appendingPathComponent("Music/Beatles/Abbey Road/Song B.mp3")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationA.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationB.path))

        // itemB "se quito de la biblioteca" -- solo queda itemA en la
        // pasada siguiente. Sin remover nada, el huerfano se queda
        // (comportamiento de siempre, §0.1: nunca se borra sin
        // confirmacion).
        let withoutRemoval = try sync.sync(items: [itemA])
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationB.path), "un huerfano nunca se borra sin que el usuario lo elija")
        XCTAssertEqual(withoutRemoval.filesCopied, 0)

        // El usuario, desde la hoja de conflictos, elige borrar
        // puntualmente el huerfano de itemB.
        let manifest = sync.loadManifest()
        let orphanSourcePath = try XCTUnwrap(manifest.records.values.first { $0.destinationRelativePath == "Music/Beatles/Abbey Road/Song B.mp3" }?.sourcePath)

        _ = try sync.sync(items: [itemA], removeOrphanedSourcePaths: [orphanSourcePath])

        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationB.path), "el huerfano elegido si se borra del dispositivo")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationA.path), "lo que SI sigue en la biblioteca nunca se toca")
        let manifestAfter = sync.loadManifest()
        XCTAssertNil(manifestAfter.records[orphanSourcePath], "su registro tambien desaparece del manifiesto")
        XCTAssertNotNil(manifestAfter.records[itemA.sourceURL.path])
    }
}
