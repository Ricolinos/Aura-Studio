import XCTest
@testable import AuraStudio

/// PLAN-studio-ajustes-3.md §2/§4 (A5 eliminar/limpiar huérfanos/
/// deduplicar, A6 migración de bibliotecas anteriores, ST-225/ST-226).
/// Encargo de "Sesión Maestra" mientras "experto en código opus" cierra
/// A3/A4: la forma exacta de las pruebas "después", mismo estilo que
/// `MediaStorageAfterA3A4Tests` (ST-223/ST-224) -- todas `throw
/// XCTSkip`, porque la API todavía no existe. Cuando cada API exista,
/// llenar el cuerpo sustituye el `XCTSkip` por las aserciones que ya
/// están descritas acá -- no hace falta rediseñar la prueba.
///
/// El fixture de A0 (`MediaFixture`) sigue sirviendo tal cual para
/// armar los ítems de estas pruebas en cuanto se llenen.
final class MediaStorageAfterA5A6Tests: XCTestCase {
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("MediaStorageAfterA5A6-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    // MARK: - (a) Eliminar en modo copia: Papelera + fuera del catálogo

    /// Forma de la prueba: con un ítem importado en modo copia (A3),
    /// eliminarlo con la API real de A5 y confirmar DOS cosas: 1) el
    /// archivo que estaba en `Música/<Artista>/<Álbum>/` ya NO existe
    /// ahí -- viajó a la Papelera del sistema (verificable por su
    /// ausencia en la ruta original; confirmar que aterrizó en la
    /// Papelera de verdad requiere `FileManager.trashItem` o
    /// equivalente, cuyo resultado hay que capturar en el momento real
    /// de borrar, no reconstruirlo después); 2) el ítem ya no aparece en
    /// `viewModel.items` ni en `biblioteca.json` tras persistir. La
    /// confirmación previa al usuario (el diálogo "¿Enviar a la
    /// Papelera?") es responsabilidad de la vista, no de esta prueba --
    /// acá se mide el resultado de la acción ya confirmada.
    func testDeletingInCopyModeSendsToTrashAndRemovesFromCatalog_pendienteDeLaAPIDeA5() throws {
        throw XCTSkip("""
            Pendiente de la API real de A5 (eliminar, ST-225). Forma: importar en modo \
            copia, capturar la ruta del archivo en Música/, eliminar el ítem con la API \
            real. Confirmar (1) el archivo ya no existe en esa ruta y el resultado de la \
            operación de borrado confirma que fue a la Papelera (FileManager.trashItem o \
            equivalente, capturado en el momento del borrado -- no se puede reconstruir \
            después que algo "pasó por la Papelera" solo mirando el disco); (2) el ítem \
            ya no está en viewModel.items ni en biblioteca.json tras persistir.
            """)
    }

    // MARK: - (b) Eliminar en modo referencia: solo el catálogo, original intacto

    /// Forma de la prueba: mismo gesto que (a) pero en modo referencia
    /// (A4) -- el original (fuera de la biblioteca) tiene que sobrevivir
    /// byte a byte (hash antes/después idéntico), y lo único que
    /// desaparece es la entrada del catálogo (y, si existe, el
    /// preparado en `.preparados/<ID>.ext`). La diferencia central con
    /// (a): acá NUNCA hay Papelera de por medio -- Aura Studio no es
    /// dueño del original, no le toca borrarlo ni moverlo.
    func testDeletingInReferenceModeOnlyRemovesFromCatalogOriginalStaysByteIdentical_pendienteDeLaAPIDeA5() throws {
        throw XCTSkip("""
            Pendiente de la API real de A5 (ST-225). Forma: importar en modo referencia, \
            capturar SHA-256 del original, eliminar el ítem con la API real. Confirmar \
            (1) el hash del original NO cambió y el archivo sigue exactamente donde \
            estaba (Aura Studio nunca es dueño del original en este modo, no lo toca ni \
            lo manda a la Papelera); (2) el ítem ya no está en viewModel.items ni en \
            biblioteca.json; (3) si tenía preparado en .preparados/<ID>.ext, tampoco \
            existe más tras la eliminación.
            """)
    }

    // MARK: - (c) "Limpiar huérfanos": solo lo no referenciado

    /// Forma de la prueba: armar `.preparados/` con dos archivos --
    /// `<ID-A>.ext` referenciado por un ítem real de la biblioteca (modo
    /// referencia), y `<ID-B>.ext` SIN ningún ítem que lo referencie
    /// (huérfano real, p. ej. dejado por una eliminación anterior o una
    /// corrida interrumpida). Correr "Limpiar huérfanos" con la API
    /// real y confirmar que `<ID-B>.ext` desaparece y `<ID-A>.ext`
    /// sobrevive intacto (mismo hash) -- el caso que de verdad importa
    /// es que lo REFERENCIADO nunca se toque, no solo que lo huérfano
    /// se borre.
    func testCleanOrphansDeletesOnlyWhatNoItemReferencesAndRespectsWhatIsReferenced_pendienteDeLaAPIDeA5() throws {
        throw XCTSkip("""
            Pendiente de la API real de A5 (limpiar huérfanos, ST-225). Forma: crear \
            .preparados/<ID-A>.ext (referenciado por item.preparedURL de un ítem real en \
            modo referencia) y .preparados/<ID-B>.ext (sin ningún ítem que lo referencie \
            -- huérfano real). Correr la limpieza de huérfanos con la API real. Confirmar \
            (1) <ID-B>.ext ya no existe; (2) <ID-A>.ext sigue existiendo con el MISMO \
            hash que antes de limpiar -- lo referenciado nunca se toca, ese es el caso \
            que de verdad importa, no solo que lo huérfano se borre.
            """)
    }

    // MARK: - (d) Deduplicación al importar: misma ruta en NFC y NFD = un solo ítem

    /// Forma de la prueba: dos rutas que representan el MISMO archivo en
    /// disco -- una escrita en NFC (precompuesto, lo que produce
    /// Windows) y otra en NFD (descompuesto, lo que produce macOS/APFS
    /// al enumerar) -- importar ambas (p. ej. una gota con las dos rutas,
    /// o dos importaciones separadas del mismo archivo real) y confirmar
    /// que el catálogo termina con UN SOLO ítem, no dos. La comparación
    /// de deduplicación tiene que normalizar a NFC antes de comparar
    /// (mismo criterio que `SharedCatalogPath`, que ya distingue NFC/NFD
    /// para RESOLVER rutas -- acá es para DETECTAR que son la misma).
    func testDeduplicationOnImportComparesPathsInNFC_pendienteDeLaAPIDeA5() throws {
        throw XCTSkip("""
            Pendiente de la API real de A5 (deduplicación al importar, ST-225). Forma: \
            un archivo real en disco cuya ruta, al leerla del sistema de archivos, puede \
            representarse tanto en NFC como en NFD (mismos bytes de contenido, distinta \
            normalización Unicode del nombre). Importar dos veces -- una vez resuelta en \
            NFC, otra en NFD -- con la API real de importación. Confirmar que \
            viewModel.items termina con UN SOLO ítem para ese archivo, no dos -- la \
            comparación de "ya existe" normaliza ambas rutas a NFC antes de comparar \
            (mismo criterio que SharedCatalogPath, que ya distingue NFC/NFD para \
            RESOLVER rutas al leer un catálogo compartido -- acá es para DETECTAR que dos \
            rutas nombran el mismo archivo al importar).
            """)
    }

    // MARK: - (e) Migración nunca silenciosa

    /// Forma de la prueba: armar una biblioteca "anterior" -- ítems SIN
    /// campo `storage` en `biblioteca.json` (el estado antes de A1) y
    /// archivos reales en `Música/<Artista>/<Álbum>/` cuyas etiquetas en
    /// disco NO coinciden con las del catálogo (el caso real que
    /// justifica la migración: el catálogo dice una cosa, el archivo
    /// dice otra). Cargar la biblioteca con `LibraryViewModel(
    /// libraryRoot:)` normal y confirmar que la CARGA no escribe NINGÚN
    /// archivo (ni etiquetas, ni .preparados/, ni biblioteca.json) --
    /// abrir la app nunca migra sola. Solo al invocar "Migrar
    /// biblioteca" (la acción explícita, con la API real de A6) las
    /// etiquetas de los archivos en Música/ se reescriben para coincidir
    /// con el catálogo, se genera lo que falte (p. ej. un `storage` por
    /// omisión), y la acción devuelve/reporta un conteo de archivos
    /// tocados -- nunca 0 cuando de verdad había discrepancias que
    /// corregir.
    func testMigrationIsNeverSilent_loadWritesNothingOnlyExplicitMigrateWritesWithCount_pendienteDeLaAPIDeA6() throws {
        throw XCTSkip("""
            Pendiente de la API real de A6 (migración, ST-226). Forma: armar biblioteca \
            "anterior" -- ítems sin storage en biblioteca.json y archivos reales en \
            Música/<Artista>/<Álbum>/ con etiquetas EN DISCO distintas de las del \
            catálogo (el caso real que motiva la migración). Cargar con \
            LibraryViewModel(libraryRoot:) normal (no la acción de migrar) y capturar \
            hashes/mtimes de todos los archivos ANTES y DESPUÉS de la carga -- deben ser \
            IDÉNTICOS, cero bytes escritos, cero .preparados/ generado, biblioteca.json \
            sin tocar (abrir la app nunca migra sola). Después, invocar "Migrar \
            biblioteca" con la API real de A6: confirmar que ahora SÍ se reescriben las \
            etiquetas en Música/ para que coincidan con el catálogo, se genera lo que \
            falte (storage por omisión, .preparados/ si el modo lo requiere), y la acción \
            reporta un conteo de archivos tocados que sea MAYOR A CERO (había \
            discrepancias reales que corregir en este fixture).
            """)
    }
}
