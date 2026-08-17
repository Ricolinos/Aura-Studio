import XCTest
@testable import AuraStudio

/// Arma un paquete de tema MINIMO pero completo (14 fuentes vacías +
/// 801 máscaras vacías -- ThemeValidator solo comprueba existencia y
/// cantidad, ver la nota en ThemeValidator.swift sobre por qué no
/// parsea la cabecera .fnt en esta pasada) bajo un directorio temporal.
enum ThemeFixture {
    static func makeCompletePackage(id: String = "fixture-tema",
                                     name: String = "Fixture",
                                     format: Int = ThemeFormat.current,
                                     omitMasks: Int = 0,
                                     omitFontRoles: [String] = []) -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ThemeFixture-\(UUID().uuidString)")
        let fontsDir = root.appendingPathComponent("fonts")
        let masksDir = root.appendingPathComponent("icons/masks")
        try! FileManager.default.createDirectory(at: fontsDir, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: masksDir, withIntermediateDirectories: true)

        for (role, _) in ThemeFormat.fontRoles where !omitFontRoles.contains(role) {
            FileManager.default.createFile(atPath: fontsDir.appendingPathComponent("\(role).fnt").path, contents: Data("fake".utf8))
        }

        var written = 0
        let required = ThemeFormat.requiredMaskCount - omitMasks
        outer: for key in 0..<ThemeFormat.iconKeyCount {
            for size in ThemeFormat.iconSizes {
                guard written < required else { break outer }
                FileManager.default.createFile(atPath: masksDir.appendingPathComponent("icon\(key)-\(size).bmp").path, contents: Data("m".utf8))
                written += 1
            }
        }

        let manifest = "theme_format: \(format)\ntheme_id: \(id)\ntheme_name: \(name)\n"
        try! manifest.write(to: root.appendingPathComponent("theme.cfg"), atomically: true, encoding: .utf8)

        return root
    }
}

final class ThemeValidatorTests: XCTestCase {
    private var tempRoots: [URL] = []

    override func tearDownWithError() throws {
        for root in tempRoots { try? FileManager.default.removeItem(at: root) }
        tempRoots = []
    }

    private func fixture(_ url: URL) -> URL {
        tempRoots.append(url)
        return url
    }

    func testCompletePackageIsValid() {
        let root = fixture(ThemeFixture.makeCompletePackage())
        switch ThemeValidator.validate(packageRoot: root, firmwareSupportedFormat: 1) {
        case .success(let manifest):
            XCTAssertEqual(manifest.id, "fixture-tema")
        case .failure(let error):
            XCTFail("no debería fallar: \(error)")
        }
    }

    func testMissingManifestFails() {
        let root = fixture(FileManager.default.temporaryDirectory.appendingPathComponent("Empty-\(UUID().uuidString)"))
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertEqual(ThemeValidator.validate(packageRoot: root, firmwareSupportedFormat: 1),
                        .failure(.manifestMissing))
    }

    func testFormatNewerThanSupportedFails() {
        let root = fixture(ThemeFixture.makeCompletePackage(format: 99))
        XCTAssertEqual(ThemeValidator.validate(packageRoot: root, firmwareSupportedFormat: 1),
                        .failure(.formatUnsupported(found: 99, supported: 1)))
    }

    func testFormatFallsBackToCurrentWhenFirmwareUnknown() {
        let root = fixture(ThemeFixture.makeCompletePackage(format: ThemeFormat.current))
        switch ThemeValidator.validate(packageRoot: root, firmwareSupportedFormat: nil) {
        case .success: break
        case .failure(let error): XCTFail("debería usar ThemeFormat.current como mejor esfuerzo: \(error)")
        }
    }

    func testInvalidIdInManifestFails() {
        let root = fixture(ThemeFixture.makeCompletePackage(id: "Con Mayusculas"))
        XCTAssertEqual(ThemeValidator.validate(packageRoot: root, firmwareSupportedFormat: 1),
                        .failure(.invalidId("Con Mayusculas")))
    }

    func testMissingFontFails() {
        let root = fixture(ThemeFixture.makeCompletePackage(omitFontRoles: ["ds_medium_16"]))
        XCTAssertEqual(ThemeValidator.validate(packageRoot: root, firmwareSupportedFormat: 1),
                        .failure(.missingFonts(["ds_medium_16"])))
    }

    func testMissingMasksFails() {
        let root = fixture(ThemeFixture.makeCompletePackage(omitMasks: 5))
        guard case .failure(.missingMasks(let found, let required)) = ThemeValidator.validate(packageRoot: root, firmwareSupportedFormat: 1) else {
            return XCTFail("debería fallar por máscaras faltantes")
        }
        XCTAssertEqual(required, ThemeFormat.requiredMaskCount)
        XCTAssertEqual(found, ThemeFormat.requiredMaskCount - 5)
    }
}
