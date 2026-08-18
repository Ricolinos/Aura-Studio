import Foundation

/// Cliente de fanart.tv (D-203): caratulas y arte de disco en alta
/// resolucion, fuente OPCIONAL con API key propia (a diferencia de
/// MusicBrainz/Cover Art Archive/LRCLIB). La key se lee del Keychain
/// via `APIKeyStore` -- nunca se guarda ni se pasa por UserDefaults.
///
/// Endpoint confirmado contra la API real (agosto 2026):
/// `GET /v3/music/albums/{release-group-id}?api_key=...` -- indexa por
/// RELEASE GROUP (el album), no por release (la edicion especifica).
/// Sin key configurada no tiene sentido intentar la llamada (fanart.tv
/// siempre devuelve 401): se devuelve nil de una, mismo criterio de
/// "mejor esfuerzo" que ya usan los demas clientes.
struct FanartTVClient {
    private struct AlbumsResponse: Decodable {
        let albums: [String: AlbumImages]?
    }

    private struct AlbumImages: Decodable {
        let albumcover: [Image]?
    }

    private struct Image: Decodable {
        let url: String
    }

    private struct ArtistResponse: Decodable {
        let artistthumb: [Image]?
        let artistbackground: [Image]?
    }

    private struct MovieResponse: Decodable {
        let movieposter: [Image]?
    }

    private struct TVResponse: Decodable {
        let tvposter: [Image]?
    }

    private let session: URLSession
    private let baseURL: URL
    /// Raiz `/v3` (ST-032): `baseURL` sigue apuntando a `/music/albums`
    /// por compatibilidad con D-203; artistas, peliculas y series
    /// cuelgan de esta.
    private let rootURL: URL

    /// De donde sale la key: el Keychain (`APIKeyStore`) en la app;
    /// inyectable en tests para no tocar el llavero real.
    private let apiKeyProvider: @Sendable () -> String?

    init(session: URLSession = .shared,
         baseURL: URL = URL(string: "https://webservice.fanart.tv/v3/music/albums")!,
         rootURL: URL = URL(string: "https://webservice.fanart.tv/v3")!,
         apiKeyProvider: @escaping @Sendable () -> String? = { APIKeyStore.load(for: .fanartTV) }) {
        self.session = session
        self.baseURL = baseURL
        self.rootURL = rootURL
        self.apiKeyProvider = apiKeyProvider
    }

    /// GET autenticado; 404 = "fanart.tv no lo tiene" (nil, no error);
    /// sin key = nil sin tocar la red.
    private func fetchJSON<T: Decodable>(_ type: T.Type, path: String) async throws -> T? {
        guard let apiKey = apiKeyProvider() else { return nil }
        var components = URLComponents(url: rootURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "api_key", value: apiKey)]
        var request = URLRequest(url: components.url!)
        request.setValue(MusicBrainzClient.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 { return nil }
        try MusicBrainzClient.validate(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func download(_ urlString: String?) async throws -> Data? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        let (data, response) = try await session.data(from: url)
        try MusicBrainzClient.validate(response)
        return data
    }

    /// ST-032: foto de artista (`artistthumb`, cuadrada, ~1000 px) por
    /// MusicBrainz artist ID.
    func fetchArtistThumb(musicBrainzArtistID: String) async throws -> Data? {
        let decoded = try await fetchJSON(ArtistResponse.self, path: "music/\(musicBrainzArtistID)")
        return try await download(decoded?.artistthumb?.first?.url)
    }

    /// ST-033: poster de pelicula. fanart.tv acepta el ID de TMDB o el de
    /// IMDb (`tt...`) en la misma ruta.
    func fetchMoviePoster(tmdbOrIMDbID: String) async throws -> Data? {
        let decoded = try await fetchJSON(MovieResponse.self, path: "movies/\(tmdbOrIMDbID)")
        return try await download(decoded?.movieposter?.first?.url)
    }

    /// ST-033: poster de serie, por ID de TheTVDB (el unico que fanart.tv
    /// indexa para TV -- se obtiene via TMDB `external_ids`).
    func fetchTVPoster(tvdbID: String) async throws -> Data? {
        let decoded = try await fetchJSON(TVResponse.self, path: "tv/\(tvdbID)")
        return try await download(decoded?.tvposter?.first?.url)
    }

    func fetchAlbumCover(releaseGroupID: String) async throws -> Data? {
        guard let apiKey = apiKeyProvider() else { return nil }

        var components = URLComponents(url: baseURL.appendingPathComponent(releaseGroupID), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "api_key", value: apiKey)]

        var request = URLRequest(url: components.url!)
        request.setValue(MusicBrainzClient.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        // fanart.tv no tiene el album: 404 normal, no un error a
        // reportar (la mayoria de los albumes simplemente no estan en
        // su base).
        if let http = response as? HTTPURLResponse, http.statusCode == 404 { return nil }
        try MusicBrainzClient.validate(response)

        let decoded = try JSONDecoder().decode(AlbumsResponse.self, from: data)
        guard let urlString = decoded.albums?[releaseGroupID]?.albumcover?.first?.url,
              let imageURL = URL(string: urlString) else { return nil }

        let (imageData, imageResponse) = try await session.data(from: imageURL)
        try MusicBrainzClient.validate(imageResponse)
        return imageData
    }
}
