import XCTest
@testable import AuraStudio

/// PLAN-general-sync.md §1.5/§9, `CONTRATO-dispositivo.md`: nombre
/// editable del iPod, guardado en el dispositivo (`device.cfg`), con
/// los límites y el saneo que fija el contrato.
final class DeviceNameStoreTests: XCTestCase {
    private var fakeIPod: URL!

    override func setUpWithError() throws {
        fakeIPod = FileManager.default.temporaryDirectory.appendingPathComponent("DeviceNameStore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeIPod, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fakeIPod)
    }

    // MARK: - Lectura/escritura

    func testSaveThenLoadRoundTrips() throws {
        let identity = DeviceIdentity(deviceID: "abc-123", deviceName: "iPod de Ricardo", updatedAt: Date())
        try DeviceNameStore.save(identity, volumeRoot: fakeIPod)

        let loaded = DeviceNameStore.load(volumeRoot: fakeIPod)

        XCTAssertEqual(loaded?.deviceID, "abc-123")
        XCTAssertEqual(loaded?.deviceName, "iPod de Ricardo")
    }

    func testLoadReturnsNilWhenFileIsAbsent() {
        XCTAssertNil(DeviceNameStore.load(volumeRoot: fakeIPod))
    }

    func testWrittenFileUsesTheSamePlainKeyValueFormatAsOtherCfgFiles() throws {
        let identity = DeviceIdentity(deviceID: "abc-123", deviceName: "iPod de Ricardo", updatedAt: Date())
        try DeviceNameStore.save(identity, volumeRoot: fakeIPod)

        let text = try String(contentsOf: fakeIPod.appendingPathComponent(DeviceNameStore.relativePath), encoding: .utf8)
        XCTAssertTrue(text.contains("device_id: abc-123"))
        XCTAssertTrue(text.contains("device_name: iPod de Ricardo"))
        // ST-013: el archivo se escribe siempre en la version vigente del
        // contrato (v2 desde device_owner), aunque no haya propietario.
        XCTAssertTrue(text.contains("contract_version: \(DeviceNameStore.currentContractVersion)"))
        XCTAssertEqual(DeviceNameStore.currentContractVersion, 2)
    }

    func testParseIgnoresUnknownKeysAndGarbageLines() {
        let text = """
        contract_version: 1
        device_id: abc-123
        device_name: iPod de Ricardo
        some_future_key: 42
        esto no es una linea valida
        """
        let identity = DeviceNameStore.parse(text)
        XCTAssertEqual(identity?.deviceID, "abc-123")
        XCTAssertEqual(identity?.deviceName, "iPod de Ricardo")
    }

    func testParseReturnsNilWithoutRequiredKeys() {
        XCTAssertNil(DeviceNameStore.parse("contract_version: 1\n"))
    }

    // MARK: - Saneo (§C del contrato)

    func testSanitizeTrimsAndCollapsesWhitespace() {
        let (name, strippedEmoji) = DeviceNameStore.sanitize("   iPod   de   Ricardo   ")
        XCTAssertEqual(name, "iPod de Ricardo")
        XCTAssertFalse(strippedEmoji)
    }

    func testSanitizeStripsControlCharactersAndNewlines() {
        let (name, _) = DeviceNameStore.sanitize("iPod\nde\tRicardo")
        XCTAssertFalse(name.contains("\n"))
        XCTAssertFalse(name.contains("\t"))
    }

    func testSanitizeStripsEmojiOutsideTheBMPAndReportsIt() {
        let (name, strippedEmoji) = DeviceNameStore.sanitize("iPod de Ricardo 🎵📱")
        XCTAssertEqual(name, "iPod de Ricardo")
        XCTAssertTrue(strippedEmoji)
    }

    func testSanitizeKeepsAccentedCharactersWithinTheBMP() {
        let (name, strippedEmoji) = DeviceNameStore.sanitize("iPod de Ñandú")
        XCTAssertEqual(name, "iPod de Ñandú")
        XCTAssertFalse(strippedEmoji)
    }

    func testSanitizeTruncatesToMaxCharactersAndMaxBytes() {
        let long = String(repeating: "a", count: 100)
        let (name, _) = DeviceNameStore.sanitize(long)
        XCTAssertEqual(name.count, DeviceNameStore.maxCharacters)

        // Acentuados pesan 2 bytes en UTF-8 -- el limite de bytes puede
        // ganarle al de caracteres antes de llegar a 32.
        let longAccented = String(repeating: "ñ", count: 40)
        let (accentedName, _) = DeviceNameStore.sanitize(longAccented)
        XCTAssertLessThanOrEqual(accentedName.utf8.count, DeviceNameStore.maxBytes)
        XCTAssertLessThanOrEqual(accentedName.count, DeviceNameStore.maxCharacters)
    }

    func testSanitizeOfEmptyOrWhitespaceOnlyStringIsEmpty() {
        let (name, _) = DeviceNameStore.sanitize("   ")
        XCTAssertTrue(name.isEmpty)
    }

    // MARK: - Default

    func testDefaultNameIsNeverEmpty() {
        XCTAssertFalse(DeviceNameStore.defaultName().isEmpty)
    }
}

/// ST-013 / `CONTRATO-dispositivo.md` v2 SS C bis: propiedad del nombre --
/// solo la instalacion de Aura Studio que nombro el iPod la primera vez
/// puede cambiarlo; un archivo v1 (sin propietario) es reclamable.
final class DeviceNameOwnershipTests: XCTestCase {
    private var fakeIPod: URL!

    override func setUpWithError() throws {
        fakeIPod = FileManager.default.temporaryDirectory.appendingPathComponent("DeviceNameOwner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeIPod, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fakeIPod)
    }

    func testOwnerRoundTripsAndFileIsV2() throws {
        let identity = DeviceIdentity(deviceID: "abc-123", deviceName: "iPod de Ricardo", updatedAt: Date(),
                                      ownerInstallationID: "INSTALL-A")
        try DeviceNameStore.save(identity, volumeRoot: fakeIPod)

        let text = try String(contentsOf: fakeIPod.appendingPathComponent(DeviceNameStore.relativePath), encoding: .utf8)
        XCTAssertTrue(text.contains("contract_version: 2"))
        XCTAssertTrue(text.contains("device_owner: INSTALL-A"))
        // Contrato SS A: ninguna linea supera 63 bytes (el buffer del firmware).
        for line in text.split(separator: "\n") {
            XCTAssertLessThanOrEqual(line.utf8.count, 63, "linea demasiado larga: \(line)")
        }
        XCTAssertEqual(DeviceNameStore.load(volumeRoot: fakeIPod)?.ownerInstallationID, "INSTALL-A")
    }

    func testV1FileLoadsWithoutOwnerAndIsClaimable() throws {
        let v1 = """
        contract_version: 1
        device_id: abc-123
        device_name: iPod de Ricardo
        device_name_updated_at: 2026-08-17T20:14:00Z

        """
        let url = fakeIPod.appendingPathComponent(DeviceNameStore.relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try v1.write(to: url, atomically: true, encoding: .utf8)

        let loaded = try XCTUnwrap(DeviceNameStore.load(volumeRoot: fakeIPod))
        XCTAssertNil(loaded.ownerInstallationID)
        XCTAssertTrue(loaded.canRename(from: "INSTALL-A"), "sin propietario, cualquiera puede -- y reclama al guardar")
        XCTAssertTrue(loaded.canRename(from: "INSTALL-B"))
    }

    func testOnlyOwnerCanRename() {
        let owned = DeviceIdentity(deviceID: "abc", deviceName: "iPod", updatedAt: Date(), ownerInstallationID: "INSTALL-A")
        XCTAssertTrue(owned.canRename(from: "INSTALL-A"))
        XCTAssertFalse(owned.canRename(from: "INSTALL-B"), "otra Mac ve el nombre pero no lo edita")
    }

    func testEmptyOwnerValueIsTreatedAsAbsent() {
        let parsed = DeviceNameStore.parse("device_id: abc\ndevice_name: iPod\ndevice_owner: \n")
        XCTAssertNil(parsed?.ownerInstallationID)
    }

    func testFirmwareOnlyNeedsDeviceNameLine() throws {
        // El firmware (D-294) lee solo `device_name`; el orden y las claves
        // extra no le importan -- pero la clave tiene que seguir siendo
        // exactamente esa y estar sola en su linea.
        let identity = DeviceIdentity(deviceID: "abc-123", deviceName: "iPod de Ñoño", updatedAt: Date(),
                                      ownerInstallationID: "INSTALL-A")
        try DeviceNameStore.save(identity, volumeRoot: fakeIPod)
        let text = try String(contentsOf: fakeIPod.appendingPathComponent(DeviceNameStore.relativePath), encoding: .utf8)
        XCTAssertTrue(text.split(separator: "\n").contains("device_name: iPod de Ñoño"))
    }
}
