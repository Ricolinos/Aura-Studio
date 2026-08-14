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

    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared,
         baseURL: URL = URL(string: "https://webservice.fanart.tv/v3/music/albums")!) {
        self.session = session
        self.baseURL = baseURL
    }

    func fetchAlbumCover(releaseGroupID: String) async throws -> Data? {
        guard let apiKey = APIKeyStore.load(for: .fanartTV) else { return nil }

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
