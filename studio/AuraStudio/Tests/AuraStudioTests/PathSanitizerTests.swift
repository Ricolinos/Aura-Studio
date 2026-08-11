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
}
