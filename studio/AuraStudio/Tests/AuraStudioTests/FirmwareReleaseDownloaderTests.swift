import XCTest
@testable import AuraStudio

/// ST-077: descarga del Release más nuevo para instalar desde cero.
/// Nada toca la red real (`MockURLProtocol`) ni el Llavero (el token se
/// inyecta explícitamente, como en `GitHubTokenTests`).
final class FirmwareReleaseDownloaderTests: XCTestCase {

    override func setUp() {
        super.setUp()
        GitHubReleaseChecker.lastAuthFailure = false
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        GitHubReleaseChecker.lastAuthFailure = false
        super.tearDown()
    }

    private func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    // MARK: - El tag nunca entra crudo a una ruta

    func testSafeTagRejectsPathTraversalAndSeparators() {
        XCTAssertTrue(FirmwareReleaseDownloader.isSafeTagComponent("v0.4.4-beta"))
        XCTAssertTrue(FirmwareReleaseDownloader.isSafeTagComponent("v1.0.0"))
        XCTAssertTrue(FirmwareReleaseDownloader.isSafeTagComponent("v0.1.6_rc1"))

        XCTAssertFalse(FirmwareReleaseDownloader.isSafeTagComponent(""))
        XCTAssertFalse(FirmwareReleaseDownloader.isSafeTagComponent("."))
        XCTAssertFalse(FirmwareReleaseDownloader.isSafeTagComponent(".."))
        XCTAssertFalse(FirmwareReleaseDownloader.isSafeTagComponent("../../etc/passwd"),
                       "un tag con separadores escaparía del directorio de caché")
        XCTAssertFalse(FirmwareReleaseDownloader.isSafeTagComponent("v1.0.0/../.."))
        XCTAssertFalse(FirmwareReleaseDownloader.isSafeTagComponent("v1 0 0"))
        XCTAssertFalse(FirmwareReleaseDownloader.isSafeTagComponent(String(repeating: "v", count: 65)))
    }

    func testCacheDirectoryRefusesUnsafeTag() {
        XCTAssertNil(FirmwareReleaseDownloader.cacheDirectory(family: .aura, tag: "../escape"))
        XCTAssertNotNil(FirmwareReleaseDownloader.cacheDirectory(family: .aura, tag: "v0.4.4-beta"))
    }

    func testCacheDirectoryIsPerFamilyAndPerTag() throws {
        let auraA = try XCTUnwrap(FirmwareReleaseDownloader.cacheDirectory(family: .aura, tag: "v1.0.0"))
        let auraB = try XCTUnwrap(FirmwareReleaseDownloader.cacheDirectory(family: .aura, tag: "v1.0.1"))
        let metro = try XCTUnwrap(FirmwareReleaseDownloader.cacheDirectory(family: .metro, tag: "v1.0.0"))
        XCTAssertNotEqual(auraA, auraB, "bajar una versión nueva no debe pisar la anterior")
        XCTAssertNotEqual(auraA, metro, "dos familias no pueden compartir directorio de artefactos")
    }

    // MARK: - Decodificación de assets

    func testReleaseDecodesAssetsAndFindsThemByName() throws {
        let json = """
        [{"tag_name":"v0.5.0","draft":false,"prerelease":false,"assets":[
          {"name":"rockbox.ipod","url":"https://api.github.com/repos/x/y/releases/assets/1","size":1298648},
          {"name":"checksums.txt","url":"https://api.github.com/repos/x/y/releases/assets/2","size":321}
        ]}]
        """
        let releases = try JSONDecoder().decode([GitHubRelease].self, from: Data(json.utf8))
        let release = try XCTUnwrap(releases.first)
        XCTAssertEqual(release.assets.count, 2)
        XCTAssertEqual(release.asset(named: "rockbox.ipod")?.size, 1298648)
        XCTAssertNil(release.asset(named: "mks5lboot"))
    }

    func testReleaseWithoutAssetsKeyStillDecodes() throws {
        // El caché de UserDefaults escrito por una versión anterior de
        // Studio no tiene `assets`. Debe seguir sirviendo para el aviso
        // de versiones en vez de invalidar el Release entero.
        let json = #"[{"tag_name":"v0.4.4-beta","draft":false,"prerelease":true}]"#
        let releases = try JSONDecoder().decode([GitHubRelease].self, from: Data(json.utf8))
        XCTAssertEqual(releases.first?.tagName, "v0.4.4-beta")
        XCTAssertEqual(releases.first?.assets, [])
    }

    // MARK: - Descarga de un asset

    func testDownloadAssetUsesAPIURLWithOctetStreamAndToken() async throws {
        let payload = Data(repeating: 0xAB, count: 64)
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString,
                           "https://api.github.com/repos/x/y/releases/assets/7")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/octet-stream",
                           "sin esta cabecera GitHub devuelve el JSON del asset, no sus bytes")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ghp_test")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                           httpVersion: nil, headerFields: nil)!
            return (response, payload)
        }
        let asset = GitHubReleaseAsset(
            name: "rockbox.ipod",
            url: "https://api.github.com/repos/x/y/releases/assets/7",
            size: 64)
        let data = try await FirmwareReleaseDownloader.downloadAsset(
            asset, session: mockSession(), token: "ghp_test", family: .aura, tag: "v0.5.0")
        XCTAssertEqual(data, payload)
    }

    func testDownloadAssetRejectsTruncatedPayload() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                           httpVersion: nil, headerFields: nil)!
            return (response, Data(repeating: 0x00, count: 10))
        }
        let asset = GitHubReleaseAsset(
            name: "rockbox.zip",
            url: "https://api.github.com/repos/x/y/releases/assets/9",
            size: 9_266_939)
        do {
            _ = try await FirmwareReleaseDownloader.downloadAsset(
                asset, session: mockSession(), token: nil, family: .aura, tag: "v0.5.0")
            XCTFail("un asset truncado no puede darse por bueno")
        } catch let error as InstallerError {
            guard case .releaseDownloadFailed(_, let reason) = error else {
                return XCTFail("error inesperado: \(error)")
            }
            XCTAssertTrue(reason.contains("incompleto"), reason)
        } catch {
            XCTFail("error inesperado: \(error)")
        }
    }

    func testDownloadAssetSurfacesHTTPStatus() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404,
                                           httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let asset = GitHubReleaseAsset(
            name: "mks5lboot",
            url: "https://api.github.com/repos/x/y/releases/assets/3",
            size: 100)
        do {
            _ = try await FirmwareReleaseDownloader.downloadAsset(
                asset, session: mockSession(), token: "ghp_test", family: .metro, tag: "v0.6.5")
            XCTFail("un 404 no puede pasar como descarga buena")
        } catch let error as InstallerError {
            guard case .releaseDownloadFailed(let family, let reason) = error else {
                return XCTFail("error inesperado: \(error)")
            }
            XCTAssertEqual(family, FirmwareFamily.metro.displayName)
            XCTAssertTrue(reason.contains("404"), reason)
        } catch {
            XCTFail("error inesperado: \(error)")
        }
    }

    // MARK: - prepareLatest

    func testPrepareLatestFailsWhenReleaseIsMissingAnAsset() async {
        // Release real pero sin `mks5lboot`: no se puede instalar desde
        // él. Tiene que decirlo con el nombre del asset, no fallar en
        // seco -- el instalador cae a lo embebido con ese motivo.
        // El mock tiene que distinguir la LISTA de Releases de la
        // descarga de un asset: si contesta el JSON a todo, la primera
        // descarga falla por tamaño y nunca se llega al asset ausente,
        // que es lo que este caso comprueba. `size: 0` = "no anunciado",
        // que el descargador acepta sin comparar.
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                           httpVersion: nil, headerFields: nil)!
            guard request.url?.path.hasSuffix("/releases") == true else {
                return (response, Data("contenido del asset".utf8))
            }
            let json = """
            [{"tag_name":"v0.5.0","draft":false,"prerelease":false,"assets":[
              {"name":"checksums.txt","url":"https://api.github.com/a/1","size":0},
              {"name":"rockbox.ipod","url":"https://api.github.com/a/2","size":0},
              {"name":"rockbox.zip","url":"https://api.github.com/a/3","size":0},
              {"name":"bootloader-ipod6g.ipod","url":"https://api.github.com/a/4","size":0}
            ]}]
            """
            return (response, Data(json.utf8))
        }
        defer {
            // prepareLatest escribe su directorio de descarga bajo
            // Application Support antes de fallar; su propio `defer` lo
            // borra, pero el directorio de la familia queda creado.
            if let dir = FirmwareReleaseDownloader.cacheDirectory(family: .aura, tag: "v0.5.0") {
                try? FileManager.default.removeItem(at: dir.deletingLastPathComponent())
            }
        }
        do {
            _ = try await FirmwareReleaseDownloader.prepareLatest(
                family: .aura, session: mockSession(), token: "ghp_test")
            XCTFail("un Release incompleto no puede darse por instalable")
        } catch let error as InstallerError {
            guard case .releaseMissingAsset(let tag, let asset) = error else {
                return XCTFail("error inesperado: \(error)")
            }
            XCTAssertEqual(tag, "v0.5.0")
            XCTAssertEqual(asset, "mks5lboot")
        } catch {
            XCTFail("error inesperado: \(error)")
        }
    }

    func testPrepareLatestExplainsTokenRejection() async {
        // ST-074: con token, un 404 es "el token no tiene acceso" y
        // `fetchReleases` devuelve [] sin lanzar. El motivo tiene que
        // llegar al usuario nombrando el token, no un genérico.
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404,
                                           httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        do {
            _ = try await FirmwareReleaseDownloader.prepareLatest(
                family: .aura, session: mockSession(), token: "ghp_test")
            XCTFail("sin Releases no hay nada que preparar")
        } catch let error as InstallerError {
            guard case .releaseDownloadFailed(_, let reason) = error else {
                return XCTFail("error inesperado: \(error)")
            }
            XCTAssertTrue(reason.contains("token"), reason)
        } catch {
            XCTFail("error inesperado: \(error)")
        }
    }

    // MARK: - BundledArtifacts sobre un directorio

    func testBundledArtifactsReadsFromDirectoryAndItsVersionFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("st077-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data("firmware".utf8).write(to: dir.appendingPathComponent("rockbox.ipod"))
        try "v9.9.9\n".write(to: dir.appendingPathComponent("firmware-version.txt"),
                             atomically: true, encoding: .utf8)

        let artifacts = BundledArtifacts(directory: dir, family: .aura)
        XCTAssertEqual(artifacts.url(for: .firmware)?.lastPathComponent, "rockbox.ipod")
        XCTAssertNil(artifacts.url(for: .mks5lboot), "lo que no está en el directorio es nil, no del bundle")
        XCTAssertEqual(artifacts.releaseTag, "v9.9.9")
    }

    func testIsCompleteRequiresAllFiveAssets() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("st077-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        for name in FirmwareReleaseDownloader.requiredAssets.dropLast() {
            try Data("x".utf8).write(to: dir.appendingPathComponent(name.rawValue))
        }
        XCTAssertFalse(FirmwareReleaseDownloader.isComplete(directory: dir),
                       "faltando uno, el directorio no puede darse por descargado")

        let last = FirmwareReleaseDownloader.requiredAssets.last!
        try Data("x".utf8).write(to: dir.appendingPathComponent(last.rawValue))
        XCTAssertTrue(FirmwareReleaseDownloader.isComplete(directory: dir))
    }
}
