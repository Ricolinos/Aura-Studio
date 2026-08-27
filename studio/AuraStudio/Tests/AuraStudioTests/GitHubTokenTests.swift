import XCTest
@testable import AuraStudio

/// ST-074. El Llavero real NO se toca aquí (en CI puede pedir permiso):
/// se prueba el formato y las cabeceras inyectando `token:` a
/// `fetchReleases` explícitamente.
final class GitHubTokenFormatTests: XCTestCase {
    func testAcceptsFineGrainedAndClassicTokens() {
        XCTAssertTrue(GitHubToken.validateFormat("github_pat_11ABCDEFG0123456789_abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"))
        XCTAssertTrue(GitHubToken.validateFormat("ghp_abcdefghijklmnopqrstuvwxyz0123456789ABCD"))
        XCTAssertTrue(GitHubToken.validateFormat("  ghp_abcdefghijklmnopqrstuvwxyz0123456789ABCD\n"),
                      "los espacios de los bordes se recortan al pegar")
    }

    func testRejectsEmptyWrongPrefixOrInnerWhitespace() {
        XCTAssertFalse(GitHubToken.validateFormat(""))
        XCTAssertFalse(GitHubToken.validateFormat("   "))
        XCTAssertFalse(GitHubToken.validateFormat("https://github.com/settings/tokens"))
        XCTAssertFalse(GitHubToken.validateFormat("gho_abcdefghijklmnopqrstuvwxyz0123456789ABCD"))
        XCTAssertFalse(GitHubToken.validateFormat("ghp_abcdefghij klmnopqrstuvwxyz0123456789"))
        XCTAssertFalse(GitHubToken.validateFormat("ghp_short"))
    }
}

final class GitHubReleaseCheckerAuthTests: XCTestCase {
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

    private let okJSON = #"[{"tag_name": "v0.4.2-beta", "draft": false, "prerelease": true}]"#.data(using: .utf8)!

    func testWithoutTokenRequestCarriesNoAuthorization() async throws {
        nonisolated(unsafe) var seen: URLRequest?
        MockURLProtocol.handler = { request in
            seen = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, self.okJSON)
        }
        let releases = try await GitHubReleaseChecker.fetchReleases(session: mockSession(), family: .aura, token: nil)
        XCTAssertEqual(releases.count, 1)
        XCTAssertNil(seen?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(seen?.value(forHTTPHeaderField: "X-GitHub-Api-Version"))
        XCTAssertEqual(seen?.value(forHTTPHeaderField: "User-Agent"), "AuraStudio")
        XCTAssertFalse(GitHubReleaseChecker.lastAuthFailure)
    }

    func testWithTokenRequestCarriesBearerAndGitHubHeaders() async throws {
        nonisolated(unsafe) var seen: URLRequest?
        MockURLProtocol.handler = { request in
            seen = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, self.okJSON)
        }
        let releases = try await GitHubReleaseChecker.fetchReleases(session: mockSession(), family: .metro,
                                                                    token: "ghp_test0123456789abcdefghijklmnopqrstuv")
        XCTAssertEqual(releases.first?.tagName, "v0.4.2-beta")
        XCTAssertEqual(seen?.url?.absoluteString, "https://api.github.com/repos/Ricolinos/Metro-Aura/releases")
        XCTAssertEqual(seen?.value(forHTTPHeaderField: "Authorization"), "Bearer ghp_test0123456789abcdefghijklmnopqrstuv")
        XCTAssertEqual(seen?.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(seen?.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")
        XCTAssertFalse(GitHubReleaseChecker.lastAuthFailure)
    }

    func testUnauthorizedWithTokenSetsAuthFailureAndReturnsEmptyWithoutThrowing() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, #"{"message":"Bad credentials"}"#.data(using: .utf8)!)
        }
        let releases = try await GitHubReleaseChecker.fetchReleases(session: mockSession(), family: .aura,
                                                                    token: "ghp_expired0123456789abcdefghijklmnopq")
        XCTAssertEqual(releases, [])
        XCTAssertTrue(GitHubReleaseChecker.lastAuthFailure)
    }

    func testAuthFailureClearsAfterSuccessfulAuthenticatedFetch() async throws {
        GitHubReleaseChecker.lastAuthFailure = true
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, self.okJSON)
        }
        _ = try await GitHubReleaseChecker.fetchReleases(session: mockSession(), family: .aura,
                                                         token: "ghp_fresh0123456789abcdefghijklmnopqrstu")
        XCTAssertFalse(GitHubReleaseChecker.lastAuthFailure)
    }

    func testNotFoundWithoutTokenStillThrowsAndDoesNotBlameToken() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        do {
            _ = try await GitHubReleaseChecker.fetchReleases(session: mockSession(), family: .aura, token: nil)
            XCTFail("sin token, un 404 debe seguir lanzando badResponse")
        } catch GitHubReleaseCheckerError.badResponse {
            XCTAssertFalse(GitHubReleaseChecker.lastAuthFailure)
        } catch {
            XCTFail("error inesperado: \(error)")
        }
    }
}
