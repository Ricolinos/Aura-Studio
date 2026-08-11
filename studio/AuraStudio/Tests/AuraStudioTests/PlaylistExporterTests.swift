import XCTest
@testable import AuraStudio

final class PlaylistExporterTests: XCTestCase {
    func testFileNameSanitizesAndAddsExtension() {
        XCTAssertEqual(PlaylistExporter.fileName(for: "Roadtrip 2026"), "Roadtrip 2026.m3u8")
        XCTAssertEqual(PlaylistExporter.fileName(for: "AC/DC only"), "AC_DC only.m3u8")
    }

    func testM3U8ContentsHasHeaderAndAbsolutePaths() {
        let contents = PlaylistExporter.m3u8Contents(trackDestinationPaths: [
            "Music/Queen/A Night at the Opera/11 Bohemian Rhapsody.mp3",
            "Music/Queen/A Night at the Opera/02 You're My Best Friend.mp3",
        ])

        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(lines[0], "#EXTM3U")
        XCTAssertEqual(lines[1], "/Music/Queen/A Night at the Opera/11 Bohemian Rhapsody.mp3")
        XCTAssertEqual(lines[2], "/Music/Queen/A Night at the Opera/02 You're My Best Friend.mp3")
    }

    func testEmptyPlaylistStillHasHeader() {
        let contents = PlaylistExporter.m3u8Contents(trackDestinationPaths: [])
        XCTAssertEqual(contents, "#EXTM3U\n")
    }
}
