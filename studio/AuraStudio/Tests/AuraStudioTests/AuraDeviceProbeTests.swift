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

    private func diskInfo() -> DiskModeInfo {
        DiskModeInfo(volumeName: "AURA", mountPath: root.path,
                     bsdName: "disk9s1", isFAT32: true)
    }

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
        XCTAssertFalse(device.isAura)
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
        XCTAssertTrue(device.isDualBoot)
    }

    func testRockboxPlusIPodControlIsDualBoot() throws {
        try mkdir(".rockbox")
        try mkdir("iPod_Control")
        let device = try XCTUnwrap(AuraDeviceProbe.probe(diskInfo: diskInfo()))
        XCTAssertEqual(device.firmware, .rockbox)
        XCTAssertTrue(device.isDualBoot)
        XCTAssertTrue(device.isRockboxFamily)
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
        XCTAssertEqual(device.firmware, .rockbox)
        XCTAssertFalse(device.isAura)
    }

    func testFirmwareBinaryAloneMeansAuraNotBootedYet() throws {
        try touch("rockbox.ipod")
        let device = try XCTUnwrap(AuraDeviceProbe.probe(diskInfo: diskInfo()))
        XCTAssertEqual(device.firmware, .aura(hasBooted: false))
        XCTAssertTrue(device.isAura)
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
