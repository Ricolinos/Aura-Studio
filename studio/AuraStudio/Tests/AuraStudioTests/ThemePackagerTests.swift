import XCTest
@testable import AuraStudio

/// Arma una carpeta con el layout de design-system/out/ del firmware
/// (fonts/a26-<rol>-<px>.fnt, icons/masks/*.bmp, icons/{light,dark}/ y
/// icons/aura/{backgrounds,tile-icons}/ opcionales) -- lo que
/// ThemePackager espera como `sourceRoot`.
enum DesignSystemOutFixture {
    static func make(includeOptional: Bool = false) -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DesignSystemOut-\(UUID().uuidString)")
        let fontsDir = root.appendingPathComponent("fonts")
        let masksDir = root.appendingPathComponent("icons/masks")
        try! FileManager.default.createDirectory(at: fontsDir, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: masksDir, withIntermediateDirectories: true)

        for (role, px) in ThemeFormat.fontRoles {
            FileManager.default.createFile(atPath: fontsDir.appendingPathComponent("a26-\(role)-\(px).fnt").path,
                                            contents: Data("fake-\(role)".utf8))
        }
        FileManager.default.createFile(atPath: masksDir.appendingPathComponent("music-12.bmp").path, contents: Data("m".utf8))

        if includeOptional {
            let lightDir = root.appendingPathComponent("icons/light")
            try! FileManager.default.createDirectory(at: lightDir, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: lightDir.appendingPathComponent("music-12.bmp").path, contents: Data("l".utf8))

            let backgroundsDir = root.appendingPathComponent("icons/aura/backgrounds")
            try! FileManager.default.createDirectory(at: backgroundsDir, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: backgroundsDir.appendingPathComponent("pink.bmp").path, contents: Data("p".utf8))
        }

        return root
    }
}

final class ThemePackagerTests: XCTestCase {
    private var tempRoots: [URL] = []

    override func tearDownWithError() throws {
        for root in tempRoots { try? FileManager.default.removeItem(at: root) }
        tempRoots = []
    }

    private func track(_ url: URL) -> URL {
        tempRoots.append(url)
        return url
    }

    func testPackageRenamesFontsByRole() throws {
        let source = track(DesignSystemOutFixture.make())
        let destination = track(FileManager.default.temporaryDirectory.appendingPathComponent("Packaged-\(UUID().uuidString)"))
        let manifest = AuraThemeManifest(id: "test", name: "Test")

        try ThemePackager.package(sourceRoot: source, manifest: manifest, destinationRoot: destination)

        for (role, _) in ThemeFormat.fontRoles {
            XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("fonts/\(role).fnt").path),
                          "falta fonts/\(role).fnt")
        }
    }

    func testPackageCopiesMasksAndWritesManifest() throws {
        let source = track(DesignSystemOutFixture.make())
        let destination = track(FileManager.default.temporaryDirectory.appendingPathComponent("Packaged-\(UUID().uuidString)"))
        let manifest = AuraThemeManifest(id: "test", name: "Test", license: .open, redistributable: true)

        try ThemePackager.package(sourceRoot: source, manifest: manifest, destinationRoot: destination)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("icons/masks/music-12.bmp").path))
        let cfgText = try String(contentsOf: destination.appendingPathComponent("theme.cfg"), encoding: .utf8)
        XCTAssertTrue(cfgText.contains("theme_id: test"))
        XCTAssertTrue(cfgText.contains("theme_redistributable: yes"))
    }

    func testPackageIncludesOptionalAssetsWhenPresent() throws {
        let source = track(DesignSystemOutFixture.make(includeOptional: true))
        let destination = track(FileManager.default.temporaryDirectory.appendingPathComponent("Packaged-\(UUID().uuidString)"))
        let manifest = AuraThemeManifest(id: "test", name: "Test")

        try ThemePackager.package(sourceRoot: source, manifest: manifest, destinationRoot: destination)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("icons/light/music-12.bmp").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("backgrounds/pink.bmp").path))
    }

    func testPackageSkipsAbsentOptionalAssetsWithoutFailing() throws {
        let source = track(DesignSystemOutFixture.make(includeOptional: false))
        let destination = track(FileManager.default.temporaryDirectory.appendingPathComponent("Packaged-\(UUID().uuidString)"))
        let manifest = AuraThemeManifest(id: "test", name: "Test")

        XCTAssertNoThrow(try ThemePackager.package(sourceRoot: source, manifest: manifest, destinationRoot: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("icons/light").path))
    }

    func testMissingSourceFontThrows() {
        let source = track(FileManager.default.temporaryDirectory.appendingPathComponent("Incomplete-\(UUID().uuidString)"))
        try! FileManager.default.createDirectory(at: source.appendingPathComponent("fonts"), withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: source.appendingPathComponent("icons/masks"), withIntermediateDirectories: true)
        let destination = track(FileManager.default.temporaryDirectory.appendingPathComponent("Packaged-\(UUID().uuidString)"))
        let manifest = AuraThemeManifest(id: "test", name: "Test")

        XCTAssertThrowsError(try ThemePackager.package(sourceRoot: source, manifest: manifest, destinationRoot: destination)) { error in
            XCTAssertEqual(error as? ThemePackagerError, .sourceFontMissing("a26-title-20.fnt"))
        }
    }

    func testMissingSourceMasksThrows() {
        let source = track(FileManager.default.temporaryDirectory.appendingPathComponent("NoMasks-\(UUID().uuidString)"))
        let fontsDir = source.appendingPathComponent("fonts")
        try! FileManager.default.createDirectory(at: fontsDir, withIntermediateDirectories: true)
        for (role, px) in ThemeFormat.fontRoles {
            FileManager.default.createFile(atPath: fontsDir.appendingPathComponent("a26-\(role)-\(px).fnt").path, contents: Data())
        }
        let destination = track(FileManager.default.temporaryDirectory.appendingPathComponent("Packaged-\(UUID().uuidString)"))
        let manifest = AuraThemeManifest(id: "test", name: "Test")

        XCTAssertThrowsError(try ThemePackager.package(sourceRoot: source, manifest: manifest, destinationRoot: destination)) { error in
            XCTAssertEqual(error as? ThemePackagerError, .sourceMasksMissing)
        }
    }
}
