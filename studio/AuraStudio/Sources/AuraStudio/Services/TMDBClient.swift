import Foundation

/// Cliente de The Movie Database (ST-022) -- API v3, key propia
/// (gratuita, `APIKeyService.tmdb`, en el Keychain). Cumple dos papeles
/// para los pósters de video:
/// 1. **Resolvedor de identificadores**: fanart.tv no busca por título;
///    indexa películas por ID de TMDB/IMDb y series por ID de TheTVDB.
///    TMDB resuelve título → ID de película, y título → ID de serie →
///    `external_ids.tvdb_id`.
/// 2. **Póster de respaldo**: TMDB trae su propio `poster_path`
///    (`image.tmdb.org`), que se usa cuando fanart.tv no tiene el
///    título (o no hay key de fanart.tv).
/// Sin key no toca la red (nil), como los demás clientes opcionales.
struct TMDBClient {
    struct Movie: Decodable, Equatable {
        let id: Int
        let title: String
        let releaseDate: String?
        let posterPath: String?

        enum CodingKeys: String, CodingKey {
            case id, title
            case releaseDate = "release_date"
            case posterPath = "poster_path"
        }

        var year: String? { releaseDate.map { String($0.prefix(4)) }.flatMap { $0.isEmpty ? nil : $0 } }
    }

    struct TVShow: Decodable, Equatable {
        let id: Int
        let name: String
        let firstAirDate: String?
        let posterPath: String?

        enum CodingKeys: String, CodingKey {
            case id, name
            case firstAirDate = "first_air_date"
            case posterPath = "poster_path"
        }

        var year: String? { firstAirDate.map { String($0.prefix(4)) }.flatMap { $0.isEmpty ? nil : $0 } }
    }

    private struct SearchResponse<T: Decodable>: Decodable {
        let results: [T]
    }

    private struct ExternalIDs: Decodable {
        let tvdbID: Int?
        let imdbID: String?

        enum CodingKeys: String, CodingKey {
            case tvdbID = "tvdb_id"
            case imdbID = "imdb_id"
        }
    }

    private let session: URLSession
    private let baseURL: URL
    private let imageBaseURL: URL
    private let apiKeyProvider: @Sendable () -> String?
    /// Idioma de títulos/pósters: los pósters "es-MX" existen para casi
    /// todo lo popular y caen a los originales cuando no.
    private let language: String

    init(session: URLSession = .shared,
         baseURL: URL = URL(string: "https://api.themoviedb.org/3")!,
         imageBaseURL: URL = URL(string: "https://image.tmdb.org/t/p/w780")!,
         language: String = "es-MX",
         apiKeyProvider: @escaping @Sendable () -> String? = { APIKeyStore.load(for: .tmdb) }) {
        self.session = session
        self.baseURL = baseURL
        self.imageBaseURL = imageBaseURL
        self.language = language
        self.apiKeyProvider = apiKeyProvider
    }

    var hasAPIKey: Bool { apiKeyProvider() != nil }

    /// Película por título (y año si se conoce -- afina mucho con
    /// remakes homónimos). Devuelve el primer resultado: TMDB ya ordena
    /// por relevancia y popularidad.
    func searchMovie(title: String, year: String? = nil) async throws -> Movie? {
        var items = [URLQueryItem(name: "query", value: title), URLQueryItem(name: "include_adult", value: "false")]
        if let year, !year.isEmpty { items.append(URLQueryItem(name: "year", value: year)) }
        let response: SearchResponse<Movie>? = try await get("search/movie", query: items)
        return response?.results.first
    }

    func searchTV(name: String, year: String? = nil) async throws -> TVShow? {
        var items = [URLQueryItem(name: "query", value: name), URLQueryItem(name: "include_adult", value: "false")]
        if let year, !year.isEmpty { items.append(URLQueryItem(name: "first_air_date_year", value: year)) }
        let response: SearchResponse<TVShow>? = try await get("search/tv", query: items)
        return response?.results.first
    }

    /// ID de TheTVDB de una serie -- lo único que fanart.tv acepta para TV.
    func tvdbID(forTVShow id: Int) async throws -> Int? {
        let ids: ExternalIDs? = try await get("tv/\(id)/external_ids", query: [])
        return ids?.tvdbID
    }

    /// Descarga el póster de TMDB (`poster_path` relativo, p. ej.
    /// `/abc.jpg`) a 780 px de ancho -- de sobra para los ≤640 px que
    /// admite el iPod, sin bajar el original de 2000 px.
    func downloadPoster(path: String?) async throws -> Data? {
        guard let path, !path.isEmpty else { return nil }
        let url = imageBaseURL.appendingPathComponent(path)
        let (data, response) = try await session.data(from: url)
        try MusicBrainzClient.validate(response)
        return data
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T? {
        guard let apiKey = apiKeyProvider() else { return nil }
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query + [
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "api_key", value: apiKey),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(MusicBrainzClient.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 { return nil }
        try MusicBrainzClient.validate(response)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// Saca título, año y (si es serie) nombre de la serie del nombre de
/// archivo o del título que ya tenga el video (ST-022). Los nombres
/// reales vienen como `The.Matrix.1999.1080p.BluRay.x264.mkv` o
/// `Breaking Bad - S01E02 - Cat's in the Bag.mp4`; sin limpiar eso, la
/// búsqueda en TMDB no encuentra nada.
enum VideoTitleParser {
    struct Parsed: Equatable {
        var title: String
        var year: String?
        /// Nombre de la serie cuando el archivo trae `SxxEyy` / `1x02`.
        var seriesName: String?
        var season: Int?
        var episode: Int?

        var isEpisode: Bool { seriesName != nil }
    }

    private static let noiseTokens: Set<String> = [
        "1080p", "720p", "480p", "2160p", "4k", "uhd", "hdr", "hdr10", "dv", "x264", "x265", "h264", "h265", "hevc",
        "avc", "aac", "ac3", "dts", "bluray", "bdrip", "brrip", "webrip", "web-dl", "webdl", "web", "hdtv", "dvdrip",
        "dvd", "remux", "proper", "repack", "extended", "unrated", "remastered", "multi", "dual", "latino", "castellano",
        "subs", "sub", "esp", "eng", "spa", "lat", "amzn", "nf", "dsnp", "hmax", "atvp", "yify", "yts", "rarbg", "10bit",
        "5.1", "7.1", "ddp5.1", "dd5.1", "atmos", "imax", "hq", "xvid", "divx", "mkv", "mp4", "avi",
    ]

    static func parse(_ raw: String) -> Parsed {
        var text = raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
        // Quitar etiquetas entre corchetes ([1080p], [Latino], [grupo]).
        text = text.replacingOccurrences(of: #"\[[^\]]*\]"#, with: " ", options: .regularExpression)

        var parsed = Parsed(title: text)

        // Serie: "S01E02", "s1e2", "1x02".
        if let match = text.range(of: #"(?i)\bS(\d{1,2})\s?E(\d{1,3})\b|\b(\d{1,2})x(\d{2,3})\b"#, options: .regularExpression) {
            let marker = String(text[match])
            let numbers = marker.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
            if numbers.count >= 2 {
                parsed.season = Int(numbers[0])
                parsed.episode = Int(numbers[1])
            }
            let before = String(text[..<match.lowerBound])
            let seriesName = cleanTitle(before)
            parsed.seriesName = seriesName.isEmpty ? nil : seriesName
            text = before
        }

        // Año entre 1900 y 2099, con o sin paréntesis; el ÚLTIMO que
        // aparezca (un título como "1917 (2019)" tiene dos).
        if let regex = try? NSRegularExpression(pattern: #"\(?\b(19\d{2}|20\d{2})\b\)?"#) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)
            if let last = matches.last, let yearRange = Range(last.range(at: 1), in: text), let fullRange = Range(last.range, in: text) {
                let year = String(text[yearRange])
                // Si el "año" es lo único que hay (película que se llama
                // "2012"), no se lo quites al título.
                let remainder = cleanTitle(String(text[..<fullRange.lowerBound]))
                if !remainder.isEmpty {
                    parsed.year = year
                    text = String(text[..<fullRange.lowerBound])
                }
            }
        }

        parsed.title = cleanTitle(text)
        if parsed.title.isEmpty { parsed.title = cleanTitle(raw) }
        return parsed
    }

    /// Quita tokens de ruido (calidad, códec, grupo), guiones sueltos y
    /// espacios repetidos.
    static func cleanTitle(_ text: String) -> String {
        let tokens = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
        var kept: [String] = []
        for token in tokens {
            let lower = token.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "-–()"))
            if lower.isEmpty { continue }
            if noiseTokens.contains(lower) { break } // lo que sigue al primer token de ruido es más ruido
            kept.append(token.trimmingCharacters(in: CharacterSet(charactersIn: "()")))
        }
        return kept.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–"))
    }
}

/// Orquesta la búsqueda de póster para un video (ST-022): TMDB resuelve
/// el título; fanart.tv aporta el póster curado si tiene el título;
/// si no, se usa el póster de TMDB. Mejor esfuerzo, sin tirar.
struct VideoArtworkResolver {
    var tmdb: TMDBClient = TMDBClient()
    var fanart: FanartTVClient = FanartTVClient()
    var hasFanartKey: @Sendable () -> Bool = { APIKeyStore.hasKey(for: .fanartTV) }

    enum Kind { case movie, series, unknown }
    enum Source: Equatable { case fanartTV, tmdb }

    struct Result: Equatable {
        let data: Data
        let source: Source
        let matchedTitle: String
        let year: String?
    }

    enum Failure: Error, Equatable {
        case missingTMDBKey
        case noMatch
        case noPoster
    }

    /// `kind` viene de la categoría del video en Studio (Películas /
    /// Series / Videos): con `unknown` se prueba película y después
    /// serie -- o al revés si el nombre trae `SxxEyy`.
    func resolve(rawTitle: String, kind: Kind) async -> Swift.Result<Result, Failure> {
        guard tmdb.hasAPIKey else { return .failure(.missingTMDBKey) }
        let parsed = VideoTitleParser.parse(rawTitle)
        let order: [Kind]
        switch kind {
        case .movie: order = [.movie]
        case .series: order = [.series]
        case .unknown: order = parsed.isEpisode ? [.series, .movie] : [.movie, .series]
        }
        var sawMatch = false
        for candidate in order {
            switch candidate {
            case .movie:
                guard let movie = try? await tmdb.searchMovie(title: parsed.title, year: parsed.year) else { continue }
                sawMatch = true
                if hasFanartKey(), let data = try? await fanart.fetchMoviePoster(tmdbOrIMDbID: String(movie.id)), !data.isEmpty {
                    return .success(Result(data: data, source: .fanartTV, matchedTitle: movie.title, year: movie.year))
                }
                if let data = try? await tmdb.downloadPoster(path: movie.posterPath), !data.isEmpty {
                    return .success(Result(data: data, source: .tmdb, matchedTitle: movie.title, year: movie.year))
                }
            case .series:
                let name = parsed.seriesName ?? parsed.title
                guard let show = try? await tmdb.searchTV(name: name, year: parsed.isEpisode ? nil : parsed.year) else { continue }
                sawMatch = true
                if hasFanartKey(),
                   let tvdb = try? await tmdb.tvdbID(forTVShow: show.id),
                   let data = try? await fanart.fetchTVPoster(tvdbID: String(tvdb)), !data.isEmpty {
                    return .success(Result(data: data, source: .fanartTV, matchedTitle: show.name, year: show.year))
                }
                if let data = try? await tmdb.downloadPoster(path: show.posterPath), !data.isEmpty {
                    return .success(Result(data: data, source: .tmdb, matchedTitle: show.name, year: show.year))
                }
            case .unknown:
                continue
            }
        }
        return .failure(sawMatch ? .noPoster : .noMatch)
    }
}
