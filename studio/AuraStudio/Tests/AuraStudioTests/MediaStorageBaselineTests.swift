import AVFoundation
import CryptoKit
import XCTest
@testable import AuraStudio

/// PLAN-studio-ajustes-3.md, Fase A0 (ST-220): arnés de línea base --
/// mide, para cada formato (MP3/FLAC/M4A/WAV) y cada modo (copia/
/// referencia), lo que dice el diagnóstico del plan (§1/§2) pero con
/// números, no con la lectura del código: cuántos bytes se escriben y
/// en qué archivo al editar campos, y qué archivo viaja al
/// sincronizar.
///
/// **"Antes" (ST-220, contra `bd57116`) queda fijo en DECISIONS.md** --
/// ese número no se vuelve a medir acá. Lo que sigue en este archivo
/// se actualiza para seguir midiendo la realidad ACTUAL de cada fase:
/// tras A3 (ST-223, `bb164dd`), el modo copia ya no pasa por
/// `LibraryFileWorker.prepareMusic`/`.preparados/` -- usa `importMusic`
/// al importar y `rewriteTags` al editar, directo sobre el archivo de
/// `Música/`. Tras A4 (ST-224, `45f66ff`), el modo referencia TAMPOCO
/// prepara siempre -- usa `ensurePreparedMusic`, que solo arma
/// `.preparados/<ID>.ext` cuando el archivo necesita conversión o sus
/// etiquetas no coinciden con el catálogo (`PreparedMusicPlan`); si ya
/// coincide, no hay preparado y al iPod viaja el original.
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

    private func modificationDate(_ url: URL) throws -> Date {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
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
        /// `Música/<Artista>/<Álbum>/` en copia; el original fuera de la
        /// biblioteca en referencia. 0 si no cambió.
        let libraryFileBytesWritten: Int
        /// `.preparados/<ID>.ext`. 0 si no existe o no cambió.
        let preparedBytesWritten: Int
    }

    private let originalMetadata = TrackMetadata(
        title: "Original", artist: "Artista Original", album: "Álbum Original",
        albumArtist: "Artista Original", year: "2020", genre: "Rock",
        trackNumber: 1, durationSeconds: 0)

    /// "Editar N campos": título, artista, álbum, año, género -- todos
    /// los que la producción sabe escribir hoy (D-037/ST-222).
    private let editedMetadata = TrackMetadata(
        title: "Editado", artist: "Artista Editado", album: "Álbum Editado",
        albumArtist: "Artista Editado", year: "2026", genre: "Jazz",
        trackNumber: 1, durationSeconds: 0)

    /// Modo copia (ST-223): el camino real es `LibraryFileWorker.
    /// importMusic` al importar y `rewriteTags` al editar, directo sobre
    /// el archivo de `Música/` -- `.preparados/` no interviene. Modo
    /// referencia: sin cambios desde ST-220, sigue siendo `prepareMusic`
    /// hacia `.preparados/` (A4 todavía no cerró).
    private func measureEdit(_ testCase: FormatCase, mode: String) async throws -> EditResult {
        let caseDir = libraryRoot.appendingPathComponent("\(testCase.name)-\(mode)-\(UUID().uuidString)")
        let musicaDir = caseDir.appendingPathComponent("Música", isDirectory: true)
        let preparadosDir = caseDir.appendingPathComponent(".preparados", isDirectory: true)
        try FileManager.default.createDirectory(at: musicaDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: preparadosDir, withIntermediateDirectories: true)
        let worker = LibraryFileWorker()

        if mode == "copia" {
            let sourceDir = caseDir.appendingPathComponent("SoltadoParaImportar", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
            let droppedURL = sourceDir.appendingPathComponent("pista.\(testCase.ext)")
            try testCase.originalData.write(to: droppedURL)

            let decision = AudioConversionRule.decide(sourceExtension: testCase.ext, audioQuality: .originalLossless)
            let destExt = AudioConversionRule.destinationExtension(sourceExtension: testCase.ext, audioQuality: .originalLossless)
            let destinationURL = musicaDir.appendingPathComponent("pista.\(destExt)")
            let imported = try await worker.importMusic(LibraryFileWorker.ImportMusicRequest(
                sourceURL: droppedURL, destinationURL: destinationURL, decision: decision,
                metadata: originalMetadata, coverArtPolicy: .albumOnly))

            let hashBeforeEdit = try sha256(imported.url)
            _ = await worker.rewriteTags(metadata: editedMetadata, coverArtPolicy: .albumOnly, at: imported.url)
            let hashAfterEdit = try sha256(imported.url)
            let sizeAfterEdit = try fileSize(imported.url)

            let preparedEntries = (try? FileManager.default.contentsOfDirectory(atPath: preparadosDir.path)) ?? []
            XCTAssertTrue(preparedEntries.isEmpty, "\(testCase.name)/copia: .preparados/ debería seguir vacío tras editar")

            return EditResult(format: testCase.name, mode: mode,
                              libraryFileBytesWritten: hashAfterEdit == hashBeforeEdit ? 0 : sizeAfterEdit,
                              preparedBytesWritten: 0)
        } else {
            let sourceDir = caseDir.appendingPathComponent("FueraDeLaBiblioteca", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
            let sourceURL = sourceDir.appendingPathComponent("pista.\(testCase.ext)")
            try testCase.originalData.write(to: sourceURL)
            let originalHashBefore = try sha256(sourceURL)

            let request = LibraryFileWorker.PrepareMusicRequest(
                sourceURL: sourceURL, stagingDirectory: preparadosDir,
                metadata: editedMetadata, audioQuality: .originalLossless, coverArtPolicy: .albumOnly,
                itemID: UUID())
            let preparedURL = try await worker.prepareMusic(request)

            let originalHashAfter = try sha256(sourceURL)
            let preparedSize = try fileSize(preparedURL)

            return EditResult(format: testCase.name, mode: mode,
                              libraryFileBytesWritten: originalHashAfter == originalHashBefore ? 0 : (try fileSize(sourceURL)),
                              preparedBytesWritten: preparedSize)
        }
    }

    /// Una sola prueba, todas las combinaciones -- para poder imprimir
    /// la tabla completa de una vez (ver `DECISIONS.md`, tabla "después
    /// de A3") en vez de reconstruirla leyendo ocho resultados sueltos.
    func testEditingFieldsAcrossFormatsAndModes_printsAfterA3Table() async throws {
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        var results: [EditResult] = []
        for testCase in try await allFormatCases() {
            for mode in ["copia", "referencia"] {
                results.append(try await measureEdit(testCase, mode: mode))
            }
        }

        print("[A3] Tabla \"después de A3\" -- editar 5 campos (título/artista/álbum/año/género), bb164dd:")
        print("[A3] formato | modo | bytes escritos en Música/ | bytes escritos en .preparados")
        for result in results {
            print("[A3] \(result.format) | \(result.mode) | \(result.libraryFileBytesWritten) | \(result.preparedBytesWritten)")
        }

        for result in results where result.mode == "copia" {
            // ST-223: modo copia -- el archivo de Música/ SÍ se edita
            // (para los tres formatos etiquetables) y .preparados/ nunca
            // interviene.
            XCTAssertEqual(result.preparedBytesWritten, 0, "\(result.format)/copia: .preparados/ no debería tener nada")
            XCTAssertGreaterThan(result.libraryFileBytesWritten, 0,
                                 "\(result.format)/copia: el archivo de Música/ debería reflejar los 5 campos editados")
        }
        for result in results where result.mode == "referencia" {
            // Sin cambios desde ST-220: el original nunca se toca, todo
            // pasa por .preparados/ (A4 todavía no cerró).
            XCTAssertEqual(result.libraryFileBytesWritten, 0, "\(result.format)/referencia: el original no debería cambiar")
            XCTAssertGreaterThan(result.preparedBytesWritten, 0, "\(result.format)/referencia: no se escribió ningún .preparados/")
        }
    }

    // MARK: - Edición idempotente (ST-223): mismos campos, sin tocar el archivo

    /// Los tres escritores nativos (ID3/FLAC/MP4) comparan los bytes que
    /// van a escribir contra los que ya hay y se saltan la escritura si
    /// son iguales (`guard updated != original else { return }`, ver
    /// `ID3Writer`/`FLACTagWriter`/`MP4TagWriter`). Reescribir con la
    /// MISMA metadata que ya está en el archivo -- el caso real de
    /// guardar sin haber cambiado nada -- no debería tocar el archivo en
    /// absoluto: 0 bytes, misma fecha de modificación. Solo tiene
    /// sentido en modo copia (el único camino con esta idempotencia hoy
    /// -- referencia sigue recopiando siempre, eso es A4).
    func testIdempotentEditWritesNothingAndKeepsTheModificationDate() async throws {
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        var rows: [(format: String, bytesWritten: Int, dateChanged: Bool)] = []

        for testCase in try await allFormatCases() {
            let caseDir = libraryRoot.appendingPathComponent("Idempotent-\(testCase.name)-\(UUID().uuidString)")
            let musicaDir = caseDir.appendingPathComponent("Música", isDirectory: true)
            let sourceDir = caseDir.appendingPathComponent("SoltadoParaImportar", isDirectory: true)
            try FileManager.default.createDirectory(at: musicaDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
            let droppedURL = sourceDir.appendingPathComponent("pista.\(testCase.ext)")
            try testCase.originalData.write(to: droppedURL)

            let decision = AudioConversionRule.decide(sourceExtension: testCase.ext, audioQuality: .originalLossless)
            let destExt = AudioConversionRule.destinationExtension(sourceExtension: testCase.ext, audioQuality: .originalLossless)
            let destinationURL = musicaDir.appendingPathComponent("pista.\(destExt)")
            let worker = LibraryFileWorker()
            let imported = try await worker.importMusic(LibraryFileWorker.ImportMusicRequest(
                sourceURL: droppedURL, destinationURL: destinationURL, decision: decision,
                metadata: originalMetadata, coverArtPolicy: .albumOnly))

            // Primera edición real -- deja al archivo con `editedMetadata`.
            _ = await worker.rewriteTags(metadata: editedMetadata, coverArtPolicy: .albumOnly, at: imported.url)
            let hashBefore = try sha256(imported.url)
            let dateBefore = try modificationDate(imported.url)

            // Un pequeño respiro: si el sistema de archivos redondea la
            // fecha de modificación al segundo, escribir "de nuevo" en el
            // mismo segundo podría no distinguirse de no haber escrito --
            // sin esto, la prueba podría pasar por casualidad de reloj,
            // no porque el escritor de verdad se salteó la escritura.
            try await Task.sleep(nanoseconds: 1_100_000_000)

            // Segunda edición: LA MISMA metadata -- nada cambió.
            _ = await worker.rewriteTags(metadata: editedMetadata, coverArtPolicy: .albumOnly, at: imported.url)
            let hashAfter = try sha256(imported.url)
            let dateAfter = try modificationDate(imported.url)

            rows.append((format: testCase.name,
                        bytesWritten: hashAfter == hashBefore ? 0 : (try fileSize(imported.url)),
                        dateChanged: dateAfter != dateBefore))
        }

        print("[A3] Tabla \"edición sin cambios\" -- reescribir con la misma metadata, bb164dd:")
        print("[A3] formato | bytes escritos | fecha de modificación cambió")
        for row in rows {
            print("[A3] \(row.format) | \(row.bytesWritten) | \(row.dateChanged)")
        }
        for row in rows {
            XCTAssertEqual(row.bytesWritten, 0, "\(row.format): reescribir con la misma metadata no debería escribir nada")
            XCTAssertFalse(row.dateChanged, "\(row.format): reescribir con la misma metadata no debería moverle la fecha al archivo")
        }
    }

    // MARK: - Rating (ST-223): nunca toca el archivo de música

    /// `LibraryViewModel.setRating` (verificado leyendo el código: solo
    /// muta `metadata.rating` en memoria y agenda `persistCatalog()`) --
    /// acá se mide de punta a punta, a través del ViewModel real, no del
    /// worker: importar en copia, calificar, confirmar que el archivo de
    /// `Música/` no cambió ni un byte ni de fecha. Representa también a
    /// favorito/categoría (mismo patrón: mutan el catálogo, nunca llaman
    /// a `refreshMusicFile`) -- no remedidos cada uno por separado esta
    /// ronda; letra (`.lrc`) tampoco, por el mismo motivo, pero no se
    /// afirma acá con un número propio.
    @MainActor
    func testRatingNeverTouchesTheMusicFile() async throws {
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        let musicaDir = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        let sourceDir = libraryRoot.appendingPathComponent("SoltadoParaImportar", isDirectory: true)
        try FileManager.default.createDirectory(at: musicaDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let droppedURL = sourceDir.appendingPathComponent("pista.mp3")
        try MediaFixture.mp3Data(title: "Original", artist: "Artista", album: "Álbum",
                                 albumArtist: "Artista", year: "2020", genre: "Rock", trackNumber: 1).write(to: droppedURL)

        let worker = LibraryFileWorker()
        let imported = try await worker.importMusic(LibraryFileWorker.ImportMusicRequest(
            sourceURL: droppedURL, destinationURL: musicaDir.appendingPathComponent("pista.mp3"),
            decision: .copyAsIs, metadata: originalMetadata, coverArtPolicy: .albumOnly))

        var item = AuraStudio.LibraryItem(sourceURL: imported.url, addedAt: Date())
        item.status = .ready
        item.storage = .copy
        item.preparedURL = imported.url
        item.metadata = originalMetadata

        let viewModel = LibraryViewModel(libraryRoot: libraryRoot,
                                         preferences: AppPreferences(defaults: makeIsolatedDefaults("MediaStorageBaseline")))
        viewModel.replaceItemsForPerformanceTesting([item])
        viewModel.makePersistenceSynchronousForTesting()

        let hashBefore = try sha256(imported.url)
        let dateBefore = try modificationDate(imported.url)

        await viewModel.setRating(4, forItem: item.id)

        let hashAfter = try sha256(imported.url)
        let dateAfter = try modificationDate(imported.url)

        print("[A3] rating: bytes escritos en el archivo de música = \(hashAfter == hashBefore ? 0 : (try fileSize(imported.url))), fecha cambió = \(dateAfter != dateBefore)")
        XCTAssertEqual(hashBefore, hashAfter, "calificar no debería tocar el archivo de música")
        XCTAssertEqual(dateBefore, dateAfter, "calificar no debería moverle la fecha al archivo de música")
        XCTAssertEqual(viewModel.items.first?.metadata?.rating, 4, "la calificación sí debe quedar en el catálogo")
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
            // ST-221: el ítem se crea ANTES para que su id nombre el
            // derivado, que es como ocurre en producción.
            var item = AuraStudio.LibraryItem(sourceURL: sourceURL, addedAt: Date())
            let request = LibraryFileWorker.PrepareMusicRequest(
                sourceURL: sourceURL, stagingDirectory: preparadosDir,
                metadata: metadata, audioQuality: .originalLossless, coverArtPolicy: .albumOnly,
                itemID: item.id)
            let preparedURL = try await worker.prepareMusic(request)

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

    // MARK: - Modo referencia contra A4 (ST-224): el preparado solo cuando hace falta

    private struct ReferenceModeResult {
        let scenario: String
        let action: String
        let preparedBytesWritten: Int
        let originalChanged: Bool
    }

    /// El camino real de producción: `LibraryFileWorker.
    /// ensurePreparedMusic` (`refreshMusicFile`, rama `storage ==
    /// .reference`, y también el punto de entrada al importar en modo
    /// referencia). Tres escenarios pedidos por "Sesión Maestra", para
    /// la tabla de A8 junto a ST-220 (antes) y su addendum (A3):
    func testReferenceModeAgainstA4_printsTable() async throws {
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        let worker = LibraryFileWorker()
        var rows: [ReferenceModeResult] = []

        // (a) Referencia sin cambios: un MP3 cuyas etiquetas YA
        // coinciden con lo que dice el catálogo (mismo `originalMetadata`
        // que el fixture escribió) -- no debería armar ningún preparado.
        do {
            let caseDir = libraryRoot.appendingPathComponent("RefSinCambios-\(UUID().uuidString)")
            let sourceDir = caseDir.appendingPathComponent("FueraDeLaBiblioteca", isDirectory: true)
            let preparadosDir = caseDir.appendingPathComponent(".preparados", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: preparadosDir, withIntermediateDirectories: true)
            let sourceURL = sourceDir.appendingPathComponent("pista.mp3")
            try MediaFixture.mp3Data(title: "Original", artist: "Artista Original", album: "Álbum Original",
                                     albumArtist: "Artista Original", year: "2020", genre: "Rock", trackNumber: 1).write(to: sourceURL)
            let originalHashBefore = try sha256(sourceURL)

            let result = await worker.ensurePreparedMusic(LibraryFileWorker.EnsurePreparedMusicRequest(
                itemID: UUID(), sourceURL: sourceURL, previousPreparedURL: nil, catalogSourceSize: nil,
                stagingDirectory: preparadosDir, metadata: originalMetadata,
                audioQuality: .originalLossless, coverArtPolicy: .albumOnly))

            let preparedEntries = (try? FileManager.default.contentsOfDirectory(atPath: preparadosDir.path)) ?? []
            XCTAssertNil(result.url, "sin cambios no debería haber preparado")
            XCTAssertTrue(preparedEntries.isEmpty, ".preparados/ debería seguir vacío")
            rows.append(ReferenceModeResult(
                scenario: "referencia sin cambios", action: "\(result.action)",
                preparedBytesWritten: 0,
                originalChanged: (try sha256(sourceURL)) != originalHashBefore))
        }

        // (b) Referencia con título editado: mismo MP3, metadata con
        // título distinto -- debería armar el preparado, con las
        // etiquetas nuevas, sin tocar el original.
        do {
            let caseDir = libraryRoot.appendingPathComponent("RefTituloEditado-\(UUID().uuidString)")
            let sourceDir = caseDir.appendingPathComponent("FueraDeLaBiblioteca", isDirectory: true)
            let preparadosDir = caseDir.appendingPathComponent(".preparados", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: preparadosDir, withIntermediateDirectories: true)
            let sourceURL = sourceDir.appendingPathComponent("pista.mp3")
            try MediaFixture.mp3Data(title: "Original", artist: "Artista Original", album: "Álbum Original",
                                     albumArtist: "Artista Original", year: "2020", genre: "Rock", trackNumber: 1).write(to: sourceURL)
            let originalHashBefore = try sha256(sourceURL)

            let result = await worker.ensurePreparedMusic(LibraryFileWorker.EnsurePreparedMusicRequest(
                itemID: UUID(), sourceURL: sourceURL, previousPreparedURL: nil, catalogSourceSize: nil,
                stagingDirectory: preparadosDir, metadata: editedMetadata,
                audioQuality: .originalLossless, coverArtPolicy: .albumOnly))

            let preparedURL = try XCTUnwrap(result.url, "editar el título debería armar un preparado")
            XCTAssertEqual(result.action, .build)
            rows.append(ReferenceModeResult(
                scenario: "referencia con título editado", action: "\(result.action)",
                preparedBytesWritten: try fileSize(preparedURL),
                originalChanged: (try sha256(sourceURL)) != originalHashBefore))
        }

        // (c) Referencia WAV con "Original sin pérdida": WAV siempre
        // convierte (nunca puede ser su propio preparado) -- debería
        // armar un preparado ALAC (.m4a), sin importar si las etiquetas
        // "coinciden" (WAV no lleva etiquetas que comparar).
        do {
            let caseDir = libraryRoot.appendingPathComponent("RefWAVOriginal-\(UUID().uuidString)")
            let sourceDir = caseDir.appendingPathComponent("FueraDeLaBiblioteca", isDirectory: true)
            let preparadosDir = caseDir.appendingPathComponent(".preparados", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: preparadosDir, withIntermediateDirectories: true)
            let sourceURL = sourceDir.appendingPathComponent("pista.wav")
            try MediaFixture.wavData().write(to: sourceURL)
            let originalHashBefore = try sha256(sourceURL)

            let result = await worker.ensurePreparedMusic(LibraryFileWorker.EnsurePreparedMusicRequest(
                itemID: UUID(), sourceURL: sourceURL, previousPreparedURL: nil, catalogSourceSize: nil,
                stagingDirectory: preparadosDir, metadata: originalMetadata,
                audioQuality: .originalLossless, coverArtPolicy: .albumOnly))

            let preparedURL = try XCTUnwrap(result.url, "WAV siempre debería armar un preparado")
            XCTAssertEqual(result.action, .build)
            XCTAssertEqual(preparedURL.pathExtension.lowercased(), "m4a", "WAV en referencia con Original debería quedar en ALAC (.m4a)")
            rows.append(ReferenceModeResult(
                scenario: "referencia WAV con Original", action: "\(result.action)",
                preparedBytesWritten: try fileSize(preparedURL),
                originalChanged: (try sha256(sourceURL)) != originalHashBefore))
        }

        print("[A4] Tabla \"referencia contra A4\" -- junto a ST-220 (antes) y su addendum (A3):")
        print("[A4] escenario | acción | bytes escritos en el preparado | ¿original cambió?")
        for row in rows {
            print("[A4] \(row.scenario) | \(row.action) | \(row.preparedBytesWritten) | \(row.originalChanged)")
        }
        for row in rows {
            XCTAssertFalse(row.originalChanged, "\(row.scenario): el original nunca debería cambiar en modo referencia")
        }
    }
}
