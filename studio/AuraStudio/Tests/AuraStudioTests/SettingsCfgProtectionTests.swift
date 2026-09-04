import XCTest
@testable import AuraStudio

/// ST-147 / contrato v19: `/.aura/settings.cfg` (ajustes compartidos entre
/// las tres familias) es propiedad del firmware, igual que `/.aura/art/`
/// desde ST-073 y `/.aura/tagcache/`+`/.aura/thumbs/` desde ST-069. Ningún
/// flujo de Studio puede borrarlo, moverlo ni reescribirlo -- estos tests
/// fijan esa promesa contra cada operación real que toca el volumen, no
/// solo contra la que más se ejercita en la práctica.
final class SettingsCfgProtectionTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default
    private let settingsContent = "# aura-shared-settings v1\nrev: 3\nupdated_by: aura\nbrightness: 20\n"

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("SettingsProtect-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    private func write(_ relative: String, _ contents: String = "x") throws {
        let url = root.appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private var settingsURL: URL { root.appendingPathComponent(LibrarySync.sharedSettingsRelativePath) }

    private func plantSettings() throws {
        try write(LibrarySync.sharedSettingsRelativePath, settingsContent)
    }

    private func assertSettingsUntouched(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(try? String(contentsOf: settingsURL, encoding: .utf8), settingsContent,
                       message, file: file, line: line)
    }

    // MARK: - Cambiar de familia

    func testSwitchingActiveFirmwareDoesNotTouchSettings() throws {
        try write(".rockbox/rockbox.ipod", "AURA")
        try write(".rockbox/aura/aura.cfg", "firmware_family: aura\n")
        try write(".firmware-metro/rockbox.ipod", "METRO")
        try write(".firmware-metro/aura/aura.cfg", "firmware_family: metro\n")
        try plantSettings()

        try FirmwareSwitcher.switchActiveFirmware(to: .metro, currentlyActive: .aura, volumeRoot: root)

        assertSettingsUntouched("cambiar de familia no puede tocar los ajustes compartidos")
    }

    // MARK: - Reparación (arranque en frío tras un corte)

    func testRepairingAfterAColdStartDoesNotTouchSettings() throws {
        // Sin arbol activo, un solo dormido: repairIfNeeded lo levanta.
        try write(".firmware-aura/rockbox.ipod", "AURA")
        try plantSettings()

        _ = try FirmwareSwitcher.repairIfNeeded(volumeRoot: root)

        assertSettingsUntouched("reparar un arranque en frío no puede tocar los ajustes compartidos")
    }

    // MARK: - Siembra y espejo de archivos del contrato

    func testSeedingContractFilesDoesNotTouchSettings() throws {
        try write(".rockbox/rockbox.ipod", "AURA")   // activo, recién extraído, sin contrato propio
        try write(".firmware-metro/aura/sync_summary.cfg", "music_count: 10\n")
        try plantSettings()

        _ = FirmwareSwitcher.seedContractFilesToActiveTree(volumeRoot: root)

        assertSettingsUntouched("sembrar el árbol activo no puede tocar los ajustes compartidos")
    }

    func testMirroringContractFilesDoesNotTouchSettings() throws {
        try write(".rockbox/aura/sync_summary.cfg", "music_count: 10\n")
        try write(".firmware-metro/rockbox.ipod", "METRO")
        try plantSettings()

        try FirmwareSwitcher.mirrorContractFilesToDormantTrees(volumeRoot: root)

        assertSettingsUntouched("espejar a los dormidos no puede tocar los ajustes compartidos")
    }

    // MARK: - Sincronización de biblioteca

    func testLibrarySyncDoesNotTouchSettings() throws {
        try plantSettings()
        let sync = LibrarySync(volumeRoot: root)

        _ = try sync.sync(items: [])   // ni siquiera un sync vacío

        assertSettingsUntouched("sincronizar la biblioteca no puede tocar los ajustes compartidos")
    }

    // MARK: - Forzar la reconstrucción de la base

    func testForcingADatabaseRebuildDoesNotTouchSettings() throws {
        try write(".aura/tagcache/database_idx.tcd")
        try write(".rockbox/database_idx.tcd")
        try plantSettings()

        LibrarySync.clearFirmwareDatabases(volumeRoot: root)

        assertSettingsUntouched("forzar la reconstrucción de la base no puede tocar los ajustes compartidos")
    }

    // MARK: - El archivo no es candidato de ningún catálogo conocido

    /// Todo lo que Studio "sabe borrar" está nombrado explícitamente en
    /// alguna de estas listas -- ninguna contiene `settings.cfg`, y esa
    /// ausencia es justo lo que lo protege (ST-147: nada en este repo
    /// enumera `/.aura/` de forma amplia).
    func testSettingsCfgIsNotNamedInAnyKnownCleanupList() {
        XCTAssertFalse(LibrarySync.tagcacheDatabaseFileNames.contains(where: { $0.contains("settings") }))
        XCTAssertFalse(FirmwareSwitcher.mirroredContractEntries.contains(where: { $0.contains("settings") }))
        XCTAssertNotEqual(LibrarySync.sharedSettingsRelativePath, LibrarySync.sharedArtDirRelativePath)
        XCTAssertNotEqual(LibrarySync.sharedSettingsRelativePath, LibrarySync.sharedTagcacheDirRelativePath)
        XCTAssertNotEqual(LibrarySync.sharedSettingsRelativePath, LibrarySync.sharedThumbsDirRelativePath)
    }
}
