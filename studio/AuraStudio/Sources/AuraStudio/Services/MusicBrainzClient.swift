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
        /// R2-3: lo que puntúa una edición (ver
        /// `docs/caratula-recomendada.md`). Los tres son opcionales
        /// porque la búsqueda de GRABACIONES trae las ediciones
        /// anidadas y sin estos campos; solo la búsqueda de ediciones
        /// (`searchReleases`) los devuelve completos.
        let status: String?
        let country: String?
        let trackCount: Int?
        /// D-203: el "album" para fanart.tv (y para casi cualquier otra
        /// fuente que indexe por album, no por edicion especifica) es el
        /// RELEASE GROUP, no el release -- confirmado contra la API real
        /// que la busqueda de `recording` ya lo trae anidado sin pedir
        /// ningun `inc=` extra.
        let releaseGroup: ReleaseGroup?

        enum CodingKeys: String, CodingKey {
            case id, title, date, status, country
            case trackCount = "track-count"
            case releaseGroup = "release-group"
        }
    }

    struct ReleaseGroup: Decodable, Equatable {
        let id: String
    }

    private struct SearchResponse: Decodable {
        let recordings: [Recording]
    }

    private struct ReleaseSearchResponse: Decodable {
        let releases: [Release]
    }

    /// ST-032: artista de MusicBrainz -- su `id` (MBID) es la llave que
    /// fanart.tv usa para las fotos de artista.
    struct Artist: Decodable, Equatable {
        let id: String
        let name: String
        let score: Int?
    }

    private struct ArtistSearchResponse: Decodable {
        let artists: [Artist]
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

        let query = Self.buildQuery(title: title, artist: artist)

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

    /// ST-104: busca EDICIONES (releases) de un album por titulo y
    /// artista, en orden de puntaje. Distinto de `searchRecording`, que
    /// busca una cancion: aca interesa el album entero, y sobre todo
    /// que vengan VARIAS ediciones -- cada una suele tener su propia
    /// tapa en Cover Art Archive, y eso es justamente lo que le da al
    /// usuario opciones para elegir en vez de una sola imagen impuesta.
    func searchReleases(album: String, artist: String?, limit: Int = 5) async throws -> [Release] {
        let trimmedAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAlbum.isEmpty else { return [] }

        var query = "release:\"\(Self.escapeLuceneQuoted(trimmedAlbum))\""
        if let artist, !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            query += " AND artist:\"\(Self.escapeLuceneQuoted(artist))\""
        }

        var components = URLComponents(url: baseURL.appendingPathComponent("release"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "\(max(1, limit))"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let data = try await performThrottled(request)
        return try JSONDecoder().decode(ReleaseSearchResponse.self, from: data).releases
    }

    /// ST-032: busca el artista por nombre. Devuelve el de mayor `score`
    /// si supera `minimumScore` (MusicBrainz puntua 100 la coincidencia
    /// exacta; por debajo de ~85 suelen ser homonimos parciales -- mejor
    /// sin foto que con la de otro).
    func searchArtist(name: String, minimumScore: Int = 85) async throws -> Artist? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents(url: baseURL.appendingPathComponent("artist"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "query", value: "artist:\"\(Self.escapeLuceneQuoted(trimmed))\""),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "5"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let data = try await performThrottled(request)
        let decoded = try JSONDecoder().decode(ArtistSearchResponse.self, from: data)
        guard let best = decoded.artists.max(by: { ($0.score ?? 0) < ($1.score ?? 0) }),
              (best.score ?? 0) >= minimumScore else { return nil }
        return best
    }

    /// D-203: arma la query de busqueda Lucene. `title`/`artist` van
    /// entre comillas para buscar la frase exacta -- si traen una
    /// comilla o una barra invertida sin escapar (titulos reales como
    /// `Rock "N" Roll` o `Y\N`), rompen la sintaxis y MusicBrainz
    /// devuelve 400, que `enrich()`/`reenrich()` tragan con `try?` y se
    /// ve identico a "no se encontro nada" -- causa real detras del
    /// reporte de que la busqueda "no sirve para nada" con canciones
    /// comunes. No hace falta escapar el resto de los caracteres
    /// especiales de Lucene (`+ - && || ! ( ) [ ] ^ ~ * ? :`): dentro de
    /// una frase entre comillas se toman literales, solo la comilla y la
    /// barra invertida rompen la frase en si.
    static func buildQuery(title: String?, artist: String?) -> String {
        var query = ""
        if let title { query += "recording:\"\(escapeLuceneQuoted(title))\"" }
        if let artist {
            if !query.isEmpty { query += " AND " }
            query += "artist:\"\(escapeLuceneQuoted(artist))\""
        }
        return query
    }

    private static func escapeLuceneQuoted(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
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
