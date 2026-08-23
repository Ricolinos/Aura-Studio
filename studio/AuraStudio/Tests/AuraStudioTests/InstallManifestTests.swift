import XCTest
@testable import AuraStudio

/// ST-058 / contrato v11: la contabilidad de la actualización selectiva.
final class InstallManifestTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("Manifest-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: dir)
    }

    /// Un zip REAL (con /usr/bin/zip, la misma familia de herramientas que
    /// el release) -- lo que se fija es que el CRC del directorio central
    /// se lea tal cual, sin calcular nada.
    private func makeZip(entries: [String: String]) throws -> URL {
        let root = dir.appendingPathComponent("payload-\(UUID().uuidString)")
        for (path, contents) in entries {
            let url = root.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        let zipURL = dir.appendingPathComponent("fixture-\(UUID().uuidString).zip")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.currentDirectoryURL = root
        p.arguments = ["-r", "-q", zipURL.path, "."]
        try p.run(); p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
        return zipURL
    }

    func testEntriesFromZipReadsCentralDirectory() throws {
        let zip = try makeZip(entries: [
            ".rockbox/rockbox.ipod": "FIRMWARE",
            ".rockbox/fonts/con espacios.fnt": "FONT",
            ".rockbox/aura/version.txt": "v1.0.0\n",
        ])
        let entries = try InstallManifest.entriesFromZip(zip)
        XCTAssertEqual(entries.count, 3)
        let fw = try XCTUnwrap(entries[".rockbox/rockbox.ipod"])
        XCTAssertEqual(fw.size, UInt64("FIRMWARE".utf8.count))
        // CRC32 de "FIRMWARE" (zlib.crc32(b"FIRMWARE") == 0x13df4b88):
        XCTAssertEqual(fw.crc32, 0x13DF4B88, "crc32 estable del contenido")
        XCTAssertNotNil(entries[".rockbox/fonts/con espacios.fnt"], "las rutas con espacios sobreviven al parseo")
    }

    func testSerializeParseRoundTrip() throws {
        let entries: [String: InstallManifest.Entry] = [
            ".rockbox/a.bin": .init(path: ".rockbox/a.bin", size: 10, crc32: 0xDEADBEEF),
            ".rockbox/con espacios/b c.fnt": .init(path: ".rockbox/con espacios/b c.fnt", size: 0, crc32: 0),
        ]
        let m = InstallManifest(tag: "v0.5.4", entries: entries)
        let back = try XCTUnwrap(InstallManifest.parse(m.serialized()))
        XCTAssertEqual(back, m)
    }

    func testParseRejectsForeignText() {
        XCTAssertNil(InstallManifest.parse("no soy un manifiesto\n"))
        XCTAssertNil(InstallManifest.parse("# aura-install-manifest v2\n"), "una versión futura cae a extracción completa")
    }

    func testDeltaFindsChangedAddedAndRemoved() {
        let e = { (p: String, s: UInt64, c: UInt32) in InstallManifest.Entry(path: p, size: s, crc32: c) }
        let old: [String: InstallManifest.Entry] = [
            ".rockbox/igual.bin": e(".rockbox/igual.bin", 5, 1),
            ".rockbox/cambia.bin": e(".rockbox/cambia.bin", 5, 2),
            ".rockbox/sefue.bin": e(".rockbox/sefue.bin", 5, 3),
            "fuera-del-arbol.txt": e("fuera-del-arbol.txt", 5, 4),
        ]
        let new: [String: InstallManifest.Entry] = [
            ".rockbox/igual.bin": e(".rockbox/igual.bin", 5, 1),
            ".rockbox/cambia.bin": e(".rockbox/cambia.bin", 6, 9),
            ".rockbox/nuevo.bin": e(".rockbox/nuevo.bin", 7, 8),
        ]
        let d = InstallManifest.delta(installed: old, new: new)
        XCTAssertEqual(d.toExtract, [".rockbox/cambia.bin", ".rockbox/nuevo.bin"])
        XCTAssertEqual(d.toDelete, [".rockbox/sefue.bin"],
                       "jamás se borra fuera de .rockbox/, ni con un manifiesto raro")
    }

    /// Punta a punta con zips reales: el delta entre dos zips detecta
    /// exactamente el archivo cambiado y el eliminado.
    func testDeltaBetweenTwoRealZips() throws {
        let oldZip = try makeZip(entries: [
            ".rockbox/rockbox.ipod": "VERSION 1",
            ".rockbox/codecs/mpa.codec": "CODEC",
            ".rockbox/viejo.rock": "OLD",
        ])
        let newZip = try makeZip(entries: [
            ".rockbox/rockbox.ipod": "VERSION 2!",
            ".rockbox/codecs/mpa.codec": "CODEC",
            ".rockbox/nuevo.rock": "NEW",
        ])
        let old = try InstallManifest.entriesFromZip(oldZip)
        let new = try InstallManifest.entriesFromZip(newZip)
        let d = InstallManifest.delta(installed: old, new: new)
        XCTAssertEqual(d.toExtract, [".rockbox/nuevo.rock", ".rockbox/rockbox.ipod"])
        XCTAssertEqual(d.toDelete, [".rockbox/viejo.rock"])
    }

    func testReadWriteOnVolume() throws {
        let m = InstallManifest(tag: "v9.9.9",
                                entries: [".rockbox/x": .init(path: ".rockbox/x", size: 1, crc32: 2)])
        try m.write(volumeRoot: dir)
        XCTAssertEqual(InstallManifest.read(volumeRoot: dir), m)
    }
}
