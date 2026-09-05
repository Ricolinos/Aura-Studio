import XCTest
@testable import AuraStudio

/// PLAN-studio-rendimiento.md Fase 4 paso 3: `applyAlbumCover` y
/// `applySimilarityEdits` sobre `LibraryFileWorker`.
@MainActor
final class ApplyAlbumCoverAndSimilarityWorkerTests: XCTestCase {
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("AlbumCoverSimilarity-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
        MainThreadWatchdog.onHangDetectedForTesting = nil
    }

    private func freshPreferences() -> AppPreferences {
        AppPreferences(defaults: UserDefaults(suiteName: "AlbumCoverSimilarityTests-\(UUID().uuidString)")!)
    }

    private func makeTracks(count: Int, musicDir: URL, kind: LibraryItemKind = .music) throws -> [AuraStudio.LibraryItem] {
        try FileManager.default.createDirectory(at: musicDir, withIntermediateDirectories: true)
        var items: [AuraStudio.LibraryItem] = []
        for i in 0..<count {
            let ext = kind == .music ? "mp3" : "mp4"
            let fileURL = musicDir.appendingPathComponent("pista-\(i).\(ext)")
            try (Data([0xFF, 0xFB, 0x90, 0x00]) + Data(repeating: UInt8(i % 256), count: 200)).write(to: fileURL)
            var item = AuraStudio.LibraryItem(sourceURL: fileURL, addedAt: Date())
            item.status = .ready
            item.preparedURL = fileURL
            item.metadata = TrackMetadata(title: "Pista \(i)", artist: "Artista", album: "Álbum")
            items.append(item)
        }
        return items
    }

    // MARK: - applyAlbumCover

    func testAppliesTheCoverToEveryTrackInTheAlbum() async throws {
        let musicDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        let tracks = try makeTracks(count: 12, musicDir: musicDir)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.replaceItemsForPerformanceTesting(tracks)
        viewModel.makePersistenceSynchronousForTesting()

        let cover = Data([0xFF, 0xD8, 0xFF, 0xE0]) + Data(repeating: 0x9, count: 300)
        let changed = await viewModel.applyAlbumCover(cover, toItems: Set(tracks.map(\.id)))

        XCTAssertEqual(changed, 12)
        for item in viewModel.items {
            XCTAssertNotNil(item.metadata?.coverArtData)
            XCTAssertTrue(item.metadataEditedByUser)
        }
        XCTAssertTrue(viewModel.taskCenter.isEmpty)
    }

    /// `markEdited: false` (la recomendación automática, R2-3) no debe
    /// marcar `metadataEditedByUser` -- si lo hiciera, blindaría para
    /// siempre una tapa que nadie eligió a mano.
    func testMarkEditedFalseDoesNotFlagUserEditedMetadata() async throws {
        let musicDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        let tracks = try makeTracks(count: 3, musicDir: musicDir)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.replaceItemsForPerformanceTesting(tracks)
        viewModel.makePersistenceSynchronousForTesting()

        let cover = Data([0xFF, 0xD8, 0xFF, 0xE0]) + Data(repeating: 0x9, count: 300)
        _ = await viewModel.applyAlbumCover(cover, toItems: Set(tracks.map(\.id)), markEdited: false)

        XCTAssertTrue(viewModel.items.allSatisfy { !$0.metadataEditedByUser })
    }

    /// Sin cambios reales (misma carátula ya puesta), no hay nada que
    /// hacer -- ni tarea en el centro, ni recuento distinto de cero.
    func testAppliesTheSameCoverAgainChangesNothing() async throws {
        let musicDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        var tracks = try makeTracks(count: 2, musicDir: musicDir)
        let cover = Data([0xFF, 0xD8, 0xFF, 0xE0]) + Data(repeating: 0x9, count: 300)
        let normalized = CoverArtNormalizer.normalized(cover)
        for i in tracks.indices { tracks[i].metadata?.coverArtData = normalized }
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.replaceItemsForPerformanceTesting(tracks)
        viewModel.makePersistenceSynchronousForTesting()

        let changed = await viewModel.applyAlbumCover(cover, toItems: Set(tracks.map(\.id)))
        XCTAssertEqual(changed, 0)
    }

    /// Criterio de cierre del paso: cero bloqueos > 250 ms, ahora con
    /// una "compilación" de 300 pistas (un caso real y no descabellado
    /// para este camino).
    func testThreeHundredTracksNeverBlockTheMainThreadOverTheWatchdogThreshold() async throws {
        setenv("AURA_WATCHDOG", "1", 1)
        let hangs = HangCollector()
        MainThreadWatchdog.onHangDetectedForTesting = { durationMs in hangs.add(durationMs) }
        MainThreadWatchdog.startIfRequested()

        let musicDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        let tracks = try makeTracks(count: 300, musicDir: musicDir)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.replaceItemsForPerformanceTesting(tracks)
        viewModel.makePersistenceSynchronousForTesting()

        let cover = Data([0xFF, 0xD8, 0xFF, 0xE0]) + Data(repeating: 0x9, count: 300)
        _ = await viewModel.applyAlbumCover(cover, toItems: Set(tracks.map(\.id)))

        XCTAssertTrue(hangs.values.isEmpty, "bloqueos del hilo principal > 250 ms aplicando carátula: \(hangs.values)")
    }

    // MARK: - applySimilarityEdits

    func testAppliesProposedEditsToTheRightFields() async throws {
        let musicDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        let tracks = try makeTracks(count: 2, musicDir: musicDir)
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.replaceItemsForPerformanceTesting(tracks)
        viewModel.makePersistenceSynchronousForTesting()

        let edits = [
            SimilarityProposedEdit(itemID: tracks[0].id, field: .artist, currentValue: "Artista", proposedValue: "Gorillaz"),
            SimilarityProposedEdit(itemID: tracks[0].id, field: .album, currentValue: "Álbum", proposedValue: "Demon Days"),
        ]
        await viewModel.applySimilarityEdits(edits)

        let updated = viewModel.items.first { $0.id == tracks[0].id }
        XCTAssertEqual(updated?.metadata?.artist, "Gorillaz")
        XCTAssertEqual(updated?.metadata?.album, "Demon Days")
        XCTAssertTrue(updated?.metadataEditedByUser ?? false)
        // El otro ítem, sin ediciones propuestas, no debe tocarse.
        XCTAssertEqual(viewModel.items.first { $0.id == tracks[1].id }?.metadata?.artist, "Artista")
    }

    /// Fotos/video no pasan por `prepareMusic` -- confirmado no
    /// crasheando ni quedando con un `preparedURL` inventado.
    func testNonMusicItemsAreEditedWithoutTouchingPreparedURL() async throws {
        let videoDir = libraryRoot.appendingPathComponent("Videos", isDirectory: true)
        try FileManager.default.createDirectory(at: videoDir, withIntermediateDirectories: true)
        let fileURL = videoDir.appendingPathComponent("clip.mp4")
        try Data([0x00, 0x01]).write(to: fileURL)
        var item = AuraStudio.LibraryItem(sourceURL: fileURL, addedAt: Date())
        item.status = .ready
        item.metadata = TrackMetadata(title: "Antes")
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.replaceItemsForPerformanceTesting([item])
        viewModel.makePersistenceSynchronousForTesting()

        await viewModel.applySimilarityEdits([SimilarityProposedEdit(itemID: item.id, field: .title, currentValue: "Antes", proposedValue: "Después")])

        let updated = viewModel.items.first { $0.id == item.id }
        XCTAssertEqual(updated?.metadata?.title, "Después")
        XCTAssertNil(updated?.preparedURL)
    }
}
