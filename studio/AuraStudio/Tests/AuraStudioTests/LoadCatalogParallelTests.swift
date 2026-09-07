import XCTest
@testable import AuraStudio

/// PLAN-studio-rendimiento.md Fase 4 paso 6 (Fase 5.1): `loadCatalog()`
/// resuelve cada ítem en paralelo (`DispatchQueue.concurrentPerform`)
/// en vez de uno a la vez -- riesgo específico de este cambio: que el
/// orden se pierda o que un ítem con archivo ausente en el medio de la
/// lista corrompa a sus vecinos al escribir por índice desde varios
/// hilos a la vez.
@MainActor
final class LoadCatalogParallelTests: XCTestCase {
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("LoadCatalogParallel-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    private func freshPreferences() -> AppPreferences {
        AppPreferences(defaults: makeIsolatedDefaults("LoadCatalogParallelTests"))
    }

    /// 200 pistas, todas presentes -- el orden en `items` tiene que
    /// salir exactamente igual al orden en que se guardaron, pese a
    /// resolverse en paralelo.
    func testOrderIsPreservedAcrossManyItems() throws {
        let musicDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        try FileManager.default.createDirectory(at: musicDir, withIntermediateDirectories: true)
        var seedItems: [AuraStudio.LibraryItem] = []
        for i in 0..<200 {
            let fileURL = musicDir.appendingPathComponent("pista-\(String(format: "%03d", i)).mp3")
            try Data("audio \(i)".utf8).write(to: fileURL)
            var item = AuraStudio.LibraryItem(sourceURL: fileURL, addedAt: Date())
            item.status = .ready
            item.preparedURL = fileURL
            item.metadata = TrackMetadata(title: "Pista \(i)")
            seedItems.append(item)
        }
        let seed = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        seed.replaceItemsForPerformanceTesting(seedItems)
        seed.persistCatalog()

        let reloaded = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        XCTAssertEqual(reloaded.items.count, 200)
        XCTAssertEqual(reloaded.items.map { $0.metadata?.title }, seedItems.map { $0.metadata?.title },
                       "el orden de carga debe coincidir con el orden guardado, pese a resolverse en paralelo")
    }

    /// Ítems con archivo fuente ausente INTERCALADOS con presentes.
    ///
    /// ST-221 cambió lo que se espera acá: los ausentes ya **no se
    /// omiten** -- se conservan marcados como no disponibles, porque
    /// omitirlos los perdía para siempre en el siguiente guardado (basta
    /// abrir la app con el disco de los originales desconectado). Lo que
    /// esta prueba sigue vigilando es lo de siempre y ahora sobre 100
    /// elementos en vez de 80: que resolver en paralelo no corra, ni
    /// duplique, ni mezcle el contenido de un ítem con el de su vecino.
    func testMissingFilesInterspersedKeepTheirPlaceWithoutCorruptingNeighbors() throws {
        let musicDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        try FileManager.default.createDirectory(at: musicDir, withIntermediateDirectories: true)
        var seedItems: [AuraStudio.LibraryItem] = []
        var fileURLs: [URL] = []
        for i in 0..<100 {
            let fileURL = musicDir.appendingPathComponent("pista-\(String(format: "%03d", i)).mp3")
            try Data("audio \(i)".utf8).write(to: fileURL)
            fileURLs.append(fileURL)
            var item = AuraStudio.LibraryItem(sourceURL: fileURL, addedAt: Date())
            item.status = .ready
            item.preparedURL = fileURL
            item.metadata = TrackMetadata(title: "Pista \(i)")
            seedItems.append(item)
        }
        let seed = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        seed.replaceItemsForPerformanceTesting(seedItems)
        seed.persistCatalog()

        // Borra 1 de cada 5 archivos DESPUES de persistir el catálogo
        // -- exactamente como "el usuario movió/borró el archivo a
        // mano", o como un disco externo desconectado.
        var expectedUnavailable: Set<Int> = []
        for i in seedItems.indices where i % 5 == 0 {
            try FileManager.default.removeItem(at: fileURLs[i])
            expectedUnavailable.insert(i)
        }

        let reloaded = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        XCTAssertEqual(reloaded.items.count, 100, "ST-221: un archivo ausente no se borra del catálogo")
        XCTAssertEqual(reloaded.items.map { $0.metadata?.title ?? "" }, seedItems.map { $0.metadata!.title! },
                       "cada ítem conserva su orden y su propio contenido, sin mezclarse con el vecino ausente")
        let unavailable = Set(reloaded.items.indices.filter { !reloaded.items[$0].isAvailable })
        XCTAssertEqual(unavailable, expectedUnavailable,
                       "no disponibles deben ser exactamente los 20 cuyo archivo se borró")
    }
}
