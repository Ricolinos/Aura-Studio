import XCTest
@testable import AuraStudio

/// Prueba el pipeline completo (ingesta -> enriquecimiento/transcode/
/// resize -> sync diferencial) contra archivos reales, no solo cada
/// pieza en aislamiento. Usa los fixtures de test-media/ (raiz de este
/// repo), generados por tools/gen_test_media.sh, y un iPod "de mentira"
/// (una carpeta temporal en vez de un volumen montado de verdad) para
/// que el sync se pueda verificar sin hardware.
final class LibraryPipelineIntegrationTests: XCTestCase {
    private var fakeIPod: URL!

    override func setUpWithError() throws {
        fakeIPod = FileManager.default.temporaryDirectory.appendingPathComponent("FakeIPod-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeIPod, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fakeIPod)
    }

    private func repoTestMediaURL() -> URL? {
        // Sube desde la ruta fuente de este archivo (#filePath, estable
        // sin importar el build system) hasta encontrar test-media/ en
        // la raiz del repo, sin asumir un layout fijo de directorio de
        // trabajo.
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir.appendingPathComponent("test-media")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    func testPhotoAndVideoPipelineEndToEnd() async throws {
        guard let testMedia = repoTestMediaURL() else {
            throw XCTSkip("test-media/ no esta generado (correr tools/gen_test_media.sh)")
        }
        let photoURL = testMedia.appendingPathComponent("Photos/photo1.jpg")
        guard FileManager.default.fileExists(atPath: photoURL.path) else {
            throw XCTSkip("fixture de foto no encontrado")
        }

        // El video de test-media/ ya esta en formato Aura; para probar
        // la transcodificacion de verdad hace falta una fuente en OTRO
        // formato (mp4 generado al vuelo).
        let videoSource = FileManager.default.temporaryDirectory.appendingPathComponent("smoke_input.mp4")
        try await generateTestVideo(at: videoSource)
        defer { try? FileManager.default.removeItem(at: videoSource) }

        let libraryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuraLibTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: libraryRoot) }
        let viewModel = await LibraryViewModel(libraryRoot: libraryRoot)
        await MainActor.run {
            viewModel.addDroppedFiles([photoURL, videoSource])
        }
        await viewModel.processAll()

        let items = await MainActor.run { viewModel.items }
        XCTAssertEqual(items.count, 2)

        let photoItem = items.first { $0.kind == .photo }
        let videoItem = items.first { $0.kind == .video }

        XCTAssertEqual(photoItem?.status, .ready)
        XCTAssertNotNil(photoItem?.preparedURL)
        XCTAssertEqual(photoItem?.preparedURL?.pathExtension.lowercased(), "jpg")

        XCTAssertEqual(videoItem?.status, .ready)
        XCTAssertNotNil(videoItem?.preparedURL)
        XCTAssertEqual(videoItem?.preparedURL?.pathExtension.lowercased(), "mpg")

        if let preparedPhotoURL = photoItem?.preparedURL {
            let data = try Data(contentsOf: preparedPhotoURL)
            XCTAssertGreaterThan(data.count, 0)
            XCTAssertEqual(data.prefix(2), Data([0xFF, 0xD8])) // firma JPEG
        }
        if let preparedVideoURL = videoItem?.preparedURL {
            let attrs = try FileManager.default.attributesOfItem(atPath: preparedVideoURL.path)
            XCTAssertGreaterThan((attrs[.size] as? Int) ?? 0, 0)

            // Fase 24: LibraryViewModel genera el poster junto al .mpg
            // transcodificado (D-066) -- se verifica ahi, no con un
            // fixture aparte, para probar el wiring real de punta a
            // punta en vez de solo la funcion de ffmpeg en aislamiento.
            let posterURL = preparedVideoURL.deletingPathExtension().appendingPathExtension("jpg")
            XCTAssertTrue(FileManager.default.fileExists(atPath: posterURL.path), "deberia generarse un poster junto al video transcodificado")
            let posterData = try Data(contentsOf: posterURL)
            XCTAssertEqual(posterData.prefix(2), Data([0xFF, 0xD8]), "el poster deberia ser un JPEG valido")
        }

        // Primer sync: todo es nuevo, se copian los 2 archivos y se
        // limpia el indice de tagcache (aca no existe, pero no debe
        // explotar si falta).
        await viewModel.sync(toVolumeAt: fakeIPod)
        let firstSummary = await MainActor.run { viewModel.lastSyncSummary }
        XCTAssertTrue(firstSummary?.contains("2") ?? false, "deberia reportar 2 archivos copiados: \(firstSummary ?? "nil")")

        let syncedPhoto = fakeIPod.appendingPathComponent("Photos/photo1.jpg")
        let syncedVideo = fakeIPod.appendingPathComponent("Videos/smoke_input.mpg")
        let syncedPoster = fakeIPod.appendingPathComponent("Videos/smoke_input.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: syncedPhoto.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: syncedVideo.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: syncedPoster.path), "el poster deberia sincronizarse junto con su video")

        // Segundo sync sin cambios: el plan diferencial no debe volver
        // a copiar nada.
        await viewModel.sync(toVolumeAt: fakeIPod)
        let secondSummary = await MainActor.run { viewModel.lastSyncSummary }
        XCTAssertTrue(secondSummary?.lowercased().contains("ya estaba todo sincronizado") ?? false, "segundo sync deberia no copiar nada: \(secondSummary ?? "nil")")
    }

    func testTagcacheIndexIsRemovedAfterSyncForcingRebuild() async throws {
        guard let testMedia = repoTestMediaURL() else {
            throw XCTSkip("test-media/ no esta generado")
        }
        let photoURL = testMedia.appendingPathComponent("Photos/photo1.jpg")
        guard FileManager.default.fileExists(atPath: photoURL.path) else {
            throw XCTSkip("fixture de foto no encontrado")
        }

        let rockboxDir = fakeIPod.appendingPathComponent(".rockbox")
        try FileManager.default.createDirectory(at: rockboxDir, withIntermediateDirectories: true)
        let fakeIndex = rockboxDir.appendingPathComponent("database_idx.tcd")
        try Data("fake preexisting index".utf8).write(to: fakeIndex)

        let libraryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuraLibTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: libraryRoot) }
        let viewModel = await LibraryViewModel(libraryRoot: libraryRoot)
        await MainActor.run { viewModel.addDroppedFiles([photoURL]) }
        await viewModel.processAll()
        await viewModel.sync(toVolumeAt: fakeIPod)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fakeIndex.path), "database_idx.tcd deberia borrarse para forzar reconstruccion")
    }

    private func generateTestVideo(at url: URL) async throws {
        let ffmpeg = FFmpegLocator.locate() ?? URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = [
            "-y", "-loglevel", "error",
            "-f", "lavfi", "-i", "testsrc=size=640x480:rate=10:duration=1",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
            "-c:v", "libx264", "-c:a", "aac",
            url.path,
        ]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw XCTSkip("no se pudo generar el video de prueba con ffmpeg")
        }
    }
}
