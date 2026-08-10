import XCTest
@testable import AuraStudio

final class MKS5LBootRunnerTests: XCTestCase {
    func testParseDFUStateFound() {
        let output = "[INFO] DFU scan:\n[INFO] DFU device state: 2\n"
        XCTAssertEqual(MKS5LBootRunner.parseDFUState(from: output), 2)
    }

    func testParseDFUStateMultilineWithNoise() {
        let output = "[INFO] DFU scan:\nsome other line\n[INFO] DFU device state: 5\ntrailing\n"
        XCTAssertEqual(MKS5LBootRunner.parseDFUState(from: output), 5)
    }

    func testParseDFUStateNotFound() {
        let output = "[INFO] DFU scan:\n[ERR] Could not open USB device\n"
        XCTAssertNil(MKS5LBootRunner.parseDFUState(from: output))
    }

    func testParseDFUStateEmptyOutput() {
        XCTAssertNil(MKS5LBootRunner.parseDFUState(from: ""))
    }
}
