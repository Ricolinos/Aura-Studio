import XCTest
@testable import AuraStudio

/// ST-056 / contrato v10: dos firmwares instalados a la vez y cambio por
/// renombre. Todo sobre carpetas temporales: lo que se fija es la
/// secuencia y sus invariantes, no el hardware.
final class FirmwareSwitcherTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("FakeIPod-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    private func write(_ relative: String, _ text: String) throws {
        let url = root.appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func read(_ relative: String) -> String? {
        try? String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    private func exists(_ relative: String) -> Bool {
        fm.fileExists(atPath: root.appendingPathComponent(relative).path)
    }

    /// Un iPod con Metro activo y Aura dormida, cada uno con su firmware y
    /// sus ajustes.
    private func makeMetroActiveAuraDormant() throws {
        try write(".rockbox/rockbox.ipod", "METRO BIN")
        try write(".rockbox/aura/aura.cfg", "firmware_family: metro\naccent: 9\n")
        try write(".rockbox/fonts/metro-list-20.fnt", "x")
        try write(".firmware-aura/rockbox.ipod", "AURA BIN")
        try write(".firmware-aura/aura/aura.cfg", "theme: 1\n")
        try write(".firmware-aura/fonts/a26-title-20.fnt", "x")
        try write("rockbox.ipod", "METRO BIN")
    }

    func testDormantFamiliesAreReadFromDirectoryNames() throws {
        try makeMetroActiveAuraDormant()
        XCTAssertEqual(FirmwareSwitcher.dormantFamilies(volumeRoot: root), [.aura])
        XCTAssertTrue(FirmwareSwitcher.hasActiveTree(volumeRoot: root))
    }

    /// El cambio: el saliente queda dormido ENTERO con sus ajustes, el
    /// entrante es el activo con los suyos, el respaldo de la raiz es el
    /// del entrante, y el marcador pide reconstruir la musica.
    func testSwitchSwapsTreesAndKeepsEachFamilysSettings() throws {
        try makeMetroActiveAuraDormant()

        try FirmwareSwitcher.switchActiveFirmware(to: .aura, currentlyActive: .metro, volumeRoot: root)

        XCTAssertEqual(read(".rockbox/rockbox.ipod"), "AURA BIN")
        XCTAssertEqual(read(".rockbox/aura/aura.cfg"), "theme: 1\n", "Aura despierta con SUS ajustes")
        XCTAssertTrue(exists(".rockbox/fonts/a26-title-20.fnt"))
        XCTAssertEqual(read(".firmware-metro/rockbox.ipod"), "METRO BIN")
        XCTAssertEqual(read(".firmware-metro/aura/aura.cfg"), "firmware_family: metro\naccent: 9\n",
                       "Metro duerme con los suyos, intactos")
        XCTAssertFalse(exists(".firmware-aura"), "nunca un dormido de la familia activa")
        XCTAssertEqual(read("rockbox.ipod"), "AURA BIN", "el respaldo del bootloader es el del activo")

        let marker = try XCTUnwrap(SyncPendingMarker.read(from: root))
        XCTAssertTrue(marker.changes.music)
        XCTAssertFalse(marker.changes.video)
        XCTAssertEqual(marker.attempts, 0)
    }

    func testSwitchBackRestoresOriginalState() throws {
        try makeMetroActiveAuraDormant()
        try FirmwareSwitcher.switchActiveFirmware(to: .aura, currentlyActive: .metro, volumeRoot: root)
        try FirmwareSwitcher.switchActiveFirmware(to: .metro, currentlyActive: .aura, volumeRoot: root)
        XCTAssertEqual(read(".rockbox/rockbox.ipod"), "METRO BIN")
        XCTAssertEqual(read(".rockbox/aura/aura.cfg"), "firmware_family: metro\naccent: 9\n")
        XCTAssertEqual(read(".firmware-aura/aura/aura.cfg"), "theme: 1\n")
        XCTAssertEqual(read("rockbox.ipod"), "METRO BIN")
    }

    func testSwitchRefusesWithoutDormantTarget() throws {
        try write(".rockbox/rockbox.ipod", "METRO BIN")
        XCTAssertThrowsError(try FirmwareSwitcher.switchActiveFirmware(to: .aura, currentlyActive: .metro, volumeRoot: root)) { error in
            XCTAssertEqual(error as? FirmwareSwitcher.SwitchError, .dormantTreeMissing(.aura))
        }
        XCTAssertEqual(read(".rockbox/rockbox.ipod"), "METRO BIN", "no toco nada")
    }

    func testSwitchRefusesSameFamily() throws {
        try makeMetroActiveAuraDormant()
        XCTAssertThrowsError(try FirmwareSwitcher.switchActiveFirmware(to: .metro, currentlyActive: .metro, volumeRoot: root)) { error in
            XCTAssertEqual(error as? FirmwareSwitcher.SwitchError, .alreadyActive(.metro))
        }
    }

    /// Un cambio que quedo a medias: el paso 2 (saliente -> dormido) se
    /// hizo y el 3 no. Queda un disco sin `/.rockbox/` y con UN dormido:
    /// la reparacion lo despierta y rehace el respaldo.
    func testRepairWakesTheOnlyDormantTree() throws {
        try write(".firmware-aura/rockbox.ipod", "AURA BIN")
        try write(".firmware-aura/aura/aura.cfg", "theme: 1\n")
        try write("rockbox.ipod", "METRO BIN") // respaldo viejo, del que se fue

        let repaired = try FirmwareSwitcher.repairIfNeeded(volumeRoot: root)
        XCTAssertEqual(repaired, .aura)
        XCTAssertEqual(read(".rockbox/rockbox.ipod"), "AURA BIN")
        XCTAssertFalse(exists(".firmware-aura"))
        XCTAssertEqual(read("rockbox.ipod"), "AURA BIN")
    }

    /// Con activo presente no hay nada que reparar; con dos dormidos y
    /// ninguno activo no se adivina.
    func testRepairDoesNothingWhenHealthyOrAmbiguous() throws {
        try makeMetroActiveAuraDormant()
        XCTAssertNil(try FirmwareSwitcher.repairIfNeeded(volumeRoot: root))
        XCTAssertEqual(read(".rockbox/rockbox.ipod"), "METRO BIN")

        try fm.removeItem(at: root.appendingPathComponent(".rockbox"))
        try write(".firmware-metro/rockbox.ipod", "METRO BIN")
        XCTAssertNil(try FirmwareSwitcher.repairIfNeeded(volumeRoot: root))
        XCTAssertTrue(exists(".firmware-aura"))
        XCTAssertTrue(exists(".firmware-metro"))
    }

    /// El instalador, antes de instalar la otra familia: estaciona el
    /// activo (reemplazando un dormido viejo de esa familia) y deja
    /// `/.rockbox/` libre para el arbol nuevo.
    func testParkActiveTreeReplacesOlderDormantOfSameFamily() throws {
        try makeMetroActiveAuraDormant()
        try write(".firmware-metro/rockbox.ipod", "METRO VIEJO")

        try FirmwareSwitcher.parkActiveTree(as: .metro, volumeRoot: root)

        XCTAssertFalse(exists(".rockbox"))
        XCTAssertEqual(read(".firmware-metro/rockbox.ipod"), "METRO BIN", "el estacionado es el activo, no el viejo")
        XCTAssertEqual(read(".firmware-metro/aura/aura.cfg"), "firmware_family: metro\naccent: 9\n")
        XCTAssertTrue(exists(".firmware-aura"), "el dormido de la OTRA familia no se toca")
    }

    /// Los archivos del contrato se copian del activo a cada dormido;
    /// `aura.cfg` y `themes/` no.
    func testMirrorCopiesContractFilesButNotSettings() throws {
        try makeMetroActiveAuraDormant()
        try write(".rockbox/aura/sync_summary.cfg", "music_count: 389\n")
        try write(".rockbox/aura/ratings.cfg", "/Music/a.mp3: 10\n")
        try write(".rockbox/aura/artist_images.cfg", "x.jpg: X\n")
        try write(".rockbox/aura/artists/x.jpg", "JPG")
        try write(".rockbox/aura/themes/neon/theme.cfg", "x")
        try write(".firmware-aura/aura/sync_summary.cfg", "music_count: 1\n") // viejo

        try FirmwareSwitcher.mirrorContractFilesToDormantTrees(volumeRoot: root)

        XCTAssertEqual(read(".firmware-aura/aura/sync_summary.cfg"), "music_count: 389\n")
        XCTAssertEqual(read(".firmware-aura/aura/ratings.cfg"), "/Music/a.mp3: 10\n")
        XCTAssertEqual(read(".firmware-aura/aura/artists/x.jpg"), "JPG")
        XCTAssertEqual(read(".firmware-aura/aura/aura.cfg"), "theme: 1\n", "los ajustes del dormido no se pisan")
        XCTAssertFalse(exists(".firmware-aura/aura/themes"), "los temas viajan con su arbol, no se espejan")
    }
}
