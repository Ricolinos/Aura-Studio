import XCTest

/// ST-188: el andamio para verificar **el arrastre de selección** de
/// ST-184 con la app corriendo de verdad.
///
/// Es el único de los ocho gestos de §A que no se puede comprobar sin
/// mover un mouse: el núcleo (`GridMarquee`, `GridSelection`) está
/// probado entero en `Tests/AuraStudioTests`, pero que un
/// `NSViewRepresentable` puesto de fondo reciba los eventos dentro de un
/// `ScrollView` con `LazyVGrid` solo se sabe corriendo la app.
///
/// **Lo escribió "experto en código opus" como seam, no como la prueba
/// final**: la sesión "mecanico sonnet" es la dueña de esta carpeta y de
/// lo que se mida acá. Lo que aporta este archivo es el contrato de
/// arranque, ya funcionando, para que escribir el gesto sea lo único que
/// falte.
///
/// ## Cómo arranca la app bajo prueba
///
/// - `AURA_UITEST_LIBRARY`: ruta de la carpeta de biblioteca. La app la
///   usa tal cual y **no la guarda en Ajustes**, así que la biblioteca
///   real del dueño queda intacta.
/// - `AURA_UITEST_DEFAULTS_SUITE`: suite de `UserDefaults` aparte, para
///   no reordenar columnas ni cambiar preferencias reales.
///
/// Las dos solo se leen en DEBUG (ver `UITestEnvironment`).
///
/// ## Qué nombres promete la app
///
/// - `albumes.cuadricula` — el contenedor de la cuadrícula. Es lo que se
///   agarra para arrastrar **desde un hueco**, que es donde empieza un
///   recuadro (desde una tarjeta se arrastra la tarjeta).
/// - `albumes.tarjeta.<n>` — la tarjeta en la posición `n` del orden
///   visible.
/// - `biblioteca.barraEstado` — la barra de estado. Su texto dice cuántos
///   álbumes hay seleccionados, que es la forma de comprobar el
///   resultado de un arrastre sin espiar el estado interno de la vista.
final class AlbumsDragSelectionUITests: XCTestCase {

    /// Biblioteca sintética mínima. La versión de verdad (1 000 álbumes
    /// con carátulas reales) la arma "mecanico sonnet" con el fixture de
    /// ST-180; acá alcanza con que la app abra sobre una carpeta que no
    /// es la del dueño.
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        libraryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuraStudioUITest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["AURA_UITEST_LIBRARY"] = libraryRoot.path
        app.launchEnvironment["AURA_UITEST_DEFAULTS_SUITE"] = "com.ricolinos.aurastudio.uitest.\(UUID().uuidString)"
        app.launch()
        return app
    }

    /// Lo único que esta prueba afirma: que el contrato de arranque
    /// funciona -- la app abre sobre la biblioteca que le dijo la prueba,
    /// sin tocar la del dueño. El gesto de arrastre en sí va aparte,
    /// sobre una biblioteca con álbumes de verdad.
    func testAppLaunchesOnTheLibraryTheTestProvides() throws {
        let app = launchApp()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30),
                      "la app no llegó a primer plano con AURA_UITEST_LIBRARY puesto")
        // La carpeta de biblioteca se crea sola al arrancar (estructura
        // Música/Imágenes/Videos): si existe, la app de verdad usó la
        // ruta del entorno y no la configurada en Ajustes.
        let music = libraryRoot.appendingPathComponent("Música", isDirectory: true)
        let deadline = Date().addingTimeInterval(30)
        while !FileManager.default.fileExists(atPath: music.path), Date() < deadline {
            usleep(200_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: music.path),
                      "la app no armó la biblioteca en la ruta que le pasó la prueba")
    }
}
