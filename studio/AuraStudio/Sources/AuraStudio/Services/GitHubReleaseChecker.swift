import Foundation

/// Version SemVer simple (`vMAJOR.MINOR.PATCH[-prerelease]`), lo unico
/// que hace falta para comparar el tag de un Release de GitHub contra
/// lo instalado (PLAN-release-updates.md S1.5). No hay nada asi en
/// Foundation.
///
/// La comparacion de dos sufijos de prerelease distintos (`beta` vs
/// `rc1`) usa orden lexicografico simple, no la regla completa de
/// precedencia de SemVer (punto 11, identificadores separados por
/// puntos comparados uno a uno). Alcance reducido a proposito: el
/// unico mantenedor de este repositorio nunca usa mas de un sufijo de
/// prerelease por release real, asi que la regla completa seria
/// trabajo sin caso de uso.
struct SemVer: Equatable, Comparable {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: String?

    static func parse(_ raw: String) -> SemVer? {
        var s = Substring(raw)
        if s.first == "v" { s.removeFirst() }
        let parts = s.split(separator: "-", maxSplits: 1)
        guard let core = parts.first else { return nil }
        let prerelease = parts.count > 1 ? String(parts[1]) : nil

        let nums = core.split(separator: ".", omittingEmptySubsequences: false)
        guard nums.count == 3,
              let major = Int(nums[0]), let minor = Int(nums[1]), let patch = Int(nums[2]),
              major >= 0, minor >= 0, patch >= 0 else {
            return nil
        }
        return SemVer(major: major, minor: minor, patch: patch, prerelease: prerelease)
    }

    static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (nil, .some): return false  // estable > cualquier prerelease
        case (.some, nil): return true   // prerelease < estable
        case let (.some(l), .some(r)): return l < r
        }
    }
}

/// Un Release de la API publica de GitHub -- solo los campos que hacen
/// falta para decidir cual es el mas nuevo utilizable.
struct GitHubRelease: Codable, Equatable {
    let tagName: String
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case draft, prerelease
    }
}

enum GitHubReleaseCheckerError: Error, Equatable {
    case badResponse
}

/// Consume `GET /repos/Ricolinos/Aura-Firmware/releases` -- publica,
/// sin token (el repo es publico). Se usa `/releases` (lista) y no
/// `/releases/latest` a proposito: `/latest` excluye prereleases y
/// drafts por definicion de GitHub, y mientras el firmware siga en
/// beta esa llamada nunca devolveria nada util. Aca es Studio quien
/// decide, con `pickLatest`, si una prerelease cuenta como "la mas
/// nueva".
enum GitHubReleaseChecker {
    static let apiURL = URL(string: "https://api.github.com/repos/Ricolinos/Aura-Firmware/releases")!

    static func fetchReleases(session: URLSession = .shared) async throws -> [GitHubRelease] {
        var request = URLRequest(url: apiURL)
        request.setValue("AuraStudio", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GitHubReleaseCheckerError.badResponse
        }
        return try JSONDecoder().decode([GitHubRelease].self, from: data)
    }

    /// Ignora drafts siempre (nunca son instalables). `includePrereleases`
    /// decide si una beta cuenta como candidata -- ver PLAN-release-updates.md
    /// S1.5, Q6: mientras el unico canal publicado sea beta, Studio la
    /// ofrece por defecto (sin ajuste todavia).
    static func pickLatest(from releases: [GitHubRelease], includePrereleases: Bool) -> GitHubRelease? {
        releases
            .filter { !$0.draft }
            .filter { includePrereleases || !$0.prerelease }
            .compactMap { release in SemVer.parse(release.tagName).map { (release, $0) } }
            .max { $0.1 < $1.1 }
            .map(\.0)
    }
}
