import XCTest
@testable import AuraStudio

/// PLAN-studio-rendimiento.md Fase 0: línea base de rendimiento contra
/// una biblioteca sintética del tamaño de referencia del dueño (~12 000
/// canciones). Nada del plan se da por resuelto sin medirlo -- estas
/// pruebas fijan los números ANTES de tocar nada (ST-152), y cada fase
/// siguiente se vuelve a correr contra ellas.
///
/// Dos mediciones (`testRecomputeRows...`) son un PROXY: `MediaSectionView.
/// rows`/`items` (Views/MediaSectionView.swift) es un computed var de una
/// `View` de SwiftUI, no una función aislada -- exactamente el problema
/// #2 del diagnóstico (Fase 0 §0). Estas pruebas reproducen la MISMA
/// operación (`items.map { MediaTableRow(item:) }.sorted(using:)`, caso
/// "sin filtros activos": scope .all, sin categoría/búsqueda/favoritos)
/// para medir el costo real hoy. Cuando la Fase 1 extraiga `RowsModel`,
/// esta prueba se reengancha a la extracción real en vez de reproducir
/// la expresión.
///
/// El resto (selección, `persistCatalog`, `GridSelection`, `loadCatalog`)
/// mide código de producción real, sin proxy: `persistCatalog()` pasó a
/// visibilidad `internal` (ver `LibraryViewModel.swift`) y `GridSelection.
/// handleTap(_:orderedIDs:modifierFlags:)` es un overload nuevo, sin
/// cambiar el camino real (`handleTap(_:orderedIDs:)` sigue leyendo
/// `NSEvent.modifierFlags` en producción) -- ambos, solo para poder medir
/// sin depender de un entorno de UI real.
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
                    durationSeconds: Double(180 + track)
                )
                items.append(item)
            }
        }
        return items
    }

    // MARK: - (a) Recomputar `rows` -- por título y por tamaño (PROXY, ver arriba)

    func testRecomputeRowsSortedByTitle() {
        let sortOrder: [KeyPathComparator<MediaTableRow>] = [.init(\.title, order: .forward)]
        measure {
            _ = syntheticItems
                .map { MediaTableRow(item: $0, syncState: nil) }
                .sorted(using: sortOrder)
        }
    }

    func testRecomputeRowsSortedBySize() {
        let sortOrder: [KeyPathComparator<MediaTableRow>] = [.init(\.fileSizeBytes, order: .forward)]
        measure {
            _ = syntheticItems
                .map { MediaTableRow(item: $0, syncState: nil) }
                .sorted(using: sortOrder)
        }
    }

    // MARK: - (b) Cambiar la selección 100 veces

    func testChangeSelectionOneHundredTimes() {
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.replaceItemsForPerformanceTesting(syntheticItems)
        let ids = syntheticItems.map(\.id)
        measure {
            for i in 0..<100 {
                let start = (i * 37) % (ids.count - 50)
                viewModel.selectionForSync = Set(ids[start..<(start + 50)])
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

    // MARK: - (d) Shift+clic de 1 a 1 000 en `GridSelection`

    func testShiftClickExtendingSelectionOneToOneThousand() {
        let orderedIDs = syntheticItems.map(\.id)
        measure {
            var selection = GridSelection<UUID>()
            selection.handleTap(orderedIDs[0], orderedIDs: orderedIDs, modifierFlags: [])
            for i in 1...1_000 {
                selection.handleTap(orderedIDs[i], orderedIDs: orderedIDs, modifierFlags: [.shift])
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
