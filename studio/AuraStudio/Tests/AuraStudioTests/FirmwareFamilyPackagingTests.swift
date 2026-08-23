import XCTest
@testable import AuraStudio

/// ST-047: dos familias de firmware embebidas. Lo que se fija aqui es el
/// CONTRATO de empaquetado que el instalador da por hecho: los artefactos
/// de Aura en la raiz de Resources (donde siempre estuvieron), los de
/// Metro en `metro/`, cada uno con su `firmware-version.txt`.
final class FirmwareFamilyPackagingTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("Bundle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("metro"),
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(_ relative: String, _ text: String) throws {
        try text.write(to: dir.appendingPathComponent(relative), atomically: true, encoding: .utf8)
    }

    func testEachFamilyResolvesItsOwnSubdirectory() throws {
        try write("rockbox.ipod", "aura firmware")
        try write("firmware-version.txt", "v0.3.1-beta\n")
        try write("metro/rockbox.ipod", "metro firmware")
        try write("metro/firmware-version.txt", "v0.4.0\n")

        let bundle = try XCTUnwrap(Bundle(url: dir))
        let aura = BundledArtifacts(bundle: bundle, family: .aura)
        let metro = BundledArtifacts(bundle: bundle, family: .metro)

        XCTAssertEqual(try String(contentsOf: XCTUnwrap(aura.url(for: .firmware)), encoding: .utf8), "aura firmware")
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(metro.url(for: .firmware)), encoding: .utf8), "metro firmware")
        XCTAssertEqual(aura.releaseTag, "v0.3.1-beta")
        XCTAssertEqual(metro.releaseTag, "v0.4.0")
    }

    /// Sin carpeta `metro/` (una build vieja, o fetch-firmware.sh corrido
    /// solo para Aura) la familia Metro no resuelve nada -- y eso es un
    /// fallo LIMPIO (`missingBundledArtifact`), no un silencio.
    func testMissingFamilyFolderIsAnExplicitMiss() throws {
        try write("rockbox.ipod", "aura firmware")
        let bundle = try XCTUnwrap(Bundle(url: dir))
        let metro = BundledArtifacts(bundle: bundle, family: .metro)
        XCTAssertNil(metro.url(for: .firmware))
        XCTAssertNil(metro.releaseTag)
        XCTAssertThrowsError(try metro.verifyAll()) { error in
            guard case InstallerError.missingBundledArtifact = error else {
                return XCTFail("esperaba missingBundledArtifact, llego \(error)")
            }
        }
    }

    /// Una familia desconocida no es instalable y no tiene artefactos --
    /// el instalador nunca debe llegar a pedirselos.
    func testUnknownFamilyIsNotInstallable() {
        XCTAssertFalse(FirmwareFamily.unknown("zeta").isInstallable)
        XCTAssertNil(FirmwareFamily.unknown("zeta").installedTreeSentinel)
        XCTAssertEqual(FirmwareFamily.installable, [.aura, .metro])
    }

    /// El centinela de "el arbol se extrajo completo" es por familia: cada
    /// una trae sus propias fuentes, y el de Aura (a26-title-20.fnt) no
    /// existe en un rockbox.zip de Metro -- con el centinela viejo, toda
    /// instalacion de Metro habria fallado "incompleta" tras extraerse bien.
    func testTreeSentinelIsPerFamily() {
        XCTAssertEqual(FirmwareFamily.aura.installedTreeSentinel, ".rockbox/fonts/a26-title-20.fnt")
        XCTAssertEqual(FirmwareFamily.metro.installedTreeSentinel, ".rockbox/fonts/metro-list-20.fnt")
    }

    // MARK: - preferencia

    @MainActor
    func testPreferencePersistsAndDefaultsToAura() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ST047-\(UUID().uuidString)"))
        let prefs = AppPreferences(defaults: defaults)
        XCTAssertEqual(prefs.firmwareFamilyToInstall, .aura)

        prefs.firmwareFamilyToInstall = .metro
        XCTAssertEqual(AppPreferences(defaults: defaults).firmwareFamilyToInstall, .metro)

        prefs.firmwareFamilyToInstall = .aura
        XCTAssertEqual(AppPreferences(defaults: defaults).firmwareFamilyToInstall, .aura)
    }

    /// Un valor guardado por una version futura (o corrupto) cae a Aura,
    /// nunca a "desconocido": el instalador necesita una familia que pueda
    /// instalar.
    @MainActor
    func testPreferenceWithUnknownStoredValueFallsBackToAura() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ST047-\(UUID().uuidString)"))
        defaults.set("zeta", forKey: "aura.firmwareFamilyToInstall")
        XCTAssertEqual(AppPreferences(defaults: defaults).firmwareFamilyToInstall, .aura)
    }
}
