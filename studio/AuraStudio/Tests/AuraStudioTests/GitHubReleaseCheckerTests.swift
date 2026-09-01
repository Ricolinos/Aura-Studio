import XCTest
@testable import AuraStudio

final class SemVerTests: XCTestCase {
    func testParsesTagWithVPrefixAndPrerelease() {
        let v = SemVer.parse("v0.1.0-beta")
        XCTAssertEqual(v, SemVer(major: 0, minor: 1, patch: 0, prerelease: "beta"))
    }

    func testParsesStableTagWithoutPrerelease() {
        let v = SemVer.parse("v1.2.3")
        XCTAssertEqual(v, SemVer(major: 1, minor: 2, patch: 3, prerelease: nil))
    }

    func testParsesWithoutVPrefix() {
        XCTAssertEqual(SemVer.parse("2.0.0"), SemVer(major: 2, minor: 0, patch: 0, prerelease: nil))
    }

    func testRejectsMissingComponent() {
        XCTAssertNil(SemVer.parse("v1.2"))
    }

    func testRejectsNonNumericComponent() {
        XCTAssertNil(SemVer.parse("v1.x.0"))
    }

    func testRejectsMalformedTag() {
        XCTAssertNil(SemVer.parse("release-final"))
    }

    func testMajorMinorPatchOrdering() {
        XCTAssertLessThan(SemVer.parse("v0.1.0")!, SemVer.parse("v0.2.0")!)
        XCTAssertLessThan(SemVer.parse("v0.9.0")!, SemVer.parse("v1.0.0")!)
        XCTAssertLessThan(SemVer.parse("v1.0.0")!, SemVer.parse("v1.0.1")!)
    }

    func testStableIsNewerThanItsOwnPrerelease() {
        XCTAssertLessThan(SemVer.parse("v0.1.0-beta")!, SemVer.parse("v0.1.0")!)
    }

    func testEqualVersionsAreNotLessThanEachOther() {
        let a = SemVer.parse("v0.1.0-beta")!
        let b = SemVer.parse("v0.1.0-beta")!
        XCTAssertFalse(a < b)
        XCTAssertFalse(b < a)
        XCTAssertEqual(a, b)
    }
}

final class GitHubReleaseCheckerPickLatestTests: XCTestCase {
    func testIgnoresDraftsAlways() {
        let releases = [
            GitHubRelease(tagName: "v0.2.0", draft: true, prerelease: false),
            GitHubRelease(tagName: "v0.1.0", draft: false, prerelease: false),
        ]
        let latest = GitHubReleaseChecker.pickLatest(from: releases, includePrereleases: true)
        XCTAssertEqual(latest?.tagName, "v0.1.0")
    }

    func testExcludesPrereleasesWhenNotIncluded() {
        let releases = [
            GitHubRelease(tagName: "v0.2.0-beta", draft: false, prerelease: true),
            GitHubRelease(tagName: "v0.1.0", draft: false, prerelease: false),
        ]
        let latest = GitHubReleaseChecker.pickLatest(from: releases, includePrereleases: false)
        XCTAssertEqual(latest?.tagName, "v0.1.0")
    }

    func testIncludesPrereleasesWhenRequested() {
        let releases = [
            GitHubRelease(tagName: "v0.2.0-beta", draft: false, prerelease: true),
            GitHubRelease(tagName: "v0.1.0", draft: false, prerelease: false),
        ]
        let latest = GitHubReleaseChecker.pickLatest(from: releases, includePrereleases: true)
        XCTAssertEqual(latest?.tagName, "v0.2.0-beta")
    }

    func testSkipsUnparseableTagsInsteadOfCrashing() {
        let releases = [
            GitHubRelease(tagName: "not-a-version", draft: false, prerelease: false),
            GitHubRelease(tagName: "v0.1.0", draft: false, prerelease: false),
        ]
        let latest = GitHubReleaseChecker.pickLatest(from: releases, includePrereleases: true)
        XCTAssertEqual(latest?.tagName, "v0.1.0")
    }

    func testEmptyListReturnsNil() {
        XCTAssertNil(GitHubReleaseChecker.pickLatest(from: [], includePrereleases: true))
    }
}

/// ST-077: `token:` se inyecta SIEMPRE, nunca se deja el valor por
/// defecto. `fetchReleases(session:)` lo resuelve con
/// `GitHubToken.load()`, o sea el Llavero REAL: en una Mac con token
/// guardado macOS puede pedir permiso y la prueba se queda esperando un
/// diálogo para siempre -- colgaba `swift test` entero, medido en esta
/// pasada (47 min a 0 % de CPU). Además, con un token presente un 404 ya
/// no lanza `badResponse` sino que devuelve `[]` (ST-074), así que
/// `testThrowsOnNonOKStatus` habría fallado por el motivo equivocado.
/// Misma disciplina que `GitHubTokenTests` documenta desde ST-074.
final class GitHubReleaseCheckerFetchTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    func testDecodesReleaseListFromJSON() async throws {
        let json = """
        [
          {"tag_name": "v0.1.0-beta", "draft": true, "prerelease": true},
          {"tag_name": "v0.0.9", "draft": false, "prerelease": false}
        ]
        """.data(using: .utf8)!
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }
        let releases = try await GitHubReleaseChecker.fetchReleases(session: mockSession(), token: nil)
        XCTAssertEqual(releases, [
            GitHubRelease(tagName: "v0.1.0-beta", draft: true, prerelease: true),
            GitHubRelease(tagName: "v0.0.9", draft: false, prerelease: false),
        ])
    }

    func testThrowsOnNonOKStatus() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        do {
            _ = try await GitHubReleaseChecker.fetchReleases(session: mockSession(), token: nil)
            XCTFail("debería fallar con status 404")
        } catch GitHubReleaseCheckerError.badResponse {
            // esperado
        } catch {
            XCTFail("error inesperado: \(error)")
        }
    }
}
