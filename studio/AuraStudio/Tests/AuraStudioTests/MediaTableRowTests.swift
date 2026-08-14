import XCTest
@testable import AuraStudio

/// D-198: formato de duracion de la tabla de biblioteca -- logica pura,
/// sin tocar disco.
final class MediaTableRowTests: XCTestCase {
    private func row(durationSeconds: Double?) -> MediaTableRow {
        var item = LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/song.mp3"))
        item.metadata = TrackMetadata(title: "Song", durationSeconds: durationSeconds)
        return MediaTableRow(item: item)
    }

    func testMissingDurationShowsDoubleDash() {
        XCTAssertEqual(row(durationSeconds: nil).durationText, "--")
    }

    func testZeroDurationShowsDoubleDash() {
        XCTAssertEqual(row(durationSeconds: 0).durationText, "--")
    }

    func testDurationUnderAMinute() {
        XCTAssertEqual(row(durationSeconds: 45).durationText, "0:45")
    }

    func testDurationRoundsToNearestSecond() {
        XCTAssertEqual(row(durationSeconds: 44.6).durationText, "0:45")
    }

    func testDurationOverAMinutePadsSeconds() {
        XCTAssertEqual(row(durationSeconds: 65).durationText, "1:05")
    }

    func testLongDuration() {
        XCTAssertEqual(row(durationSeconds: 3725).durationText, "62:05")
    }

    func testTitleFallsBackToFilenameWithoutExtension() {
        var item = LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/Some Track.flac"))
        item.metadata = nil
        XCTAssertEqual(MediaTableRow(item: item).title, "Some Track")
    }
}
