import AVFoundation
import CryptoKit
import XCTest
@testable import AuraStudio

/// PLAN-studio-ajustes-3.md, Fase A0 (ST-220): línea base "antes" --
/// contra bd57116, antes de que "experto en código opus" empiece a
/// tocar el contrato de almacenamiento (A1+). Mide, para cada formato
/// (MP3/FLAC/M4A/WAV) y cada modo (copia/referencia), lo que dice el
/// diagnóstico del plan (§1) pero con números, no con la lectura del
/// código: cuántos bytes se escriben y en qué archivo al editar
/// campos, y qué archivo viaja al sincronizar. Sirve de contraste para
/// A2/A3 (escritores nativos FLAC/M4A, modo copia real).
@MainActor
final class MediaStorageBaselineTests: XCTestCase {
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("MediaStorageBaseline-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    private func sha256(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    private func fileSize(_ url: URL) throws -> Int {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
    }

    // MARK: - Fixture por formato

    private struct FormatCase {
        let name: String
        let ext: String
        let originalData: Data
    }

    private func allFormatCases() async throws -> [FormatCase] {
        [
            FormatCase(name: "MP3", ext: "mp3", originalData: MediaFixture.mp3Data(
                title: "Original", artist: "Artista Original", album: "Álbum Original",
                albumArtist: "Artista Original", year: "2020", genre: "Rock", trackNumber: 1)),
            FormatCase(name: "FLAC", ext: "flac", originalData: MediaFixture.flacData(
                title: "Original", artist: "Artista Original", album: "Álbum Original",
                albumArtist: "Artista Original", year: "2020", genre: "Rock", trackNumber: 1)),
            FormatCase(name: "M4A", ext: "m4a", originalData: try await MediaFixture.m4aData(
                title: "Original", artist: "Artista Original", album: "Álbum Original")),
            FormatCase(name: "WAV", ext: "wav", originalData: MediaFixture.wavData()),
        ]
    }

    /// Confirma que el fixture cumple lo que pide el plan: "etiquetas
    /// leíbles por AVFoundation" -- no basta con que el archivo exista,
    /// tiene que decir "Original" al leerlo de vuelta (salvo WAV, que
    /// nunca las lleva -- D-037, documentado en `MediaFixture.wavData`).
    func testFixturesCarryReadableTagsViaAVFoundation() async throws {
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        for testCase in try await allFormatCases() where testCase.name != "WAV" {
            let url = libraryRoot.appendingPathComponent("fixture.\(testCase.ext)")
            try testCase.originalData.write(to: url)
            let asset = AVURLAsset(url: url)
            let metadata = try await asset.load(.metadata)
            var foundTitle: String?
            for item in metadata where item.commonKey == .commonKeyTitle {
                foundTitle = try? await item.load(.stringValue)
            }
            XCTAssertEqual(foundTitle, "Original", "\(testCase.name): el título del fixture no se puede leer con AVFoundation")
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - "Editar N campos -> qué archivos cambian, cuántos bytes"

    private struct EditResult {
        let format: String
        let mode: String
        let originalChanged: Bool
        let originalBytesWritten: Int
        let preparedBytesWritten: Int
        let preparedIsByteIdenticalToOriginal: Bool
    }

    /// El camino real de producción: `LibraryFileWorker.prepareMusic`
    /// (la misma copia deliberada de `LibraryViewModel.prepareMusic`
    /// que ya prueba `LibraryFileWorkerEquivalenceTests`), con
    /// `audioQuality: .originalLossless` -- sin esto, un `.compressed`
    /// dispara un transcode real que no hace falta para medir "qué
    /// archivo se toca", y que dependería de que el formato de origen
    /// sea decodificable de verdad (nuestro FLAC/M4A sintéticos no lo
    /// son al 100%, aunque sus etiquetas sí se lean).
    private func measureEdit(_ testCase: FormatCase, mode: String) async throws -> EditResult {
        let caseDir = libraryRoot.appendingPathComponent("\(testCase.name)-\(mode)-\(UUID().uuidString)")
        let musicaDir = caseDir.appendingPathComponent("Música", isDirectory: true)
        let preparadosDir = caseDir.appendingPathComponent(".preparados", isDirectory: true)
        try FileManager.default.createDirectory(at: musicaDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: preparadosDir, withIntermediateDirectories: true)

        // Modo copia: el original YA vive dentro de la biblioteca
        // (Música/). Modo referencia: vive afuera -- una carpeta que
        // simula el disco del usuario, nunca tocada por la app.
        let sourceDir = mode == "copia" ? musicaDir : caseDir.appendingPathComponent("FueraDeLaBiblioteca", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let sourceURL = sourceDir.appendingPathComponent("pista.\(testCase.ext)")
        try testCase.originalData.write(to: sourceURL)
        let originalHashBefore = try sha256(sourceURL)
        let originalSizeBefore = try fileSize(sourceURL)

        // "Editar N campos": título, artista, álbum, año, género --
        // todos los que la producción sabe escribir hoy en MP3 (D-037).
        let editedMetadata = TrackMetadata(
            title: "Editado", artist: "Artista Editado", album: "Álbum Editado",
            albumArtist: "Artista Editado", year: "2026", genre: "Jazz",
            trackNumber: 1, durationSeconds: 0)

        let request = LibraryFileWorker.PrepareMusicRequest(
            sourceURL: sourceURL, stagingDirectory: preparadosDir,
            metadata: editedMetadata, audioQuality: .originalLossless, coverArtPolicy: .albumOnly)
        let worker = LibraryFileWorker()
        let preparedURL = try await worker.prepareMusic(request)

        let originalHashAfter = try sha256(sourceURL)
        let originalSizeAfter = try fileSize(sourceURL)
        let preparedSize = try fileSize(preparedURL)
        let preparedHash = try sha256(preparedURL)

        return EditResult(
            format: testCase.name, mode: mode,
            originalChanged: originalHashBefore != originalHashAfter,
            originalBytesWritten: originalSizeAfter == originalSizeBefore && originalHashBefore == originalHashAfter ? 0 : originalSizeAfter,
            preparedBytesWritten: preparedSize,
            preparedIsByteIdenticalToOriginal: preparedHash == originalHashBefore)
    }

    /// Una sola prueba, todas las combinaciones -- para poder imprimir
    /// la tabla completa de una vez (ver `DECISIONS.md`, tabla "antes"
    /// de A0) en vez de reconstruirla leyendo ocho resultados sueltos.
    func testEditingFieldsAcrossFormatsAndModes_printsBeforeTable() async throws {
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        var results: [EditResult] = []
        for testCase in try await allFormatCases() {
            for mode in ["copia", "referencia"] {
                results.append(try await measureEdit(testCase, mode: mode))
            }
        }

        print("[A0] Tabla \"antes\" -- editar 5 campos (título/artista/álbum/año/género), bd57116:")
        print("[A0] formato | modo | original cambió | bytes escritos en .preparados | .preparados == copia byte a byte del original")
        for result in results {
            print("[A0] \(result.format) | \(result.mode) | \(result.originalChanged) | \(result.preparedBytesWritten) | \(result.preparedIsByteIdenticalToOriginal)")
        }

        for result in results {
            // El original NUNCA se toca, en ningún modo -- ni copia ni
            // referencia. Es el hecho central que A3/A4 van a cambiar
            // (modo copia: el archivo de Música/ SÍ se editará).
            XCTAssertFalse(result.originalChanged, "\(result.format)/\(result.mode): el original no debería cambiar en bd57116")
            // Siempre se escribe un .preparados/ completo, del tamaño
            // del original (o del original + delta de tag para MP3).
            XCTAssertGreaterThan(result.preparedBytesWritten, 0, "\(result.format)/\(result.mode): no se escribió ningún .preparados/")
        }

        // El hecho que el plan diagnostica y que esta prueba confirma
        // con bytes reales: MP3 SÍ cambia (ID3Writer reescribe la tag);
        // FLAC/M4A/WAV NO -- el .preparados/ es una copia idéntica del
        // original, byte a byte, así que los 5 campos editados NUNCA
        // llegan al archivo que de verdad viaja al iPod.
        for result in results where result.format == "MP3" {
            XCTAssertFalse(result.preparedIsByteIdenticalToOriginal,
                          "MP3/\(result.mode): ID3Writer debería reescribir la tag en .preparados/")
        }
        for result in results where result.format != "MP3" {
            XCTAssertTrue(result.preparedIsByteIdenticalToOriginal,
                         "\(result.format)/\(result.mode): antes de A2, .preparados/ debe ser copia idéntica -- si esto falla, algo ya empezó a escribir etiquetas nativas")
        }
    }

    // MARK: - "Sincronizar -> qué archivo viaja"

    /// El camino real de producción: `LibrarySync.sync`, contra un
    /// directorio de scratch que hace de "iPod" -- nunca un dispositivo
    /// de verdad. Confirma con una copia real de archivos (no solo
    /// leyendo el código) que lo que aterriza en el volumen es
    /// `item.preparedURL`, nunca `item.sourceURL`, para los cuatro
    /// formatos por igual -- la capa de sync es agnóstica al formato,
    /// la diferencia entre formatos vive entera en qué escribió
    /// `prepareMusic` en ese `preparedURL` (ver la prueba de arriba).
    func testSyncCopiesThePreparedFileNeverTheOriginal() async throws {
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        let ipodRoot = libraryRoot.appendingPathComponent("iPod-sintetico", isDirectory: true)
        try FileManager.default.createDirectory(at: ipodRoot, withIntermediateDirectories: true)
        let preparadosDir = libraryRoot.appendingPathComponent(".preparados", isDirectory: true)
        try FileManager.default.createDirectory(at: preparadosDir, withIntermediateDirectories: true)
        let musicaDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        try FileManager.default.createDirectory(at: musicaDir, withIntermediateDirectories: true)

        var items: [AuraStudio.LibraryItem] = []
        let worker = LibraryFileWorker()
        for testCase in try await allFormatCases() {
            let sourceURL = musicaDir.appendingPathComponent("\(testCase.name).\(testCase.ext)")
            try testCase.originalData.write(to: sourceURL)
            let metadata = TrackMetadata(title: testCase.name, artist: "Artista", album: "Álbum",
                                        albumArtist: "Artista", year: "2020", genre: "Rock",
                                        trackNumber: 1, durationSeconds: 0)
            let request = LibraryFileWorker.PrepareMusicRequest(
                sourceURL: sourceURL, stagingDirectory: preparadosDir,
                metadata: metadata, audioQuality: .originalLossless, coverArtPolicy: .albumOnly)
            let preparedURL = try await worker.prepareMusic(request)

            var item = AuraStudio.LibraryItem(sourceURL: sourceURL, addedAt: Date())
            item.status = .ready
            item.metadata = metadata
            item.preparedURL = preparedURL
            items.append(item)
        }

        let sync = LibrarySync(volumeRoot: ipodRoot)
        let result = try sync.sync(items: items)
        XCTAssertEqual(result.filesCopied, items.count, "deberían viajar los \(items.count) archivos preparados")

        for item in items {
            guard let preparedURL = item.preparedURL else { XCTFail("sin preparedURL"); continue }
            let expectedHash = try sha256(preparedURL)
            // Busca el archivo real que aterrizó en el iPod sintético
            // por su nombre de destino -- no asumimos la ruta exacta
            // (depende de `musicOrganization`), solo que EXISTA una
            // copia byte a byte del preparado en algún lado dentro del
            // volumen, nunca del original.
            let musicRoot = ipodRoot.appendingPathComponent("Music", isDirectory: true)
            let matches = (try? FileManager.default.subpathsOfDirectory(atPath: musicRoot.path)) ?? []
            var found = false
            for subpath in matches {
                let candidate = musicRoot.appendingPathComponent(subpath)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
                if (try? sha256(candidate)) == expectedHash { found = true; break }
            }
            XCTAssertTrue(found, "no se encontró una copia del preparado de \(item.metadata?.title ?? "?") dentro del iPod sintético")
        }
    }
}
