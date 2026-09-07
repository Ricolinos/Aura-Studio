import XCTest
@testable import AuraStudio

/// ST-227: el String Catalog y el código no pueden divergir en silencio.
///
/// Una clave que no está en el catálogo **no falla**: `String(localized:)`
/// devuelve la clave misma, así que la app muestra `media-section.eliminar`
/// en pantalla y sigue andando. Es exactamente la clase de defecto que hay
/// que cazar con una prueba y no con la vista.
@MainActor
final class LocalizationCatalogTests: XCTestCase {
    private func catalog() throws -> [String: Any] {
        let url = try XCTUnwrap(AuraBundle.strings.url(forResource: "Localizable", withExtension: "xcstrings"),
                                "el catálogo tiene que estar en el bundle -- si esto falla, el recurso no se está empaquetando")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testTheCatalogIsInTheBundleAndItsSourceIsSpanish() throws {
        let catalog = try catalog()
        XCTAssertEqual(catalog["sourceLanguage"] as? String, "es",
                       "el idioma fuente es el español: el texto se escribe en español y de ahí se traduce")
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        XCTAssertGreaterThan(strings.count, 300, "el catálogo llegó vacío o a medias")
    }

    /// Lo que de verdad prueba que el puente entre los dos sistemas de
    /// compilación funciona: pedir una clave y recibir el texto, no la
    /// clave.
    func testLookingUpAKeyReturnsItsSpanishTextAndNotTheKey() throws {
        let strings = try XCTUnwrap(try catalog()["strings"] as? [String: Any])
        let key = try XCTUnwrap(strings.keys.sorted().first)
        let expected = try XCTUnwrap((((strings[key] as? [String: Any])?["localizations"] as? [String: Any])?["es"]
                                      as? [String: Any])?["stringUnit"] as? [String: Any])["value"] as? String

        let resolved = String(localized: String.LocalizationValue(key), bundle: AuraBundle.strings)

        XCTAssertEqual(resolved, expected)
        XCTAssertNotEqual(resolved, key, "si devuelve la clave, el catálogo no se está resolviendo")
    }
}
