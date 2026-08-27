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
    /// El firmware instalado se declara de una familia que esta version de
    /// Studio no conoce (ST-046): no hay repositorio al que consultar.
    case unknownFamily
}

/// Consume `GET /repos/<owner>/<repo>/releases`. ST-074: los repos
/// del firmware son privados desde 2026-08; si el usuario guardó un
/// token de solo lectura en el Llavero (`GitHubToken`), la petición
/// va autenticada; sin token se sigue preguntando como repo público
/// (GitHub contesta 404 y el aviso de versiones simplemente calla).
/// Se usa `/releases` (lista) y no
/// `/releases/latest` a proposito: `/latest` excluye prereleases y
/// drafts por definicion de GitHub, y mientras el firmware siga en
/// beta esa llamada nunca devolveria nada util. Aca es Studio quien
/// decide, con `pickLatest`, si una prerelease cuenta como "la mas
/// nueva".
enum GitHubReleaseChecker {
    static let apiURL = URL(string: "https://api.github.com/repos/Ricolinos/Aura-Firmware/releases")!

    /// ST-046: el repositorio ya no es uno solo. Metro-Aura es un firmware
    /// hermano que publica sus propios Releases con los mismos assets
    /// (`rockbox.ipod`, `rockbox.zip`, `bootloader-ipod6g.ipod`,
    /// `mks5lboot`), asi que la maquinaria sirve igual -- lo unico que
    /// cambia es a que repo se le pregunta. `nil` para una familia
    /// desconocida: sin repo no hay a donde preguntar, y preguntarle al de
    /// Aura seria justo el error que ST-046 arregla.
    static func apiURL(for family: FirmwareFamily) -> URL? {
        guard let repo = family.releaseRepository else { return nil }
        return URL(string: "https://api.github.com/repos/\(repo)/releases")
    }

    /// ST-074: `true` si la última consulta CON token fue rechazada por
    /// GitHub (401/403: token inválido, expirado o revocado; 404: el
    /// token existe pero no tiene acceso a ese repo -- GitHub esconde
    /// los repos privados a los tokens sin permiso con un 404, no con
    /// un 403). Ajustes lo lee para decir "El token no es válido o
    /// expiró". Se vuelve `false` en cuanto una consulta con token
    /// responde 200. Sin token nunca se toca: un 404 público no dice
    /// nada del token.
    ///
    /// Estado global de proceso (no hay instancia): se escribe y lee
    /// desde el hilo que hizo la consulta; `nonisolated(unsafe)` como en
    /// `MockURLProtocol.handler` para el modo estricto de Swift 6.
    nonisolated(unsafe) static var lastAuthFailure = false

    static let authFailureStatusCodes: Set<Int> = [401, 403, 404]

    /// `token`: por defecto, el del Llavero. Las pruebas lo inyectan
    /// explícitamente (`nil` o un valor fijo) para no tocar el Llavero
    /// real, que en CI puede pedir permiso.
    ///
    /// Con token, un rechazo de autenticación NO lanza: devuelve `[]`
    /// ("sin información") y deja `lastAuthFailure = true`. El chequeo
    /// automático así calla en vez de fallar, y Ajustes puede explicar
    /// por qué. Sin token, un status distinto de 200 sigue lanzando
    /// `badResponse` como siempre.
    static func fetchReleases(session: URLSession = .shared,
                               family: FirmwareFamily = .aura,
                               token: String? = GitHubToken.load()) async throws -> [GitHubRelease] {
        guard let url = apiURL(for: family) else { throw GitHubReleaseCheckerError.unknownFamily }
        var request = URLRequest(url: url)
        request.setValue("AuraStudio", forHTTPHeaderField: "User-Agent")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubReleaseCheckerError.badResponse
        }
        if token != nil, authFailureStatusCodes.contains(http.statusCode) {
            lastAuthFailure = true
            return []
        }
        guard http.statusCode == 200 else {
            throw GitHubReleaseCheckerError.badResponse
        }
        if token != nil { lastAuthFailure = false }
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
