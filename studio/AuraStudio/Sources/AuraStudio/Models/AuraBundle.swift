import Foundation

/// ST-227: dónde vive el String Catalog.
///
/// **Por qué hace falta un tipo entero para esto.** Este código se
/// compila de dos formas: con SwiftPM (`swift build`/`swift test`, el
/// camino de verificación) y con el proyecto de Xcode, que es el
/// entregable real. SwiftPM mete los recursos en un bundle propio y los
/// expone como `Bundle.module`; el proyecto de Xcode los mete en el
/// bundle de la app, que es `Bundle.main`. `Bundle.module` **no existe**
/// fuera de SwiftPM: usarlo directo no compilaría el entregable.
///
/// Éste es el único sitio del repo donde esa diferencia existe. Si algún
/// día se rompe, se rompe acá y hay una prueba que lo dice.
enum AuraBundle {
    private static let `default`: Bundle = {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }()

    /// ST-227 (A7c, addendum 3): la única costura de este archivo, y
    /// existe por una prueba concreta.
    ///
    /// El defecto que Windows encontró --una oración armada de ocho
    /// pedazos donde solo uno venía del catálogo-- **no se ve mirando
    /// cadenas sueltas**: cada pedazo está bien; lo que está mal es la
    /// unión. La única forma de verlo es **componer la frase entera en
    /// otro idioma** y buscar restos de español. Y para eso hay que
    /// poder decirle a `LS` de qué tabla leer.
    ///
    /// Solo la escriben las pruebas, y la devuelven a `nil` al terminar.
    /// La app nunca la toca: `AppLanguageApplier` cambia el idioma por
    /// `AppleLanguages`, que es lo que el sistema lee al arrancar.
    nonisolated(unsafe) static var overrideForTests: Bundle?

    static var strings: Bundle { overrideForTests ?? `default` }
}

/// El texto localizado de `key`.
///
/// Nombre corto a propósito: aparece cientos de veces, y un nombre largo
/// convierte cada línea de interfaz en una línea sobre localización. La
/// clave es siempre un literal para que se pueda inventariar sin
/// ejecutar nada (ver `LocalizationCatalogTests`).
func LS(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: AuraBundle.strings)
}

/// Igual, pero con argumentos que se sustituyen en los marcadores del
/// catálogo (`%@`, `%lld`).
///
/// Usa `String.localizedStringWithFormat` y no `String(format:)` a
/// propósito: es el que respeta los **argumentos posicionales**
/// (`%1$@`, `%2$@`), y una traducción que necesita cambiar el orden de
/// las palabras -- japonés y alemán, sin ir más lejos -- no tiene otra
/// forma de hacerlo.
func LSf(_ key: String.LocalizationValue, _ arguments: any CVarArg...) -> String {
    String.localizedStringWithFormat(LS(key), arguments)
}
