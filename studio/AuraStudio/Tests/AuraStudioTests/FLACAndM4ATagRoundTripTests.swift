import XCTest
import AVFoundation
@testable import AuraStudio

/// PLAN-studio-ajustes-3.md, Fase A2 (ST-222): preparado por encargo de
/// "Sesión Maestra" para cuando "experto en código opus" anuncie la
/// firma de sus escritores nativos de FLAC/M4A -- el lado de LECTURA
/// (por bytes crudos, `FLACTagReader`/`MP4TagReader`, y por
/// AVFoundation) ya queda armado y probado contra el fixture actual.
/// Cuando la firma real exista, sustituir la generación del fixture de
/// abajo por una llamada al escritor real es el único cambio que hace
/// falta -- las aserciones de lectura no cambian.
final class FLACAndM4ATagRoundTripTests: XCTestCase {
    private var scratchDir: URL!

    override func setUpWithError() throws {
        scratchDir = FileManager.default.temporaryDirectory.appendingPathComponent("FLACM4ARoundTrip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratchDir)
    }

    // MARK: - El lector propio (bytes crudos) contra el fixture de hoy

    /// Confirma que `FLACTagReader` (nuestro parser de VORBIS_COMMENT,
    /// sin AVFoundation) lee de vuelta exactamente lo que
    /// `MediaFixture.flacData` escribió -- la mitad "lectura" de la
    /// verificación de ida y vuelta que A2 va a necesitar, ya lista.
    func testFLACTagReaderReadsBackWhatTheFixtureWrote() throws {
        let data = MediaFixture.flacData(title: "Título de Prueba", artist: "Artista de Prueba",
                                         album: "Álbum de Prueba", albumArtist: "Artista Álbum",
                                         year: "2026", genre: "Electrónica", trackNumber: 7)
        let comments = try XCTUnwrap(FLACTagReader.readVorbisComments(from: data))
        XCTAssertEqual(comments["TITLE"], "Título de Prueba")
        XCTAssertEqual(comments["ARTIST"], "Artista de Prueba")
        XCTAssertEqual(comments["ALBUM"], "Álbum de Prueba")
        XCTAssertEqual(comments["ALBUMARTIST"], "Artista Álbum")
        XCTAssertEqual(comments["DATE"], "2026")
        XCTAssertEqual(comments["GENRE"], "Electrónica")
        XCTAssertEqual(comments["TRACKNUMBER"], "7")
    }

    /// Lo mismo, pero por `MP4TagReader` (bytes crudos de `ilst`) contra
    /// el M4A que ya escribe `MediaFixture.m4aData` vía `AVAssetWriter`
    /// -- confirma que el lector entiende la jerarquía real
    /// `moov/udta/meta/ilst` que produce el escritor de Apple, no solo
    /// una estructura inventada por la propia prueba.
    func testMP4TagReaderReadsBackWhatTheFixtureWrote() async throws {
        let data = try await MediaFixture.m4aData(title: "Título M4A", artist: "Artista M4A", album: "Álbum M4A")
        let atoms = MP4TagReader.readIlstAtoms(from: data)
        XCTAssertEqual(atoms["title"], "Título M4A")
        XCTAssertEqual(atoms["artist"], "Artista M4A")
        XCTAssertEqual(atoms["album"], "Álbum M4A")
    }

    // MARK: - FLAC: la ida y vuelta de verdad (ST-222)

    /// Un FLAC con más de lo mínimo: STREAMINFO, un SEEKTABLE, un
    /// VORBIS_COMMENT viejo, padding, y bytes de "audio" después del
    /// último bloque. El fixture compartido no tiene ni seektable ni
    /// padding ni audio, y son justo las tres cosas que el escritor
    /// tiene que dejar en paz.
    private func flacWithBlocksAndAudio() -> (file: Data, audio: Data) {
        let base = MediaFixture.flacData(title: "Viejo", artist: "Viejo", album: "Viejo",
                                         albumArtist: "Viejo", year: "1999", genre: "Viejo",
                                         trackNumber: 1)
        let layout = FLACTagReader.metadataBlockLayout(from: base)!
        // El fixture trae STREAMINFO + VORBIS_COMMENT; se rearma con un
        // SEEKTABLE y un PADDING en medio.
        var out = Data("fLaC".utf8)
        var offset = 4
        var streamInfo = Data()
        var vorbis = Data()
        for (type, length) in layout {
            let payload = base.subdata(in: (offset + 4)..<(offset + 4 + length))
            if type == 0 { streamInfo = payload } else if type == 4 { vorbis = payload }
            offset += 4 + length
        }
        let seekTable = Data(repeating: 0xAB, count: 36) // 2 puntos de búsqueda
        let padding = Data(repeating: 0, count: 512)

        func block(_ type: UInt8, _ payload: Data, last: Bool) -> Data {
            var out = Data([last ? (type | 0x80) : type])
            let length = UInt32(payload.count)
            out.append(UInt8((length >> 16) & 0xFF))
            out.append(UInt8((length >> 8) & 0xFF))
            out.append(UInt8(length & 0xFF))
            return out + payload
        }
        out += block(0, streamInfo, last: false)
        out += block(3, seekTable, last: false)
        out += block(4, vorbis, last: false)
        out += block(1, padding, last: true)

        let audio = Data((0..<2048).map { UInt8($0 % 251) })
        return (out + audio, audio)
    }

    private var editedTag: AudioTag {
        AudioTag(title: "Título Nuevo", artist: "Artista Nuevo", album: "Álbum Nuevo",
                 albumArtist: "Artista del Álbum", year: "2026", genre: "Electrónica",
                 composer: "Compositor", trackNumber: 4, discNumber: 2)
    }

    func testFLACWriterRoundTripsThroughOurReader() throws {
        let (original, _) = flacWithBlocksAndAudio()

        let written = try FLACTagWriter.writing(editedTag, into: original)

        let comments = try XCTUnwrap(FLACTagReader.readVorbisComments(from: written))
        XCTAssertEqual(comments["TITLE"], "Título Nuevo")
        XCTAssertEqual(comments["ARTIST"], "Artista Nuevo")
        XCTAssertEqual(comments["ALBUM"], "Álbum Nuevo")
        XCTAssertEqual(comments["ALBUMARTIST"], "Artista del Álbum")
        XCTAssertEqual(comments["DATE"], "2026")
        XCTAssertEqual(comments["GENRE"], "Electrónica")
        XCTAssertEqual(comments["COMPOSER"], "Compositor")
        XCTAssertEqual(comments["TRACKNUMBER"], "4")
        XCTAssertEqual(comments["DISCNUMBER"], "2")
        XCTAssertNil(comments["TITLE"].map { $0 == "Viejo" ? $0 : nil } ?? nil,
                     "no puede quedar rastro del comentario anterior")
    }

    /// La lectura que de verdad usa la app en producción
    /// (`LocalTagReader` va por AVFoundation) tiene que ver lo mismo que
    /// nuestro parser de bytes crudos. Si difieren, el escritor armó algo
    /// que solo uno de los dos perdona.
    func testFLACWriterRoundTripsThroughAVFoundation() async throws {
        let (original, _) = flacWithBlocksAndAudio()
        let written = try FLACTagWriter.writing(editedTag, into: original)
        let url = scratchDir.appendingPathComponent("etiquetado.flac")
        try written.write(to: url)

        let metadata = try await AVURLAsset(url: url).load(.metadata)
        let values = try await withThrowingTaskGroup(of: (String, String?).self) { group -> [String: String] in
            for item in metadata {
                group.addTask {
                    let key = (item.key as? String) ?? item.identifier?.rawValue ?? ""
                    return (key.uppercased(), try await item.load(.stringValue))
                }
            }
            var result: [String: String] = [:]
            for try await (key, value) in group {
                if let value { result[key] = value }
            }
            return result
        }

        XCTAssertTrue(values.values.contains("Título Nuevo"), "AVFoundation debe ver el título nuevo: \(values)")
        XCTAssertTrue(values.values.contains("Artista Nuevo"), "AVFoundation debe ver el artista nuevo: \(values)")
        XCTAssertFalse(values.values.contains("Viejo"), "no puede quedar nada del anterior: \(values)")
    }

    /// El punto entero del escritor nativo: el audio del usuario no se
    /// toca. Ni un byte.
    func testFLACWriterLeavesTheAudioAndStreamInfoUntouched() throws {
        let (original, audio) = flacWithBlocksAndAudio()

        let written = try FLACTagWriter.writing(editedTag, into: original)

        let audioStart = try XCTUnwrap(FLACTagReader.audioStartOffset(from: written))
        XCTAssertEqual(written.subdata(in: audioStart..<written.count), audio,
                       "los fotogramas de audio se copian byte a byte")

        func streamInfo(_ data: Data) -> Data {
            let layout = FLACTagReader.metadataBlockLayout(from: data)!
            var offset = 4
            for (type, length) in layout {
                if type == 0 { return data.subdata(in: (offset + 4)..<(offset + 4 + length)) }
                offset += 4 + length
            }
            return Data()
        }
        XCTAssertEqual(streamInfo(written), streamInfo(original), "STREAMINFO no es nuestro y no se toca")
    }

    func testFLACWriterPreservesSeekTableAndPadding() throws {
        let (original, _) = flacWithBlocksAndAudio()

        let written = try FLACTagWriter.writing(editedTag, into: original)

        let layout = try XCTUnwrap(FLACTagReader.metadataBlockLayout(from: written))
        XCTAssertEqual(layout.first?.type, 0, "STREAMINFO tiene que seguir siendo el primero")
        let seekTables = layout.filter { $0.type == 3 }
        XCTAssertEqual(seekTables.count, 1)
        XCTAssertEqual(seekTables.first?.length, 36, "el SEEKTABLE pasa entero")
        XCTAssertEqual(layout.filter { $0.type == 1 }.map(\.length), [512], "el padding se conserva, en un solo bloque")
        XCTAssertEqual(layout.last?.type, 1, "y queda al final, que es donde sirve")
        XCTAssertEqual(layout.filter { $0.type == 4 }.count, 1, "un solo VORBIS_COMMENT, no dos")
    }

    func testFLACWriterEmbedsTheCoverAsAFrontCoverPicture() throws {
        let (original, _) = flacWithBlocksAndAudio()
        let cover = MediaFixture.jpegData(seed: 7)
        var tag = editedTag
        tag.coverArtData = cover

        let written = try FLACTagWriter.writing(tag, into: original)

        let picture = try XCTUnwrap(FLACTagReader.readPicture(from: written))
        XCTAssertEqual(picture.pictureType, 3, "3 = portada frontal")
        XCTAssertEqual(picture.mimeType, "image/jpeg")
        XCTAssertEqual(picture.imageData, cover, "la carátula viaja entera")
    }

    /// Un `.flac` que en realidad es Ogg no se toca: decir que no es
    /// mejor que escribir algo que el archivo no sabe leer.
    func testFLACWriterRefusesAFileThatIsNotNativeFLAC() {
        let ogg = Data("OggS".utf8) + Data(repeating: 0, count: 64)
        XCTAssertThrowsError(try FLACTagWriter.writing(editedTag, into: ogg)) { error in
            XCTAssertEqual(error as? FLACTagWriter.WriterError, .notANativeFLAC)
        }
    }

    /// Escribir dos veces lo mismo da el mismo archivo -- que es lo que
    /// hace que `write(_:toFileAt:)` pueda no tocar el disco y no
    /// moverle la fecha de modificación a la canción.
    func testFLACWriterIsIdempotent() throws {
        let (original, _) = flacWithBlocksAndAudio()

        let once = try FLACTagWriter.writing(editedTag, into: original)
        let twice = try FLACTagWriter.writing(editedTag, into: once)

        XCTAssertEqual(once, twice)
    }

    // MARK: - M4A

    func testM4AWriterRoundTripsThroughOurReader() async throws {
        let original = try await MediaFixture.m4aData(title: "Viejo", artist: "Viejo", album: "Viejo")

        let written = try MP4TagWriter.writing(editedTag, into: original)

        let atoms = MP4TagReader.readIlstAtoms(from: written)
        XCTAssertEqual(atoms["title"], "Título Nuevo")
        XCTAssertEqual(atoms["artist"], "Artista Nuevo")
        XCTAssertEqual(atoms["album"], "Álbum Nuevo")
        XCTAssertEqual(atoms["albumArtist"], "Artista del Álbum")
        XCTAssertEqual(atoms["year"], "2026")
        XCTAssertEqual(atoms["genre"], "Electrónica")
        XCTAssertEqual(atoms["composer"], "Compositor")
        let numbers = MP4TagReader.readTrackAndDisc(from: written)
        XCTAssertEqual(numbers.track, 4)
        XCTAssertEqual(numbers.disc, 2)
    }

    func testM4AWriterRoundTripsThroughAVFoundation() async throws {
        let original = try await MediaFixture.m4aData(title: "Viejo", artist: "Viejo", album: "Viejo")
        let written = try MP4TagWriter.writing(editedTag, into: original)
        let url = scratchDir.appendingPathComponent("etiquetado.m4a")
        try written.write(to: url)

        let metadata = try await AVURLAsset(url: url).load(.metadata)
        var values: [String] = []
        for item in metadata {
            if let value = try await item.load(.stringValue) { values.append(value) }
        }

        XCTAssertTrue(values.contains("Título Nuevo"), "AVFoundation debe ver el título nuevo: \(values)")
        XCTAssertTrue(values.contains("Artista Nuevo"))
        XCTAssertTrue(values.contains("Álbum Nuevo"))
        XCTAssertFalse(values.contains("Viejo"), "no puede quedar nada del anterior: \(values)")
    }

    func testM4AWriterEmbedsTheCover() async throws {
        let original = try await MediaFixture.m4aData(title: "Viejo", artist: "Viejo", album: "Viejo")
        let cover = MediaFixture.jpegData(seed: 3)
        var tag = editedTag
        tag.coverArtData = cover

        let written = try MP4TagWriter.writing(tag, into: original)

        let stored = try XCTUnwrap(MP4TagReader.readCoverArt(from: written))
        XCTAssertEqual(stored.typeIndicator, 13, "13 = JPEG; es cómo el lector sabe qué decodifica")
        XCTAssertEqual(stored.imageData, cover)
    }

    /// Los átomos que no gobierna el catálogo (los que pone iTunes o el
    /// codificador) no son nuestros y no se tiran.
    func testM4AWriterKeepsAtomsItDoesNotManage() async throws {
        let original = try await MediaFixture.m4aData(title: "Viejo", artist: "Viejo", album: "Viejo")
        let before = Set(MP4TagReader.ilstAtomTypes(from: original))
        let unmanaged = before.subtracting(["\u{A9}nam", "\u{A9}ART", "\u{A9}alb", "aART",
                                            "\u{A9}day", "\u{A9}gen", "\u{A9}wrt", "trkn", "disk", "covr"])

        let written = try MP4TagWriter.writing(editedTag, into: original)

        let after = Set(MP4TagReader.ilstAtomTypes(from: written))
        XCTAssertTrue(unmanaged.isSubset(of: after),
                      "se perdieron átomos ajenos: \(unmanaged.subtracting(after))")
    }

    /// El audio decodificado no cambia. Es la verificación que importa:
    /// un `stco` mal corregido produce un archivo que abre sin error y
    /// suena mal, así que comprobar la estructura no alcanza.
    func testM4AWriterKeepsTheDecodedAudioIdentical() async throws {
        let original = try await MediaFixture.m4aData(title: "Viejo", artist: "Viejo", album: "Viejo")
        let written = try MP4TagWriter.writing(editedTag, into: original)

        let before = try await decodedSamples(of: original, extension: "m4a")
        let after = try await decodedSamples(of: written, extension: "m4a")
        XCTAssertFalse(before.isEmpty, "control: el fixture tiene audio de verdad")
        XCTAssertEqual(before, after, "las muestras decodificadas no pueden cambiar al etiquetar")
    }

    /// El caso peligroso, y el único en que `stco` importa: `moov`
    /// ANTES de `mdat` (un archivo optimizado para red). Al crecer las
    /// etiquetas, todo el audio se corre; sin corregir los
    /// desplazamientos, el archivo sigue abriendo y suena mal.
    func testM4AWriterPatchesChunkOffsetsWhenMoovIsBeforeMdat() async throws {
        let fastStart = try await fastStartM4A(title: "Viejo", artist: "Viejo", album: "Viejo")
        try XCTSkipIf(fastStart == nil, "no se pudo producir un M4A con moov antes de mdat en esta máquina")
        let original = try XCTUnwrap(fastStart)
        XCTAssertLessThan(try XCTUnwrap(topLevelBoxStart("moov", in: original)),
                          try XCTUnwrap(topLevelBoxStart("mdat", in: original)),
                          "control: este fixture tiene que tener moov antes de mdat")

        let written = try MP4TagWriter.writing(editedTag, into: original)
        XCTAssertGreaterThan(written.count, original.count, "control: las etiquetas nuevas hacen crecer el moov")

        let before = try await decodedSamples(of: original, extension: "m4a")
        let after = try await decodedSamples(of: written, extension: "m4a")
        XCTAssertFalse(before.isEmpty, "control: el fixture tiene audio de verdad")
        XCTAssertEqual(before, after, "con moov antes de mdat, los stco/co64 tienen que quedar corregidos")
    }

    // MARK: - El despachador por formato

    func testWavAndAiffAreNotTaggedAndSayWhy() throws {
        let url = scratchDir.appendingPathComponent("x.wav")
        try MediaFixture.wavData().write(to: url)
        let bytesBefore = try Data(contentsOf: url)

        let result = LocalTagWriter.write(editedTag, toFileAt: url)

        XCTAssertFalse(result.written)
        XCTAssertEqual(try Data(contentsOf: url), bytesBefore, "un formato que no se etiqueta no se toca")
        XCTAssertTrue(result.reason?.contains(".wav") ?? false, "el motivo tiene que decir cuál es: \(result.reason ?? "nil")")
    }

    func testAnEmptyTagNeverTouchesTheFile() throws {
        let (original, _) = flacWithBlocksAndAudio()
        let url = scratchDir.appendingPathComponent("x.flac")
        try original.write(to: url)

        let result = LocalTagWriter.write(AudioTag(), toFileAt: url)

        XCTAssertFalse(result.written)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testTheDispatcherPicksTheRightWriterForEachFormat() throws {
        let flacURL = scratchDir.appendingPathComponent("a.flac")
        try flacWithBlocksAndAudio().file.write(to: flacURL)
        XCTAssertTrue(LocalTagWriter.write(editedTag, toFileAt: flacURL).written)
        XCTAssertEqual(FLACTagReader.readVorbisComments(from: try Data(contentsOf: flacURL))?["TITLE"], "Título Nuevo")

        let mp3URL = scratchDir.appendingPathComponent("a.mp3")
        try MediaFixture.mp3Data(title: "Viejo", artist: "Viejo", album: "Viejo",
                                 albumArtist: "Viejo", year: "1999", genre: "Viejo",
                                 trackNumber: 1).write(to: mp3URL)
        XCTAssertTrue(LocalTagWriter.write(editedTag, toFileAt: mp3URL).written)
    }

    // MARK: - Andamio

    /// Un M4A con `moov` antes de `mdat`, que es lo que produce
    /// `shouldOptimizeForNetworkUse`. Se pide a AVFoundation en vez de
    /// reordenar las cajas a mano: reordenarlas requeriría la misma
    /// aritmética de desplazamientos que esta prueba viene a verificar,
    /// y entonces no verificaría nada.
    private func fastStartM4A(title: String, artist: String, album: String) async throws -> Data? {
        let sourceURL = scratchDir.appendingPathComponent("origen.m4a")
        try await MediaFixture.m4aData(title: title, artist: artist, album: album).write(to: sourceURL)
        let outputURL = scratchDir.appendingPathComponent("faststart-\(UUID().uuidString).m4a")

        let asset = AVURLAsset(url: sourceURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            return nil
        }
        session.outputURL = outputURL
        session.outputFileType = .m4a
        session.shouldOptimizeForNetworkUse = true
        await session.export()
        guard session.status == .completed else { return nil }
        let data = try Data(contentsOf: outputURL)
        guard let moov = topLevelBoxStart("moov", in: data), let mdat = topLevelBoxStart("mdat", in: data),
              moov < mdat else { return nil }
        return data
    }

    /// Recorrido mínimo de cajas de nivel superior -- lo justo para
    /// saber en qué orden quedaron `moov` y `mdat`.
    private func topLevelBoxStart(_ type: String, in data: Data) -> Int? {
        var offset = 0
        while offset + 8 <= data.count {
            let size32 = data.subdata(in: offset..<(offset + 4)).reduce(0) { ($0 << 8) | Int($1) }
            let boxType = String(data: data.subdata(in: (offset + 4)..<(offset + 8)), encoding: .isoLatin1) ?? ""
            let size: Int
            if size32 == 1 {
                guard offset + 16 <= data.count else { return nil }
                size = data.subdata(in: (offset + 8)..<(offset + 16)).reduce(0) { ($0 << 8) | Int($1) }
            } else if size32 == 0 {
                size = data.count - offset
            } else {
                size = size32
            }
            if boxType == type { return offset }
            guard size >= 8 else { return nil }
            offset += size
        }
        return nil
    }

    /// Las muestras de audio ya decodificadas, para comparar dos
    /// archivos por lo que suenan y no por cómo están armados.
    private func decodedSamples(of data: Data, extension ext: String) async throws -> Data {
        let url = scratchDir.appendingPathComponent("decodificar-\(UUID().uuidString).\(ext)")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

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
            guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { continue }
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                                              totalLengthOut: &length, dataPointerOut: &pointer) == noErr,
                  let pointer else { continue }
            samples.append(UnsafeBufferPointer(start: UnsafeRawPointer(pointer).assumingMemoryBound(to: UInt8.self),
                                               count: length))
        }
        return samples
    }
}
