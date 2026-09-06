import XCTest
@testable import AuraStudio

/// ST-193: `AppUpdateDecision` es **la referencia** de esta
/// funcionalidad para las dos plataformas (acuerdo de la sesión maestra:
/// se escribe primero en Swift y Windows la porta citando la ST). Estas
/// pruebas son, por lo tanto, la especificación ejecutable de las reglas
/// -- si Windows se comporta distinto en cualquiera de estos casos, uno
/// de los dos está mal.
///
/// Todo acá es puro: no hay red, ni reloj, ni disco.
final class AppUpdateDecisionTests: XCTestCase {

    private func release(_ tag: String,
                         draft: Bool = false,
                         prerelease: Bool = false,
                         assets: [String] = [],
                         htmlURL: String? = nil) -> GitHubRelease {
        GitHubRelease(
            tagName: tag, draft: draft, prerelease: prerelease,
            assets: assets.map {
                GitHubReleaseAsset(name: $0, url: "https://api.github.com/assets/1", size: 1,
                                   browserDownloadURL: "https://github.com/descarga/\($0)")
            },
            htmlURL: htmlURL)
    }

    // MARK: - El patrón de nombres (el único contrato nuevo)

    /// Congelado por la sesión maestra y verificado contra los Releases
    /// v0.2.2 y v0.2.3 reales. Cambiarlo rompe la actualización de todas
    /// las versiones ya instaladas, así que este caso es un candado.
    func testAssetNamesFollowTheFrozenPattern() {
        let version = SemVer(major: 0, minor: 3, patch: 0, prerelease: nil)
        XCTAssertEqual(AppUpdatePlatform.mac.assetName(forVersion: version),
                       "AuraStudio-0.3.0.dmg")
        XCTAssertEqual(AppUpdatePlatform.windowsARM64.assetName(forVersion: version),
                       "AuraStudioSetup-0.3.0-arm64.exe")
        XCTAssertEqual(AppUpdatePlatform.windowsX64.assetName(forVersion: version),
                       "AuraStudioSetup-0.3.0-x64.exe")
    }

    func testAssetNameKeepsThePrereleaseSuffix() {
        let version = SemVer(major: 0, minor: 3, patch: 0, prerelease: "beta")
        XCTAssertEqual(AppUpdatePlatform.mac.assetName(forVersion: version),
                       "AuraStudio-0.3.0-beta.dmg")
    }

    // MARK: - Cuándo hay novedad

    func testOffersANewerVersionWithItsAsset() throws {
        let decision = AppUpdateDecision.decide(
            installedVersion: "0.2.3",
            releases: [release("v0.3.0", assets: ["AuraStudio-0.3.0.dmg"])],
            includePrereleases: true,
            platform: .mac)

        let update = try XCTUnwrap(decision)
        XCTAssertEqual(update.tag, "v0.3.0")
        XCTAssertEqual(update.version, SemVer(major: 0, minor: 3, patch: 0, prerelease: nil))
        XCTAssertEqual(update.assetName, "AuraStudio-0.3.0.dmg")
        XCTAssertEqual(update.downloadURL?.absoluteString,
                       "https://github.com/descarga/AuraStudio-0.3.0.dmg")
    }

    /// Nunca se ofrece "actualizar" hacia atrás, ni a la misma.
    func testSaysNothingWhenTheInstalledVersionIsTheNewestOrNewer() {
        XCTAssertNil(AppUpdateDecision.decide(
            installedVersion: "0.3.0",
            releases: [release("v0.3.0", assets: ["AuraStudio-0.3.0.dmg"])],
            includePrereleases: true, platform: .mac))

        XCTAssertNil(AppUpdateDecision.decide(
            installedVersion: "0.4.0",
            releases: [release("v0.3.0", assets: ["AuraStudio-0.3.0.dmg"])],
            includePrereleases: true, platform: .mac))
    }

    func testPicksTheHighestVersionNotTheFirstOne() throws {
        let decision = AppUpdateDecision.decide(
            installedVersion: "0.2.0",
            releases: [release("v0.2.1"), release("v0.3.0"), release("v0.2.9")],
            includePrereleases: true, platform: .mac)

        XCTAssertEqual(try XCTUnwrap(decision).tag, "v0.3.0")
    }

    func testDraftsNeverCount() {
        XCTAssertNil(AppUpdateDecision.decide(
            installedVersion: "0.2.3",
            releases: [release("v0.3.0", draft: true)],
            includePrereleases: true, platform: .mac))
    }

    func testPrereleasesCountOnlyWhenAsked() throws {
        let releases = [release("v0.3.0", prerelease: true)]

        XCTAssertNil(AppUpdateDecision.decide(
            installedVersion: "0.2.3", releases: releases,
            includePrereleases: false, platform: .mac))

        let withBetas = AppUpdateDecision.decide(
            installedVersion: "0.2.3", releases: releases,
            includePrereleases: true, platform: .mac)
        XCTAssertEqual(try XCTUnwrap(withBetas).tag, "v0.3.0")
    }

    /// Un tag que no es SemVer se ignora sin romper el resto.
    func testIgnoresTagsThatAreNotVersions() throws {
        let decision = AppUpdateDecision.decide(
            installedVersion: "0.2.3",
            releases: [release("nightly"), release("v0.3.0")],
            includePrereleases: true, platform: .mac)

        XCTAssertEqual(try XCTUnwrap(decision).tag, "v0.3.0")
    }

    /// Sin saber qué hay instalado no se puede afirmar que algo sea más
    /// nuevo: lo prudente es callar.
    func testSaysNothingWhenTheInstalledVersionCannotBeParsed() {
        XCTAssertNil(AppUpdateDecision.decide(
            installedVersion: "no-es-una-version",
            releases: [release("v0.3.0", assets: ["AuraStudio-0.3.0.dmg"])],
            includePrereleases: true, platform: .mac))
    }

    // MARK: - El asset que falta

    /// Se avisa igual de la versión nueva, pero SIN descarga: un botón
    /// "Descargar" que falla es peor que no tenerlo.
    func testAnnouncesTheVersionEvenWhenTheInstallerIsMissing() throws {
        let decision = AppUpdateDecision.decide(
            installedVersion: "0.2.3",
            releases: [release("v0.3.0", assets: ["AuraStudioSetup-0.3.0-arm64.exe"])],
            includePrereleases: true, platform: .mac)

        let update = try XCTUnwrap(decision)
        XCTAssertNil(update.downloadURL)
        XCTAssertEqual(update.assetName, "AuraStudio-0.3.0.dmg")
        XCTAssertNotNil(update.releasePageURL)
    }

    /// Cada plataforma se lleva SU archivo, no el primero que haya.
    func testEachPlatformPicksItsOwnAsset() throws {
        let releases = [release("v0.3.0", assets: [
            "AuraStudio-0.3.0.dmg",
            "AuraStudioSetup-0.3.0-arm64.exe",
            "AuraStudioSetup-0.3.0-x64.exe",
        ])]

        for (platform, expected) in [(AppUpdatePlatform.mac, "AuraStudio-0.3.0.dmg"),
                                     (.windowsARM64, "AuraStudioSetup-0.3.0-arm64.exe"),
                                     (.windowsX64, "AuraStudioSetup-0.3.0-x64.exe")] {
            let decision = AppUpdateDecision.decide(
                installedVersion: "0.2.3", releases: releases,
                includePrereleases: true, platform: platform)
            XCTAssertEqual(try XCTUnwrap(decision).downloadURL?.absoluteString,
                           "https://github.com/descarga/\(expected)",
                           "\(platform) se llevó el archivo equivocado")
        }
    }

    // MARK: - La página del Release

    func testPrefersTheReleasePageGitHubGives() throws {
        let decision = AppUpdateDecision.decide(
            installedVersion: "0.2.3",
            releases: [release("v0.3.0", htmlURL: "https://github.com/otro/sitio")],
            includePrereleases: true, platform: .mac)

        XCTAssertEqual(try XCTUnwrap(decision).releasePageURL?.absoluteString,
                       "https://github.com/otro/sitio")
    }

    /// Sin `html_url` (respuesta recortada, caché viejo) se arma con el
    /// repo y el tag, que es una URL estable de GitHub.
    func testFallsBackToTheCanonicalReleasePage() throws {
        let decision = AppUpdateDecision.decide(
            installedVersion: "0.2.3",
            releases: [release("v0.3.0")],
            includePrereleases: true, platform: .mac)

        XCTAssertEqual(try XCTUnwrap(decision).releasePageURL?.absoluteString,
                       "https://github.com/Ricolinos/Aura-Studio/releases/tag/v0.3.0")
    }
}
