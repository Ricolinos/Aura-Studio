import XCTest
@testable import AuraStudio

/// PLAN-studio-rendimiento.md Fase 4 paso 1: `LibraryFileWorker.
/// prepareMusic` es una copia deliberada de `LibraryViewModel.
/// prepareMusic` (mismo orden de pasos, mismas reglas) para poder
/// correr fuera del actor principal. Esta prueba es la que hace ese
/// refactor seguro: mismo resultado byte a byte que el camino viejo,
/// para 50 pistas -- si algún día divergen, esto lo dice, no un bug
/// reportado por el dueño meses después.
@MainActor
final class LibraryFileWorkerEquivalenceTests: XCTestCase {
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("FileWorkerEquiv-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    private func freshPreferences(audioQuality: AppPreferences.AudioQuality,
                                  coverArtPolicy: AppPreferences.CoverArtPolicy) -> AppPreferences {
        let prefs = AppPreferences(defaults: UserDefaults(suiteName: "FileWorkerEquivTests-\(UUID().uuidString)")!)
        prefs.audioQuality = audioQuality
        prefs.coverArtPolicy = coverArtPolicy
        return prefs
    }

    private func makeTracks(count: Int, musicDir: URL, coverArt: Data?) throws -> [AuraStudio.LibraryItem] {
        try FileManager.default.createDirectory(at: musicDir, withIntermediateDirectories: true)
        var items: [AuraStudio.LibraryItem] = []
        for i in 0..<count {
            let fileURL = musicDir.appendingPathComponent("pista-\(i).mp3")
            // Bytes con sync de frame MPEG válido al principio (igual
            // que ID3WriterTests) -- no hace falta audio real: ni
            // `prepareMusic` viejo ni el worker nuevo decodifican nada
            // para el camino "mantener original" (solo copian + ID3).
            let fakeAudio = Data([0xFF, 0xFB, 0x90, 0x00]) + Data(repeating: UInt8(i % 256), count: 200)
            try fakeAudio.write(to: fileURL)

            var item = AuraStudio.LibraryItem(sourceURL: fileURL, addedAt: Date())
            item.status = .ready
            item.metadata = TrackMetadata(
                title: "Canción \(i)", artist: "Artista \(i % 5)", album: "Álbum \(i % 7)",
                albumArtist: "Artista \(i % 5)", year: "1999", genre: "Rock",
                trackNumber: i, coverArtData: coverArt, durationSeconds: 200
            )
            items.append(item)
        }
        return items
    }

    /// El camino real de la app: "mantener original" (sin transcodificar
    /// -- no depende de que `ffmpeg` esté instalado en la máquina que
    /// corre la prueba) con carátula por pista embebida.
    func testFiftyTracksProduceByteIdenticalOutputKeepingOriginalWithPerTrackCover() async throws {
        let musicDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        let coverArt = Data([0xFF, 0xD8, 0xFF, 0xE0]) + Data(repeating: 0x42, count: 500) // cabecera JPEG + relleno
        let tracks = try makeTracks(count: 50, musicDir: musicDir, coverArt: coverArt)

        let oldPrefs = freshPreferences(audioQuality: .originalLossless, coverArtPolicy: .perTrack)
        let oldViewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: oldPrefs)
        let worker = LibraryFileWorker()

        for track in tracks {
            let oldResult = try oldViewModel.prepareMusic(item: track, metadata: track.metadata!)
            let oldData = try Data(contentsOf: oldResult)
            try FileManager.default.removeItem(at: oldResult) // limpio para que el worker no reutilice el archivo viejo

            let request = LibraryFileWorker.PrepareMusicRequest(
                sourceURL: track.sourceURL, stagingDirectory: oldResult.deletingLastPathComponent(),
                metadata: track.metadata!, audioQuality: .originalLossless, coverArtPolicy: .perTrack)
            let newResult = try await worker.prepareMusic(request)
            let newData = try Data(contentsOf: newResult)

            XCTAssertEqual(oldData, newData, "\(track.metadata?.title ?? "?"): el worker nuevo debe producir bytes idénticos al camino viejo")
            XCTAssertEqual(oldResult.lastPathComponent, newResult.lastPathComponent)
        }
    }

    /// Mismo lote, con "una carátula por álbum" (no se embebe nada) --
    /// el otro valor real de `coverArtPolicy` que existe en la app.
    func testFiftyTracksProduceByteIdenticalOutputWithAlbumOnlyCover() async throws {
        let musicDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        let tracks = try makeTracks(count: 50, musicDir: musicDir, coverArt: nil)

        let oldPrefs = freshPreferences(audioQuality: .originalLossless, coverArtPolicy: .albumOnly)
        let oldViewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: oldPrefs)
        let worker = LibraryFileWorker()

        for track in tracks {
            let oldResult = try oldViewModel.prepareMusic(item: track, metadata: track.metadata!)
            let oldData = try Data(contentsOf: oldResult)
            try FileManager.default.removeItem(at: oldResult)

            let request = LibraryFileWorker.PrepareMusicRequest(
                sourceURL: track.sourceURL, stagingDirectory: oldResult.deletingLastPathComponent(),
                metadata: track.metadata!, audioQuality: .originalLossless, coverArtPolicy: .albumOnly)
            let newResult = try await worker.prepareMusic(request)
            let newData = try Data(contentsOf: newResult)

            XCTAssertEqual(oldData, newData)
        }
    }

    /// Letra sincronizada: el sidecar `.lrc` también debe salir idéntico.
    func testLyricsSidecarIsAlsoByteIdentical() async throws {
        let musicDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        var tracks = try makeTracks(count: 3, musicDir: musicDir, coverArt: nil)
        for i in tracks.indices {
            tracks[i].metadata?.syncedLyrics = "[00:01.00]Línea \(i)\n[00:02.00]Otra línea"
        }

        let oldPrefs = freshPreferences(audioQuality: .originalLossless, coverArtPolicy: .albumOnly)
        let oldViewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: oldPrefs)
        let worker = LibraryFileWorker()

        for track in tracks {
            let oldResult = try oldViewModel.prepareMusic(item: track, metadata: track.metadata!)
            let oldLRC = oldResult.deletingPathExtension().appendingPathExtension("lrc")
            let oldLyrics = try Data(contentsOf: oldLRC)
            try FileManager.default.removeItem(at: oldResult)
            try FileManager.default.removeItem(at: oldLRC)

            let request = LibraryFileWorker.PrepareMusicRequest(
                sourceURL: track.sourceURL, stagingDirectory: oldResult.deletingLastPathComponent(),
                metadata: track.metadata!, audioQuality: .originalLossless, coverArtPolicy: .albumOnly)
            let newResult = try await worker.prepareMusic(request)
            let newLRC = newResult.deletingPathExtension().appendingPathExtension("lrc")

            XCTAssertEqual(oldLyrics, try Data(contentsOf: newLRC))
        }
    }
}
