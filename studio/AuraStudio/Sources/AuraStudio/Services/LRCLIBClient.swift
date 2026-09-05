import Foundation

/// Cliente de LRCLIB (lrclib.net), sin API key. Devuelve letras
/// sincronizadas en formato .lrc -- el mismo formato que aura_lrc.c ya
/// sabe parsear en el firmware (D-019), asi que el archivo que este
/// cliente trae se puede escribir tal cual como sidecar junto a la
/// pista, sin ninguna conversion.
struct LRCLIBClient {
    private struct SearchResult: Decodable {
        let syncedLyrics: String?
        /// ST-012 / contrato SS3: si LRCLIB solo tiene la letra sin
        /// marcas de tiempo, se usa igual -- Studio la escribe como .lrc
        /// y el firmware decide que hacer sin timestamps (hoy la ignora;
        /// el dia que muestre letra estatica, ya esta en el iPod).
        let plainLyrics: String?
        let duration: Double?
    }

    static let clientIdentifier = "AuraStudio v0.2.0 (https://github.com/Ricolinos/Aura-Studio)"

    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = URL(string: "https://lrclib.net/api")!) {
        self.session = session
        self.baseURL = baseURL
    }

    /// `durationSeconds` es opcional pero mejora mucho la precision del
    /// match -- LRCLIB usa duracion +/- 2s como señal fuerte de que es
    /// la version correcta de la cancion.
    func fetchSyncedLyrics(title: String, artist: String, album: String? = nil, durationSeconds: Int? = nil) async throws -> String? {
        var components = URLComponents(url: baseURL.appendingPathComponent("get"), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        if let album {
            items.append(URLQueryItem(name: "album_name", value: album))
        }
        if let durationSeconds {
            items.append(URLQueryItem(name: "duration", value: String(durationSeconds)))
        }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.setValue(MusicBrainzClient.userAgent, forHTTPHeaderField: "User-Agent")
        // LRCLIB hoy no aplica ningun limite de tasa, pero su propio
        // cliente web se identifica con esta cabecera y su documentacion
        // la pide por cortesia: si algun dia tienen que limitar, quieren
        // poder distinguir clientes en vez de cortar por IP a ciegas.
        request.setValue(Self.clientIdentifier, forHTTPHeaderField: "Lrclib-Client")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            return nil
        }
        try MusicBrainzClient.validate(response)

        let decoded = try JSONDecoder().decode(SearchResult.self, from: data)
        if let synced = decoded.syncedLyrics, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return synced
        }
        if let plain = decoded.plainLyrics, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return plain
        }
        return nil
    }
}
