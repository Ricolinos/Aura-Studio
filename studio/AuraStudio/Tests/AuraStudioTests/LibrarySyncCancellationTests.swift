import XCTest
@testable import AuraStudio

/// PLAN-general-sync.md §8: la copia transaccional (`.aura-tmp` +
/// rename atomico) y la cancelacion en frontera segura -- estos tests
/// son la razon de ser del rediseño: verifican que cancelar (o que el
/// dispositivo se desconecte) nunca deja un archivo final a medio
/// escribir, y que lo ya copiado sobrevive. `LibrarySync.sync()` es
/// sincrono, asi que `isCancelled` se controla con precision total
/// (sin carreras de Task/hilos) contando cuantas veces se llamo.
final class LibrarySyncCancellationTests: XCTestCase {
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

    private func musicItem(title: String, artist: String = "Queen", album: String = "A Night at the Opera",
                            contents: Data = Data("fake mp3 bytes".utf8)) throws -> AuraStudio.LibraryItem {
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("staged-\(UUID().uuidString).mp3")
        try contents.write(to: staging)
        stagingFiles.append(staging)
        var item = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/source-\(UUID().uuidString).mp3"))
        item.metadata = TrackMetadata(title: title, artist: artist, album: album)
        item.preparedURL = staging
        item.status = .ready
        return item
    }

    private func hasAnyTempFile(under root: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return false }
        for case let url as URL in enumerator where url.pathExtension == LibrarySync.temporaryFileExtension {
            return true
        }
        return false
    }

    // MARK: - Cancelacion entre archivos

    func testCancellationBetweenFilesCopiesTheFirstAndLeavesNoPartials() throws {
        let itemA = try musicItem(title: "Song A")
        let itemB = try musicItem(title: "Song B")
        let itemC = try musicItem(title: "Song C")
        let sync = LibrarySync(volumeRoot: fakeIPod)

        final class Box { var cancel = false }
        let box = Box()

        let result = try sync.sync(items: [itemA, itemB, itemC], isCancelled: { box.cancel }) { copied, _ in
            if copied == 1 { box.cancel = true }
        }

        XCTAssertTrue(result.wasCancelled)
        XCTAssertEqual(result.filesCopied, 1)
        XCTAssertEqual(result.filesRemaining, 2)
        XCTAssertFalse(hasAnyTempFile(under: fakeIPod), "no debe quedar ningun .aura-tmp")
        XCTAssertFalse(sync.hasInProgressMarker(), "cancelar en frontera de archivo SI corre finalize -- el marcador se borra")

        let manifest = sync.loadManifest()
        XCTAssertEqual(manifest.records.count, 1, "solo el primer archivo quedo registrado")

        let songBDestination = fakeIPod.appendingPathComponent("Music/Queen/A Night at the Opera/Song B.mp3")
        XCTAssertFalse(FileManager.default.fileExists(atPath: songBDestination.path), "el segundo archivo nunca deberia haberse tocado")
    }

    // MARK: - Cancelacion a mitad de archivo (dentro de un bloque)

    func testCancellationMidFileLeavesNoDestinationAndNoTempFile() throws {
        // Mas grande que copyBlockSize (4 MB) para forzar mas de un
        // bloque -- la cancelacion ocurre DESPUES del primer bloque,
        // ANTES del segundo, es decir a mitad de la copia de este
        // archivo puntual.
        let bigContents = Data(repeating: 0xAB, count: LibrarySync.copyBlockSize + 1024)
        let item = try musicItem(title: "Big Song", contents: bigContents)
        let sync = LibrarySync(volumeRoot: fakeIPod)

        final class Counter { var calls = 0 }
        let counter = Counter()
        // Llamada 1: frontera de archivo (antes de empezar) -- debe
        // dejar pasar. Llamada 2: antes del primer bloque -- debe dejar
        // pasar. Llamada 3: antes del segundo bloque -- cancela.
        let isCancelled: () -> Bool = {
            counter.calls += 1
            return counter.calls > 2
        }

        let result = try sync.sync(items: [item], isCancelled: isCancelled)

        XCTAssertTrue(result.wasCancelled)
        XCTAssertEqual(result.filesCopied, 0)
        XCTAssertGreaterThan(counter.calls, 2, "hace falta mas de un bloque para que este test pruebe lo que dice probar")

        let destination = fakeIPod.appendingPathComponent("Music/Queen/A Night at the Opera/Big Song.mp3")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path), "nunca debe existir un archivo final truncado")
        XCTAssertFalse(hasAnyTempFile(under: fakeIPod), "el temporal a medio escribir se borra al cancelar")

        let manifest = sync.loadManifest()
        XCTAssertTrue(manifest.records.isEmpty)
    }

    // MARK: - Desconexion / fallo real a mitad de sync

    // PLAN-sync-media-hardening.md PARTE 1A: visto en produccion, un
    // solo archivo con nombre invalido para FAT32/msdosfs abortaba
    // sync() entero (`throw` sin capturar en el loop) -- lo copiado
    // ANTES del archivo problematico ya estaba en el disco, pero
    // `finalize` (portadas, resumen, marcador del firmware) nunca
    // corria, asi que Studio seguia mostrando "Todavia no
    // sincronizaste" y el firmware "Aun no te has sincronizado". Este
    // test documentaba ese comportamiento como el esperado; ahora
    // documenta el arreglo: la falla de UN archivo se registra en
    // `result.failures` y el resto del plan (y el cierre del batch)
    // sigue de largo.
    func testUnexpectedFailureMidSyncIsRecordedAsFailureAndRestOfSyncContinues() throws {
        let itemA = try musicItem(title: "Song A", artist: "Queen", album: "A Night at the Opera")
        // Bloqueo deliberado: un archivo REGULAR (no carpeta) en la
        // ruta donde el segundo item necesitaria crear un directorio --
        // `createDirectory` falla con un error real, exactamente el
        // tipo de fallo de I/O que produce un archivo corrupto o un
        // nombre invalido (mismo camino de codigo que una desconexion
        // fisica a mitad de copia: una excepcion real, no una
        // cancelacion deliberada).
        let itemB = try musicItem(title: "Song B", artist: "Beatles", album: "Abbey Road")
        let blockingPath = fakeIPod.appendingPathComponent("Music/Beatles")
        try FileManager.default.createDirectory(at: fakeIPod.appendingPathComponent("Music"), withIntermediateDirectories: true)
        try Data().write(to: blockingPath)

        let sync = LibrarySync(volumeRoot: fakeIPod)

        let result = try sync.sync(items: [itemA, itemB])

        XCTAssertEqual(result.filesCopied, 1, "Song A se copio bien pese a que Song B fallo")
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.failures.first?.sourcePath, itemB.sourceURL.path)
        XCTAssertFalse(result.wasCancelled, "una falla real de un solo archivo no es una cancelacion")
        XCTAssertFalse(sync.hasInProgressMarker(), "el sync SI llego a finalize -- el resto del plan se proceso pese a la falla de Song B")

        let songADestination = fakeIPod.appendingPathComponent("Music/Queen/A Night at the Opera/Song A.mp3")
        XCTAssertTrue(FileManager.default.fileExists(atPath: songADestination.path), "lo copiado ANTES de la falla sobrevive")
        let manifest = sync.loadManifest()
        XCTAssertEqual(manifest.records.count, 1, "el manifiesto se guarda por archivo -- el primero quedo registrado aunque el segundo haya fallado")
        XCTAssertFalse(hasAnyTempFile(under: fakeIPod), "el intento fallido de crear el directorio nunca llego a abrir un temporal")

        // "Reconectar": el obstaculo desaparece y se vuelve a
        // sincronizar -- Song B nunca quedo en el manifiesto, asi que
        // este segundo intento lo recoge sin recopiar Song A.
        try FileManager.default.removeItem(at: blockingPath)
        let retryResult = try sync.sync(items: [itemA, itemB])

        XCTAssertEqual(retryResult.filesCopied, 1, "Song A ya estaba sincronizada, solo Song B hacia falta")
        XCTAssertTrue(retryResult.failures.isEmpty)
        XCTAssertFalse(retryResult.wasCancelled)
        XCTAssertFalse(sync.hasInProgressMarker())
        let songBDestination = fakeIPod.appendingPathComponent("Music/Beatles/Abbey Road/Song B.mp3")
        XCTAssertTrue(FileManager.default.fileExists(atPath: songBDestination.path))
    }

    // MARK: - Barrido de temporales huerfanos

    func testOrphanedTempFileFromAPreviousInterruptedSyncIsSweptBeforeStarting() throws {
        let item = try musicItem(title: "Song A")
        let albumDir = fakeIPod.appendingPathComponent("Music/Queen/A Night at the Opera", isDirectory: true)
        try FileManager.default.createDirectory(at: albumDir, withIntermediateDirectories: true)
        let orphan = albumDir.appendingPathComponent("Leftover.mp3.\(LibrarySync.temporaryFileExtension)")
        try Data("basura de un sync interrumpido".utf8).write(to: orphan)

        let sync = LibrarySync(volumeRoot: fakeIPod)
        _ = try sync.sync(items: [item])

        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path), "el temporal huerfano se borra al empezar el siguiente sync")
    }

    // MARK: - Sincronizar solo una seleccion (restrictCopyToSourcePaths)

    func testRestrictingCopyToASubsetLeavesOthersPendingWithoutLosingThem() throws {
        let itemA = try musicItem(title: "Song A")
        let itemB = try musicItem(title: "Song B")
        let sync = LibrarySync(volumeRoot: fakeIPod)

        let result = try sync.sync(items: [itemA, itemB], restrictCopyToSourcePaths: [itemA.sourceURL.path])

        XCTAssertEqual(result.filesCopied, 1)
        XCTAssertFalse(result.wasCancelled, "no es una cancelacion, es una restriccion deliberada de alcance")
        let songBDestination = fakeIPod.appendingPathComponent("Music/Queen/A Night at the Opera/Song B.mp3")
        XCTAssertFalse(FileManager.default.fileExists(atPath: songBDestination.path))

        // Un sync SIN restriccion despues si copia lo que quedo afuera.
        let followUp = try sync.sync(items: [itemA, itemB])
        XCTAssertEqual(followUp.filesCopied, 1, "Song A ya estaba, solo faltaba Song B")
        XCTAssertTrue(FileManager.default.fileExists(atPath: songBDestination.path))
    }
}
