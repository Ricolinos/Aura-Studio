import XCTest
@testable import AuraStudio

/// ST-046 / contrato v8: distinguir QUE firmware de la familia Aura esta
/// instalado, leyendo `firmware_family` de `aura.cfg`.
///
/// El caso real que motiva todo esto (iPod del dueño, 2026-08-20):
/// Metro-Aura instalado, `.rockbox/aura/` presente, `version.txt` con
/// `v0.4.0`. Studio lo clasificaba como Aura, le preguntaba al repositorio
/// de Aura por actualizaciones y comparaba ese `v0.4.0` contra los tags de
/// Aura. No habia explotado solo porque 0.4.0 resultaba ser mayor que el
/// ultimo tag de Aura (`v0.3.1-beta`) -- en cuanto Aura publicara 0.5.0,
/// Studio habria ofrecido "actualizar" y eso habria BORRADO Metro.
final class FirmwareFamilyTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FakeIPod-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func writeConfig(_ contents: String) throws {
        let url = root.appendingPathComponent(".rockbox/aura/aura.cfg")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    private func diskInfo(usb: USBDeviceIdentity? = nil) -> DiskModeInfo {
        DiskModeInfo(volumeName: "IPOD", mountPath: root.path,
                     bsdName: "disk9s1", isFAT32: true, usb: usb, volumeUUID: "VOL-1")
    }

    // MARK: - parse

    /// La regla que hace el cambio retrocompatible: Aura-Firmware nunca
    /// escribio esta clave, asi que su ausencia ES su firma. Si esto se
    /// rompe, todo iPod con Aura instalada pasa a reportarse como
    /// "desconocido" y se queda sin actualizaciones.
    func testMissingKeyMeansAura() {
        XCTAssertEqual(FirmwareFamily.parse(configValue: nil), .aura)
        XCTAssertEqual(FirmwareFamily.parse(configValue: ""), .aura)
        XCTAssertEqual(FirmwareFamily.parse(configValue: "   "), .aura)
    }

    func testKnownFamilies() {
        XCTAssertEqual(FirmwareFamily.parse(configValue: "metro"), .metro)
        XCTAssertEqual(FirmwareFamily.parse(configValue: "aura"), .aura)
        XCTAssertEqual(FirmwareFamily.parse(configValue: "moonlit"), .moonlit)
    }

    /// ST-065: cada familia tiene su icono y ninguna vista lo decide por
    /// su cuenta -- si dos familias compartieran simbolo, el selector y la
    /// cabecera del instalador serian ambiguos.
    func testSymbolNameIsDistinctPerFamily() {
        let symbols = FirmwareFamily.installable.map(\.symbolName)
        XCTAssertEqual(Set(symbols).count, symbols.count, "\(symbols)")
        XCTAssertEqual(FirmwareFamily.moonlit.symbolName, "moon.stars")
        XCTAssertEqual(FirmwareFamily.unknown("zeta").symbolName, "questionmark")
    }

    /// El firmware escribe con `fdprintf` y Studio lee con un
    /// `hasPrefix`/`dropFirst` -- nadie normaliza en el camino, asi que el
    /// espacio despues de los dos puntos llega hasta aca.
    func testParseToleratesSpacingAndCase() {
        XCTAssertEqual(FirmwareFamily.parse(configValue: " metro "), .metro)
        XCTAssertEqual(FirmwareFamily.parse(configValue: "METRO"), .metro)
        XCTAssertEqual(FirmwareFamily.parse(configValue: "Metro\r"), .metro)
    }

    /// Una familia que esta version de Studio no conoce NO es Aura: un
    /// firmware que se molesto en declararse esta diciendo justamente que
    /// es otra cosa. Tratarla como Aura seria repetir el bug con un
    /// firmware futuro.
    func testUnknownFamilyIsNotAura() {
        let family = FirmwareFamily.parse(configValue: "zeta")
        XCTAssertEqual(family, .unknown("zeta"))
        XCTAssertNotEqual(family, .aura)
        XCTAssertNil(family.releaseRepository)
    }

    func testReleaseRepositories() {
        XCTAssertEqual(FirmwareFamily.aura.releaseRepository, "Ricolinos/Aura-Firmware")
        XCTAssertEqual(FirmwareFamily.metro.releaseRepository, "Ricolinos/Metro-Aura")
        XCTAssertEqual(GitHubReleaseChecker.apiURL(for: .aura),
                       URL(string: "https://api.github.com/repos/Ricolinos/Aura-Firmware/releases"))
        XCTAssertEqual(GitHubReleaseChecker.apiURL(for: .metro),
                       URL(string: "https://api.github.com/repos/Ricolinos/Metro-Aura/releases"))
        XCTAssertEqual(FirmwareFamily.moonlit.releaseRepository, "Ricolinos/moonlit-aura")
        XCTAssertEqual(GitHubReleaseChecker.apiURL(for: .moonlit),
                       URL(string: "https://api.github.com/repos/Ricolinos/moonlit-aura/releases"))
        XCTAssertNil(GitHubReleaseChecker.apiURL(for: .unknown("zeta")))
    }

    // MARK: - lectura de aura.cfg

    private func writeSentinel(_ family: FirmwareFamily) throws {
        let url = root.appendingPathComponent(family.installedTreeSentinel!)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try Data("fnt".utf8).write(to: url)
    }

    // MARK: - ST-067: arbol recien instalado, sin arrancar

    /// El caso exacto del iPod del dueño (2026-08-26): moonlit recien
    /// copiado, `aura.cfg` creado por `ClockSyncWriter` solo con la hora,
    /// sin `firmware_family`. Antes se leia como Aura y Extras lo
    /// estacionaba como `/.firmware-aura`.
    func testNeverBootedMoonlitIsIdentifiedBySentinel() throws {
        try writeConfig("""
        rtc_sync_year: 2026
        rtc_sync_month: 8
        tz_local_quarters: -24
        """)
        try writeSentinel(.moonlit)
        XCTAssertEqual(FirmwareCapabilities.declaredFamily(volumeRoot: root), .moonlit)
    }

    func testNeverBootedMetroWithoutConfigIsIdentifiedBySentinel() throws {
        try writeSentinel(.metro)
        XCTAssertEqual(FirmwareCapabilities.declaredFamily(volumeRoot: root), .metro)
    }

    /// La clave escrita por el firmware manda sobre el centinela.
    func testDeclaredKeyBeatsSentinel() throws {
        try writeConfig("firmware_family: metro\n")
        try writeSentinel(.moonlit)
        XCTAssertEqual(FirmwareCapabilities.declaredFamily(volumeRoot: root), .metro)
    }

    /// Un Aura real (sin clave, sin centinelas ajenos) sigue siendo Aura.
    func testAuraTreeWithoutForeignSentinelsIsAura() throws {
        try writeConfig("theme: 0\n")
        try writeSentinel(.aura)
        XCTAssertEqual(FirmwareCapabilities.declaredFamily(volumeRoot: root), .aura)
        XCTAssertNil(FirmwareCapabilities.familyBySentinel(volumeRoot: root))
    }

    func testSeedDeclaredFamilyUpsertsKeepingClockLines() throws {
        try writeConfig("rtc_sync_year: 2026\ntz_local_quarters: -24\n")
        FirmwareCapabilities.seedDeclaredFamily(volumeRoot: root, family: .moonlit)
        let text = try String(contentsOf: root.appendingPathComponent(".rockbox/aura/aura.cfg"), encoding: .utf8)
        XCTAssertEqual(text, "firmware_family: moonlit\nrtc_sync_year: 2026\ntz_local_quarters: -24\n")
        XCTAssertEqual(FirmwareCapabilities.declaredFamily(volumeRoot: root), .moonlit)
        // Idempotente: una segunda siembra no duplica la clave.
        FirmwareCapabilities.seedDeclaredFamily(volumeRoot: root, family: .moonlit)
        let again = try String(contentsOf: root.appendingPathComponent(".rockbox/aura/aura.cfg"), encoding: .utf8)
        XCTAssertEqual(again.components(separatedBy: "firmware_family:").count - 1, 1)
    }

    func testSeedDeclaredFamilyWritesNothingForAura() {
        FirmwareCapabilities.seedDeclaredFamily(volumeRoot: root, family: .aura)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".rockbox/aura/aura.cfg").path))
    }

    func testSeedDeclaredFamilyCreatesConfigWhenMissing() throws {
        FirmwareCapabilities.seedDeclaredFamily(volumeRoot: root, family: .metro)
        XCTAssertEqual(FirmwareCapabilities.declaredFamily(volumeRoot: root), .metro)
    }

    func testDeclaredFamilyWithoutConfigIsAura() {
        XCTAssertEqual(FirmwareCapabilities.declaredFamily(volumeRoot: root), .aura)
    }

    /// Un `aura.cfg` de Aura real: tiene las otras claves y no esta.
    func testDeclaredFamilyWithConfigButNoKeyIsAura() throws {
        try writeConfig("""
        sync_marker_supported: 1
        theme_format_supported: 1
        theme: 0
        """)
        XCTAssertEqual(FirmwareCapabilities.declaredFamily(volumeRoot: root), .aura)
    }

    /// Las tres primeras lineas del `aura.cfg` real del iPod del dueño con
    /// Metro-Aura v0.4.0 instalado.
    func testDeclaredFamilyReadsMetro() throws {
        try writeConfig("""
        firmware_family: metro
        sync_marker_supported: 1
        theme: 0
        accent: 9
        """)
        XCTAssertEqual(FirmwareCapabilities.declaredFamily(volumeRoot: root), .metro)
    }

    /// La clave no tiene por que ser la primera linea: el firmware
    /// reescribe el archivo entero en cada `save()` y el orden es suyo.
    func testDeclaredFamilyFindsKeyAnywhere() throws {
        try writeConfig("""
        theme: 0
        accent: 9
        firmware_family: metro
        """)
        XCTAssertEqual(FirmwareCapabilities.declaredFamily(volumeRoot: root), .metro)
    }

    // MARK: - integracion con el probe

    /// El nucleo de ST-046: identidad y capacidad son cosas distintas.
    /// Metro cumple el contrato de biblioteca (por eso sincroniza bien y
    /// por eso `supportsAuraContract` DEBE seguir siendo true), pero no es
    /// Aura.
    func testProbeSeparatesIdentityFromCapability() throws {
        try writeConfig("firmware_family: metro\nsync_marker_supported: 1\n")
        let device = try XCTUnwrap(AuraDeviceProbe.probe(diskInfo: diskInfo()))

        XCTAssertEqual(device.declaredFamily, .metro)
        XCTAssertTrue(device.supportsAuraContract,
                      "Metro habla el mismo §D: biblioteca y sync tienen que seguir habilitados")
        XCTAssertFalse(device.isAuraFirmware,
                       "pero NO es Aura: de esto depende no ofrecerle el firmware de Aura")
    }

    /// ST-065: moonlit habla el contrato (biblioteca y sync siguen) pero
    /// no publica `theme_format_supported` -> "Temas" se deshabilita. Aura
    /// y Metro si la publican.
    func testProbeReadsThemeFormatSupport() throws {
        try writeConfig("firmware_family: moonlit\nsync_marker_supported: 1\n")
        let moonlit = try XCTUnwrap(AuraDeviceProbe.probe(diskInfo: diskInfo()))
        XCTAssertEqual(moonlit.declaredFamily, .moonlit)
        XCTAssertTrue(moonlit.supportsAuraContract)
        XCTAssertFalse(moonlit.themeFormatSupported)
        XCTAssertNil(FirmwareCapabilities.supportedThemeFormat(volumeRoot: root))

        try writeConfig("sync_marker_supported: 1\ntheme_format_supported: 1\n")
        let aura = try XCTUnwrap(AuraDeviceProbe.probe(diskInfo: diskInfo()))
        XCTAssertTrue(aura.themeFormatSupported)
        XCTAssertEqual(FirmwareCapabilities.supportedThemeFormat(volumeRoot: root), 1)
    }

    func testProbeReportsAuraWhenKeyIsAbsent() throws {
        try writeConfig("sync_marker_supported: 1\n")
        let device = try XCTUnwrap(AuraDeviceProbe.probe(diskInfo: diskInfo()))
        XCTAssertEqual(device.declaredFamily, .aura)
        XCTAssertTrue(device.supportsAuraContract)
        XCTAssertTrue(device.isAuraFirmware)
    }

    // MARK: - regresiones de actualizacion

    /// **La regresion que importa.** El respaldo por hash compara contra el
    /// `rockbox.ipod` EMBEBIDO en la app, que es el de Aura: contra
    /// cualquier otro firmware el hash siempre difiere, asi que la funcion
    /// contestaba "si, hay actualizacion" para siempre. Ese "si" es el que
    /// alimentaba el boton que habria sobrescrito Metro.
    ///
    /// LIMITE de esta prueba, dicho explicito: en el arnes de SwiftPM
    /// `BundledArtifacts` no tiene firmware embebido (`Vendor/firmware-dist/`
    /// esta en .gitignore y lo puebla `fetch-firmware.sh`), asi que la
    /// funcion tambien devolveria `false` por esa via. Lo que la prueba fija
    /// es el contrato ("nunca `true` para otra familia"), no por cual de las
    /// dos guardas sale. La guarda de familia es la PRIMERA linea de
    /// `isUpdateAvailable`, a proposito, para que el orden no dependa de si
    /// hay artefactos.
    func testHashFallbackNeverFiresForOtherFamilies() async {
        try? FileManager.default.createDirectory(
            at: root.appendingPathComponent(".rockbox"), withIntermediateDirectories: true)
        try? Data("no soy el firmware de Aura".utf8)
            .write(to: root.appendingPathComponent(".rockbox/rockbox.ipod"))

        // Desde ST-047 Metro (y desde ST-065 moonlit) SI son instalables y
        // vienen embebidos: contra un binario falso el hash difiere y eso es
        // una actualizacion legitima de SU propia familia, no el bug de
        // ST-046. Lo que sigue vigente es que una familia desconocida jamas
        // recibe "hay actualizacion".
        let unknown = await AuraUpdateChecker.isUpdateAvailable(deviceMountPath: root.path,
                                                                 family: .unknown("zeta"))
        XCTAssertFalse(unknown)
    }

    /// Sin repositorio no hay a quien preguntarle, y adivinar "sera Aura"
    /// es exactamente el bug original.
    func testUnknownFamilyGetsNoUpdateOffer() async {
        let result = await AuraUpdateChecker.checkForUpdate(deviceMountPath: root.path,
                                                             family: .unknown("zeta"))
        XCTAssertFalse(result)
    }

    /// El cache se guarda por familia. Con una sola llave, conectar un iPod
    /// con Metro y luego uno con Aura le habria mostrado al segundo los
    /// tags del primero durante las 24h del TTL.
    func testReleaseCacheIsPerFamily() throws {
        let defaults = try XCTUnwrap(makeIsolatedDefaults("ST046"))
        let auraReleases = [GitHubRelease(tagName: "v0.3.1-beta", draft: false, prerelease: true)]
        let metroReleases = [GitHubRelease(tagName: "v0.4.0", draft: false, prerelease: false)]

        ReleaseCache.store(auraReleases, defaults: defaults, family: .aura)
        ReleaseCache.store(metroReleases, defaults: defaults, family: .metro)

        XCTAssertEqual(ReleaseCache.load(defaults: defaults, family: .aura), auraReleases)
        XCTAssertEqual(ReleaseCache.load(defaults: defaults, family: .metro), metroReleases)
    }

    /// Las llaves historicas se conservan tal cual para Aura: nadie pierde
    /// su cache al actualizar Studio.
    func testAuraKeepsTheHistoricCacheKeys() {
        XCTAssertEqual(ReleaseCache.dataKey(for: .aura), ReleaseCache.dataKey)
        XCTAssertEqual(ReleaseCache.timestampKey(for: .aura), ReleaseCache.timestampKey)
        XCTAssertNotEqual(ReleaseCache.dataKey(for: .metro), ReleaseCache.dataKey)
    }

    func testLatestKnownTagReadsTheRightFamily() throws {
        let defaults = try XCTUnwrap(makeIsolatedDefaults("ST046"))
        ReleaseCache.store([GitHubRelease(tagName: "v0.3.1-beta", draft: false, prerelease: true)],
                           defaults: defaults, family: .aura)
        ReleaseCache.store([GitHubRelease(tagName: "v0.4.0", draft: false, prerelease: false)],
                           defaults: defaults, family: .metro)

        XCTAssertEqual(AuraUpdateChecker.latestKnownTag(family: .metro, defaults: defaults), "v0.4.0")
        XCTAssertEqual(AuraUpdateChecker.latestKnownTag(family: .aura, defaults: defaults), "v0.3.1-beta")
    }
}
