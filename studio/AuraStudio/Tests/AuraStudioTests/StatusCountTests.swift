import XCTest
@testable import AuraStudio

/// ST-227 (A7d): **los conteos de la barra de estado, con plural de
/// verdad y con el número formateado.**
///
/// `LibraryStats.count(_:singular:plural:)` recibía el singular y el
/// plural **en español**, escritos en cada uno de sus 33 sitios de
/// llamada. Sustituirlo por una clave de plural corriente no bastaba:
/// `count` muestra el número con `formatted(n)`, que le pone el
/// separador de miles del idioma, y un `%lld` dentro de un plural no lo
/// hace -- una biblioteca de 12 345 canciones habría pasado a decir
/// "12345".
///
/// Por eso estas claves usan **sustitución**: el argumento 1 es el número
/// y elige la FORMA; el argumento 2 es ese mismo número ya formateado y
/// es lo que se MUESTRA. Es la única combinación que da las dos cosas.
@MainActor
final class StatusCountTests: XCTestCase {
    /// La comprobación que motivó todo esto: el separador de miles
    /// sobrevive dentro del plural.
    func testTheThousandsSeparatorSurvivesInsideThePlural() {
        let texto = LibraryStats.count(12_345, .songs)
        XCTAssertTrue(texto.contains(LibraryStats.formatted(12_345)),
                      "el número tiene que salir formateado: «\(texto)»")
        XCTAssertFalse(texto.contains("12345"),
                       "salió sin separador de miles: «\(texto)»")
    }

    /// Y la forma sigue eligiéndose por el número, no por el texto.
    func testTheFormIsChosenByTheNumber() {
        XCTAssertNotEqual(LibraryStats.count(1, .songs), LibraryStats.count(2, .songs))
        XCTAssertTrue(LibraryStats.count(1, .songs).hasPrefix("1 "))
    }

    /// Ninguna de las once devuelve la clave: si una se escribió mal, la
    /// barra de estado mostraría `status.plural.…` en pantalla.
    func testEveryCountedNounResolves() {
        for noun in LibraryStats.CountedNoun.allCases {
            for n in [0, 1, 2, 5, 21, 1_234] {
                let texto = LibraryStats.count(n, noun)
                XCTAssertFalse(texto.contains("status.plural."),
                               "\(noun) con \(n) devolvió la clave: «\(texto)»")
                XCTAssertFalse(texto.isEmpty)
            }
        }
    }
}
