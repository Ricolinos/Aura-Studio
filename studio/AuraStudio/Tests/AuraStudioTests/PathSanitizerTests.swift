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
}
