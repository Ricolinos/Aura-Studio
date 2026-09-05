import Combine
import XCTest
@testable import AuraStudio

/// PLAN-studio-rendimiento.md Fase 0: línea base de rendimiento contra
/// una biblioteca sintética del tamaño de referencia del dueño (~12 000
/// canciones). Nada del plan se da por resuelto sin medirlo -- estas
/// pruebas fijan los números ANTES de tocar nada (ST-152), y cada fase
/// siguiente se vuelve a correr contra ellas.
///
/// PLAN-studio-rendimiento.md Fase 1 (ST-153): `testRecomputeRows...`
/// medían un PROXY (`MediaSectionView.rows` era un computed var de una
/// `View`, no una función aislada). Ahora que `RowsModel` existe, miden
/// el camino real de punta a punta -- `RowsModel.recompute(...)`, con el
/// salto a `Task.detached` que toma con 12 000 ítems incluido.
///
/// Todo lo demás (selección, `persistCatalog`, `GridSelection`,
/// `loadCatalog`) también mide código de producción real, sin proxy:
/// `persistCatalog()` pasó a visibilidad `internal` (ver
/// `LibraryViewModel.swift`) y `GridSelection.
/// handleTap(_:orderedIDs:modifierFlags:)` es un overload nuevo, sin
/// cambiar el camino real (`handleTap(_:orderedIDs:)` sigue leyendo
/// `NSEvent.modifierFlags` en producción) -- ambos, solo para poder medir
/// sin depender de un entorno de UI real. La selección se mide contra
/// `SelectionStore` (Fase 1), no contra `LibraryViewModel.selectionForSync`
/// (que ya no existe).
@MainActor
final class LibraryPerformanceBaselineTests: XCTestCase {
    private var libraryRoot: URL!
    private var syntheticItems: [AuraStudio.LibraryItem]!

    /// 900 álbumes / 300 artistas / 12 000 canciones -- el caso de
    /// referencia del plan. 3 álbumes por artista (900/300); 13 pistas
    /// por álbum + 1 extra en los primeros 300 álbumes para llegar
    /// exacto a 12 000 (900*13 + 300 = 12 000).
    private static let totalItems = 12_000
    private static let albumCount = 900
    private static let artistCount = 300

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerfLibrary-\(UUID().uuidString)", isDirectory: true)
        syntheticItems = try Self.makeSyntheticItems(libraryRoot: libraryRoot)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    private func freshPreferences() -> AppPreferences {
        AppPreferences(defaults: UserDefaults(suiteName: "PerfBaselineTests-\(UUID().uuidString)")!)
    }

    /// Archivos "diminutos" a propósito (Fase 0 §2): lo que cuesta medir
    /// es el NÚMERO de syscalls de `stat()` (la clave de orden "Tamaño"),
    /// no el tamaño real declarado -- un archivo de unos pocos bytes
    /// ejercita exactamente el mismo costo por ítem que uno de música de
    /// verdad, sin escribir gigabytes de más ni depender de `ffmpeg`
    /// (spawnear el proceso 12 000 veces sería, de lejos, más lento que
    /// lo que se está tratando de medir).
    private static func makeSyntheticItems(libraryRoot: URL) throws -> [AuraStudio.LibraryItem] {
        let fm = FileManager.default
        let musicDir = libraryRoot.appendingPathComponent(PersistedLibrary.musicDirName, isDirectory: true)
        try fm.createDirectory(at: musicDir, withIntermediateDirectories: true)

        let tinyPayload = Data(repeating: 0xAA, count: 256)
        let baseTracksPerAlbum = totalItems / albumCount
        let albumsWithExtraTrack = totalItems % albumCount

        var items: [AuraStudio.LibraryItem] = []
        items.reserveCapacity(totalItems)

        for albumNumber in 0..<albumCount {
            let tracksThisAlbum = baseTracksPerAlbum + (albumNumber < albumsWithExtraTrack ? 1 : 0)
            let artistNumber = albumNumber % artistCount
            let artist = "Artista \(String(format: "%03d", artistNumber))"
            let albumName = "Álbum \(String(format: "%04d", albumNumber))"
            let albumDir = musicDir
                .appendingPathComponent(artist, isDirectory: true)
                .appendingPathComponent(albumName, isDirectory: true)
            try fm.createDirectory(at: albumDir, withIntermediateDirectories: true)

            // PLAN-studio-rendimiento.md Fase 3 punto 2: una carátula
            // "real" (tamaño plausible, ~15 KB) por álbum, compartida por
            // sus pistas -- como en una biblioteca de verdad -- para que
            // la prueba (c) pueda medir el efecto de saltarse las
            // carátulas sin cambios en vez de reescribir las 12 000 en
            // cada guardado.
            let albumCoverArt = Data(repeating: UInt8(albumNumber % 256), count: 15_000)

            for track in 1...tracksThisAlbum {
                let fileURL = albumDir.appendingPathComponent(String(format: "%02d Canción.mp3", track))
                try tinyPayload.write(to: fileURL)

                var item = AuraStudio.LibraryItem(sourceURL: fileURL, addedAt: Date())
                item.status = .ready
                item.preparedURL = fileURL
                item.metadata = TrackMetadata(
                    title: "Canción \(track) de \(albumName)",
                    artist: artist,
                    album: albumName,
                    albumArtist: artist,
                    year: "1986",
                    genre: "Rock",
                    trackNumber: track,
                    coverArtData: albumCoverArt,
                    durationSeconds: Double(180 + track)
                )
                items.append(item)
            }
        }
        return items
    }

    // MARK: - (a) Recomputar `rows` -- por título y por tamaño
    //
    // PLAN-studio-rendimiento.md Fase 1 (ST-153): ya no es un proxy --
    // `RowsModel` existe, así que esto mide el camino real de punta a
    // punta (con 12 000 ítems siempre toma la rama `Task.detached`, ver
    // `RowsModel.asyncThreshold`), incluido el costo del salto de hilo.

    func testRecomputeRowsSortedByTitle() throws {
        let sortOrder: [KeyPathComparator<MediaTableRow>] = [.init(\.title, order: .forward)]
        measure {
            let rowsModel = RowsModel()
            let done = expectation(description: "rows computed")
            let cancellable = rowsModel.$rows.dropFirst().sink { _ in done.fulfill() }
            rowsModel.recompute(items: syntheticItems, deviceSyncIndex: nil, sortOrder: sortOrder)
            wait(for: [done], timeout: 10)
            cancellable.cancel()
        }
    }

    func testRecomputeRowsSortedBySize() throws {
        let sortOrder: [KeyPathComparator<MediaTableRow>] = [.init(\.fileSizeBytes, order: .forward)]
        measure {
            let rowsModel = RowsModel()
            let done = expectation(description: "rows computed")
            let cancellable = rowsModel.$rows.dropFirst().sink { _ in done.fulfill() }
            rowsModel.recompute(items: syntheticItems, deviceSyncIndex: nil, sortOrder: sortOrder)
            wait(for: [done], timeout: 10)
            cancellable.cancel()
        }
    }

    // MARK: - (b) Cambiar la selección 100 veces

    /// PLAN-studio-rendimiento.md Fase 1 (ST-153): `selectionForSync`
    /// desapareció de `LibraryViewModel` -- la selección se publica ahora
    /// en `SelectionStore` (chico, sin relación con el catálogo de 12 000
    /// ítems). Se mide igual, sobre el reemplazo real.
    func testChangeSelectionOneHundredTimes() {
        let selectionStore = SelectionStore()
        let ids = syntheticItems.map(\.id)
        measure {
            for i in 0..<100 {
                let start = (i * 37) % (ids.count - 50)
                selectionStore.replace(with: Set(ids[start..<(start + 50)]))
            }
        }
    }

    // MARK: - (c) `persistCatalog()`

    func testPersistCatalog() {
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.replaceItemsForPerformanceTesting(syntheticItems)
        measure {
            viewModel.persistCatalog()
        }
    }

    // MARK: - statusSummary (ST-153 addendum, Fase 1 punto 3)
    //
    // Antes: `LibraryStats.music(items:selected:)` recalculaba TODO
    // (artistas/álbumes/duración/tamaño de los 12 000 ítems) en cada
    // acceso, sin importar que solo cambiara qué había seleccionado.
    // Después: el total sale de `StatusSummaryModel` (cacheado, ver
    // `MediaSectionView.statusSummary`) y esta prueba mide lo único que
    // sigue corriendo en cada cambio de selección -- el texto de
    // `LibraryStats.musicSelectionText`, proporcional a lo seleccionado.

    func testStatusSummaryFullRecomputeEveryAccess_beforeFix() {
        let selected = Array(syntheticItems.prefix(50))
        measure {
            _ = LibraryStats.music(items: syntheticItems, selected: selected, options: .default)
        }
    }

    func testStatusSummarySelectionOnly_afterFix() {
        let statusSummaryModel = StatusSummaryModel()
        statusSummaryModel.recompute(items: syntheticItems, kind: .music, options: .default,
                                     presetCategory: nil, photoCollections: [])
        let selected = Array(syntheticItems.prefix(50))
        measure {
            _ = LibraryStats.musicSelectionText(selected: selected, totalCount: syntheticItems.count, options: .default)
        }
    }

    // MARK: - (d) Shift+clic de 1 a 1 000 en `GridSelection`
    //
    // PLAN-studio-rendimiento.md Fase 2 punto 2: `GridOrder` (el
    // diccionario id→índice) se construye UNA VEZ, fuera del `measure`
    // -- así es como lo va a usar la vista real (una vez por cambio de
    // cuadrícula, nunca por clic). Lo que se mide son los 1000 clics.
    func testShiftClickExtendingSelectionOneToOneThousand() {
        let order = GridOrder(syntheticItems.map(\.id))
        measure {
            var selection = GridSelection<UUID>()
            selection.handleTap(order.ids[0], order: order, modifierFlags: [])
            for i in 1...1_000 {
                selection.handleTap(order.ids[i], order: order, modifierFlags: [.shift])
            }
        }
    }

    // MARK: - (e) `loadCatalog` en frío

    func testLoadCatalogCold() {
        let seed = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        seed.replaceItemsForPerformanceTesting(syntheticItems)
        seed.persistCatalog()
        measure {
            let loaded = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
            XCTAssertEqual(loaded.items.count, Self.totalItems)
        }
    }
}
