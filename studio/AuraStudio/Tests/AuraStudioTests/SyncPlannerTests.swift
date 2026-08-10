import XCTest
@testable import AuraStudio

final class SyncPlannerTests: XCTestCase {
    func testNewFileIsCopied() {
        let current = [(sourcePath: "/a.mp3", size: Int64(100), modifiedAt: 1000.0, destinationRelativePath: "Music/a.mp3")]
        let plan = SyncPlanner.plan(current: current, previousManifest: .empty)

        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].action, .copy)
    }

    func testUnchangedFileIsSkipped() {
        let record = SyncRecord(sourcePath: "/a.mp3", sourceSize: 100, sourceModifiedAt: 1000.0, destinationRelativePath: "Music/a.mp3")
        let manifest = SyncManifest(records: ["/a.mp3": record])
        let current = [(sourcePath: "/a.mp3", size: Int64(100), modifiedAt: 1000.0, destinationRelativePath: "Music/a.mp3")]

        let plan = SyncPlanner.plan(current: current, previousManifest: manifest)

        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].action, .skip)
    }

    func testChangedSizeTriggersRecopy() {
        let record = SyncRecord(sourcePath: "/a.mp3", sourceSize: 100, sourceModifiedAt: 1000.0, destinationRelativePath: "Music/a.mp3")
        let manifest = SyncManifest(records: ["/a.mp3": record])
        let current = [(sourcePath: "/a.mp3", size: Int64(200), modifiedAt: 1000.0, destinationRelativePath: "Music/a.mp3")]

        let plan = SyncPlanner.plan(current: current, previousManifest: manifest)

        XCTAssertEqual(plan[0].action, .copy)
    }

    func testChangedModificationDateTriggersRecopy() {
        let record = SyncRecord(sourcePath: "/a.mp3", sourceSize: 100, sourceModifiedAt: 1000.0, destinationRelativePath: "Music/a.mp3")
        let manifest = SyncManifest(records: ["/a.mp3": record])
        let current = [(sourcePath: "/a.mp3", size: Int64(100), modifiedAt: 2000.0, destinationRelativePath: "Music/a.mp3")]

        let plan = SyncPlanner.plan(current: current, previousManifest: manifest)

        XCTAssertEqual(plan[0].action, .copy)
    }

    func testMixOfNewChangedAndUnchanged() {
        let unchanged = SyncRecord(sourcePath: "/unchanged.mp3", sourceSize: 100, sourceModifiedAt: 1000.0, destinationRelativePath: "Music/unchanged.mp3")
        let changed = SyncRecord(sourcePath: "/changed.mp3", sourceSize: 50, sourceModifiedAt: 500.0, destinationRelativePath: "Music/changed.mp3")
        let manifest = SyncManifest(records: ["/unchanged.mp3": unchanged, "/changed.mp3": changed])

        let current = [
            (sourcePath: "/unchanged.mp3", size: Int64(100), modifiedAt: 1000.0, destinationRelativePath: "Music/unchanged.mp3"),
            (sourcePath: "/changed.mp3", size: Int64(999), modifiedAt: 500.0, destinationRelativePath: "Music/changed.mp3"),
            (sourcePath: "/new.mp3", size: Int64(10), modifiedAt: 10.0, destinationRelativePath: "Music/new.mp3"),
        ]

        let plan = SyncPlanner.plan(current: current, previousManifest: manifest)
        let actionsByPath = Dictionary(uniqueKeysWithValues: plan.map { ($0.sourcePath, $0.action) })

        XCTAssertEqual(actionsByPath["/unchanged.mp3"], .skip)
        XCTAssertEqual(actionsByPath["/changed.mp3"], .copy)
        XCTAssertEqual(actionsByPath["/new.mp3"], .copy)
    }

    func testManifestRoundTripsThroughJSON() throws {
        let record = SyncRecord(sourcePath: "/a.mp3", sourceSize: 100, sourceModifiedAt: 1000.0, destinationRelativePath: "Music/a.mp3")
        let manifest = SyncManifest(records: ["/a.mp3": record])

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(SyncManifest.self, from: data)

        XCTAssertEqual(decoded, manifest)
    }
}
