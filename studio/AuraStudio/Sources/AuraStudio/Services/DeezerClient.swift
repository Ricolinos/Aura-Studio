import Foundation

/// Cliente de Deezer (D-203): caratula alternativa de album, 1000x1000.
/// Sin API key ni registro -- es la unica fuente opcional cuyos
/// terminos permiten explicitamente el uso no comercial de este tipo de
/// app (ver `ServicesSettingsView`). Una sola portada por album, la del
/// primer resultado de busqueda.
struct DeezerClient {
    private struct SearchResponse: Decodable {
        let data: [Track]
    }

    private struct Track: Decodable {
        let album: Album
    }

    private struct Album: Decodable {
        let coverXL: String

        enum CodingKeys: String, CodingKey {
            case coverXL = "cover_xl"
        }
    }

    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared,
         baseURL: URL = URL(string: "https://api.deezer.com/search")!) {
        self.session = session
        self.baseURL = baseURL
    }

    func fetchAlbumCover(title: String, artist: String) async throws -> Data? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: "artist:\"\(escapeQuoted(artist))\" track:\"\(escapeQuoted(title))\""),
            URLQueryItem(name: "limit", value: "1"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue(MusicBrainzClient.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        try MusicBrainzClient.validate(response)

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        guard let urlString = decoded.data.first?.album.coverXL,
              let imageURL = URL(string: urlString) else { return nil }

        let (imageData, imageResponse) = try await session.data(from: imageURL)
        try MusicBrainzClient.validate(imageResponse)
        return imageData
    }

    private struct ArtistSearchResponse: Decodable {
        let data: [Artist]
    }

    private struct Artist: Decodable {
        let name: String
        let pictureXL: String?

        enum CodingKeys: String, CodingKey {
            case name
            case pictureXL = "picture_xl"
        }
    }

    /// ST-021: foto de artista (`picture_xl`, 1000x1000) del primer
    /// resultado cuyo nombre coincida (sin mayusculas/acentos) -- Deezer
    /// devuelve tambien parecidos, y "Gorillaz" no debe llevarse la foto
    /// de "Gorillaz Sound System". `baseURL` es `/search`; el buscador
    /// de artistas es su hermano `/search/artist`.
    func fetchArtistPicture(name: String) async throws -> Data? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents(url: baseURL.appendingPathComponent("artist"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: escapeQuoted(trimmed)),
            URLQueryItem(name: "limit", value: "5"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(MusicBrainzClient.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try MusicBrainzClient.validate(response)
        let decoded = try JSONDecoder().decode(ArtistSearchResponse.self, from: data)
        let wanted = LibraryGrouping.normalize(trimmed)
        guard let match = decoded.data.first(where: { LibraryGrouping.normalize($0.name) == wanted }),
              let urlString = match.pictureXL, let imageURL = URL(string: urlString) else { return nil }
        let (imageData, imageResponse) = try await session.data(from: imageURL)
        try MusicBrainzClient.validate(imageResponse)
        return imageData
    }

    /// La query de Deezer no es Lucene (no acepta escape con barra
    /// invertida) -- una comilla doble sin cerrar simplemente rompe la
    /// frase de busqueda, asi que se quita en vez de escaparse.
    private func escapeQuoted(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "")
    }
}
