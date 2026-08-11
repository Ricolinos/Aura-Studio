import XCTest
@testable import AuraStudio

final class CatalogSummaryWriterTests: XCTestCase {
    func testSerializesAllFieldsAsFlatKeyValue() {
        var summary = CatalogSummary()
        summary.music = CatalogTypeSummary(count: 120, bytes: 489_234_931)
        summary.video = CatalogTypeSummary(count: 3, bytes: 1_234_567_890)
        summary.photo = CatalogTypeSummary(count: 40, bytes: 85_000_000)
        summary.playlistCount = 2

        let text = CatalogSummaryWriter.serialize(summary)
        let lines = text.split(separator: "\n").map(String.init)

        XCTAssertTrue(lines.contains("music_count: 120"))
        XCTAssertTrue(lines.contains("music_bytes: 489234931"))
        XCTAssertTrue(lines.contains("video_count: 3"))
        XCTAssertTrue(lines.contains("video_bytes: 1234567890"))
        XCTAssertTrue(lines.contains("photo_count: 40"))
        XCTAssertTrue(lines.contains("photo_bytes: 85000000"))
        XCTAssertTrue(lines.contains("playlist_count: 2"))
    }

    func testZeroedSummarySerializesCleanly() {
        let text = CatalogSummaryWriter.serialize(CatalogSummary())
        XCTAssertTrue(text.contains("music_count: 0"))
        XCTAssertTrue(text.contains("playlist_count: 0"))
    }
}
