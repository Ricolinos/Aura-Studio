import XCTest
@testable import AuraStudio

final class AuraThemeIDTests: XCTestCase {
    func testValidIds() {
        XCTAssertTrue(AuraThemeID.isValid("apple-personal"))
        XCTAssertTrue(AuraThemeID.isValid("a"))
        XCTAssertTrue(AuraThemeID.isValid("mi-tema-2"))
        XCTAssertTrue(AuraThemeID.isValid(String(repeating: "a", count: 32)))
    }

    func testInvalidIds() {
        XCTAssertFalse(AuraThemeID.isValid(""))
        XCTAssertFalse(AuraThemeID.isValid("default"))
        XCTAssertFalse(AuraThemeID.isValid("Mi-Tema"))
        XCTAssertFalse(AuraThemeID.isValid("mi tema"))
        XCTAssertFalse(AuraThemeID.isValid("../etc"))
        XCTAssertFalse(AuraThemeID.isValid("tema.viejo"))
        XCTAssertFalse(AuraThemeID.isValid("tema/otro"))
        XCTAssertFalse(AuraThemeID.isValid(String(repeating: "a", count: 33)))
    }
}

final class AuraThemeManifestTests: XCTestCase {
    func testParsesFullManifest() {
        let text = """
        theme_format: 1
        theme_id: aura-inverso-demo
        theme_name: Aura Inverso (prueba)
        theme_author: Alguien
        theme_license: open
        theme_redistributable: yes
        palette_light_shell_bg: #1C1C1E
        palette_dark_shell_bg: #FFFFFF
        category_video: #FF9500
        accent_default: #FF2D55
        accent_presets: #FF2D55,#FF3B30,#FF9500
        """
        guard let manifest = AuraThemeManifest.parse(text) else {
            return XCTFail("debería parsear")
        }
        XCTAssertEqual(manifest.format, 1)
        XCTAssertEqual(manifest.id, "aura-inverso-demo")
        XCTAssertEqual(manifest.name, "Aura Inverso (prueba)")
        XCTAssertEqual(manifest.author, "Alguien")
        XCTAssertEqual(manifest.license, .open)
        XCTAssertTrue(manifest.redistributable)
        XCTAssertEqual(manifest.paletteLight[.shellBg], "#1C1C1E")
        XCTAssertEqual(manifest.paletteDark[.shellBg], "#FFFFFF")
        XCTAssertNil(manifest.paletteDark[.textPrimary])
        XCTAssertEqual(manifest.category[.video], "#FF9500")
        XCTAssertEqual(manifest.accentDefault, "#FF2D55")
        XCTAssertEqual(manifest.accentPresets, ["#FF2D55", "#FF3B30", "#FF9500"])
    }

    func testMissingFormatFailsToParse() {
        let text = "theme_id: sin-formato\ntheme_name: Sin formato"
        XCTAssertNil(AuraThemeManifest.parse(text))
    }

    func testUnknownKeysAreIgnoredSilently() {
        let text = """
        theme_format: 1
        theme_id: x
        requires_firmware_min: 0.9.0
        un_campo_que_no_existe_todavia: 42
        """
        XCTAssertNotNil(AuraThemeManifest.parse(text))
    }

    func testCommentLinesAreIgnored() {
        let text = """
        # comentario
        theme_format: 1
        theme_id: con-comentario
        """
        let manifest = AuraThemeManifest.parse(text)
        XCTAssertEqual(manifest?.id, "con-comentario")
    }

    func testSerializeRoundTrip() {
        var manifest = AuraThemeManifest(id: "roundtrip", name: "Ida y vuelta", license: .personal, redistributable: false)
        manifest.paletteLight[.shellBg] = "#FFFFFF"
        manifest.paletteDark[.shellBg] = "#1C1C1E"
        manifest.category[.video] = "#1E3A5F"
        manifest.accentDefault = "#FF2D55"
        manifest.accentPresets = ["#FF2D55", "#007AFF"]

        let text = manifest.serialized()
        let reparsed = AuraThemeManifest.parse(text)
        XCTAssertEqual(reparsed, manifest)
    }

    func testFormatSupportedComparison() {
        let older = AuraThemeManifest(format: 1, id: "x", name: "X")
        XCTAssertTrue(older.isFormatCurrentOrOlder)

        let newer = AuraThemeManifest(format: 99, id: "x", name: "X")
        XCTAssertFalse(newer.isFormatCurrentOrOlder)
    }
}
