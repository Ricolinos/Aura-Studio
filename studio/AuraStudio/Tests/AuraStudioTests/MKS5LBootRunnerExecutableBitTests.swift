import XCTest
@testable import AuraStudio

/// ST-018: el runner rechaza al crearse un binario que no se puede
/// ejecutar -- un mks5lboot sin bit de ejecucion (asi llega desde un
/// Release de GitHub) dejaba al instalador en "Esperando modo DFU..."
/// para siempre, con el iPod ya en DFU.
final class MKS5LBootRunnerExecutableBitTests: XCTestCase {
    private func makeTemporaryBinary(executable: Bool) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mks5lboot-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("mks5lboot")
        try "#!/bin/sh\nexit 1\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: executable ? 0o755 : 0o644],
            ofItemAtPath: url.path
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return url
    }

    func testInitRejectsBinaryWithoutExecuteBit() throws {
        let url = try makeTemporaryBinary(executable: false)
        XCTAssertThrowsError(try MKS5LBootRunner(executableURL: url)) { error in
            XCTAssertEqual(
                error as? MKS5LBootRunner.RunError,
                .binaryNotExecutable(path: url.path)
            )
        }
    }

    func testInitAcceptsExecutableBinary() throws {
        let url = try makeTemporaryBinary(executable: true)
        let runner = try MKS5LBootRunner(executableURL: url)
        XCTAssertEqual(runner.executableURL, url)
        // Un mks5lboot que termina con exit 1 = "no hay iPod en DFU",
        // sin error: la ausencia de dispositivo no es un fallo.
        XCTAssertNil(try runner.scanDFU())
    }

    func testInitRejectsMissingBinary() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-existe-\(UUID().uuidString)")
        XCTAssertThrowsError(try MKS5LBootRunner(executableURL: url)) { error in
            XCTAssertEqual(error as? MKS5LBootRunner.RunError, .binaryNotFound)
        }
    }

    func testNotExecutableErrorExplainsItself() {
        let message = MKS5LBootRunner.RunError.binaryNotExecutable(path: "/x/mks5lboot").errorDescription ?? ""
        XCTAssertTrue(message.contains("permiso de ejecución"))
        XCTAssertTrue(message.contains("/x/mks5lboot"))
    }
}
