import XCTest
@testable import AuraStudio

final class ClockSyncWriterTests: XCTestCase {
    private func fixedDate() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 18
        c.hour = 14; c.minute = 32; c.second = 7
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return cal.date(from: c)!
    }

    func testUpsertAddsAllSevenKeysToEmptyFile() {
        let tz = TimeZone(identifier: "America/Mexico_City")!
        let lines = ClockSyncWriter.upsertClockLines([], date: fixedDate(), timeZone: tz)
        XCTAssertTrue(lines.contains("rtc_sync_year: 2026"))
        XCTAssertTrue(lines.contains("rtc_sync_month: 8"))
        XCTAssertTrue(lines.contains("rtc_sync_day: 18"))
        XCTAssertTrue(lines.contains("rtc_sync_hour: 14"))
        XCTAssertTrue(lines.contains("rtc_sync_min: 32"))
        XCTAssertTrue(lines.contains("rtc_sync_sec: 7"))
        // Mexico City = UTC-6 (sin horario de verano) = -24 cuartos de hora.
        XCTAssertTrue(lines.contains("tz_local_quarters: -24"))
    }

    func testUpsertReplacesExistingKeysInPlacePreservingOthers() {
        let tz = TimeZone(identifier: "America/Mexico_City")!
        let original = ["theme: 1", "rtc_sync_year: 2020", "theme_id: mi-tema", "tz_local_quarters: 0"]
        let lines = ClockSyncWriter.upsertClockLines(original, date: fixedDate(), timeZone: tz)

        XCTAssertEqual(lines.first, "theme: 1")
        XCTAssertTrue(lines.contains("theme_id: mi-tema"))
        XCTAssertEqual(lines.filter { $0.hasPrefix("rtc_sync_year:") }.count, 1)
        XCTAssertTrue(lines.contains("rtc_sync_year: 2026"))
        XCTAssertEqual(lines.filter { $0.hasPrefix("tz_local_quarters:") }.count, 1)
        XCTAssertTrue(lines.contains("tz_local_quarters: -24"))
    }

    func testPositiveTimeZoneOffset() {
        let tz = TimeZone(identifier: "Asia/Tokyo")! // UTC+9 -> 36 cuartos
        let lines = ClockSyncWriter.upsertClockLines([], date: fixedDate(), timeZone: tz)
        XCTAssertTrue(lines.contains("tz_local_quarters: 36"))
    }

    // MARK: - writeToDisk (I/O)

    private var fakeIPod: URL!

    override func setUpWithError() throws {
        fakeIPod = FileManager.default.temporaryDirectory.appendingPathComponent("FakeIPod-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeIPod, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fakeIPod)
    }

    func testWriteToDiskCreatesConfigWhenMissing() throws {
        try ClockSyncWriter.writeToDisk(mountPath: fakeIPod.path, date: fixedDate(), timeZone: TimeZone(identifier: "America/Mexico_City")!)
        let cfg = fakeIPod.appendingPathComponent(".rockbox/aura/aura.cfg")
        let text = try String(contentsOf: cfg, encoding: .utf8)
        XCTAssertTrue(text.contains("rtc_sync_year: 2026"))
        XCTAssertTrue(text.contains("tz_local_quarters: -24"))
    }

    func testWriteToDiskPreservesUnrelatedLines() throws {
        let dir = fakeIPod.appendingPathComponent(".rockbox/aura")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "theme: 1\ntheme_id: mi-tema\n".write(to: dir.appendingPathComponent("aura.cfg"), atomically: true, encoding: .utf8)

        try ClockSyncWriter.writeToDisk(mountPath: fakeIPod.path, date: fixedDate(), timeZone: TimeZone(identifier: "America/Mexico_City")!)

        let text = try String(contentsOf: dir.appendingPathComponent("aura.cfg"), encoding: .utf8)
        XCTAssertTrue(text.contains("theme_id: mi-tema"))
        XCTAssertTrue(text.contains("rtc_sync_year: 2026"))
    }

    func testWriteToDiskIgnoresInvalidMountPath() throws {
        try ClockSyncWriter.writeToDisk(mountPath: "", date: fixedDate(), timeZone: .current)
        try ClockSyncWriter.writeToDisk(mountPath: "relative/path", date: fixedDate(), timeZone: .current)
        // No lanza, no crea nada -- silencioso ante rutas invalidas.
    }
}
