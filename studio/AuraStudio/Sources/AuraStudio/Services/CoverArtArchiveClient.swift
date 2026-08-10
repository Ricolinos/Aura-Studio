import Foundation

/// Cliente de Cover Art Archive (coverartarchive.org), sin API key.
/// Complementa a MusicBrainzClient: una vez que se sabe el
/// release id de MusicBrainz, esto trae la imagen de tapa real.
struct CoverArtArchiveClient {
    private struct ImageEntry: Decodable {
        let image: String
        let front: Bool
        let thumbnails: Thumbnails?
    }

    private struct Thumbnails: Decodable {
        let large: String?
        let small: String?
    }

    private struct CoverArtResponse: Decodable {
        let images: [ImageEntry]
    }

    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = URL(string: "https://coverartarchive.org")!) {
        self.session = session
        self.baseURL = baseURL
    }

    /// Devuelve los bytes de la tapa (preferentemente el thumbnail
    /// "large", que alcanza de sobra para el LCD de 320x240 del iPod y
    /// pesa mucho menos que la imagen original) para el release dado,
    /// o nil si ese release no tiene tapa registrada.
    func fetchFrontCover(releaseID: String) async throws -> Data? {
        var request = URLRequest(url: baseURL.appendingPathComponent("release/\(releaseID)"))
        request.setValue(MusicBrainzClient.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            return nil
        }
        try MusicBrainzClient.validate(response)

        let decoded = try JSONDecoder().decode(CoverArtResponse.self, from: data)
        guard let front = decoded.images.first(where: { $0.front }) ?? decoded.images.first else {
            return nil
        }
        // La API a veces devuelve URLs "http://" (nunca "https://") para
        // los thumbnails -- App Transport Security las bloquea por
        // default en la app real (a diferencia de `swift test`/`curl`,
        // que no aplican ATS), asi que se fuerza https antes de pedirla.
        // El propio servidor sirve el mismo contenido por ambos, asi que
        // no hace falta ningun cambio de configuracion en Info.plist.
        let imageURLString = (front.thumbnails?.large ?? front.image).replacingOccurrences(of: "http://", with: "https://")
        guard let imageURL = URL(string: imageURLString) else { return nil }

        var imageRequest = URLRequest(url: imageURL)
        imageRequest.setValue(MusicBrainzClient.userAgent, forHTTPHeaderField: "User-Agent")
        let (imageData, imageResponse) = try await session.data(for: imageRequest)
        try MusicBrainzClient.validate(imageResponse)
        return imageData
    }
}
