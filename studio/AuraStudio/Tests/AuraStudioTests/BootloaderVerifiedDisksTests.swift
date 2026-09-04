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

/// ST-143: el registro pasa de "cuándo lo verificamos" a "qué bootloader
/// verificamos", y de ahí sale la oferta de "Actualizar el arranque".
/// Los mismos casos que `BootloaderUpdateTests.cs` en el port.
@MainActor
final class BootloaderUpdateTests: XCTestCase {
    private func makePreferences(suite: String = "BootloaderUpdate-\(UUID().uuidString)") -> AppPreferences {
        AppPreferences(defaults: UserDefaults(suiteName: suite)!)
    }

    // MARK: - El registro

    func testTheHashIsWhatGetsRecorded() {
        let prefs = makePreferences()
        prefs.recordBootloaderVerified(diskKey: "VOL-1", hash: "abc123")
        XCTAssertEqual(prefs.bootloaderHash(diskKey: "VOL-1"), "abc123")
        XCTAssertTrue(prefs.isBootloaderVerified(diskKey: "VOL-1"))
    }

    func testWithoutAHashItIsRecordedAsUnknown() {
        // Lo que pasa cuando el disco se ve corriendo Aura/Rockbox: hay
        // bootloader nuestro, pero nadie sabe de qué versión.
        let prefs = makePreferences()
        prefs.recordBootloaderVerified(diskKey: "VOL-1")
        XCTAssertEqual(prefs.bootloaderHash(diskKey: "VOL-1"), BootloaderUpdate.unknownBootloader)
    }

    func testARecordFromBeforeThisChangeMigratesToUnknown() {
        // Antes de ST-143 el valor era una fecha. Perder esas entradas
        // obligaría a un DFU innecesario en cada iPod ya instalado.
        let suite = "BootloaderUpdate-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(["VOL-VIEJO": Date()], forKey: "aura.bootloaderVerifiedDisks")

        let prefs = makePreferences(suite: suite)
        XCTAssertTrue(prefs.isBootloaderVerified(diskKey: "VOL-VIEJO"))
        XCTAssertEqual(prefs.bootloaderHash(diskKey: "VOL-VIEJO"), BootloaderUpdate.unknownBootloader)
    }

    // MARK: - La regla

    func testADifferentBootloaderIsOffered() {
        XCTAssertTrue(BootloaderUpdate.isAvailable(recordedHash: "viejo", embeddedHash: "nuevo",
                                                   hasOurFirmware: true))
        XCTAssertEqual(BootloaderUpdate.reason(recordedHash: "viejo", embeddedHash: "nuevo",
                                               hasOurFirmware: true), .differentBootloader)
    }

    func testTheSameBootloaderIsNotOffered() {
        XCTAssertFalse(BootloaderUpdate.isAvailable(recordedHash: "igual", embeddedHash: "igual",
                                                    hasOurFirmware: true))
        XCTAssertNil(BootloaderUpdate.reason(recordedHash: "igual", embeddedHash: "igual",
                                             hasOurFirmware: true))
    }

    func testAnUnknownRecordIsOfferedAsUnknown() {
        XCTAssertEqual(BootloaderUpdate.reason(recordedHash: BootloaderUpdate.unknownBootloader,
                                               embeddedHash: "nuevo", hasOurFirmware: true),
                       .unknownBootloader)
    }

    func testADiskWeNeverVerifiedIsAlsoUnknown() {
        // Lo instaló otra Mac: hay firmware nuestro en el disco, pero
        // esta instalación nunca grabó ese arranque.
        XCTAssertEqual(BootloaderUpdate.reason(recordedHash: nil, embeddedHash: "nuevo",
                                               hasOurFirmware: true),
                       .unknownBootloader)
    }

    func testWithoutOurFirmwareNothingIsOffered() {
        // Un iPod de fábrica: lo que corresponde es instalar, no
        // "actualizar el arranque".
        XCTAssertFalse(BootloaderUpdate.isAvailable(recordedHash: nil, embeddedHash: "nuevo",
                                                    hasOurFirmware: false))
        XCTAssertFalse(BootloaderUpdate.isAvailable(recordedHash: "viejo", embeddedHash: "nuevo",
                                                    hasOurFirmware: false))
    }

    func testWithoutAnEmbeddedBootloaderNothingIsOffered() {
        // Una build sin `fetch-firmware.sh`: no hay con qué comparar, y
        // ofrecer flashear algo que no existe sería peor que no ofrecer.
        XCTAssertFalse(BootloaderUpdate.isAvailable(recordedHash: "viejo", embeddedHash: nil,
                                                    hasOurFirmware: true))
        XCTAssertFalse(BootloaderUpdate.isAvailable(recordedHash: "viejo", embeddedHash: "",
                                                    hasOurFirmware: true))
    }
}
