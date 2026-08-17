import XCTest
@testable import AuraStudio

@MainActor
final class ThemeInstallerTests: XCTestCase {
    private var fakeIPod: URL!

    override func setUpWithError() throws {
        fakeIPod = FileManager.default.temporaryDirectory.appendingPathComponent("FakeIPod-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeIPod, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fakeIPod)
    }

    private func writeAuraConfig(_ text: String) throws {
        let dir = fakeIPod.appendingPathComponent(".rockbox/aura")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try text.write(to: dir.appendingPathComponent("aura.cfg"), atomically: true, encoding: .utf8)
    }

    // MARK: - activeThemeID / supportedThemeFormat

    func testActiveThemeIDDefaultsWhenNoConfig() {
        XCTAssertEqual(ThemeInstaller.activeThemeID(mountPath: fakeIPod.path), "default")
    }

    func testActiveThemeIDReadsConfig() throws {
        try writeAuraConfig("theme: 1\ntheme_id: mi-tema\n")
        XCTAssertEqual(ThemeInstaller.activeThemeID(mountPath: fakeIPod.path), "mi-tema")
    }

    func testActiveThemeIDEmptyValueIsDefault() throws {
        try writeAuraConfig("theme: 1\ntheme_id: \n")
        XCTAssertEqual(ThemeInstaller.activeThemeID(mountPath: fakeIPod.path), "default")
    }

    func testSupportedFormatReadsConfig() throws {
        try writeAuraConfig("theme_format_supported: 1\n")
        XCTAssertEqual(ThemeInstaller.supportedThemeFormat(mountPath: fakeIPod.path), 1)
    }

    func testSupportedFormatNilWhenAbsent() throws {
        try writeAuraConfig("theme: 1\n")
        XCTAssertNil(ThemeInstaller.supportedThemeFormat(mountPath: fakeIPod.path))
    }

    // MARK: - install / listInstalled

    func testInstallCopiesPackageAndListsIt() async throws {
        let source = ThemeFixture.makeCompletePackage(id: "instalado", name: "Instalado")
        defer { try? FileManager.default.removeItem(at: source) }

        let manifest = try await ThemeInstaller.install(packageRoot: source, mountPath: fakeIPod.path)
        XCTAssertEqual(manifest.id, "instalado")

        let installed = ThemeInstaller.listInstalled(mountPath: fakeIPod.path)
        XCTAssertEqual(installed.count, 1)
        XCTAssertEqual(installed.first?.id, "instalado")
        XCTAssertEqual(installed.first?.name, "Instalado")
        XCTAssertTrue(installed.first?.loadable ?? false)
    }

    func testListInstalledMarksInvalidPackageAsNotLoadable() async throws {
        let source = ThemeFixture.makeCompletePackage(id: "roto", name: "Roto", format: 99)
        defer { try? FileManager.default.removeItem(at: source) }

        // install() valida ANTES de copiar -- para dejar un paquete
        // roto instalado (y probar que listInstalled() lo detecta), se
        // copia directo con ditto, sin pasar por ThemeInstaller.install().
        let root = fakeIPod.appendingPathComponent(ThemeInstaller.themesRelativePath)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [source.path, root.appendingPathComponent("roto").path]
        try process.run()
        process.waitUntilExit()

        let installed = ThemeInstaller.listInstalled(mountPath: fakeIPod.path)
        XCTAssertEqual(installed.count, 1)
        XCTAssertFalse(installed.first?.loadable ?? true)
        XCTAssertNotNil(installed.first?.reason)
    }

    func testInstallRejectsPackageWithIncompatibleFormat() async throws {
        try writeAuraConfig("theme_format_supported: 1\n")
        let source = ThemeFixture.makeCompletePackage(id: "futuro", format: 99)
        defer { try? FileManager.default.removeItem(at: source) }

        do {
            _ = try await ThemeInstaller.install(packageRoot: source, mountPath: fakeIPod.path)
            XCTFail("debería rechazar un theme_format mayor al soportado")
        } catch ThemeInstallerError.validationFailed(.formatUnsupported(let found, let supported)) {
            XCTAssertEqual(found, 99)
            XCTAssertEqual(supported, 1)
        }
    }

    // MARK: - activate

    func testActivatePreservesOtherConfigLines() throws {
        try writeAuraConfig("theme: 1\nlanguage: 0\ntheme_id: viejo\n")
        try ThemeInstaller.activate(id: "nuevo", mountPath: fakeIPod.path)

        let text = try String(contentsOf: fakeIPod.appendingPathComponent(".rockbox/aura/aura.cfg"), encoding: .utf8)
        XCTAssertTrue(text.contains("theme: 1"))
        XCTAssertTrue(text.contains("language: 0"))
        XCTAssertTrue(text.contains("theme_id: nuevo"))
        XCTAssertFalse(text.contains("theme_id: viejo"))
    }

    func testActivateAddsKeyWhenAbsent() throws {
        try writeAuraConfig("theme: 1\n")
        try ThemeInstaller.activate(id: "recien-activado", mountPath: fakeIPod.path)
        let text = try String(contentsOf: fakeIPod.appendingPathComponent(".rockbox/aura/aura.cfg"), encoding: .utf8)
        XCTAssertTrue(text.contains("theme_id: recien-activado"))
    }

    func testActivateRejectsInvalidId() {
        XCTAssertThrowsError(try ThemeInstaller.activate(id: "Invalido Con Espacio", mountPath: fakeIPod.path)) { error in
            XCTAssertEqual(error as? ThemeInstallerError, .invalidId("Invalido Con Espacio"))
        }
    }

    // MARK: - delete

    func testDeleteRemovesInstalledTheme() async throws {
        let source = ThemeFixture.makeCompletePackage(id: "para-borrar")
        defer { try? FileManager.default.removeItem(at: source) }
        _ = try await ThemeInstaller.install(packageRoot: source, mountPath: fakeIPod.path)

        try ThemeInstaller.delete(id: "para-borrar", mountPath: fakeIPod.path)

        XCTAssertTrue(ThemeInstaller.listInstalled(mountPath: fakeIPod.path).isEmpty)
    }

    func testDeleteRejectsDefault() {
        XCTAssertThrowsError(try ThemeInstaller.delete(id: "default", mountPath: fakeIPod.path)) { error in
            XCTAssertEqual(error as? ThemeInstallerError, .cannotDeleteDefault)
        }
    }

    func testDeleteRejectsInvalidId() {
        XCTAssertThrowsError(try ThemeInstaller.delete(id: "../etc", mountPath: fakeIPod.path)) { error in
            XCTAssertEqual(error as? ThemeInstallerError, .invalidId("../etc"))
        }
    }

    // MARK: - rutas invalidas

    func testOperationsRejectEmptyMountPath() async {
        do {
            _ = try await ThemeInstaller.install(packageRoot: fakeIPod, mountPath: "")
            XCTFail("debería rechazar mountPath vacío")
        } catch ThemeInstallerError.invalidMountPath {
            // esperado
        } catch {
            XCTFail("error inesperado: \(error)")
        }
    }

    func testOperationsRejectRelativeMountPath() {
        XCTAssertThrowsError(try ThemeInstaller.activate(id: "default", mountPath: "relative/path")) { error in
            XCTAssertEqual(error as? ThemeInstallerError, .invalidMountPath)
        }
    }
}
