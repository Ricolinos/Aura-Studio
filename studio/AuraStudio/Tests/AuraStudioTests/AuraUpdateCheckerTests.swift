import XCTest
@testable import AuraStudio

final class AuraUpdateCheckerVersionMarkerTests: XCTestCase {
    private var fakeIPod: URL!

    override func setUpWithError() throws {
        fakeIPod = FileManager.default.temporaryDirectory.appendingPathComponent("FakeIPod-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeIPod, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fakeIPod)
    }

    private func writeVersionMarker(_ text: String) throws {
        let dir = fakeIPod.appendingPathComponent(".rockbox/aura")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try text.write(to: dir.appendingPathComponent("version.txt"), atomically: true, encoding: .utf8)
    }

    func testReadsAndTrimsTag() throws {
        try writeVersionMarker("v0.1.0-beta\n")
        XCTAssertEqual(AuraUpdateChecker.installedVersionTag(deviceMountPath: fakeIPod.path), "v0.1.0-beta")
    }

    func testNilWhenFileAbsent() {
        XCTAssertNil(AuraUpdateChecker.installedVersionTag(deviceMountPath: fakeIPod.path))
    }

    func testNilWhenFileEmpty() throws {
        try writeVersionMarker("   \n")
        XCTAssertNil(AuraUpdateChecker.installedVersionTag(deviceMountPath: fakeIPod.path))
    }

    func testNilForRelativeMountPath() {
        XCTAssertNil(AuraUpdateChecker.installedVersionTag(deviceMountPath: "relative/path"))
    }

    func testNilForEmptyMountPath() {
        XCTAssertNil(AuraUpdateChecker.installedVersionTag(deviceMountPath: ""))
    }
}

final class ReleaseCacheTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "ReleaseCacheTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testStoreThenLoadRoundTrips() {
        let releases = [GitHubRelease(tagName: "v0.1.0-beta", draft: false, prerelease: true)]
        ReleaseCache.store(releases, defaults: defaults)
        XCTAssertEqual(ReleaseCache.load(defaults: defaults), releases)
    }

    func testLoadNilWhenNeverStored() {
        XCTAssertNil(ReleaseCache.load(defaults: defaults))
    }

    func testLoadNilWhenExpired() {
        let releases = [GitHubRelease(tagName: "v0.1.0-beta", draft: false, prerelease: true)]
        ReleaseCache.store(releases, defaults: defaults)
        // Simula que el cache vencio -- se guarda un timestamp mas
        // viejo que el TTL, sin esperar 24h de verdad.
        defaults.set(Date().addingTimeInterval(-ReleaseCache.ttl - 1), forKey: ReleaseCache.timestampKey)
        XCTAssertNil(ReleaseCache.load(defaults: defaults))
    }
}

final class AuraUpdateCheckerCheckForUpdateTests: XCTestCase {
    private var fakeIPod: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        fakeIPod = FileManager.default.temporaryDirectory.appendingPathComponent("FakeIPod-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeIPod, withIntermediateDirectories: true)
        suiteName = "AuraUpdateCheckerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fakeIPod)
        defaults.removePersistentDomain(forName: suiteName)
        MockURLProtocol.handler = nil
    }

    private func writeVersionMarker(_ text: String) throws {
        let dir = fakeIPod.appendingPathComponent(".rockbox/aura")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try text.write(to: dir.appendingPathComponent("version.txt"), atomically: true, encoding: .utf8)
    }

    private func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func stubReleases(_ releases: [GitHubRelease]) throws {
        let data = try JSONEncoder().encode(releases)
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }
    }

    func testUpdateAvailableWhenInstalledIsOlderThanLatest() async throws {
        try writeVersionMarker("v0.1.0-beta")
        try stubReleases([GitHubRelease(tagName: "v0.2.0", draft: false, prerelease: false)])

        let result = await AuraUpdateChecker.checkForUpdate(deviceMountPath: fakeIPod.path,
                                                              session: mockSession(),
                                                              defaults: defaults)
        XCTAssertTrue(result)
    }

    func testNoUpdateWhenInstalledMatchesLatest() async throws {
        try writeVersionMarker("v0.1.0-beta")
        try stubReleases([GitHubRelease(tagName: "v0.1.0-beta", draft: false, prerelease: true)])

        let result = await AuraUpdateChecker.checkForUpdate(deviceMountPath: fakeIPod.path,
                                                              session: mockSession(),
                                                              defaults: defaults)
        XCTAssertFalse(result)
    }

    func testUsesCacheInsteadOfRefetching() async throws {
        try writeVersionMarker("v0.1.0-beta")
        ReleaseCache.store([GitHubRelease(tagName: "v0.5.0", draft: false, prerelease: false)], defaults: defaults)
        MockURLProtocol.handler = { _ in XCTFail("no debería consultar la red con cache vigente"); throw URLError(.badServerResponse) }

        let result = await AuraUpdateChecker.checkForUpdate(deviceMountPath: fakeIPod.path,
                                                              session: mockSession(),
                                                              defaults: defaults)
        XCTAssertTrue(result)
    }

    // D-300 en Aura-Firmware / cross-repo: reportado en vivo -- se
    // publico un Release nuevo y ni siquiera el boton manual "Buscar
    // actualizaciones de Aura" lo detectaba, porque ninguna ruta
    // saltaba la cache de 24h. `forceRefresh: true` (usado por los
    // chequeos manuales, ver ContentView.swift) tiene que ignorar una
    // cache vigente pero YA DESACTUALIZADA y consultar la red de
    // verdad.
    func testForceRefreshBypassesStaleCacheAndFetchesLive() async throws {
        try writeVersionMarker("v0.1.0-beta")
        // La cache "vigente" (TTL sin vencer) dice que ya esta al dia
        // -- desactualizada, un Release mas nuevo se publico despues de
        // que se guardo este cache.
        ReleaseCache.store([GitHubRelease(tagName: "v0.1.0-beta", draft: false, prerelease: true)], defaults: defaults)
        try stubReleases([GitHubRelease(tagName: "v0.2.0-beta", draft: false, prerelease: true)])

        let cachedResult = await AuraUpdateChecker.checkForUpdate(deviceMountPath: fakeIPod.path,
                                                                    session: mockSession(),
                                                                    defaults: defaults)
        XCTAssertFalse(cachedResult, "sin forceRefresh, la cache vigente (aunque desactualizada) manda")

        let forcedResult = await AuraUpdateChecker.checkForUpdate(deviceMountPath: fakeIPod.path,
                                                                    session: mockSession(),
                                                                    defaults: defaults,
                                                                    forceRefresh: true)
        XCTAssertTrue(forcedResult, "forceRefresh ignora la cache y consulta la red -- SI hay un Release mas nuevo")
    }

    func testFallsBackToHashCheckWhenNoVersionMarker() async {
        // Sin version.txt no hay nada que comparar contra GitHub -- cae
        // a isUpdateAvailable(deviceMountPath:), que en este entorno de
        // test no resuelve BundledArtifacts.shared (Bundle.main es el
        // bundle de XCTest, sin rockbox.ipod embebido) y por lo tanto
        // devuelve false de forma determinista. Se compara contra la
        // llamada directa en vez de fijar `false` a mano, para no
        // depender de ese detalle del entorno de test.
        let expected = await AuraUpdateChecker.isUpdateAvailable(deviceMountPath: fakeIPod.path)
        let result = await AuraUpdateChecker.checkForUpdate(deviceMountPath: fakeIPod.path,
                                                              session: mockSession(),
                                                              defaults: defaults)
        XCTAssertEqual(result, expected)
    }

    func testFallsBackToHashCheckWhenVersionMarkerIsMalformed() async throws {
        try writeVersionMarker("no-es-un-tag")
        let expected = await AuraUpdateChecker.isUpdateAvailable(deviceMountPath: fakeIPod.path)
        let result = await AuraUpdateChecker.checkForUpdate(deviceMountPath: fakeIPod.path,
                                                              session: mockSession(),
                                                              defaults: defaults)
        XCTAssertEqual(result, expected)
    }

    func testFallsBackToHashCheckWhenOffline() async throws {
        try writeVersionMarker("v0.1.0-beta")
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }

        let expected = await AuraUpdateChecker.isUpdateAvailable(deviceMountPath: fakeIPod.path)
        let result = await AuraUpdateChecker.checkForUpdate(deviceMountPath: fakeIPod.path,
                                                              session: mockSession(),
                                                              defaults: defaults)
        XCTAssertEqual(result, expected)
    }

    func testFalseForEmptyMountPath() async {
        let result = await AuraUpdateChecker.checkForUpdate(deviceMountPath: "",
                                                              session: mockSession(),
                                                              defaults: defaults)
        XCTAssertFalse(result)
    }
}
