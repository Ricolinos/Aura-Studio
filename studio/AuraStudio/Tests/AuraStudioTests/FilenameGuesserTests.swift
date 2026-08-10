import XCTest
@testable import AuraStudio

final class FilenameGuesserTests: XCTestCase {
    func testArtistDashTitlePattern() {
        let url = URL(fileURLWithPath: "/tmp/Aura QA - Aura Test Tone.mp3")
        let guess = FilenameGuesser.guess(from: url)
        XCTAssertEqual(guess.artist, "Aura QA")
        XCTAssertEqual(guess.title, "Aura Test Tone")
    }

    func testTitleOnlyWhenNoDash() {
        let url = URL(fileURLWithPath: "/tmp/aura-test.flac")
        let guess = FilenameGuesser.guess(from: url)
        XCTAssertNil(guess.artist)
        XCTAssertEqual(guess.title, "aura-test")
    }

    func testMultipleDashesKeepsRemainderAsTitle() {
        let url = URL(fileURLWithPath: "/tmp/Artist - Song - Remix.mp3")
        let guess = FilenameGuesser.guess(from: url)
        XCTAssertEqual(guess.artist, "Artist")
        XCTAssertEqual(guess.title, "Song - Remix")
    }
}
