import XCTest
@testable import AuraStudio

/// ST-227: los plurales del catálogo dan el MISMO español que daban los
/// ternarios.
///
/// El cambio no es cosmético: un ternario `n == 1 ? "canción" :
/// "canciones"` tiene exactamente dos formas, y hay idiomas que no
/// funcionan así -- el ruso tiene tres y el japonés una. La forma en
/// español tiene que quedar idéntica, o el arreglo para otros idiomas
/// habría roto el que ya estaba bien.
@MainActor
final class LocalizationPluralTests: XCTestCase {
    func testSpanishPluralsReadExactlyAsTheyDidBefore() {
        XCTAssertEqual(LSf("albums-view.plural.canciones", 1), "1 canción")
        XCTAssertEqual(LSf("albums-view.plural.canciones", 2), "2 canciones")
        XCTAssertEqual(LSf("albums-view.plural.canciones", 0), "0 canciones")
        XCTAssertEqual(LSf("albums-view.plural.canciones", 21), "21 canciones",
                       "el español no tiene forma especial para 21, a diferencia del ruso")
    }

    /// Xcode **rechaza** una variación de plural cuyo texto no contiene
    /// el número, y tiene razón: `"\(n) \(plural)"` pega el número por
    /// fuera y ahí la concordancia deja de ser traducible -- el ruso la
    /// necesita pegada, y hay idiomas donde el número va en otro lugar
    /// de la frase.
    ///
    /// Diez claves mías empezaron así. `swift test` las daba por buenas;
    /// lo que las cazó fue `xcodebuild`. Éstas son las que quedaron, con
    /// el número adentro.
    func testPluralPhrasesCarryTheNumberInsideTheText() {
        XCTAssertEqual(LSf("library-grouping.plural.canciones-frase", 1), "1 canción")
        XCTAssertEqual(LSf("library-grouping.plural.canciones-frase", 7), "7 canciones")
        XCTAssertEqual(LSf("library-view-model.plural.posters-encontrados", 1), "Pósters: 1 encontrado")
        XCTAssertEqual(LSf("library-view-model.plural.posters-encontrados", 3), "Pósters: 3 encontrados")
        XCTAssertEqual(LSf("library-view-model.plural.ya-tenian-foto", 1), "1 ya tenía foto")
        XCTAssertEqual(LSf("library-view-model.plural.ya-tenian-foto", 4), "4 ya tenían foto")
    }

    /// Dos números en la misma frase, con argumentos POSICIONALES: es lo
    /// que permite que una traducción los ponga en otro orden.
    func testAPhraseWithTwoNumbersKeepsThemInOrder() {
        XCTAssertEqual(LSf("library-status-summary.plural.dias-horas", 1, 5), "1 día 5 h")
        XCTAssertEqual(LSf("library-status-summary.plural.dias-horas", 3, 0), "3 días 0 h")
    }

    /// Y el caso que **no** es un plural aunque lo parezca: el texto no
    /// dice cuántos, dice qué pasa. Son dos claves sueltas, que es lo que
    /// Xcode sugiere para esto.
    func testATextThatNeverNamesTheCountIsTwoPlainKeys() {
        XCTAssertTrue(LS("library-view-model.eliminar-referencia-uno").hasPrefix("Se quitará"))
        XCTAssertTrue(LS("library-view-model.eliminar-referencia-varios").hasPrefix("Se quitarán"))
    }
}
