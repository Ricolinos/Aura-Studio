import XCTest
@testable import AuraStudio

/// ST-016: la unica lectura real de "que firmware corre" es lo que el
/// propio firmware anuncia por USB. Estos tests fijan la clasificacion
/// contra los descriptores reales (iPod del dueño en modo disco de Apple,
/// leidos con `ioreg`; y los de Rockbox, `usb_core.c` del firmware).
final class USBDeviceIdentityTests: XCTestCase {
    func testAppleDiskModeIsClassifiedAsApple() {
        XCTAssertEqual(RunningFirmware.classify(vendorName: "Apple Inc.", productName: "iPod"), .apple)
    }

    func testRockboxDescriptorsAreClassifiedAsRockboxFamily() {
        XCTAssertEqual(RunningFirmware.classify(vendorName: "Rockbox.org", productName: "Rockbox media player"),
                       .rockboxFamily)
        // Basta con que una de las dos cadenas lo diga.
        XCTAssertEqual(RunningFirmware.classify(vendorName: "", productName: "Rockbox media player"),
                       .rockboxFamily)
    }

    func testAnythingElseIsUnknownNeverGuessed() {
        XCTAssertEqual(RunningFirmware.classify(vendorName: "", productName: ""), .unknown)
        XCTAssertEqual(RunningFirmware.classify(vendorName: "Apple Inc.", productName: "iPad"), .unknown)
        XCTAssertEqual(RunningFirmware.classify(vendorName: "Ugreen", productName: "USB3 Hub"), .unknown)
    }

    func testIPodClassicVIDPIDIsRecognised() {
        let ipod = USBDeviceIdentity(vendorName: "Apple Inc.", productName: "iPod", serialNumber: "000A270013923F13",
                                     vendorID: 0x05AC, productID: 0x1261)
        XCTAssertTrue(ipod.isIPodClassicUSB)
        XCTAssertEqual(ipod.runningFirmware, .apple)
    }

    /// Un iPad tambien es 0x05AC -- el PID es lo que decide.
    func testOtherAppleDevicesAreNotIPodClassic() {
        let ipad = USBDeviceIdentity(vendorName: "Apple Inc.", productName: "iPad", serialNumber: nil,
                                     vendorID: 0x05AC, productID: 0x12AB)
        XCTAssertFalse(ipad.isIPodClassicUSB)
    }

    func testRockboxKeepsAppleVIDPIDSoIdentityStillMatches() {
        let running = USBDeviceIdentity(vendorName: "Rockbox.org", productName: "Rockbox media player",
                                        serialNumber: nil, vendorID: 0x05AC, productID: 0x1261)
        XCTAssertTrue(running.isIPodClassicUSB)
        XCTAssertEqual(running.runningFirmware, .rockboxFamily)
    }
}
