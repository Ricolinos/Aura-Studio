import XCTest
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

    // MARK: - Pendiente: cuando el escritor real de A2 exista

    /// Deliberadamente `throw XCTSkip` -- no hay todavía una firma que
    /// llamar. Documenta la forma exacta de la prueba de ida y vuelta
    /// que A2 necesita, para que llenarla sea sustituir un bloque y
    /// correr, no diseñar de cero: escribir con el escritor real de
    /// Opus sobre el fixture (`MediaFixture.flacData`/`m4aData`, que ya
    /// producen archivos válidos y legibles), releer con
    /// `FLACTagReader`/`MP4TagReader` (bytes crudos, no confía en que
    /// AVFoundation perdone un escritor que dejó algo mal armado) y con
    /// `AVURLAsset.load(.metadata)` (el camino que de verdad usa
    /// `LocalTagReader` en producción) -- las tres lecturas deben
    /// coincidir entre sí y con los campos editados.
    func testFLACWriterRoundTrip_pendienteDeLaFirmaDeA2() throws {
        throw XCTSkip("""
            Pendiente de la firma real del escritor FLAC (ST-222). Forma \
            de la prueba cuando exista: 1) generar con MediaFixture.flacData \
            un FLAC base; 2) escribir campos editados con el escritor real de \
            A2 sobre una copia; 3) FLACTagReader.readVorbisComments(from:) y \
            AVURLAsset.load(.metadata) deben mostrar los campos editados, \
            nunca los originales; 4) el bloque STREAMINFO no debe cambiar \
            (mismo audio, solo cambian los tags).
            """)
    }

    func testM4AWriterRoundTrip_pendienteDeLaFirmaDeA2() throws {
        throw XCTSkip("""
            Pendiente de la firma real del escritor M4A (ST-222). Misma \
            forma que el de FLAC: MediaFixture.m4aData como base, el \
            escritor real de A2 sobre una copia, MP4TagReader.readIlstAtoms(from:) \
            y AVURLAsset.load(.metadata) deben coincidir en los campos \
            editados; la pista de audio (moov/trak) no debe cambiar.
            """)
    }
}
