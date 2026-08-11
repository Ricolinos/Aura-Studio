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
    private let rateLimiter: MusicBrainzRateLimiter

    init(session: URLSession = .shared,
         baseURL: URL = URL(string: "https://musicbrainz.org/ws/2")!,
         rateLimiter: MusicBrainzRateLimiter = .shared) {
        self.session = session
        self.baseURL = baseURL
        self.rateLimiter = rateLimiter
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

        let data = try await performThrottled(request)
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded.recordings.max { ($0.score ?? 0) < ($1.score ?? 0) }
    }

    /// MusicBrainz aplica 1 request/segundo por IP y, ademas, devuelve
    /// 503 transitorios incluso cuando estas dentro del limite (su propia
    /// documentacion lo describe como esperable, y se reprodujo al
    /// verificar la API). Sin esto, una biblioteca grande se enriquece a
    /// toda velocidad, se come throttling y pierde metadata en silencio:
    /// `enrich()` traga el error con `try?` y devuelve la cancion sin
    /// completar, que parece "no se encontro" y no "me frenaron".
    private func performThrottled(_ request: URLRequest,
                                   maxAttempts: Int = 3) async throws -> Data {
        var lastStatus = 0

        for attempt in 1...maxAttempts {
            await rateLimiter.waitForTurn()

            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200

            if (200..<300).contains(status) {
                return data
            }
            lastStatus = status

            // Solo se reintenta lo transitorio: un 404 o un 400 no
            // mejoran esperando.
            guard status == 503 || status == 429, attempt < maxAttempts else { break }
            try? await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
        }

        throw EnrichmentError.httpError(statusCode: lastStatus)
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
