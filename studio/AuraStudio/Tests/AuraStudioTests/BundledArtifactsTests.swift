import XCTest
@testable import AuraStudio

final class BundledArtifactsTests: XCTestCase {
    func testParseChecksumsRealFormat() {
        // Mismo formato exacto que produce `shasum -a 256` (usado por
        // tools/... al generar checksums.txt, mismo formato que produce el firmware).
        let text = """
        e30b3c3d2a0eca694637a5753a554f525a869f07462d7c8354d7f6ed9a79871f  rockbox.ipod
        9768fb8052ea3f253fe10cde8908aeebde7c3ebb27c32efda0c2dde4467eac39  bootloader-ipod6g.ipod
        e5cfd5ff9ff883400e0449911394e3bb8fba6c10a3e5693311b67f8aaf86ebed  mks5lboot
        """
        let parsed = BundledArtifacts.parseChecksums(text)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed["rockbox.ipod"], "e30b3c3d2a0eca694637a5753a554f525a869f07462d7c8354d7f6ed9a79871f")
        XCTAssertEqual(parsed["bootloader-ipod6g.ipod"], "9768fb8052ea3f253fe10cde8908aeebde7c3ebb27c32efda0c2dde4467eac39")
        XCTAssertEqual(parsed["mks5lboot"], "e5cfd5ff9ff883400e0449911394e3bb8fba6c10a3e5693311b67f8aaf86ebed")
    }

    func testParseChecksumsIgnoresBlankLines() {
        let text = "abc123  file.bin\n\n\ndef456  other.bin\n"
        let parsed = BundledArtifacts.parseChecksums(text)
        XCTAssertEqual(parsed.count, 2)
    }

    func testSha256HexMatchesKnownVector() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "hello world\n".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let hash = try BundledArtifacts.sha256Hex(of: tmp)
        // sha256sum de "hello world\n" -- vector conocido.
        XCTAssertEqual(hash, "a948904f2f0f479b8f8197694b30184b0d2ed1c1cd2a1ec0fb85d299a192a447")
    }

    func testVerifyAllThrowsOnMismatch() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try "not the real firmware".write(to: dir.appendingPathComponent("rockbox.ipod"), atomically: true, encoding: .utf8)
        try "not the real bootloader".write(to: dir.appendingPathComponent("bootloader-ipod6g.ipod"), atomically: true, encoding: .utf8)
        try "not the real tool".write(to: dir.appendingPathComponent("mks5lboot"), atomically: true, encoding: .utf8)
        try """
        0000000000000000000000000000000000000000000000000000000000000000  rockbox.ipod
        0000000000000000000000000000000000000000000000000000000000000000  bootloader-ipod6g.ipod
        0000000000000000000000000000000000000000000000000000000000000000  mks5lboot
        """.write(to: dir.appendingPathComponent("checksums.txt"), atomically: true, encoding: .utf8)

        let bundle = Bundle(url: dir)!
        let artifacts = BundledArtifacts(bundle: bundle)

        XCTAssertThrowsError(try artifacts.verifyAll()) { error in
            guard case InstallerError.checksumMismatch = error else {
                return XCTFail("expected checksumMismatch, got \(error)")
            }
        }
    }

    /// Arma un rockbox.zip real (con /usr/bin/zip, misma herramienta que
    /// package_dist.sh) conteniendo exactamente las rutas dadas, para
    /// probar verifyRockboxTreeContents() sin depender de un Release real.
    private func makeZipFixture(entries: [String]) throws -> URL {
        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        for entry in entries {
            let fileURL = workDir.appendingPathComponent(entry)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "x".write(to: fileURL, atomically: true, encoding: .utf8)
        }
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = workDir
        process.arguments = ["-rq", zipURL.path, "."]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        try FileManager.default.removeItem(at: workDir)
        return zipURL
    }

    // D-297/D-298 (Aura-Firmware), ST-018: rockbox.zip con checksum
    // correcto pero sin codecs/rocks reales -- verifyAll() no lo hubiera
    // detectado antes de este pase (el bug real ocurrido en producción:
    // el Release publicado tenía el checksum consistente consigo mismo).
    func testVerifyRockboxTreeContentsPassesWithRequiredEntries() throws {
        let zipURL = try makeZipFixture(entries: BundledArtifacts.requiredRockboxTreeEntries)
        defer { try? FileManager.default.removeItem(at: zipURL) }
        XCTAssertNoThrow(try BundledArtifacts.verifyRockboxTreeContents(at: zipURL))
    }

    func testVerifyRockboxTreeContentsFailsWithoutRequiredEntries() throws {
        let zipURL = try makeZipFixture(entries: [".rockbox/fonts/a26-title-20.fnt"])
        defer { try? FileManager.default.removeItem(at: zipURL) }
        XCTAssertThrowsError(try BundledArtifacts.verifyRockboxTreeContents(at: zipURL)) { error in
            guard case InstallerError.incompleteRockboxTree(let missing) = error else {
                return XCTFail("expected incompleteRockboxTree, got \(error)")
            }
            XCTAssertEqual(Set(missing), Set(BundledArtifacts.requiredRockboxTreeEntries))
        }
    }
}
