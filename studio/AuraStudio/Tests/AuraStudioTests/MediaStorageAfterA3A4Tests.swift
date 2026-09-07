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
final class MediaStorageAfterA3A4Tests: XCTestCase {
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("MediaStorageAfterA3A4-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
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
    func testImportingMP3FLACM4AInCopyMode_fileIsReadyNoPreparados_pendienteDeLaAPIDeA3() throws {
        throw XCTSkip("""
            Pendiente de la API real de A3 (modo copia = preparado, ST-223). \
            Forma: importar MediaFixture.{mp3,flac,m4a}Data con el importador \
            real de A3, en modo copia. Confirmar (1) Música/<Artista>/<Álbum>/ \
            tiene el archivo con las etiquetas del catálogo ya escritas \
            (releído con ID3Writer/FLACTagReader/MP4TagReader); (2) .preparados/ \
            no tiene ninguna entrada para este ítem; (3) item.preparedURL == \
            item.sourceURL exactamente (mismo archivo, no una copia más).
            """)
    }

    // MARK: - (b) Estrella/favorito/letra/categoría: 0 bytes en archivos de audio

    /// Forma de la prueba: con un ítem ya importado en modo copia,
    /// cambiar SOLO rating/favorito/letra/categoría (nunca título ni
    /// otro campo de etiqueta) y confirmar que el archivo de audio en
    /// `Música/` no cambia ni un byte (mismo hash antes/después) -- lo
    /// que cambia es el catálogo (`biblioteca.json`), `ratings.cfg`
    /// (rating), o el `.lrc` hermano (letra). Repetir para los cuatro
    /// campos por separado, no solo uno.
    func testRatingFavoriteLyricsCategory_writeZeroBytesToAudioFile_pendienteDeLaAPIDeA3() throws {
        throw XCTSkip("""
            Pendiente de la API real de A3 (ST-223). Forma: importar en modo \
            copia, capturar SHA-256 del archivo en Música/, aplicar cada \
            cambio por separado -- rating, isFavorite, syncedLyrics, category \
            -- con la API real de edición. Confirmar en cada caso que el hash \
            del archivo de audio en Música/ NO cambió; solo debe cambiar \
            biblioteca.json (rating/favorito/categoría) o aparecer/actualizarse \
            el .lrc hermano (letra) -- nunca el propio archivo de audio.
            """)
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
    func testEditingTitleInCopyMode_onlyLibraryFileChanges_deltaIsTagSizeNotWholeFile_pendienteDeLaAPIDeA3() throws {
        throw XCTSkip("""
            Pendiente de la API real de A3 (ST-223). Forma: importar en modo \
            copia (MediaFixture.mp3Data, por ejemplo, con audio real de \
            tamaño conocido -- varios KB de frames), medir el tamaño del \
            archivo en Música/ antes de editar, editar SOLO el título con la \
            API real, medir el tamaño después. El delta absoluto debe ser \
            pequeño (cientos de bytes, el tamaño de un tag reescrito) --  \
            XCTAssertLessThan(abs(delta), 2048) es un umbral razonable a \
            falta de un número exacto; el punto es que NO sea del orden del \
            tamaño del audio (que en este fixture es varios KB). Y \
            .preparados/ debe seguir vacío para este ítem (sigue siendo (a)).
            """)
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
    func testSyncCopiesLibraryFileInCopyModeOrPreparedInReferenceMode_verifiedByHash_pendienteDeLaAPIDeA3YA4() throws {
        throw XCTSkip("""
            Pendiente de las API reales de A3 y A4 (ST-223/ST-224). Forma: \
            igual que testSyncCopiesThePreparedFileNeverTheOriginal (ST-220), \
            pero con un ítem en modo copia y otro en modo referencia. Para \
            el de modo copia: el archivo que aterriza en el iPod sintético \
            debe tener el mismo hash que item.sourceURL (Música/), no un \
            .preparados/ que ya no debería existir para ese ítem. Para el de \
            modo referencia: el mismo hash que item.preparedURL, sin cambios \
            respecto a la prueba de ST-220.
            """)
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
    func testWAVCopiedBecomesMP3InMusica_pendienteDeLaAPIDeA3() throws {
        throw XCTSkip("""
            Pendiente de la API real de A3 (conversión WAV/AIFF -> MP3 al \
            copiar, ST-223, §0.2/§2 del plan). Forma: importar MediaFixture. \
            wavData() en modo copia, confirmar que el archivo resultante en \
            Música/<Artista>/<Álbum>/ tiene extensión .mp3 (no .wav) y que \
            sus primeros bytes son un frame MPEG válido (sync 0xFFEx/0xFFFx), \
            no la cabecera RIFF/WAVE del original. En modo referencia: el \
            WAV original sigue intacto (mismo hash), y .preparados/ tiene la \
            versión convertida a MP3 -- sin cambios respecto a como ya \
            funciona hoy para WAV (ST-220).
            """)
    }
}
