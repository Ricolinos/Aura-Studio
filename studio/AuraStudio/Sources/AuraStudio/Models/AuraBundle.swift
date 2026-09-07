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
    static let strings: Bundle = {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }()
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
