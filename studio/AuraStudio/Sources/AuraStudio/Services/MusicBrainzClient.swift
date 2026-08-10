import Foundation

/// Cliente de la API publica de MusicBrainz (musicbrainz.org/doc/MusicBrainz_API),
/// sin API key -- solo requiere un User-Agent descriptivo por su
/// politica de uso, que es lo unico "especial" que hace falta configurar
/// aca. Se usa para resolver titulo/artista/album/año/genero a partir de
/// lo poco que ya tenga el archivo (tags existentes o el nombre del
/// archivo), buscando la grabacion mas parecida.
struct MusicBrainzClient {
    struct Recording: Decodable, Equatable {
        let id: String
        let title: String
        let score: Int?
        let artistCredit: [ArtistCredit]?
        let releases: [Release]?

        enum CodingKeys: String, CodingKey {
            case id, title, score
            case artistCredit = "artist-credit"
            case releases
        }
    }

    struct ArtistCredit: Decodable, Equatable {
        let name: String
    }

    struct Release: Decodable, Equatable {
        let id: String
        let title: String
        let date: String?
    }

    private struct SearchResponse: Decodable {
        let recordings: [Recording]
    }

    static let userAgent = "AuraStudio/0.1.0 (https://github.com/Ricolinos/Aura-Proyect)"
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = URL(string: "https://musicbrainz.org/ws/2")!) {
        self.session = session
        self.baseURL = baseURL
    }

    /// Busca la grabacion mas parecida a `title`/`artist` (si se conoce
    /// alguno; ambos son opcionales porque puede ser lo unico que se
    /// pudo sacar del nombre del archivo). Devuelve el resultado con
    /// mayor `score`, o nil si no hubo ningun match razonable.
    func searchRecording(title: String?, artist: String?) async throws -> Recording? {
        guard title != nil || artist != nil else { return nil }

        var query = ""
        if let title { query += "recording:\"\(title)\"" }
        if let artist {
            if !query.isEmpty { query += " AND " }
            query += "artist:\"\(artist)\""
        }

        var components = URLComponents(url: baseURL.appendingPathComponent("recording"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "5"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        try Self.validate(response)

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded.recordings.max { ($0.score ?? 0) < ($1.score ?? 0) }
    }

    static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw EnrichmentError.httpError(statusCode: http.statusCode)
        }
    }
}

enum EnrichmentError: Error, LocalizedError {
    case httpError(statusCode: Int)
    case noMatch

    var errorDescription: String? {
        switch self {
        case .httpError(let code):
            return "Error de red (HTTP \(code))"
        case .noMatch:
            return "No se encontro ningun resultado"
        }
    }
}
