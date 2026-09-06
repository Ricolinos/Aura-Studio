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
    #else
    static var libraryPath: String? { nil }
    static var defaultsSuiteName: String? { nil }
    #endif

    /// `true` cuando la app corre bajo una prueba de interfaz.
    static var isActive: Bool { libraryPath != nil }

    /// Los `accessibilityIdentifier` que la app promete. Viven acá y no
    /// sueltos en cada vista para que la prueba y la vista no puedan
    /// desincronizarse en silencio -- un identificador mal escrito en un
    /// XCUITest no falla al compilar, falla al no encontrar nada.
    enum ID {
        static let albumsGrid = "albumes.cuadricula"
        static let statusBar = "biblioteca.barraEstado"

        /// La tarjeta en la posición `index` del orden VISIBLE (el mismo
        /// que ve el usuario, ya filtrado y ordenado). Por posición y no
        /// por id de álbum a propósito: un arrastre se describe como
        /// "de la tarjeta 0 a la 5", y la clave de agrupación de un
        /// álbum lleva adentro un separador de unidad (0x1F) que no
        /// sirve como identificador.
        static func albumCard(_ index: Int) -> String { "albumes.tarjeta.\(index)" }
    }
}
