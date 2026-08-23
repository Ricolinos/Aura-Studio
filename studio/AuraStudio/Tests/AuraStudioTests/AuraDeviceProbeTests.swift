import XCTest
@testable import AuraStudio

/// La deteccion "este iPod tiene Aura" es por archivos en el volumen
/// montado, no por USB: en modo almacenamiento el firmware no se esta
/// ejecutando. Estos tests fijan cada combinacion contra carpetas
/// temporales reales, sin hardware.
final class AuraDeviceProbeTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FakeIPod-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func diskInfo(usb: USBDeviceIdentity? = nil) -> DiskModeInfo {
        DiskModeInfo(volumeName: "AURA", mountPath: root.path,
                     bsdName: "disk9s1", isFAT32: true, usb: usb, volumeUUID: "VOL-1")
    }

    /// Descriptores reales leidos con `ioreg` del iPod del dueño en modo
    /// disco de Apple (ST-016).
    private static let appleDiskModeUSB = USBDeviceIdentity(
        vendorName: "Apple Inc.", productName: "iPod", serialNumber: "000A270013923F13",
        vendorID: 0x05AC, productID: 0x1261)
    /// Descriptores que anuncia Rockbox/Aura (`usb_core.c:141-145` del
    /// firmware, mismo VID/PID que Apple).
    private static let rockboxUSB = USBDeviceIdentity(
        vendorName: "Rockbox.org", productName: "Rockbox media player",
        serialNumber: "0123456789ABCDEF0123456789ABCDEF01234567",
        vendorID: 0x05AC, productID: 0x1261)

    private func touch(_ relative: String) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    private func mkdir(_ relative: String) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(relative),
                                                 withIntermediateDirectories: true)
    }

    /// D-179: un volumen sin `iPod_Control/` ni rastro de Rockbox ya no
    /// se reporta como "firmware original" -- es un disco vacio, y la
    /// UI le dice al usuario algo distinto en cada caso.
    func testEmptyVolumeIsEmptyNotStock() throws {
        let device = try XCTUnwrap(AuraDeviceProbe.probe(diskInfo: diskInfo()))
        XCTAssertEqual(device.firmware, .empty)
        XCTAssertFalse(device.supportsAuraContract)
        XCTAssertFalse(device.originalFirmwarePresent)
    }

    func testIPodControlAloneMeansOriginalAppleFirmware() throws {
        try mkdir("iPod_Control/Music")
        let device = try XCTUnwrap(AuraDeviceProbe.probe(diskInfo: diskInfo()))
        XCTAssertEqual(device.firmware, .stock)
        XCTAssertTrue(device.originalFirmwarePresent)
        XCTAssertFalse(device.isDualBoot)
        XCTAssertFalse(device.isRockboxFamily)
    }

    func testAuraPlusIPodControlIsDualBoot() throws {
        try touch(".rockbox/aura/aura.cfg")
        try mkdir("iPod_Control/Music")
        let device = try XCTUnwrap(AuraDeviceProbe.probe(diskInfo: diskInfo()))
        XCTAssertEqual(device.firmware, .aura(hasBooted: true))
        XCTAssertTrue(device.supportsAuraContract)
        XCTAssertTrue(device.isDualBoot)
    }

    // MARK: - ST-016: lectura real por USB + evidencia de arranque

    /// El caso exacto del dueño (2026-08-17): iPod con firmware original de
    /// Apple, al que se le copio a mano la carpeta `.rockbox` de Aura para
    /// probar. Antes: "Aura instalado (dual boot)". Ahora: archivos sin
    /// evidencia, firmware de Apple corriendo, nada habilitado.
    func testCopiedAuraFolderOnStockIPodIsNotAuraNorDualBoot() throws {
        try mkdir(".rockbox/icons/aura/masks")
        try mkdir("iPod_Control/Music")
        let device = try XCTUnwrap(AuraDeviceProbe.probe(diskInfo: diskInfo(usb: Self.appleDiskModeUSB)))
        XCTAssertEqual(device.firmware, .aura(hasBooted: false))
        XCTAssertEqual(device.runningFirmware, .apple)
        XCTAssertTrue(device.hasAuraFiles)
        XCTAssertFalse(device.supportsAuraContract)
        XCTAssertFalse(device.isDualBoot)
        XCTAssertFalse(device.rockboxFamilyVerified)
        XCTAssertFalse(device.canSkipBootloaderFlash(diskRecordedAsVerified: false))
        XCTAssertFalse(device.canSkipBootloaderFlash(diskRecordedAsVerified: true),
                       "sin rastro de arranque, ni el registro local alcanza")
    }

    /// Conectado mientras Aura atiende el USB: la lectura real manda,
    /// aunque `aura.cfg` todavia no exista (primer arranque en curso).
    func testAuraFilesWithRockboxUSBIsAuraEvenBeforeFirstConfigWrite() throws {
        try mkdir(".rockbox/icons/aura/masks")
        let device = try XCTUnwrap(AuraDeviceProbe.probe(diskInfo: diskInfo(usb: Self.rockboxUSB)))
        XCTAssertEqual(device.runningFirmware, .rockboxFamily)
        XCTAssertTrue(device.supportsAuraContract)
        XCTAssertTrue(device.rockboxFamilyVerified)
        XCTAssertTrue(device.canSkipBootloaderFlash(diskRecordedAsVerified: false))
    }

    /// Aura que ya arranco (aura.cfg), conectada desde el modo disco de
    /// Apple: es Aura (la biblioteca aplica), pero el instalador solo se
    /// salta el DFU si ademas Studio tiene el registro local del disco.
    func testBootedAuraInAppleDiskModeNeedsLocalRecordToSkipDFU() throws {
        try touch(".rockbox/aura/aura.cfg")
        let device = try XCTUnwrap(AuraDeviceProbe.probe(diskInfo: diskInfo(usb: Self.appleDiskModeUSB)))
        XCTAssertEqual(device.runningFirmware, .apple)
        XCTAssertTrue(device.supportsAuraContract)
        XCTAssertFalse(device.canSkipBootloaderFlash(diskRecordedAsVerified: false))
        XCTAssertTrue(device.canSkipBootloaderFlash(diskRecordedAsVerified: true))
    }

    /// Modo USB del bootloader sobre un disco vacio (D-175/D-183): el USB
    /// lo atiende Rockbox, asi que hay bootloader -- aunque no haya
    /// archivos. `isAura` no (no hay Aura en el disco), pero el flasheo
    /// se puede saltar.
    func testEmptyDiskWithRockboxUSBHasBootloaderButNoAura() throws {
        let device = try XCTUnwrap(AuraDeviceProbe.probe(diskInfo: diskInfo(usb: Self.rockboxUSB)))
        XCTAssertEqual(device.firmware, .empty)
        XCTAssertFalse(device.supportsAuraContract)
        XCTAssertTrue(device.rockboxFamilyVerified)
        XCTAssertTrue(device.canSkipBootloaderFlash(diskRecordedAsVerified: false))
    }

    func testProbeCarriesUSBSerialAndVolumeUUID() throws {
        let device = try XCTUnwrap(AuraDeviceProbe.probe(diskInfo: diskInfo(usb: Self.appleDiskModeUSB)))
        XCTAssertEqual(device.usbSerial, "000A270013923F13")
        XCTAssertEqual(device.volumeUUID, "VOL-1")
        XCTAssertEqual(device.diskRecordKey, "VOL-1", "el UUID del volumen manda sobre el serial USB")
    }

    func testWithoutUSBIdentityRunningFirmwareIsUnknown() throws {
        try touch(".rockbox/aura/aura.cfg")
        let device = try XCTUnwrap(AuraDeviceProbe.probe(diskInfo: diskInfo()))
        XCTAssertEqual(device.runningFirmware, .unknown)
        XCTAssertTrue(device.supportsAuraContract, "el rastro de arranque sigue valiendo sin lectura USB")
    }

    /// ST-016: un `.rockbox` sin rastro de arranque junto a `iPod_Control/`
    /// ya NO es "dual boot" -- solo archivos. Con `.resume.cfg` (que solo
    /// escribe un Rockbox corriendo) si.
    func testRockboxPlusIPodControlIsDualBootOnlyWithBootEvidence() throws {
        try mkdir(".rockbox")
        try mkdir("iPod_Control")
        var device = try XCTUnwrap(AuraDeviceProbe.probe(diskInfo: diskInfo()))
        XCTAssertEqual(device.firmware, .rockbox(hasBooted: false))
        XCTAssertTrue(device.isRockboxFamily)
        XCTAssertFalse(device.isDualBoot)

        try touch(".rockbox/.resume.cfg")
        device = try XCTUnwrap(AuraDeviceProbe.probe(diskInfo: diskInfo()))
        XCTAssertEqual(device.firmware, .rockbox(hasBooted: true))
        XCTAssertTrue(device.isDualBoot)
    }

    /// D-179: los iconos del design system viajan en el arbol .rockbox
    /// desde D-178 -- son un marcador de Aura que existe desde el
    /// momento de la instalacion, sin esperar el primer arranque.
    func testAuraIconsDirAloneIsDetectedAsAura() throws {
        try mkdir(".rockbox/icons/aura/masks")
        let device = try XCTUnwrap(AuraDeviceProbe.probe(diskInfo: diskInfo()))
        XCTAssertEqual(device.firmware, .aura(hasBooted: false))
    }

    func testRockboxWithoutAuraIsNotDetectedAsAura() throws {
        try mkdir(".rockbox")
        let device = try XCTUnwrap(AuraDeviceProbe.probe(diskInfo: diskInfo()))
        XCTAssertEqual(device.firmware, .rockbox(hasBooted: false))
        XCTAssertFalse(device.supportsAuraContract)
    }

    func testRockboxConfigCfgAlsoCountsAsBootEvidence() throws {
        try touch(".rockbox/config.cfg")
        let device = try XCTUnwrap(AuraDeviceProbe.probe(diskInfo: diskInfo()))
        XCTAssertEqual(device.firmware, .rockbox(hasBooted: true))
    }

    /// ST-016: archivos de Aura sin evidencia de arranque son eso --
    /// `hasAuraFiles`, pero NO `isAura` (lo que habilita biblioteca/sync).
    func testFirmwareBinaryAloneMeansAuraFilesWithoutEvidence() throws {
        try touch("rockbox.ipod")
        let device = try XCTUnwrap(AuraDeviceProbe.probe(diskInfo: diskInfo()))
        XCTAssertEqual(device.firmware, .aura(hasBooted: false))
        XCTAssertTrue(device.hasAuraFiles)
        XCTAssertFalse(device.supportsAuraContract)
    }

    func testAuraDirWithoutConfigMeansNotBootedYet() throws {
        try mkdir(".rockbox/aura")
        let device = try XCTUnwrap(AuraDeviceProbe.probe(diskInfo: diskInfo()))
        XCTAssertEqual(device.firmware, .aura(hasBooted: false))
    }

    func testAuraConfigMeansBooted() throws {
        try touch(".rockbox/aura/aura.cfg")
        let device = try XCTUnwrap(AuraDeviceProbe.probe(diskInfo: diskInfo()))
        XCTAssertEqual(device.firmware, .aura(hasBooted: true))
    }

    func testSummaryIsNilWhenNeverSynced() throws {
        try touch(".rockbox/aura/aura.cfg")
        XCTAssertNil(try XCTUnwrap(AuraDeviceProbe.probe(diskInfo: diskInfo())).librarySummary)
    }

    /// El resumen que lee el probe es exactamente el que escribe
    /// LibrarySync -- se prueban juntos para que un cambio de formato en
    /// uno rompa el test y no la app.
    func testSummaryIsReadBackFromWhatLibrarySyncWrote() throws {
        var written = CatalogSummary()
        written.music = CatalogTypeSummary(count: 12, bytes: 34_567)
        written.video = CatalogTypeSummary(count: 2, bytes: 89_000)
        written.photo = CatalogTypeSummary(count: 5, bytes: 4_321)
        written.playlistCount = 3

        let url = root.appendingPathComponent(LibrarySync.summaryRelativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try CatalogSummaryWriter.serialize(written).write(to: url, atomically: true, encoding: .utf8)

        let device = try XCTUnwrap(AuraDeviceProbe.probe(diskInfo: diskInfo()))
        XCTAssertEqual(device.librarySummary, written)
    }

    func testNonFAT32VolumeIsReportedAsSuch() throws {
        let info = DiskModeInfo(volumeName: "AURA", mountPath: root.path,
                                bsdName: "disk9s1", isFAT32: false)
        XCTAssertFalse(try XCTUnwrap(AuraDeviceProbe.probe(diskInfo: info)).isFAT32)
    }

    // MARK: - Nombre del dispositivo (PLAN-general-sync.md §1.5/§9)

    func testDisplayNameFallsBackToVolumeNameWithoutDeviceCfg() throws {
        let device = try XCTUnwrap(AuraDeviceProbe.probe(diskInfo: diskInfo()))
        XCTAssertNil(device.deviceIdentity)
        XCTAssertEqual(device.displayName, "AURA")
    }

    func testDisplayNameUsesTheSavedDeviceNameWhenPresent() throws {
        try touch(".rockbox/aura/aura.cfg")
        let identity = DeviceIdentity(deviceID: "abc-123", deviceName: "iPod de Ricardo", updatedAt: Date())
        try DeviceNameStore.save(identity, volumeRoot: root)

        let device = try XCTUnwrap(AuraDeviceProbe.probe(diskInfo: diskInfo()))
        XCTAssertEqual(device.deviceIdentity?.deviceID, "abc-123")
        XCTAssertEqual(device.displayName, "iPod de Ricardo")
    }
}

final class CatalogSummaryReaderTests: XCTestCase {
    func testParsesFlatKeyValue() {
        let summary = CatalogSummaryReader.parse("""
        music_count: 120
        music_bytes: 489234931
        video_count: 3
        video_bytes: 1234567890
        photo_count: 40
        photo_bytes: 85000000
        playlist_count: 2
        """)

        XCTAssertEqual(summary.music, CatalogTypeSummary(count: 120, bytes: 489_234_931))
        XCTAssertEqual(summary.video, CatalogTypeSummary(count: 3, bytes: 1_234_567_890))
        XCTAssertEqual(summary.photo, CatalogTypeSummary(count: 40, bytes: 85_000_000))
        XCTAssertEqual(summary.playlistCount, 2)
    }

    func testIgnoresGarbageLinesAndMissingKeys() {
        let summary = CatalogSummaryReader.parse("basura\nmusic_count: 7\nvideo_count: nope\n")
        XCTAssertEqual(summary.music.count, 7)
        XCTAssertEqual(summary.video.count, 0)
    }

    func testRoundTripsThroughTheWriter() {
        var original = CatalogSummary()
        original.music = CatalogTypeSummary(count: 1, bytes: 2)
        original.video = CatalogTypeSummary(count: 3, bytes: 4)
        original.photo = CatalogTypeSummary(count: 5, bytes: 6)
        original.playlistCount = 7

        XCTAssertEqual(CatalogSummaryReader.parse(CatalogSummaryWriter.serialize(original)),
                        original)
    }
}
