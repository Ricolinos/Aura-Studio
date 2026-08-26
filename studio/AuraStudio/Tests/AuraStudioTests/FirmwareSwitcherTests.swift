import XCTest
@testable import AuraStudio

/// ST-056 / contrato v10 (y ST-065, tres arboles): varios firmwares
/// instalados a la vez y cambio por renombre. Todo sobre carpetas temporales: lo que se fija es la
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

    // MARK: - ST-061: sembrar los archivos del contrato al arbol activo

    /// Arbol activo fresco (sin sync_summary) + dormido con los archivos:
    /// se heredan. Con el activo ya poblado, no se toca nada.
    func testSeedContractFilesFromDormantTree() throws {
        try makeMetroActiveAuraDormant()
        try write(".firmware-aura/aura/sync_summary.cfg", "music_count: 389\n")
        try write(".firmware-aura/aura/artist_images.cfg", "x.jpg: X\n")
        try write(".firmware-aura/aura/artists/x.jpg", "JPG")
        try write(".firmware-aura/aura/video_categories.cfg", "peli.mpg: movie\n")

        XCTAssertTrue(FirmwareSwitcher.seedContractFilesToActiveTree(volumeRoot: root))
        XCTAssertEqual(read(".rockbox/aura/sync_summary.cfg"), "music_count: 389\n")
        XCTAssertEqual(read(".rockbox/aura/video_categories.cfg"), "peli.mpg: movie\n")
        XCTAssertEqual(read(".rockbox/aura/artists/x.jpg"), "JPG")
        XCTAssertEqual(read(".rockbox/aura/aura.cfg"), "firmware_family: metro\naccent: 9\n",
                       "los ajustes del activo no se tocan")

        // Segunda llamada: el activo ya tiene sync_summary -> no-op.
        try write(".firmware-aura/aura/sync_summary.cfg", "music_count: 1\n")
        XCTAssertFalse(FirmwareSwitcher.seedContractFilesToActiveTree(volumeRoot: root))
        XCTAssertEqual(read(".rockbox/aura/sync_summary.cfg"), "music_count: 389\n")
    }

    func testSeedDoesNothingWithoutDonor() throws {
        try makeMetroActiveAuraDormant() // dormido sin sync_summary
        XCTAssertFalse(FirmwareSwitcher.seedContractFilesToActiveTree(volumeRoot: root))
        XCTAssertFalse(exists(".rockbox/aura/sync_summary.cfg"))
    }

    // MARK: - v12 / ST-059: sello de biblioteca

    /// Primer cambio tras v12 (sin sello compartido): se crea, se anota
    /// como del saliente, y el entrante -- sin sello propio -- SI recibe
    /// marcador. El comportamiento de siempre, mas el arranque en frio.
    func testFirstSwitchBootstrapsStampAndStillWritesMarker() throws {
        try makeMetroActiveAuraDormant()
        try FirmwareSwitcher.switchActiveFirmware(to: .aura, currentlyActive: .metro, volumeRoot: root)

        XCTAssertNotNil(SyncPendingMarker.read(from: root), "sin sello del entrante -> marcador")
        let shared = try XCTUnwrap(read(".aura/library-stamp"))
        XCTAssertEqual(read(".firmware-metro/aura/db_stamp.txt"), shared,
                       "el saliente (base al dia) queda anotado con el sello nuevo")
    }

    /// La ida y VUELTA sin sync de por medio: el arbol que vuelve tiene su
    /// sello anotado e igual al compartido -> sin marcador -> sin
    /// reconstruccion (el reporte del dueño: ~5 min por cada cambio).
    func testSwitchBackWithoutSyncWritesNoMarker() throws {
        try makeMetroActiveAuraDormant()
        try FirmwareSwitcher.switchActiveFirmware(to: .aura, currentlyActive: .metro, volumeRoot: root)
        // Aura reconstruyo y anoto (lo que haria el firmware al terminar):
        let shared = try XCTUnwrap(read(".aura/library-stamp"))
        try write(".rockbox/aura/db_stamp.txt", shared)
        try? fm.removeItem(at: root.appendingPathComponent(".aura/sync-pending.json"))

        try FirmwareSwitcher.switchActiveFirmware(to: .metro, currentlyActive: .aura, volumeRoot: root)

        XCTAssertNil(SyncPendingMarker.read(from: root),
                     "Metro vuelve con su base intacta: nada que reconstruir")
        XCTAssertEqual(read(".firmware-aura/aura/db_stamp.txt"), shared,
                       "la anotacion de Aura viaja con su arbol")
    }

    /// Con un sync REAL de por medio (sello renovado), el cambio si deja
    /// marcador aunque el arbol entrante tenga sello -- esta viejo.
    func testSwitchAfterSyncWritesMarker() throws {
        try makeMetroActiveAuraDormant()
        try FirmwareSwitcher.switchActiveFirmware(to: .aura, currentlyActive: .metro, volumeRoot: root)
        try? fm.removeItem(at: root.appendingPathComponent(".aura/sync-pending.json"))

        FirmwareSwitcher.bumpLibraryStamp(volumeRoot: root) // "hubo sync de musica"

        try FirmwareSwitcher.switchActiveFirmware(to: .metro, currentlyActive: .aura, volumeRoot: root)
        XCTAssertNotNil(SyncPendingMarker.read(from: root),
                        "el sello de Metro quedo viejo: reconstruye")
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

    // MARK: - ST-065: tres familias a la vez (moonlit activa, dos dormidas)

    private func makeMoonlitActiveWithTwoDormant() throws {
        try write(".rockbox/rockbox.ipod", "MOONLIT BIN")
        try write(".rockbox/aura/aura.cfg", "firmware_family: moonlit\nsync_marker_supported: 1\n")
        try write(".rockbox/fonts/moonlit-body-18.fnt", "x")
        try write(".firmware-aura/rockbox.ipod", "AURA BIN")
        try write(".firmware-aura/aura/aura.cfg", "theme: 1\n")
        try write(".firmware-metro/rockbox.ipod", "METRO BIN")
        try write(".firmware-metro/aura/aura.cfg", "firmware_family: metro\naccent: 9\n")
        try write("rockbox.ipod", "MOONLIT BIN")
    }

    func testThreeTreesDormantFamiliesListsBothSleepers() throws {
        try makeMoonlitActiveWithTwoDormant()
        XCTAssertEqual(FirmwareSwitcher.dormantFamilies(volumeRoot: root), [.aura, .metro])
        XCTAssertEqual(FirmwareCapabilities.declaredFamily(volumeRoot: root), .moonlit)
    }

    /// Cambiar de moonlit a Aura toca solo esos dos arboles: Metro sigue
    /// dormido donde estaba y moonlit se estaciona bajo SU nombre.
    func testThreeTreesSwitchLeavesThirdFamilyUntouched() throws {
        try makeMoonlitActiveWithTwoDormant()
        try FirmwareSwitcher.switchActiveFirmware(to: .aura, currentlyActive: .moonlit, volumeRoot: root)

        XCTAssertEqual(read(".rockbox/rockbox.ipod"), "AURA BIN")
        XCTAssertEqual(read(".rockbox/aura/aura.cfg"), "theme: 1\n")
        XCTAssertEqual(read(".firmware-moonlit/rockbox.ipod"), "MOONLIT BIN")
        XCTAssertEqual(read(".firmware-moonlit/aura/aura.cfg"), "firmware_family: moonlit\nsync_marker_supported: 1\n")
        XCTAssertTrue(exists(".firmware-moonlit/fonts/moonlit-body-18.fnt"))
        XCTAssertEqual(read(".firmware-metro/rockbox.ipod"), "METRO BIN", "el tercero no se toca")
        XCTAssertEqual(read(".firmware-metro/aura/aura.cfg"), "firmware_family: metro\naccent: 9\n")
        XCTAssertFalse(exists(".firmware-aura"), "nunca un dormido de la familia activa")
        XCTAssertEqual(read("rockbox.ipod"), "AURA BIN")
        XCTAssertEqual(FirmwareSwitcher.dormantFamilies(volumeRoot: root), [.metro, .moonlit])
    }

    /// El espejo escribe en TODOS los dormidos, no solo en "el otro".
    func testThreeTreesMirrorWritesToBothDormant() throws {
        try makeMoonlitActiveWithTwoDormant()
        try write(".rockbox/aura/sync_summary.cfg", "music_count: 389\n")
        try write(".rockbox/aura/artists/x.jpg", "JPG")

        try FirmwareSwitcher.mirrorContractFilesToDormantTrees(volumeRoot: root)

        for tree in [".firmware-aura", ".firmware-metro"] {
            XCTAssertEqual(read("\(tree)/aura/sync_summary.cfg"), "music_count: 389\n", tree)
            XCTAssertEqual(read("\(tree)/aura/artists/x.jpg"), "JPG", tree)
        }
        XCTAssertEqual(read(".firmware-aura/aura/aura.cfg"), "theme: 1\n")
        XCTAssertEqual(read(".firmware-metro/aura/aura.cfg"), "firmware_family: metro\naccent: 9\n")
    }

    /// Sin activo y con DOS dormidos (moonlit se perdio a medio cambio) no
    /// se adivina: nil y nada nuevo en el disco.
    func testThreeTreesRepairRefusesToGuessBetweenTwoDormant() throws {
        try makeMoonlitActiveWithTwoDormant()
        try fm.removeItem(at: root.appendingPathComponent(".rockbox"))

        XCTAssertNil(try FirmwareSwitcher.repairIfNeeded(volumeRoot: root))
        XCTAssertFalse(exists(".rockbox"))
        XCTAssertFalse(exists(".firmware-moonlit"))
        XCTAssertTrue(exists(".firmware-aura"))
        XCTAssertTrue(exists(".firmware-metro"))
        XCTAssertEqual(read("rockbox.ipod"), "MOONLIT BIN", "el respaldo de la raiz no se toca")
    }

    // MARK: - ST-069 / contrato v15: /.aura/tagcache y /.aura/thumbs son del firmware

    private func plantSharedFirmwareData() throws {
        try write(".aura/tagcache/database_idx.tcd", "IDX")
        try write(".aura/tagcache/database_0.tcd", "T0")
        try write(".aura/tagcache/db_stamp.txt", "2026-08-26T00:00:00Z-abcd1234")
        try write(".aura/thumbs/albums/a.jpg", "JPG")
        try write(".aura/thumbs/artists/b.jpg", "JPG")
        try write(".aura/thumbs/photos/c.jpg", "JPG")
    }

    private func assertSharedFirmwareDataIntact(_ context: String, file: StaticString = #filePath, line: UInt = #line) {
        for path in [".aura/tagcache/database_idx.tcd", ".aura/tagcache/database_0.tcd",
                     ".aura/tagcache/db_stamp.txt", ".aura/thumbs/albums/a.jpg",
                     ".aura/thumbs/artists/b.jpg", ".aura/thumbs/photos/c.jpg"] {
            XCTAssertTrue(exists(path), "\(context): \(path) debe seguir existiendo", file: file, line: line)
        }
        XCTAssertEqual(read(".aura/tagcache/db_stamp.txt"), "2026-08-26T00:00:00Z-abcd1234",
                       "\(context): el sello compartido no se reescribe", file: file, line: line)
    }

    /// Cambio de familia completo (estacionar, despertar, reparar, borrar
    /// dormido, sembrar, espejar): la base y las miniaturas compartidas
    /// sobreviven a todos.
    func testTreeFlowsNeverTouchSharedTagcacheOrThumbs() throws {
        try makeMetroActiveAuraDormant()
        try plantSharedFirmwareData()

        try FirmwareSwitcher.switchActiveFirmware(to: .aura, currentlyActive: .metro, volumeRoot: root)
        assertSharedFirmwareDataIntact("switchActiveFirmware")

        // Instalacion de otra familia: se estaciona el activo y se extrae
        // uno fresco; luego se borra el dormido de la misma familia.
        try FirmwareSwitcher.parkActiveTree(as: .aura, volumeRoot: root)
        assertSharedFirmwareDataIntact("parkActiveTree")
        try write(".rockbox/rockbox.ipod", "MOONLIT BIN")
        try write(".rockbox/aura/aura.cfg", "firmware_family: moonlit\n")
        try FirmwareSwitcher.removeDormantTree(of: .moonlit, volumeRoot: root)
        try FirmwareSwitcher.removeDormantTree(of: .metro, volumeRoot: root)
        assertSharedFirmwareDataIntact("removeDormantTree")
        try FirmwareSwitcher.refreshRootBinary(volumeRoot: root)
        _ = FirmwareSwitcher.seedContractFilesToActiveTree(volumeRoot: root)
        try FirmwareSwitcher.mirrorContractFilesToDormantTrees(volumeRoot: root)
        assertSharedFirmwareDataIntact("seed/mirror")

        // Cambio a medias: sin activo y un solo dormido -> se repara.
        try fm.removeItem(at: root.appendingPathComponent(".rockbox"))
        XCTAssertEqual(try FirmwareSwitcher.repairIfNeeded(volumeRoot: root), .aura)
        assertSharedFirmwareDataIntact("repairIfNeeded")
        XCTAssertFalse(exists(".firmware-metro"), "el dormido de Metro si se borro (era el objetivo)")
    }
}
