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

    // MARK: - La ayuda de último recurso en la pantalla de DFU

    func testTheServicePauseIsNotOfferedBeforeTheWait() {
        // El caso normal tiene que seguir siendo de CERO contraseñas:
        // antes del plazo, la opción no existe.
        XCTAssertFalse(BootloaderUpdate.shouldOfferServicePause(
            mode: .updateBootloader, secondsWaiting: 0, isDFUDetected: false, alreadyPaused: false))
        XCTAssertFalse(BootloaderUpdate.shouldOfferServicePause(
            mode: .updateBootloader, secondsWaiting: BootloaderUpdate.assistDelaySeconds - 1,
            isDFUDetected: false, alreadyPaused: false))
    }

    func testAfterTheWaitWithoutDetectionItIsOffered() {
        XCTAssertTrue(BootloaderUpdate.shouldOfferServicePause(
            mode: .updateBootloader, secondsWaiting: BootloaderUpdate.assistDelaySeconds,
            isDFUDetected: false, alreadyPaused: false))
    }

    func testWithTheIPodAlreadyDetectedThereIsNothingToHelpWith() {
        XCTAssertFalse(BootloaderUpdate.shouldOfferServicePause(
            mode: .updateBootloader, secondsWaiting: 999, isDFUDetected: true, alreadyPaused: false))
    }

    func testItIsNotOfferedTwice() {
        // Ya pausados, volver a pedir la contraseña no arreglaría nada.
        XCTAssertFalse(BootloaderUpdate.shouldOfferServicePause(
            mode: .updateBootloader, secondsWaiting: 999, isDFUDetected: false, alreadyPaused: true))
    }

    func testTheFullInstallerNeverOffersItHere() {
        // Ese flujo ya lo propone ANTES de llegar al DFU: ofrecerlo dos
        // veces sería pedir la contraseña dos veces por lo mismo.
        for mode in [InstallerMode.install, .restore] {
            XCTAssertFalse(BootloaderUpdate.shouldOfferServicePause(
                mode: mode, secondsWaiting: 999, isDFUDetected: false, alreadyPaused: false))
        }
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
