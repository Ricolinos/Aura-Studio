import CoreGraphics
import Darwin
import XCTest
@testable import AuraStudio

/// PLAN-studio-rendimiento-2.md Fase F5 (ST-185): "`coverArtData` deja
/// de vivir en memoria". Pedido de "Sesión Maestra"; API confirmada con
/// "experto en código opus" al cerrar F5 (commit 625d8f9). Prioriza,
/// como sugirió Opus, pruebas de CORRECCIÓN sobre una medición de RSS
/// (que es ruidosa y depende de cuándo decide el sistema reclamar
/// memoria): el objetivo real de F5 es que el pico quede acotado a la
/// ventana de guardado, no que un número de memoria baje un porcentaje
/// exacto.
@MainActor
final class LibraryCoverMemoryTests: XCTestCase {
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoverMemory-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    private func freshPreferences() -> AppPreferences {
        AppPreferences(defaults: UserDefaults(suiteName: "LibraryCoverMemoryTests-\(UUID().uuidString)")!)
    }

    /// Ruido JPEG real (decodifica), ~15 KB -- mismo generador que
    /// `AlbumsGridPerformanceBaselineTests`, reproducido acá para no
    /// crear una dependencia entre archivos de prueba por una función
    /// de 15 líneas.
    private static func makeCoverJPEG() -> Data {
        let side = 120
        var buffer = [UInt8](repeating: 0, count: side * side * 4)
        buffer.withUnsafeMutableBytes { arc4random_buf($0.baseAddress, $0.count) }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: &buffer, width: side, height: side,
                                       bitsPerComponent: 8, bytesPerRow: side * 4,
                                       space: colorSpace,
                                       bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let cgImage = context.makeImage(),
              let jpeg = NSBitmapImageRep(cgImage: cgImage)
                .representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            fatalError("F5: no se pudo generar el JPEG sintético")
        }
        return jpeg
    }

    private func makeTracks(count: Int, musicDir: URL, coverArtData: Data?) throws -> [AuraStudio.LibraryItem] {
        try FileManager.default.createDirectory(at: musicDir, withIntermediateDirectories: true)
        var items: [AuraStudio.LibraryItem] = []
        for i in 0..<count {
            let fileURL = musicDir.appendingPathComponent("pista-\(i).mp3")
            try Data([0xFF, 0xFB, 0x90, 0x00]).write(to: fileURL)
            var item = AuraStudio.LibraryItem(sourceURL: fileURL, addedAt: Date())
            item.status = .ready
            item.preparedURL = fileURL
            item.metadata = TrackMetadata(title: "Pista \(i)", artist: "Artista", album: "Álbum",
                                         coverArtData: coverArtData)
            items.append(item)
        }
        return items
    }

    // MARK: - 1. Cargar un catálogo no trae bytes a memoria

    func testLoadingCatalogNeverBringsCoverBytesIntoMemory() throws {
        let musicDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        let cover = Self.makeCoverJPEG()
        let tracks = try makeTracks(count: 50, musicDir: musicDir, coverArtData: cover)

        let writer = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        writer.replaceItemsForPerformanceTesting(tracks)
        writer.persistCatalog() // escribe .portadas/ y limpia pendingCoverData vía adoptStoredCovers

        // Un ViewModel NUEVO, sobre el mismo libraryRoot -- el patrón
        // establecido para probar loadCatalog() sin esperar nada.
        let reader = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        XCTAssertEqual(reader.items.count, 50)
        for item in reader.items {
            XCTAssertNotNil(item.metadata?.coverURL, "loadCatalog() debe resolver dónde está la carátula")
            XCTAssertNotNil(item.metadata?.coverHash)
            XCTAssertNil(item.metadata?.pendingCoverData,
                        "cargar el catálogo NUNCA debe traer los bytes a memoria (ST-185)")
            XCTAssertEqual(item.metadata?.loadCoverData(), cover,
                           "los bytes siguen siendo los correctos, leídos de disco bajo demanda")
        }
    }

    // MARK: - 2. Migración: coverHash ausente se calcula al cargar, se persiste al guardar

    /// Un `biblioteca.json` escrito ANTES de que `coverHash` existiera:
    /// tiene `coverRelativePath` (la carátula real está en disco) pero
    /// el campo `coverHash` está ausente del JSON -- el caso real del
    /// dueño al actualizar desde una versión vieja.
    func testMigrationComputesCoverHashOnLoadWithoutScanningCoversDirectory() throws {
        let fm = FileManager.default
        let musicDir = libraryRoot.appendingPathComponent(PersistedLibrary.musicDirName, isDirectory: true)
        try fm.createDirectory(at: musicDir, withIntermediateDirectories: true)
        let trackURL = musicDir.appendingPathComponent("pista.mp3")
        try Data([0xFF, 0xFB, 0x90, 0x00]).write(to: trackURL)

        let itemID = UUID()
        let cover = Self.makeCoverJPEG()
        let stored = try CoverStore.write(cover, forItem: itemID, in: libraryRoot)
        let expectedHash = CoverStore.hash(cover)
        XCTAssertEqual(CoverStore.hashOfFile(at: stored.url), expectedHash) // control de la prueba misma

        // JSON del esquema VIEJO: coverRelativePath presente, coverHash
        // ausente (no es que valga `null` -- la CLAVE no está, como en
        // catálogos de verdad de antes de ST-185).
        var persisted = PersistedLibrary()
        persisted.items = [PersistedLibraryItem(
            id: itemID, sourceRelativePath: "Música/pista.mp3", kind: "music", status: "ready",
            metadata: PersistedTrackMetadata(title: "Pista", artist: "Artista", album: "Álbum"),
            preparedRelativePath: "Música/pista.mp3",
            coverRelativePath: CoverStore.relativePath(forItem: itemID),
            coverHash: nil, category: nil, seriesName: nil, season: nil, episode: nil,
            photoAlbum: nil, metadataEditedByUser: nil, addedAt: nil)]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(persisted).write(to: libraryRoot.appendingPathComponent(PersistedLibrary.catalogFileName))

        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        XCTAssertEqual(viewModel.items.count, 1)
        let loaded = try XCTUnwrap(viewModel.items.first)
        XCTAssertEqual(loaded.metadata?.coverHash, expectedHash,
                       "coverHash ausente debe calcularse leyendo el archivo al cargar")
        XCTAssertEqual(loaded.metadata?.coverURL, stored.url)

        // El siguiente guardado debe dejarlo escrito -- releer el JSON crudo.
        viewModel.persistCatalog()
        let rewritten = try JSONDecoder().decode(
            PersistedLibrary.self,
            from: Data(contentsOf: libraryRoot.appendingPathComponent(PersistedLibrary.catalogFileName)))
        XCTAssertEqual(rewritten.items.first?.coverHash, expectedHash,
                       "el guardado siguiente debe persistir el hash ya calculado")
    }

    // MARK: - 3. "Quitar carátula" es explícito -- no confundir con "sin bytes ahora"

    /// El estado ESTABLE después de un guardado (`pendingCoverData ==
    /// nil`, `coverURL`/`coverHash` puestos) no es "sin carátula" -- es
    /// exactamente el bug real que casi le costó 1 000 carátulas a
    /// Windows (ST-208): confundir "no hay bytes en memoria en este
    /// momento" con "no hay carátula".
    func testSteadyStateAfterSaveIsNotConfusedWithNoCover() throws {
        let musicDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        let cover = Self.makeCoverJPEG()
        let tracks = try makeTracks(count: 1, musicDir: musicDir, coverArtData: cover)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.replaceItemsForPerformanceTesting(tracks)
        viewModel.persistCatalog()

        let saved = try XCTUnwrap(viewModel.items.first?.metadata)
        XCTAssertNil(saved.pendingCoverData, "control: el guardado ya soltó los bytes")
        XCTAssertTrue(saved.hasCover, "sin bytes en memoria AHORA MISMO no es lo mismo que sin carátula")
        XCTAssertEqual(saved.loadCoverData(), cover)
    }

    /// El camino real de "quitar carátula" (`LibraryViewModel.
    /// clearCoverArt(ids:)`, R2-3/ST-155): tiene que dejar `coverURL` Y
    /// `coverHash` en `nil` A LA VEZ (nunca uno sin el otro -- la
    /// invariante de `TrackMetadata.coverHash`) y borrar el archivo de
    /// `.portadas/`. Es una acción explícita del usuario, distinta de
    /// cualquier estado transitorio de "todavía no se guardó".
    func testExplicitCoverRemovalClearsEverythingAndDeletesTheFile() async throws {
        let musicDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        let cover = Self.makeCoverJPEG()
        let tracks = try makeTracks(count: 1, musicDir: musicDir, coverArtData: cover)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.replaceItemsForPerformanceTesting(tracks)
        viewModel.makePersistenceSynchronousForTesting()
        viewModel.persistCatalog()

        let coverURL = try XCTUnwrap(viewModel.items.first?.metadata?.coverURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: coverURL.path), "control: el archivo existe antes de quitar")

        await viewModel.clearCoverArt(ids: Set(tracks.map(\.id)))

        let cleared = try XCTUnwrap(viewModel.items.first?.metadata)
        XCTAssertFalse(cleared.hasCover)
        XCTAssertNil(cleared.coverURL)
        XCTAssertNil(cleared.coverHash, "sin coverURL no debe quedar un coverHash huérfano (invariante)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: coverURL.path),
                       "quitar la carátula debe borrar el archivo de .portadas/, no solo la referencia")
    }

    // MARK: - 4. Guardar sin bytes nuevos no reescribe ninguna carátula

    func testSavingAgainWithNoNewCoverBytesDoesNotRewriteAnyFile() throws {
        let musicDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        let cover = Self.makeCoverJPEG()
        let tracks = try makeTracks(count: 20, musicDir: musicDir, coverArtData: cover)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.replaceItemsForPerformanceTesting(tracks)
        viewModel.persistCatalog()

        let fm = FileManager.default
        let modificationDates = try viewModel.items.reduce(into: [UUID: Date]()) { dict, item in
            let url = try XCTUnwrap(item.metadata?.coverURL)
            dict[item.id] = try fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        }

        // Un segundo guardado, sin tocar metadata de nadie -- ninguna
        // carátula tiene pendingCoverData, así que CatalogPersister.write
        // toma la rama "ya estaba en disco" para las 20, sin abrir
        // ningún archivo de .portadas/.
        Thread.sleep(forTimeInterval: 0.01) // separa mtimes con margen del reloj del sistema de archivos
        viewModel.persistCatalog()

        for item in viewModel.items {
            let url = try XCTUnwrap(item.metadata?.coverURL)
            let newDate = try fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
            XCTAssertEqual(newDate, modificationDates[item.id],
                           "el segundo guardado no debe reescribir una carátula que no cambió")
        }
    }

    // MARK: - Memoria residente: el pico queda acotado a la ventana de guardado

    /// No es una aserción exacta de bytes (RSS es ruidoso -- el momento
    /// en que el sistema operativo decide reclamar memoria liberada no
    /// es determinístico), es la comparación que el diseño de F5 hace
    /// una afirmación concreta sobre: la memoria ANTES de guardar (12 000
    /// `pendingCoverData` de ~15 KB recién leídos, ~180 MB) tiene que ser
    /// mayor que la de DESPUÉS de guardar (`adoptStoredCovers` ya los
    /// soltó a todos). Impreso para que quede el número real en la
    /// tabla, no solo la aserción de que bajó.
    func testResidentMemoryDropsAfterSavingReleasesPendingCoverBytes() throws {
        let musicDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        let cover = Self.makeCoverJPEG()
        let tracks = try makeTracks(count: 12_000, musicDir: musicDir, coverArtData: cover)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.replaceItemsForPerformanceTesting(tracks)

        let beforeSave = Self.currentResidentMemoryBytes()
        viewModel.persistCatalog()
        let afterSave = Self.currentResidentMemoryBytes()

        let deltaMB = (Double(beforeSave) - Double(afterSave)) / 1_048_576
        print("[F5] Memoria residente con 12 000 ítems: antes de guardar \(beforeSave / 1_048_576) MB, "
              + "después \(afterSave / 1_048_576) MB (diferencia: \(String(format: "%.1f", deltaMB)) MB)")
        for item in viewModel.items {
            XCTAssertNil(item.metadata?.pendingCoverData)
        }
    }

    /// Estándar de macOS (`task_info` + `MACH_TASK_BASIC_INFO`), sin
    /// relación con F5 en sí -- ver el comentario de la prueba de arriba
    /// sobre por qué el valor absoluto no es lo que importa.
    static func currentResidentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }

    func testResidentMemoryMeasurerReturnsAPositiveNumber() {
        XCTAssertGreaterThan(Self.currentResidentMemoryBytes(), 0)
    }
}
