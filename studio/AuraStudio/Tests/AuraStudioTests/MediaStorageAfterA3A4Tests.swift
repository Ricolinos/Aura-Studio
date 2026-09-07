import AVFoundation
import CryptoKit
import XCTest
@testable import AuraStudio

/// PLAN-studio-ajustes-3.md §2/§4 (A3 modo copia real, A4 modo
/// referencia real, ST-223/ST-224). Encargo de "Sesión Maestra"
/// mientras "experto en código opus" cierra A1/A2: la forma exacta de
/// las pruebas "después" -- todas `throw XCTSkip`, porque la API
/// todavía no existe (A1 define `storage`, A2 los escritores nativos,
/// A3/A4 el modo copia/referencia real). Cuando cada API exista,
/// llenar el cuerpo sustituye el `XCTSkip` por las aserciones que ya
/// están descritas acá -- no hace falta rediseñar la prueba.
///
/// El fixture de A0 (`MediaFixture`) y los lectores de A2
/// (`FLACTagReader`/`MP4TagReader`) ya están listos para reusarse tal
/// cual en cuanto se llenen estas pruebas.
@MainActor
final class MediaStorageAfterA3A4Tests: XCTestCase {
    private var libraryRoot: URL!
    private var sourceDirs: [URL] = []

    override func setUpWithError() throws {
        sourceDirs = []
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("MediaStorageAfterA3A4-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
        for dir in sourceDirs { try? FileManager.default.removeItem(at: dir) }
    }

    // MARK: - Andamio (ST-223)

    private func freshPreferences(copy: Bool,
                                  quality: AppPreferences.AudioQuality = .originalLossless) -> AppPreferences {
        let prefs = AppPreferences(defaults: makeIsolatedDefaults("MediaStorageAfterA3A4"))
        prefs.copyMediaIntoLibrary = copy
        prefs.audioQuality = quality
        // Nada de red en una prueba: lo que se mide es el manejo de
        // archivos, no el enriquecimiento.
        prefs.enrichOnline = false
        prefs.fetchSyncedLyrics = false
        return prefs
    }

    private func sha256(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    /// Una carpeta fuera de la biblioteca, que hace de "el disco del
    /// usuario": lo que se suelta nunca sale de acá.
    private func makeSource(_ name: String, _ data: Data) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaStorageAfterA3A4-origen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        sourceDirs.append(dir)
        let url = dir.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private var preparadosContents: [String] {
        (try? FileManager.default.contentsOfDirectory(
            atPath: libraryRoot.appendingPathComponent(PersistedLibrary.preparedDirName).path)) ?? []
    }

    private func importInCopyMode(_ url: URL,
                                  quality: AppPreferences.AudioQuality = .originalLossless)
        async -> (viewModel: LibraryViewModel, item: AuraStudio.LibraryItem?) {
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot,
                                         preferences: freshPreferences(copy: true, quality: quality))
        viewModel.makePersistenceSynchronousForTesting()
        viewModel.addDroppedFiles([url])
        await viewModel.processAll()
        return (viewModel, viewModel.items.first)
    }

    // MARK: - (a) Modo copia: importar deja el archivo listo, sin .preparados/

    /// Forma de la prueba: importar un MP3/FLAC/M4A sintético
    /// (`MediaFixture.mp3Data`/`flacData`/`m4aData`) en modo copia real
    /// (A3) y confirmar TRES cosas a la vez, para los tres formatos:
    /// 1) el archivo en `Música/<Artista>/<Álbum>/` existe y ya lleva
    ///    las etiquetas del catálogo (releído con `FLACTagReader`/
    ///    `MP4TagReader`/ID3 según formato -- el archivo de la
    ///    biblioteca ES el preparado, §2);
    /// 2) `.preparados/` queda VACÍO para este ítem -- ya no
    ///    interviene en modo copia (a diferencia de hoy, ver ST-220);
    /// 3) `item.preparedURL == item.sourceURL` -- el mismo archivo, no
    ///    una tercera copia.
    func testImportingMP3FLACM4AInCopyModeLeavesTheFileReadyAndNothingInPreparados() async throws {
        let formats: [(name: String, ext: String, data: Data)] = [
            ("MP3", "mp3", MediaFixture.mp3Data(title: "Original", artist: "Artista Original",
                                                album: "Álbum Original", albumArtist: "Artista Original",
                                                year: "2020", genre: "Rock", trackNumber: 1)),
            ("FLAC", "flac", MediaFixture.flacData(title: "Original", artist: "Artista Original",
                                                   album: "Álbum Original", albumArtist: "Artista Original",
                                                   year: "2020", genre: "Rock", trackNumber: 1)),
            ("M4A", "m4a", try await MediaFixture.m4aData(title: "Original", artist: "Artista Original",
                                                          album: "Álbum Original")),
        ]

        for format in formats {
            try? FileManager.default.removeItem(at: libraryRoot)
            let sourceURL = try makeSource("pista.\(format.ext)", format.data)
            let (_, imported) = await importInCopyMode(sourceURL)
            let item = try XCTUnwrap(imported, "\(format.name): no quedó ningún elemento")

            // (1) el archivo está en Música/<Artista>/<Álbum>/
            XCTAssertTrue(item.sourceURL.path.contains("/Música/"), "\(format.name): \(item.sourceURL.path)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: item.sourceURL.path), format.name)
            XCTAssertEqual(item.storage, .copy, format.name)

            // (2) `.preparados/` no tiene nada de este ítem: en modo
            // copia ya no interviene.
            XCTAssertTrue(preparadosContents.isEmpty,
                          "\(format.name): `.preparados/` debería estar vacío y tiene \(preparadosContents)")

            // (3) el mismo archivo, no una tercera copia.
            XCTAssertEqual(item.preparedURL, item.sourceURL, format.name)

            // Y lleva las etiquetas del catálogo escritas adentro.
            let bytes = try Data(contentsOf: item.sourceURL)
            switch format.ext {
            case "flac":
                let comments = try XCTUnwrap(FLACTagReader.readVorbisComments(from: bytes))
                XCTAssertEqual(comments["TITLE"], item.metadata?.title)
                XCTAssertEqual(comments["ARTIST"], item.metadata?.artist)
            case "m4a":
                let atoms = MP4TagReader.readIlstAtoms(from: bytes)
                XCTAssertEqual(atoms["title"], item.metadata?.title)
                XCTAssertEqual(atoms["artist"], item.metadata?.artist)
            default:
                let asset = AVURLAsset(url: item.sourceURL)
                var title: String?
                for entry in try await asset.load(.metadata) where entry.commonKey == .commonKeyTitle {
                    title = try? await entry.load(.stringValue)
                }
                XCTAssertEqual(title, item.metadata?.title, format.name)
            }
        }
    }

    // MARK: - (b) Estrella/favorito/letra/categoría: 0 bytes en archivos de audio

    /// Forma de la prueba: con un ítem ya importado en modo copia,
    /// cambiar SOLO rating/favorito/letra/categoría (nunca título ni
    /// otro campo de etiqueta) y confirmar que el archivo de audio en
    /// `Música/` no cambia ni un byte (mismo hash antes/después) -- lo
    /// que cambia es el catálogo (`biblioteca.json`), `ratings.cfg`
    /// (rating), o el `.lrc` hermano (letra). Repetir para los cuatro
    /// campos por separado, no solo uno.
    func testRatingFavoriteLyricsAndCategoryNeverTouchTheAudioFile() async throws {
        let sourceURL = try makeSource("pista.mp3", MediaFixture.mp3Data(
            title: "Original", artist: "Artista Original", album: "Álbum Original",
            albumArtist: "Artista Original", year: "2020", genre: "Rock", trackNumber: 1))
        let (viewModel, imported) = await importInCopyMode(sourceURL)
        let item = try XCTUnwrap(imported)
        let libraryFile = item.sourceURL
        let hashBefore = try sha256(libraryFile)
        let modifiedBefore = try FileManager.default.attributesOfItem(atPath: libraryFile.path)[.modificationDate] as? Date

        // Los cuatro campos, uno por uno -- no vale medirlos juntos: si
        // solo uno de los cuatro tocara el archivo, medirlos en bloque
        // lo escondería.
        await viewModel.setRating(4, forItem: item.id)
        XCTAssertEqual(try sha256(libraryFile), hashBefore, "una estrella no puede tocar el archivo de audio")

        viewModel.setFavorite(true, forItems: [item.id])
        XCTAssertEqual(try sha256(libraryFile), hashBefore, "un favorito no puede tocar el archivo de audio")

        viewModel.setCategory("Recuerdos", forItem: item.id)
        XCTAssertEqual(try sha256(libraryFile), hashBefore, "una categoría no puede tocar el archivo de audio")

        // La letra viaja como `.lrc` hermano (ST-012), nunca dentro del
        // audio.
        var withLyrics = try XCTUnwrap(viewModel.items.first?.metadata)
        withLyrics.syncedLyrics = "[00:00.00] Una letra"
        await viewModel.applyReview(id: item.id, metadata: withLyrics)
        XCTAssertEqual(try sha256(libraryFile), hashBefore, "la letra no puede tocar el archivo de audio")
        let lrcURL = libraryFile.deletingPathExtension().appendingPathExtension("lrc")
        XCTAssertTrue(FileManager.default.fileExists(atPath: lrcURL.path), "la letra sí debe quedar como .lrc hermano")

        let modifiedAfter = try FileManager.default.attributesOfItem(atPath: libraryFile.path)[.modificationDate] as? Date
        XCTAssertEqual(modifiedBefore, modifiedAfter, "tampoco puede moverse la fecha de modificación")
    }

    // MARK: - (c) Editar título: solo el archivo de la biblioteca, delta ~ tamaño del tag

    /// Forma de la prueba: editar el título (un campo de etiqueta real)
    /// de un ítem en modo copia. Confirmar que SOLO cambia el archivo
    /// de `Música/` (nunca aparece nada en `.preparados/`) y que el
    /// delta de tamaño entre antes/después es del orden de unos pocos
    /// cientos de bytes (lo que pesa un tag reescrito), NO del orden
    /// del archivo de audio completo -- la diferencia central con hoy
    /// (ST-220: hoy CUALQUIER edición recopia el archivo entero a
    /// `.preparados/`).
    func testEditingTheTitleRewritesOnlyTheTagNotTheWholeFile() async throws {
        let sourceURL = try makeSource("pista.mp3", MediaFixture.mp3Data(
            title: "Original", artist: "Artista Original", album: "Álbum Original",
            albumArtist: "Artista Original", year: "2020", genre: "Rock", trackNumber: 1))
        let (viewModel, imported) = await importInCopyMode(sourceURL)
        let item = try XCTUnwrap(imported)
        let libraryFile = item.sourceURL
        let sizeBefore = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: libraryFile.path)[.size] as? Int)
        let hashBefore = try sha256(libraryFile)

        var edited = try XCTUnwrap(item.metadata)
        edited.title = "Título Editado"
        await viewModel.applyReview(id: item.id, metadata: edited)

        let sizeAfter = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: libraryFile.path)[.size] as? Int)
        XCTAssertNotEqual(try sha256(libraryFile), hashBefore, "el título editado sí tiene que llegar al archivo")
        XCTAssertLessThan(abs(sizeAfter - sizeBefore), 2048,
                          "el delta debe ser del orden de un tag reescrito, no del archivo entero (\(sizeBefore) -> \(sizeAfter))")
        XCTAssertTrue(preparadosContents.isEmpty,
                      "en modo copia no puede aparecer nada en `.preparados/`: \(preparadosContents)")

        // Y el archivo dice lo nuevo.
        let asset = AVURLAsset(url: libraryFile)
        var title: String?
        for entry in try await asset.load(.metadata) where entry.commonKey == .commonKeyTitle {
            title = try? await entry.load(.stringValue)
        }
        XCTAssertEqual(title, "Título Editado")
    }

    // MARK: - (d) Modo referencia: original intacto, preparado por UUID mayúsculas

    /// Forma de la prueba: en modo referencia (A4), el original (fuera
    /// de la biblioteca) nunca cambia -- ni al editar rating/favorito/
    /// letra/categoría NI al editar título (a diferencia de (c), que es
    /// modo copia). El preparado vive en `.preparados/<ID>.<ext>` con el
    /// UUID del ítem EN MAYÚSCULAS (contrato nuevo, fin de las
    /// colisiones por nombre base de ST-220 §1), y solo se regenera
    /// cuando cambia un campo que va en una etiqueta (título, artista,
    /// álbum, etc.) o el archivo de origen (tamaño+mtime) -- nunca por
    /// rating/favorito/letra/categoría, que no tocan el preparado.
    func testReferenceMode_originalNeverChanges_preparedIsUppercaseUUID_regeneratedOnlyOnTagFieldOrSourceChange_pendienteDeLaAPIDeA4() throws {
        throw XCTSkip("""
            Pendiente de la API real de A4 (modo referencia, ST-224). Forma: \
            importar en modo referencia, capturar SHA-256 del original. \
            Editar rating/favorito/letra/categoría uno por uno: el hash del \
            original no cambia NUNCA, y (a diferencia de (b)) tampoco debería \
            regenerar el preparado. Editar título: el hash del original \
            SIGUE sin cambiar, pero .preparados/<ID-en-mayúsculas>.<ext> SÍ se \
            regenera (nombre exacto: item.id.uuidString.uppercased() + \
            extensión). Tocar el archivo origen por fuera (cambiar tamaño+ \
            mtime sin que Aura lo sepa) y volver a procesar: el preparado \
            también se regenera. Sin tocar nada de lo anterior: el preparado \
            NO se regenera (comparado por mtime del archivo, no se reescribe \
            si nada relevante cambió).
            """)
    }

    // MARK: - (e) Sync: copia el archivo correcto según el modo

    /// Forma de la prueba: `LibrarySync.sync` real (como en ST-220),
    /// pero ahora con A3/A4 ya implementados -- confirmar por hash que
    /// lo que viaja al iPod sintético es item.sourceURL cuando el modo
    /// es copia (el archivo de Música/ ES el preparado, ya no hay
    /// `.preparados/` de por medio) y item.preparedURL cuando el modo
    /// es referencia (sin cambios respecto a ST-220 para ese modo).
    func testSyncCopiesTheLibraryFileInCopyModeAndThePreparedOneInReferenceMode() async throws {
        let data = MediaFixture.mp3Data(title: "Pista", artist: "Artista", album: "Álbum",
                                        albumArtist: "Artista", year: "2020", genre: "Rock", trackNumber: 1)

        // Modo copia: el archivo de Música/ ES el que viaja.
        let copySource = try makeSource("copia.mp3", data)
        let (_, copyImported) = await importInCopyMode(copySource)
        let copyItem = try XCTUnwrap(copyImported)
        XCTAssertEqual(copyItem.preparedURL, copyItem.sourceURL)
        XCTAssertTrue(preparadosContents.isEmpty, "\(preparadosContents)")

        // Modo referencia: el original no se toca y viaja el derivado.
        let referenceRoot = libraryRoot.appendingPathComponent("referencia", isDirectory: true)
        let referenceSource = try makeSource("referencia.mp3", data)
        let referenceHashBefore = try sha256(referenceSource)
        let referenceVM = LibraryViewModel(libraryRoot: referenceRoot,
                                           preferences: freshPreferences(copy: false))
        referenceVM.makePersistenceSynchronousForTesting()
        referenceVM.addDroppedFiles([referenceSource])
        await referenceVM.processAll()
        let referenceItem = try XCTUnwrap(referenceVM.items.first)
        XCTAssertEqual(referenceItem.sourceURL, referenceSource, "el original no se mueve")
        XCTAssertEqual(try sha256(referenceSource), referenceHashBefore, "el original no se toca")
        let preparedURL = try XCTUnwrap(referenceItem.preparedURL)
        XCTAssertNotEqual(preparedURL, referenceItem.sourceURL, "en referencia sí hay un derivado aparte")
        XCTAssertEqual(preparedURL.lastPathComponent, "\(referenceItem.id.uuidString).mp3",
                       "y se llama por el id del elemento (ST-221)")

        // Un iPod sintético para cada uno: lo que se comprueba es qué
        // archivo aterriza, no cómo se organizan entre sí.
        for (item, expectedURL, label) in [(copyItem, copyItem.sourceURL, "copia"),
                                           (referenceItem, preparedURL, "referencia")] {
            let ipodRoot = libraryRoot.appendingPathComponent("iPod-\(label)", isDirectory: true)
            try FileManager.default.createDirectory(at: ipodRoot, withIntermediateDirectories: true)
            let result = try LibrarySync(volumeRoot: ipodRoot).sync(items: [item])
            XCTAssertEqual(result.filesCopied, 1, label)

            let expectedHash = try sha256(expectedURL)
            let musicRoot = ipodRoot.appendingPathComponent("Music", isDirectory: true)
            let landed = ((try? FileManager.default.subpathsOfDirectory(atPath: musicRoot.path)) ?? [])
                .map { musicRoot.appendingPathComponent($0) }
                .filter { url in
                    var isDirectory: ObjCBool = false
                    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                        && !isDirectory.boolValue
                }
            XCTAssertTrue(landed.contains { (try? sha256($0)) == expectedHash },
                          "\(label): al iPod tenía que viajar \(expectedURL.lastPathComponent)")
        }
    }

    // MARK: - (f) WAV copiado se convierte a MP3 en Música/

    /// Forma de la prueba: importar un WAV sintético (`MediaFixture.
    /// wavData`) en modo copia -- por §0.2/§2, WAV (y AIFF) copiados se
    /// convierten a MP3 256 kbps al importar, con aviso en Ajustes. El
    /// archivo que queda en `Música/<Artista>/<Álbum>/` debe tener
    /// extensión `.mp3`, no `.wav`, y debe decodificar como MP3 real
    /// (frames MPEG válidos, no los bytes crudos del WAV). En modo
    /// referencia, sigue como hoy: el original WAV no se toca, el
    /// preparado convertido a MP3 vive en `.preparados/`.
    /// §0.2 y §2 del plan, **corregido por la maestra durante A3**: con
    /// "Mantener formato original", WAV y AIFF se convierten a **ALAC**
    /// (`.m4a`), no a MP3. Convertirlos a MP3 bajo un ajuste que se
    /// llama "mantener el formato original" era perder calidad a
    /// escondidas. A MP3 van con "Comprimido", como cualquier otro.
    func testWAVCopiedBecomesLosslessALACInMusica() async throws {
        let sourceURL = try makeSource("pista.wav", MediaFixture.wavData())
        let sourceHash = try sha256(sourceURL)

        let (_, imported) = await importInCopyMode(sourceURL)
        let item = try XCTUnwrap(imported)

        XCTAssertEqual(item.sourceURL.pathExtension, "m4a",
                       "un WAV copiado no se queda en WAV: \(item.sourceURL.lastPathComponent)")
        XCTAssertTrue(item.sourceURL.path.contains("/Música/"))
        XCTAssertEqual(item.storage, .copy)
        XCTAssertEqual(item.preparedURL, item.sourceURL)
        XCTAssertTrue(preparadosContents.isEmpty, "\(preparadosContents)")

        // El original del usuario, intacto.
        XCTAssertEqual(try sha256(sourceURL), sourceHash, "el WAV original no se toca nunca")

        // Y es ALAC de verdad, no un WAV renombrado.
        let tracks = try await AVURLAsset(url: item.sourceURL).loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(tracks.first)
        let descriptions = try await track.load(.formatDescriptions)
        let description = try XCTUnwrap(descriptions.first)
        let formatID = CMFormatDescriptionGetMediaSubType(description)
        XCTAssertEqual(formatID, kAudioFormatAppleLossless,
                       "el archivo de la biblioteca tiene que ser ALAC")
    }

    // MARK: - Conversión a ALAC (ST-223, §0.2 corregido)

    /// Sin pérdida quiere decir sin pérdida: las muestras decodificadas
    /// del ALAC tienen que ser **exactamente** las del WAV de origen. Es
    /// la única forma de comprobar la promesa de Ajustes; que el archivo
    /// exista y diga "ALAC" no prueba nada sobre el audio.
    func testWAVToALACKeepsTheSamplesExactly() async throws {
        let sourceURL = try makeSource("pista.wav", MediaFixture.wavData(seconds: 0.3))
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("alac-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try await AppleLosslessEncoder.encode(input: sourceURL, output: outputURL)

        let before = try await decodedPCM16(sourceURL)
        let after = try await decodedPCM16(outputURL)
        XCTAssertFalse(before.isEmpty, "control: el WAV de prueba tiene audio")
        XCTAssertEqual(after.count, before.count, "mismo número de muestras: nada de remuestrear")
        XCTAssertEqual(before, after, "ALAC es sin pérdida: las muestras tienen que ser idénticas")
    }

    /// Hallazgo de Windows durante A3: su perfil ALAC por defecto
    /// remuestreaba a 48 kHz, y el archivo decía "sin pérdida" con
    /// muestras que no eran las del usuario. Ninguna prueba de
    /// etiquetas, tamaño o existencia lo habría visto.
    ///
    /// Acá el formato de salida se arma **desde el de entrada** -- tasa,
    /// canales y bits se copian, con la única excepción de 8 → 16 bits,
    /// que es el mínimo que ALAC codifica. Esta prueba lo demuestra con
    /// un formato distinto del habitual: si algo estuviera fijado a
    /// 44,1 kHz estéreo, acá se vería.
    func testALACFollowsTheSourceFormatAndDoesNotPinOneOfItsOwn() async throws {
        let sourceURL = try makeSource("mono48.wav",
                                       MediaFixture.wavData(sampleRate: 48000, channels: 1, seconds: 0.25))
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("alac-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try await AppleLosslessEncoder.encode(input: sourceURL, output: outputURL)

        let tracks = try await AVURLAsset(url: outputURL).loadTracks(withMediaType: .audio)
        let descriptions = try await XCTUnwrap(tracks.first).load(.formatDescriptions)
        let basic = try XCTUnwrap(CMAudioFormatDescriptionGetStreamBasicDescription(
            try XCTUnwrap(descriptions.first))?.pointee)
        XCTAssertEqual(basic.mSampleRate, 48000, "la tasa de muestreo se copia del origen")
        XCTAssertEqual(basic.mChannelsPerFrame, 1, "y el número de canales también")

        let before = try await decodedPCM16(sourceURL)
        let after = try await decodedPCM16(outputURL)
        XCTAssertFalse(before.isEmpty, "control: el WAV de prueba tiene audio")
        XCTAssertEqual(after.count, before.count, "mismo número de bytes de PCM: nada de remuestrear")
        XCTAssertEqual(before, after)
    }

    /// AIFF, incluido el `sowt` de QuickTime -- que es PCM pero con los
    /// bytes en el orden de WAV. Darlo vuelta "para convertirlo"
    /// produciría ruido, la clase de defecto que se oye y no se ve.
    func testAIFFToALACKeepsTheSamplesExactlyIncludingSowt() async throws {
        for (name, isSowt) in [("clasico", false), ("sowt", true)] {
            let sourceURL = try makeSource("pista-\(name).aiff", Self.aiffData(sowt: isSowt))
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("alac-\(UUID().uuidString).m4a")
            defer { try? FileManager.default.removeItem(at: outputURL) }

            try await AppleLosslessEncoder.encode(input: sourceURL, output: outputURL)

            let before = try await decodedPCM16(sourceURL)
            let after = try await decodedPCM16(outputURL)
            XCTAssertFalse(before.isEmpty, "\(name): control, el AIFF de prueba tiene audio")
            XCTAssertEqual(after.count, before.count, "\(name): mismo número de muestras, nada de remuestrear")
            XCTAssertEqual(before, after, "\(name): las muestras tienen que ser idénticas")
        }
    }

    /// Un AIFF-C comprimido se rechaza con el motivo dicho. Convertirlo
    /// "funcionaría" -- AVFoundation lo decodifica -- y el resultado
    /// sería un ALAC sin pérdida de un audio que ya perdió calidad,
    /// vendido como sin pérdida y ocupando el triple.
    func testCompressedAIFFIsRejectedWithAReason() async throws {
        let sourceURL = try makeSource("comprimido.aiff", Self.aiffData(sowt: false, compression: "ima4"))
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("alac-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        do {
            try await AppleLosslessEncoder.encode(input: sourceURL, output: outputURL)
            XCTFail("un AIFF-C comprimido no se debe convertir")
        } catch let error as AppleLosslessEncoder.EncodeError {
            XCTAssertEqual(error, .compressedAIFFNotSupported("ima4"))
            XCTAssertTrue(error.errorDescription?.contains("comprimido") ?? false,
                          "el motivo tiene que decirlo: \(error.errorDescription ?? "nil")")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path),
                       "no puede quedar un archivo a medias")
    }

    /// El ALAC que queda en la biblioteca lleva las etiquetas del
    /// catálogo -- con `MP4TagWriter` de A2, que es justamente lo que
    /// permitió elegir ALAC en vez de MP3.
    func testTheALACInTheLibraryCarriesTheCatalogTags() async throws {
        let sourceURL = try makeSource("pista.wav", MediaFixture.wavData())
        let (viewModel, imported) = await importInCopyMode(sourceURL)
        let item = try XCTUnwrap(imported)

        var edited = try XCTUnwrap(item.metadata)
        edited.title = "Título del Catálogo"
        edited.artist = "Artista del Catálogo"
        edited.album = "Álbum del Catálogo"
        await viewModel.applyReview(id: item.id, metadata: edited)

        let atoms = MP4TagReader.readIlstAtoms(from: try Data(contentsOf: item.sourceURL))
        XCTAssertEqual(atoms["title"], "Título del Catálogo")
        XCTAssertEqual(atoms["artist"], "Artista del Catálogo")
        XCTAssertEqual(atoms["album"], "Álbum del Catálogo")
    }

    /// Una conversión que falla **no deja rastro**: ni el archivo en la
    /// biblioteca, ni el temporal `.aura-tmp`. Es la garantía que hace
    /// que la importación atómica sirva de algo.
    func testAFailedConversionLeavesNothingBehind() async throws {
        // Un ".wav" que no es un WAV: el codificador no lo puede leer.
        let sourceURL = try makeSource("roto.wav", Data(repeating: 0x5A, count: 4096))

        let (_, imported) = await importInCopyMode(sourceURL)
        let item = try XCTUnwrap(imported)

        if case .failed = item.status {} else {
            XCTFail("una conversión que falla tiene que dejar el elemento en estado fallido: \(item.status)")
        }
        let musicaDir = libraryRoot.appendingPathComponent(PersistedLibrary.musicDirName)
        let leftovers = FileManager.default.enumerator(at: musicaDir, includingPropertiesForKeys: nil)?
            .compactMap { ($0 as? URL)?.lastPathComponent }
            .filter { $0.hasSuffix(".aura-tmp") || $0.hasSuffix(".wav") || $0.hasSuffix(".m4a") } ?? []
        XCTAssertTrue(leftovers.isEmpty, "no puede quedar nada en la biblioteca: \(leftovers)")
        XCTAssertEqual(item.sourceURL, sourceURL, "el elemento sigue apuntando a su original")
    }

    /// El caso que la maestra pidió explícitamente: en una Mac **sin
    /// ffmpeg**, importar en copia con "Comprimido" falla con el motivo
    /// dicho y no deja nada. Se salta donde ffmpeg sí está instalado --
    /// decirlo es mejor que fingir que se probó.
    func testCompressedWithoutFFmpegFailsWithAReasonAndLeavesNothing() async throws {
        try XCTSkipUnless(FFmpegLocator.locate() == nil,
                          "esta máquina tiene ffmpeg instalado: el camino sin ffmpeg no se puede ejercitar acá")
        let sourceURL = try makeSource("pista.wav", MediaFixture.wavData())

        let (_, imported) = await importInCopyMode(sourceURL, quality: .compressed)
        let item = try XCTUnwrap(imported)

        if case .failed(let reason) = item.status {
            XCTAssertTrue(reason.lowercased().contains("ffmpeg"), "el motivo tiene que nombrarlo: \(reason)")
        } else {
            XCTFail("sin ffmpeg, importar en Comprimido tiene que fallar: \(item.status)")
        }
        XCTAssertEqual(item.sourceURL, sourceURL, "el WAV no puede haberse copiado sin convertir")
    }

    // MARK: - Andamio de audio

    /// Las muestras ya decodificadas a PCM de 16 bits, para comparar dos
    /// archivos por lo que suenan y no por cómo están armados.
    private func decodedPCM16(_ url: URL) async throws -> Data {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return Data() }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        guard reader.startReading() else { return Data() }
        var samples = Data()
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                              totalLengthOut: &length, dataPointerOut: &pointer) == noErr,
                  let pointer else { continue }
            samples.append(UnsafeBufferPointer(start: UnsafeRawPointer(pointer).assumingMemoryBound(to: UInt8.self),
                                               count: length))
        }
        return samples
    }

    /// Un AIFF de verdad, armado a mano: `FORM`/`COMM`/`SSND` con una
    /// onda sencilla. Con `sowt` sale un AIFF-C cuyas muestras van en el
    /// orden de WAV (lo que escribe QuickTime), y con `compression` se
    /// puede fabricar el AIFF-C comprimido que hay que rechazar.
    private static func aiffData(sowt: Bool, compression: String? = nil,
                                 frames: Int = 4410, channels: Int = 2, sampleRate: Int = 44100) -> Data {
        func be16(_ v: Int) -> [UInt8] { [UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }
        func be32(_ v: Int) -> [UInt8] {
            [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
        }
        /// La tasa de muestreo va como coma flotante extendida de 80
        /// bits, que es lo único incómodo del formato.
        func extended80(_ value: Int) -> [UInt8] {
            var exponent = 16383 + 63
            var mantissa = UInt64(value)
            while mantissa & 0x8000_0000_0000_0000 == 0 && mantissa != 0 {
                mantissa <<= 1
                exponent -= 1
            }
            var out = be16(exponent)
            for shift in stride(from: 56, through: 0, by: -8) { out.append(UInt8((mantissa >> UInt64(shift)) & 0xFF)) }
            return out
        }

        let isAIFC = sowt || compression != nil
        let compressionType = compression ?? (sowt ? "sowt" : "NONE")

        var samples: [UInt8] = []
        for frame in 0..<frames {
            let value = Int16(truncatingIfNeeded: (frame % 512) * 60 - 15360)
            for _ in 0..<channels {
                // AIFF clásico guarda big-endian; `sowt` little-endian.
                samples += sowt
                    ? [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)]
                    : [UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
            }
        }

        var comm: [UInt8] = []
        comm += be16(channels)
        comm += be32(frames)
        comm += be16(16)
        comm += extended80(sampleRate)
        if isAIFC {
            comm += Array(compressionType.utf8)
            comm += [0x00, 0x00] // nombre legible vacío (pascal string + relleno)
        }

        var ssnd: [UInt8] = be32(0) + be32(0) + samples

        var body: [UInt8] = Array((isAIFC ? "AIFC" : "AIFF").utf8)
        if isAIFC {
            // `FVER` es obligatorio en AIFF-C.
            body += Array("FVER".utf8) + be32(4) + be32(0xA2805140)
        }
        body += Array("COMM".utf8) + be32(comm.count) + comm
        if comm.count % 2 == 1 { body.append(0) }
        body += Array("SSND".utf8) + be32(ssnd.count) + ssnd
        if ssnd.count % 2 == 1 { body.append(0) }

        return Data(Array("FORM".utf8) + be32(body.count) + body)
    }
}
