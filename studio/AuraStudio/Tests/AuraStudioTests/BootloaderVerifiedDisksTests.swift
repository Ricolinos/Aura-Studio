import XCTest
@testable import AuraStudio

/// ST-016: registro local "a este disco ya le verificamos el bootloader"
/// -- la mitad que sustituye a la lectura de la NOR (imposible desde una
/// Mac) cuando el iPod llega en modo disco de Apple.
@MainActor
final class BootloaderVerifiedDisksTests: XCTestCase {
    private func makePreferences() -> AppPreferences {
        AppPreferences(defaults: UserDefaults(suiteName: "BootloaderVerified-\(UUID().uuidString)")!)
    }

    func testStartsEmpty() {
        let prefs = makePreferences()
        XCTAssertFalse(prefs.isBootloaderVerified(diskKey: "VOL-1"))
        XCTAssertFalse(prefs.isBootloaderVerified(diskKey: nil))
    }

    func testRecordThenQueryThenForget() {
        let prefs = makePreferences()
        prefs.recordBootloaderVerified(diskKey: "VOL-1")
        XCTAssertTrue(prefs.isBootloaderVerified(diskKey: "VOL-1"))
        XCTAssertFalse(prefs.isBootloaderVerified(diskKey: "VOL-2"))

        prefs.forgetBootloaderVerified(diskKey: "VOL-1")
        XCTAssertFalse(prefs.isBootloaderVerified(diskKey: "VOL-1"))
    }

    func testNilOrEmptyKeyIsNeverRecorded() {
        let prefs = makePreferences()
        prefs.recordBootloaderVerified(diskKey: nil)
        prefs.recordBootloaderVerified(diskKey: "")
        XCTAssertTrue(prefs.bootloaderVerifiedDisks.isEmpty)
    }

    func testPersistsAcrossInstances() {
        let suite = "BootloaderVerified-\(UUID().uuidString)"
        let first = AppPreferences(defaults: UserDefaults(suiteName: suite)!)
        first.recordBootloaderVerified(diskKey: "VOL-9")

        let second = AppPreferences(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertTrue(second.isBootloaderVerified(diskKey: "VOL-9"))
    }
}
