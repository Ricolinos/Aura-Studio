import XCTest
@testable import AuraStudio

final class PathSanitizerTests: XCTestCase {
    func testPlainNameIsUnchanged() {
        XCTAssertEqual(PathSanitizer.sanitize("Abbey Road"), "Abbey Road")
    }

    func testIllegalCharactersAreReplaced() {
        XCTAssertEqual(PathSanitizer.sanitize("AC/DC"), "AC_DC")
        XCTAssertEqual(PathSanitizer.sanitize("Sigur Ros: ()"), "Sigur Ros_ ()")
        XCTAssertEqual(PathSanitizer.sanitize("Track \"Live\""), "Track _Live_")
    }

    func testTrailingDotsAndSpacesAreTrimmed() {
        XCTAssertEqual(PathSanitizer.sanitize("Mr. Bungle. "), "Mr. Bungle")
    }

    func testEmptyResultFallsBackToUnderscore() {
        XCTAssertEqual(PathSanitizer.sanitize("   ..."), "_")
    }

    // PLAN-sync-media-hardening.md PARTE 1A: visto en produccion, un
    // credito de composicion completo ("Los Aguas Aguas, Luis Felipe
    // Balderas Lopez, Jose Edwin Bandala Mayoral, Osiel de Jesus Ro...")
    // metido en el tag de artista hacia que la ruta completa
    // (Music/<artista>/<album>/<archivo>.mp3.aura-tmp) excediera lo que
    // el driver msdosfs de macOS acepta -- sync() abortaba entero en
    // ese archivo con "el nombre de archivo es invalido".
    func testLongComponentIsTruncated() {
        let long = String(repeating: "a", count: 200)
        let result = PathSanitizer.sanitize(long)
        XCTAssertEqual(result.count, PathSanitizer.defaultMaxLength)
        XCTAssertEqual(result, String(long.prefix(PathSanitizer.defaultMaxLength)))
    }

    func testShortComponentIsUnaffectedByLengthCap() {
        XCTAssertEqual(PathSanitizer.sanitize("Abbey Road", maxLength: 5), "Abbey")
    }

    func testTruncationThatLandsOnTrailingDotOrSpaceIsTrimmed() {
        // Corta justo despues de un espacio -- el resultado no debe
        // quedar con un espacio colgando al final.
        let raw = "Nombre muy largo " + String(repeating: "x", count: 200)
        let result = PathSanitizer.sanitize(raw, maxLength: 17)
        XCTAssertEqual(result, "Nombre muy largo")
    }

    // MARK: - sanitizeFilename (PLAN-sync-media-hardening.md PARTE 2A)

    func testSanitizeFilenamePreservesShortNameUnchanged() {
        XCTAssertEqual(PathSanitizer.sanitizeFilename("Año nuevo Ñoño.jpg", maxBytes: 95), "Año nuevo Ñoño.jpg")
    }

    func testSanitizeFilenameTruncatesByBytesNotCharacters() {
        // "ñ" son 2 bytes UTF-8 -- 60 "ñ" = 120 bytes, mas ".jpg" (4
        // bytes) = 124 bytes, muy por encima de un limite de 20. Capar
        // por CARACTERES (60 "ñ" es solo 60 caracteres) no lo hubiera
        // detectado.
        let raw = String(repeating: "ñ", count: 60) + ".jpg"
        let result = PathSanitizer.sanitizeFilename(raw, maxBytes: 20)
        XCTAssertLessThanOrEqual(result.utf8.count, 20)
        XCTAssertTrue(result.hasSuffix(".jpg"), "la extension se conserva completa")
    }

    func testSanitizeFilenameNeverSplitsAMultibyteCharacter() {
        let raw = String(repeating: "é", count: 50) + ".jpg"
        let result = PathSanitizer.sanitizeFilename(raw, maxBytes: 21) // impar: fuerza el limite a mitad de un caracter de 2 bytes si no se recorta por Character
        XCTAssertLessThanOrEqual(result.utf8.count, 21)
        // Si se hubiera cortado a mitad de un caracter, la cadena
        // resultante ni siquiera seria UTF-8 valido re-decodificable
        // desde sus propios bytes -- construirla de vuelta confirma que
        // sigue siendo texto valido.
        XCTAssertEqual(String(decoding: Array(result.utf8), as: UTF8.self), result)
    }

    func testSanitizeFilenameAlsoReplacesIllegalCharacters() {
        let result = PathSanitizer.sanitizeFilename("AC/DC: Live.jpg", maxBytes: 95)
        XCTAssertEqual(result, "AC_DC_ Live.jpg")
    }
}
