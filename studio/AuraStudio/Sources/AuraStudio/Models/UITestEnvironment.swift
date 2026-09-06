import Foundation

/// ST-188: cómo arranca la app cuando la maneja una prueba de interfaz.
///
/// El arrastre de selección (ST-184) es el único de los ocho gestos que
/// no se puede verificar sin correr la app: el núcleo está probado
/// entero, pero que un `NSViewRepresentable` de fondo reciba los eventos
/// del ratón dentro de un `ScrollView` con `LazyVGrid` solo se sabe
/// moviendo un mouse. Un XCUITest sí puede hacerlo
/// (`press(forDuration:thenDragTo:)`), y para eso necesita dos cosas que
/// la app no ofrecía: arrancar sobre una biblioteca **sintética** en una
/// ruta dada, y poder nombrar los elementos de la cuadrícula.
///
/// **Nunca se toca la biblioteca del dueño.** La prueba pasa la ruta por
/// variable de entorno; la app la usa tal cual y **no la guarda en
/// Ajustes**, así que la carpeta configurada de verdad queda intacta. Lo
/// mismo con los ajustes: se puede pedir una suite de `UserDefaults`
/// aparte, para que abrir la app bajo prueba no reordene columnas ni
/// cambie preferencias reales.
///
/// Solo existe en **DEBUG**: en una build de Release estas variables no
/// se leen, así que no hay forma de redirigir la biblioteca de una app
/// instalada por más que se lance con el entorno puesto. Mismo criterio
/// que `MainThreadWatchdog`.
enum UITestEnvironment {
    /// Ruta absoluta de la carpeta de biblioteca que debe usar la app.
    static let libraryPathKey = "AURA_UITEST_LIBRARY"
    /// Nombre de la suite de `UserDefaults` a usar en vez de la estándar.
    static let defaultsSuiteKey = "AURA_UITEST_DEFAULTS_SUITE"
    /// ST-188 (addendum): poner la ventana en la pantalla PRINCIPAL, con
    /// un tamaño fijo, ignorando dónde quedó la última vez.
    ///
    /// No es una preferencia estética: `XCUIElement.press(forDuration:
    /// thenDragTo:)` **revienta** (`point.x/y != INFINITY`) cuando la
    /// ventana está en una pantalla secundaria. Es un defecto conocido de
    /// XCTest, no del código de la app, y sin esto el gesto de arrastre
    /// —lo único que ST-188 existe para poder verificar— no se puede
    /// ejercer en una Mac con dos pantallas, que es justamente la del
    /// dueño.
    static let mainScreenKey = "AURA_UITEST_MAIN_SCREEN"

    #if DEBUG
    static var libraryPath: String? {
        guard let path = ProcessInfo.processInfo.environment[libraryPathKey],
              !path.isEmpty else { return nil }
        return path
    }

    static var defaultsSuiteName: String? {
        guard let suite = ProcessInfo.processInfo.environment[defaultsSuiteKey],
              !suite.isEmpty else { return nil }
        return suite
    }

    static var forcesMainScreenWindow: Bool {
        ProcessInfo.processInfo.environment[mainScreenKey] == "1"
    }
    #else
    static var libraryPath: String? { nil }
    static var defaultsSuiteName: String? { nil }
    static var forcesMainScreenWindow: Bool { false }
    #endif

    /// Tamaño con el que se coloca la ventana bajo
    /// `AURA_UITEST_MAIN_SCREEN`. Fijo a propósito: una prueba que
    /// calcula coordenadas necesita una ventana del mismo tamaño en cada
    /// corrida, y 1280×800 entra en cualquier pantalla razonable.
    static let mainScreenWindowSize = CGSize(width: 1280, height: 800)

    /// `true` cuando la app corre bajo una prueba de interfaz.
    static var isActive: Bool { libraryPath != nil }

    /// Los `accessibilityIdentifier` que la app promete. Viven acá y no
    /// sueltos en cada vista para que la prueba y la vista no puedan
    /// desincronizarse en silencio -- un identificador mal escrito en un
    /// XCUITest no falla al compilar, falla al no encontrar nada.
    enum ID {
        static let albumsGrid = "albumes.cuadricula"
        static let statusBar = "biblioteca.barraEstado"

        /// ST-188 (2.º addendum): la fila de la barra lateral. Buscar
        /// por TEXTO no sirve: "Álbumes" aparece también en el menú
        /// Visualización ("Ir a › Álbumes", ⌘2, ST-063), y un
        /// `firstMatch` sobre todo el árbol puede resolver a ése —
        /// activarlo no navega a ningún lado y la prueba se queda
        /// mirando la sección equivocada sin ningún error. Fue
        /// exactamente lo que pasó.
        static func sidebarRow(_ key: String) -> String { "biblioteca.barraLateral.\(key)" }

        /// La tarjeta en la posición `index` del orden VISIBLE (el mismo
        /// que ve el usuario, ya filtrado y ordenado). Por posición y no
        /// por id de álbum a propósito: un arrastre se describe como
        /// "de la tarjeta 0 a la 5", y la clave de agrupación de un
        /// álbum lleva adentro un separador de unidad (0x1F) que no
        /// sirve como identificador.
        static func albumCard(_ index: Int) -> String { "albumes.tarjeta.\(index)" }
    }
}

/// ST-188 (2.º addendum): un archivo de diagnóstico que la prueba SÍ
/// puede leer.
///
/// `print` desde el proceso de la app bajo prueba **no llega** a la
/// salida de `xcodebuild test` -- se comprobó buscándolo en el log
/// capturado, en `log show` acotado al pid, y en el `.xcresult`: en
/// ninguno aparecía. Lo que sí aparece son los `print` del proceso de
/// PRUEBA, que es otro proceso.
///
/// Así que el diagnóstico se escribe donde la prueba puede ir a
/// buscarlo: `<AURA_UITEST_LIBRARY>/uitest.log`. La prueba ya conoce esa
/// ruta —la eligió ella— y puede adjuntarla al resultado.
///
/// Solo escribe bajo prueba: sin `AURA_UITEST_LIBRARY` no hay dónde, y
/// no se inventa ninguna ruta.
enum UITestLog {
    static func write(_ message: String) {
        #if DEBUG
        guard let path = UITestEnvironment.libraryPath else { return }
        let url = URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent("uitest.log")
        let line = "\(ISO8601DateFormatter().string(from: Date()))  \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
        #endif
    }
}
