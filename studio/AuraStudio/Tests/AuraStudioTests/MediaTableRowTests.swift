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

    // MARK: - Estado ordenable (ST-030)

    private func statusRow(_ status: LibraryItemStatus, sync: SyncItemState? = nil) -> MediaTableRow {
        var item = LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/song.mp3"))
        item.status = status
        return MediaTableRow(item: item, syncState: sync)
    }

    func testStatusRankPutsSyncedFirstAndFailedLast() {
        let ranks = [
            statusRow(.ready, sync: .synced),
            statusRow(.ready),
            statusRow(.ready, sync: .pending),
            statusRow(.ready, sync: .changedLocally),
            statusRow(.ready, sync: .modifiedOnDevice),
            statusRow(.ready, sync: .removedFromDevice),
            statusRow(.queued),
            statusRow(.enriching),
            statusRow(.transcoding(progress: 0.5)),
            statusRow(.needsReview),
            statusRow(.failed("x")),
        ].map(\.statusRank)
        XCTAssertEqual(ranks, ranks.sorted(), "el rango debe crecer de sincronizado a fallido")
        XCTAssertEqual(Set(ranks).count, ranks.count, "cada estado tiene su propio rango")
    }

    func testSortingByStatusRankGroupsPendingBeforeFailed() {
        let rows = [statusRow(.failed("x")), statusRow(.ready, sync: .pending), statusRow(.ready, sync: .synced)]
        let sorted = rows.sorted(using: [KeyPathComparator(\.statusRank)])
        XCTAssertEqual(sorted.map(\.statusRank), [0, 2, 10])
    }
}
