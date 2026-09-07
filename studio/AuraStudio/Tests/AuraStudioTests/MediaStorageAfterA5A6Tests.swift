import AVFoundation
import CryptoKit
import XCTest
@testable import AuraStudio

/// PLAN-studio-ajustes-3.md §2/§4 (A5 eliminar/limpiar huérfanos/
/// deduplicar, A6 migración de bibliotecas anteriores, ST-225/ST-226).
/// Encargo de "Sesión Maestra" mientras "experto en código opus" cierra
/// A3/A4: la forma exacta de las pruebas "después", mismo estilo que
/// `MediaStorageAfterA3A4Tests` (ST-223/ST-224) -- todas `throw
/// XCTSkip`, porque la API todavía no existe. Cuando cada API exista,
/// llenar el cuerpo sustituye el `XCTSkip` por las aserciones que ya
/// están descritas acá -- no hace falta rediseñar la prueba.
///
/// El fixture de A0 (`MediaFixture`) sigue sirviendo tal cual para
/// armar los ítems de estas pruebas en cuanto se llenen.
@MainActor
final class MediaStorageAfterA5A6Tests: XCTestCase {
    private var libraryRoot: URL!
    private var sourceDirs: [URL] = []

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("MediaStorageAfterA5A6-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
        for dir in sourceDirs { try? FileManager.default.removeItem(at: dir) }
        sourceDirs = []
    }

    // MARK: - (a) Eliminar en modo copia: Papelera + fuera del catálogo

    /// Forma de la prueba: con un ítem importado en modo copia (A3),
    /// eliminarlo con la API real de A5 y confirmar DOS cosas: 1) el
    /// archivo que estaba en `Música/<Artista>/<Álbum>/` ya NO existe
    /// ahí -- viajó a la Papelera del sistema (verificable por su
    /// ausencia en la ruta original; confirmar que aterrizó en la
    /// Papelera de verdad requiere `FileManager.trashItem` o
    /// equivalente, cuyo resultado hay que capturar en el momento real
    /// de borrar, no reconstruirlo después); 2) el ítem ya no aparece en
    /// `viewModel.items` ni en `biblioteca.json` tras persistir. La
    /// confirmación previa al usuario (el diálogo "¿Enviar a la
    /// Papelera?") es responsabilidad de la vista, no de esta prueba --
    /// acá se mide el resultado de la acción ya confirmada.
    func testDeletingInCopyModeSendsToTrashAndRemovesFromCatalog() async throws {
        let (viewModel, item) = try await importedItem(copy: true)
        let libraryFile = item.sourceURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: libraryFile.path))

        // Ningún borrado sin confirmar: pedirlo NO borra nada.
        viewModel.deleteItems(ids: [item.id])
        XCTAssertNotNil(viewModel.pendingDeletion, "tiene que pedir confirmación")
        XCTAssertTrue(FileManager.default.fileExists(atPath: libraryFile.path),
                      "pedir la eliminación no puede tocar el disco todavía")
        XCTAssertEqual(viewModel.items.count, 1)
        let pending = try XCTUnwrap(viewModel.pendingDeletion)
        XCTAssertGreaterThan(pending.filesToTrash, 0)
        XCTAssertTrue(pending.message.contains("Papelera"), "el diálogo lo dice: \(pending.message)")

        let outcome = viewModel.confirmPendingDeletion()

        XCTAssertTrue(viewModel.items.isEmpty, "el elemento sale del catálogo")
        XCTAssertFalse(FileManager.default.fileExists(atPath: libraryFile.path),
                       "el archivo ya no está donde estaba")
        XCTAssertEqual(outcome.failures, 0)
        // A la Papelera, no borrado: tiene que poder recuperarse. La ruta
        // de destino la devuelve el propio borrado -- es la única prueba
        // de que fue a la Papelera y no a `removeItem`.
        let trashed = try XCTUnwrap(outcome.trashed.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashed.path),
                      "el archivo tiene que estar en la Papelera, no borrado")
        XCTAssertTrue(trashed.path.contains(".Trash"), "y en la Papelera de verdad: \(trashed.path)")
        for url in outcome.trashed { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - (b) Eliminar en modo referencia: solo el catálogo, original intacto

    /// Forma de la prueba: mismo gesto que (a) pero en modo referencia
    /// (A4) -- el original (fuera de la biblioteca) tiene que sobrevivir
    /// byte a byte (hash antes/después idéntico), y lo único que
    /// desaparece es la entrada del catálogo (y, si existe, el
    /// preparado en `.preparados/<ID>.ext`). La diferencia central con
    /// (a): acá NUNCA hay Papelera de por medio -- Aura Studio no es
    /// dueño del original, no le toca borrarlo ni moverlo.
    func testDeletingInReferenceModeOnlyRemovesFromCatalogAndTheOriginalStaysByteIdentical() async throws {
        let (viewModel, item) = try await importedItem(copy: false)
        let originalHash = try sha256(item.sourceURL)

        viewModel.deleteItems(ids: [item.id])
        let pending = try XCTUnwrap(viewModel.pendingDeletion)
        XCTAssertEqual(pending.filesToTrash, 0, "en referencia no va nada a la Papelera")
        XCTAssertFalse(pending.message.contains("Papelera"),
                       "y el diálogo no puede prometerlo: \(pending.message)")
        viewModel.confirmPendingDeletion()

        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.sourceURL.path))
        XCTAssertEqual(try sha256(item.sourceURL), originalHash,
                       "el archivo del usuario queda byte a byte igual")
    }

    // MARK: - (c) "Limpiar huérfanos": solo lo no referenciado

    /// Forma de la prueba: armar `.preparados/` con dos archivos --
    /// `<ID-A>.ext` referenciado por un ítem real de la biblioteca (modo
    /// referencia), y `<ID-B>.ext` SIN ningún ítem que lo referencie
    /// (huérfano real, p. ej. dejado por una eliminación anterior o una
    /// corrida interrumpida). Correr "Limpiar huérfanos" con la API
    /// real y confirmar que `<ID-B>.ext` desaparece y `<ID-A>.ext`
    /// sobrevive intacto (mismo hash) -- el caso que de verdad importa
    /// es que lo REFERENCIADO nunca se toque, no solo que lo huérfano
    /// se borre.
    func testCleanOrphansDeletesOnlyWhatNoItemReferences() async throws {
        let (viewModel, item) = try await importedItem(copy: false)
        // Se fuerza un derivado real editando el título (ST-224).
        var edited = try XCTUnwrap(item.metadata)
        edited.title = "Título Editado"
        await viewModel.applyReview(id: item.id, metadata: edited)
        let inUse = try XCTUnwrap(viewModel.items.first?.preparedURL)
        let inUseHash = try sha256(inUse)

        // Un huérfano de verdad: nadie lo referencia.
        let staging = libraryRoot.appendingPathComponent(PersistedLibrary.preparedDirName, isDirectory: true)
        let orphan = staging.appendingPathComponent("\(UUID().uuidString).mp3")
        try Data(repeating: 7, count: 4096).write(to: orphan)

        viewModel.scanForOrphans()
        let scan = try XCTUnwrap(viewModel.orphanScan)
        XCTAssertEqual(scan.files.map(\.url.lastPathComponent), [orphan.lastPathComponent],
                       "solo el huérfano, nunca el que está en uso")
        XCTAssertEqual(scan.totalBytes, 4096, "el tamaño se dice antes de borrar")

        viewModel.deleteFoundOrphans()

        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: inUse.path),
                      "lo referenciado nunca se toca -- ese es el caso que de verdad importa")
        XCTAssertEqual(try sha256(inUse), inUseHash)
    }

    /// La limpieza no puede mirar las carpetas del usuario. Es una lista
    /// corta y explícita a propósito.
    func testOrphanScanNeverLooksAtTheUsersFolders() {
        XCTAssertEqual(OrphanScan.scannedDirectories,
                       [PersistedLibrary.preparedDirName, PersistedLibrary.coversDirName])
        XCTAssertFalse(OrphanScan.scannedDirectories.contains(PersistedLibrary.musicDirName))
        XCTAssertFalse(OrphanScan.scannedDirectories.contains(PersistedLibrary.imagesDirName))
        XCTAssertFalse(OrphanScan.scannedDirectories.contains(PersistedLibrary.videosDirName))
    }

    // MARK: - (d) Deduplicación al importar: misma ruta en NFC y NFD = un solo ítem

    /// Forma de la prueba: dos rutas que representan el MISMO archivo en
    /// disco -- una escrita en NFC (precompuesto, lo que produce
    /// Windows) y otra en NFD (descompuesto, lo que produce macOS/APFS
    /// al enumerar) -- importar ambas (p. ej. una gota con las dos rutas,
    /// o dos importaciones separadas del mismo archivo real) y confirmar
    /// que el catálogo termina con UN SOLO ítem, no dos. La comparación
    /// de deduplicación tiene que normalizar a NFC antes de comparar
    /// (mismo criterio que `SharedCatalogPath`, que ya distingue NFC/NFD
    /// para RESOLVER rutas -- acá es para DETECTAR que son la misma).
    /// ST-223 (A3) la adelantó: la deduplicación al importar entró con
    /// el modo copia, no en A5. Lo que A5 agrega es el aviso de
    /// PARECIDOS (mismo tamaño y duración en carpetas distintas), que es
    /// otra cosa y no borra nada.
    func testDeduplicationOnImportComparesPathsInNFC() throws {
        let externalDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DedupNFC-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: externalDir) }

        // El MISMO archivo, nombrado con acento: macOS lo deja
        // descompuesto en disco, y una ruta compuesta lo resuelve igual.
        let decomposedName = "Pro\u{0301}fugos.mp3"
        let composedName = decomposedName.precomposedStringWithCanonicalMapping
        XCTAssertNotEqual(Array(decomposedName.utf8), Array(composedName.utf8),
                          "el fixture tiene que diferir byte a byte, o la prueba no prueba nada")
        let fileURL = externalDir.appendingPathComponent(decomposedName)
        try MediaFixture.mp3Data(title: "Prófugos", artist: "Soda Stéreo", album: "Signos",
                                 albumArtist: "Soda Stéreo", year: "1986", genre: "Rock",
                                 trackNumber: 1).write(to: fileURL)

        let prefs = AppPreferences(defaults: makeIsolatedDefaults("MediaStorageAfterA5A6"))
        prefs.copyMediaIntoLibrary = false
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: prefs)

        viewModel.addDroppedFiles([externalDir.appendingPathComponent(decomposedName)])
        viewModel.addDroppedFiles([externalDir.appendingPathComponent(composedName)])

        XCTAssertEqual(viewModel.items.count, 1,
                       "las dos rutas nombran el mismo archivo: un solo elemento")
    }

    // MARK: - (e) Migración nunca silenciosa

    /// Forma de la prueba: armar una biblioteca "anterior" -- ítems SIN
    /// campo `storage` en `biblioteca.json` (el estado antes de A1) y
    /// archivos reales en `Música/<Artista>/<Álbum>/` cuyas etiquetas en
    /// disco NO coinciden con las del catálogo (el caso real que
    /// justifica la migración: el catálogo dice una cosa, el archivo
    /// dice otra). Cargar la biblioteca con `LibraryViewModel(
    /// libraryRoot:)` normal y confirmar que la CARGA no escribe NINGÚN
    /// archivo (ni etiquetas, ni .preparados/, ni biblioteca.json) --
    /// abrir la app nunca migra sola. Solo al invocar "Migrar
    /// biblioteca" (la acción explícita, con la API real de A6) las
    /// etiquetas de los archivos en Música/ se reescriben para coincidir
    /// con el catálogo, se genera lo que falte (p. ej. un `storage` por
    /// omisión), y la acción devuelve/reporta un conteo de archivos
    /// tocados -- nunca 0 cuando de verdad había discrepancias que
    /// corregir.
    func testOpeningAnOldLibraryWritesNothingAndOnlyMigratingDoes() async throws {
        let (catalogItemID, musicFile) = try seedLegacyLibrary()

        // 1. Abrir NO puede escribir nada. El catálogo queda fuera del
        //    resumen a propósito: persistir la inferencia de `storage` sí
        //    es contrato (ST-221), y es lo único que la carga escribe.
        let before = try treeSummary(excluding: [PersistedLibrary.catalogFileName])
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot,
                                         preferences: legacyPreferences())
        viewModel.makePersistenceSynchronousForTesting()
        let after = try treeSummary(excluding: [PersistedLibrary.catalogFileName])
        XCTAssertEqual(before, after, "abrir una biblioteca anterior no escribe ni un archivo")

        // 2. Y lo dice: la detección es solo del catálogo.
        let need = try XCTUnwrap(viewModel.migrationNeed)
        XCTAssertTrue(need.isNeeded)
        XCTAssertEqual(need.itemsWithoutStorage, 2, "ninguno de los dos traía `storage`")
        // Solo el REFERENCIADO cuenta: en modo copia el derivado es el
        // archivo mismo, así que su nombre no tiene por qué ser un id --
        // el `.preparados/` que le quedó es un huérfano, no un renombrado
        // pendiente, y se lo lleva el paso final.
        XCTAssertEqual(need.legacyPrepared, 1, "el preparado del referenciado tiene el nombre viejo")

        // 3. Migrar sí escribe, y dice cuánto tocó.
        viewModel.migrateLibrary()
        try await waitForMigration(viewModel)
        let summary = try XCTUnwrap(viewModel.lastMigrationSummary)
        XCTAssertFalse(summary.cancelled)
        XCTAssertGreaterThan(summary.touched, 0, "había cosas de verdad que corregir: \(summary.message)")
        XCTAssertEqual(summary.preparedRenamed, 1, "el preparado del referenciado se renombra por id")
        XCTAssertGreaterThan(summary.orphansDeleted, 0,
                             "y el que quedó del copiado se limpia al final, no antes")

        // El archivo de Música/ ahora dice lo que dice el catálogo.
        let item = try XCTUnwrap(viewModel.items.first { $0.id == catalogItemID })
        XCTAssertEqual(item.storage, .copy)
        let asset = AVURLAsset(url: musicFile)
        var title: String?
        for entry in try await asset.load(.metadata) where entry.commonKey == .commonKeyTitle {
            title = try? await entry.load(.stringValue)
        }
        XCTAssertEqual(title, "Título del Catálogo",
                       "la migración escribe las etiquetas del catálogo en la copia")

        // 4. Y las señales se apagan solas: no hay campo "migrada".
        XCTAssertNil(viewModel.migrationNeed)
    }

    /// Correrla dos veces no toca nada la segunda vez, y deja el árbol
    /// idéntico. Una migración que se puede repetir sin consecuencia es
    /// la que se puede reintentar tras un fallo.
    func testMigratingTwiceTouchesNothingTheSecondTime() async throws {
        _ = try seedLegacyLibrary()
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: legacyPreferences())
        viewModel.makePersistenceSynchronousForTesting()

        viewModel.migrateLibrary()
        try await waitForMigration(viewModel)
        XCTAssertGreaterThan(try XCTUnwrap(viewModel.lastMigrationSummary).touched, 0)
        viewModel.dismissMigrationSummary()
        let afterFirst = try treeSummary(excluding: [PersistedLibrary.catalogFileName])

        viewModel.migrateLibrary()
        try await waitForMigration(viewModel)
        let second = try XCTUnwrap(viewModel.lastMigrationSummary)

        XCTAssertEqual(second.touched, 0, "la segunda corrida no tiene nada que hacer: \(second.message)")
        XCTAssertEqual(try treeSummary(excluding: [PersistedLibrary.catalogFileName]), afterFirst,
                       "y el árbol queda idéntico")
    }

    // MARK: - Andamio de migración

    private func legacyPreferences() -> AppPreferences {
        let prefs = AppPreferences(defaults: makeIsolatedDefaults("MediaStorageAfterA5A6"))
        prefs.copyMediaIntoLibrary = true
        prefs.enrichOnline = false
        prefs.fetchSyncedLyrics = false
        return prefs
    }

    private func waitForMigration(_ viewModel: LibraryViewModel) async throws {
        for _ in 0..<600 {
            if viewModel.lastMigrationSummary != nil && !viewModel.isMigrating { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("la migración no terminó")
    }

    /// Resumen del árbol: ruta relativa, tamaño y contenido de cada
    /// archivo. Es lo que permite afirmar "no se escribió NADA" en vez de
    /// "no se escribió lo que se me ocurrió mirar".
    private func treeSummary(excluding: Set<String> = []) throws -> [String] {
        guard let walker = FileManager.default.enumerator(at: libraryRoot,
                                                          includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        var summary: [String] = []
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            guard !excluding.contains(url.lastPathComponent) else { continue }
            let data = try Data(contentsOf: url)
            let relative = url.path.replacingOccurrences(of: libraryRoot.path + "/", with: "")
            summary.append("\(relative)|\(data.count)|\(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())")
        }
        return summary.sorted()
    }

    /// Una biblioteca "anterior": el catálogo NO trae `storage`, el
    /// preparado tiene el nombre viejo (por nombre base, no por id) y las
    /// etiquetas del archivo **no** coinciden con el catálogo -- que es
    /// el caso real que motiva toda la migración.
    ///
    /// Lleva **dos** elementos a propósito. Uno copiado bajo `Música/`
    /// con etiquetas desfasadas -- ese es el caso que motiva la
    /// migración, y su derivado viejo queda huérfano porque en modo copia
    /// el archivo ES el derivado. Y uno **referenciado** con el derivado
    /// nombrado a la vieja: es el único que ejercita el renombrado a
    /// `.preparados/<ID>`, y sin él la prueba habría dado por buena una
    /// migración que nunca renombra nada.
    private func seedLegacyLibrary() throws -> (itemID: UUID, musicFile: URL) {
        let itemID = UUID()
        let referencedID = UUID()
        let musicDir = libraryRoot.appendingPathComponent("Música/Artista/Álbum", isDirectory: true)
        try FileManager.default.createDirectory(at: musicDir, withIntermediateDirectories: true)
        let musicFile = musicDir.appendingPathComponent("pista.mp3")
        try MediaFixture.mp3Data(title: "Título Viejo del Archivo", artist: "Artista",
                                 album: "Álbum", albumArtist: "Artista", year: "2020",
                                 genre: "Rock", trackNumber: 1).write(to: musicFile)

        let staging = libraryRoot.appendingPathComponent(PersistedLibrary.preparedDirName, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let legacyPrepared = staging.appendingPathComponent("pista.mp3")
        try Data("preparado viejo".utf8).write(to: legacyPrepared)

        // El referenciado: su original vive FUERA de la biblioteca.
        let outsideDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("A6-fuera-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        sourceDirs.append(outsideDir)
        let referencedSource = outsideDir.appendingPathComponent("referenciada.mp3")
        try MediaFixture.mp3Data(title: "Referenciada", artist: "Artista", album: "Álbum",
                                 albumArtist: "Artista", year: "2020", genre: "Rock",
                                 trackNumber: 2).write(to: referencedSource)
        let legacyReferencedPrepared = staging.appendingPathComponent("referenciada.mp3")
        try MediaFixture.mp3Data(title: "Referenciada", artist: "Artista", album: "Álbum",
                                 albumArtist: "Artista", year: "2020", genre: "Rock",
                                 trackNumber: 2).write(to: legacyReferencedPrepared)

        let json = """
        {
          "items": [
            {
              "id": "\(itemID.uuidString)",
              "sourceRelativePath": "Música/Artista/Álbum/pista.mp3",
              "kind": "music",
              "status": "ready",
              "metadata": { "title": "Título del Catálogo", "artist": "Artista", "album": "Álbum", "trackNumber": 1 },
              "preparedRelativePath": ".preparados/pista.mp3",
              "metadataEditedByUser": true
            },
            {
              "id": "\(referencedID.uuidString)",
              "sourceRelativePath": "\(referencedSource.path)",
              "kind": "music",
              "status": "ready",
              "metadata": { "title": "Referenciada", "artist": "Artista", "album": "Álbum", "trackNumber": 2 },
              "preparedRelativePath": ".preparados/referenciada.mp3",
              "metadataEditedByUser": true
            }
          ],
          "playlists": []
        }
        """
        try Data(json.utf8).write(to: libraryRoot.appendingPathComponent(PersistedLibrary.catalogFileName))
        return (itemID, musicFile)
    }

    // MARK: - Andamio (ST-225)

    private func sha256(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    private func importedItem(copy: Bool) async throws
        -> (viewModel: LibraryViewModel, item: AuraStudio.LibraryItem) {
        let externalDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("A5-origen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)
        sourceDirs.append(externalDir)
        let sourceURL = externalDir.appendingPathComponent("pista.mp3")
        try MediaFixture.mp3Data(title: "Pista", artist: "Artista", album: "Álbum",
                                 albumArtist: "Artista", year: "2020", genre: "Rock",
                                 trackNumber: 1).write(to: sourceURL)

        let prefs = AppPreferences(defaults: makeIsolatedDefaults("MediaStorageAfterA5A6"))
        prefs.copyMediaIntoLibrary = copy
        prefs.enrichOnline = false
        prefs.fetchSyncedLyrics = false
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: prefs)
        viewModel.makePersistenceSynchronousForTesting()
        viewModel.addDroppedFiles([sourceURL])
        await viewModel.processAll()
        return (viewModel, try XCTUnwrap(viewModel.items.first))
    }
}
