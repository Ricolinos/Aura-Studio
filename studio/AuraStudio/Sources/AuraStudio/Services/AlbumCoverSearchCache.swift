import Foundation

/// Ronda rendimiento-3, camino B: caché en disco de las candidatas de
/// carátula ya descargadas.
///
/// Diagnóstico: `AlbumCoverSearch.candidates` bajaba de la red TODAS las
/// tapas de un álbum cada vez que se abría el picker (o corría la acción
/// plural) — hasta ~6 peticiones por álbum entre Cover Art Archive y
/// Deezer, segundos por álbum, y todo se tiraba al cerrar la hoja.
/// Reabrir el mismo álbum, o retomar una cola de álbumes dudosos al día
/// siguiente, empezaba de cero.
///
/// Las candidatas se guardan en `<biblioteca>/.portadas/busqueda/<clave>/`
/// como `N.jpg` + un `candidates.json` con la metadata de cada una
/// (fuente, puntaje, desempates). La clave incluye título, artista, año
/// y número de pistas: si el usuario corrige la metadata del álbum, la
/// clave cambia y la búsqueda se hace fresca — nunca se recomienda con
/// datos viejos.
///
/// Vigencia de 7 días: las tapas de un álbum ya publicado no cambian, y
/// una semana acota lo que esta carpeta puede crecer si cambian de
/// opinión arriba. No hay borrado proactivo de entradas viejas más allá
/// de esa vigencia al leer — son unos pocos cientos de KB por álbum y el
/// usuario siempre puede purgar `.portadas/busqueda/` sin romper nada
/// (es derivado 100% regenerable, igual que `.preparados/`).
struct AlbumCoverSearchCache: Sendable {
    /// Vigencia de una búsqueda cacheada. Las tapas de un álbum ya
    /// publicado son estables; el tope existe para no servir por siempre
    /// una candidata bajada de una fuente que pudo corregirse.
    static let timeToLive: TimeInterval = 7 * 24 * 60 * 60

    /// Identidad de UNA búsqueda: el álbum tal como la biblioteca lo
    /// conoce. Cambiar año o número de pistas (una corrección del
    /// usuario) produce otra clave — el puntaje de cada candidata se
    /// calculó contra esos hechos y no debe sobrevivirles.
    struct Key: Hashable {
        let album: String
        let artist: String?
        let year: String?
        let trackCount: Int
    }

    let directory: URL
    /// Inyectable para pruebas (el reloj real no se toca en la suite).
    var now: @Sendable () -> Date = { Date() }

    init(libraryRoot: URL) {
        self.directory = CoverStore.directory(in: libraryRoot)
            .appendingPathComponent("busqueda", isDirectory: true)
    }

    init(directory: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.now = now
    }

    // MARK: - Formato en disco

    private struct StoredCandidate: Codable {
        let file: String
        let source: String
        let detail: String?
        let score: Int
        let isFrontCover: Bool
        let isOfficial: Bool
        let releaseYear: String?
        let discoveryOrder: Int
    }

    private struct StoredSearch: Codable {
        var fetchedAt: TimeInterval
        var candidates: [StoredCandidate]
    }

    // MARK: - Lectura

    /// Las candidatas cacheadas, o `nil` si no hay entrada o está vencida.
    /// Una imagen que falte en disco (borrada a mano) invalida solo ESA
    /// candidata; las demás sobreviven.
    func load(_ key: Key) -> [AlbumCoverSearch.Candidate]? {
        let folder = folderURL(for: key)
        let manifestURL = folder.appendingPathComponent("candidates.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let stored = try? JSONDecoder().decode(StoredSearch.self, from: data) else { return nil }
        guard now().timeIntervalSince1970 - stored.fetchedAt < Self.timeToLive else { return nil }

        var result: [AlbumCoverSearch.Candidate] = []
        for candidate in stored.candidates {
            guard let source = Self.source(from: candidate.source),
                  let imageData = try? Data(contentsOf: folder.appendingPathComponent(candidate.file)),
                  !imageData.isEmpty else { continue }
            result.append(AlbumCoverSearch.Candidate(
                data: imageData, source: source, detail: candidate.detail,
                score: candidate.score, isFrontCover: candidate.isFrontCover,
                isOfficial: candidate.isOfficial, releaseYear: candidate.releaseYear,
                discoveryOrder: candidate.discoveryOrder))
        }
        return result.isEmpty ? nil : result
    }

    // MARK: - Escritura

    /// Guarda las candidatas de una búsqueda recién hecha. Mejor
    /// esfuerzo de punta a punta: un fallo de disco acá no puede tirar
    /// la búsqueda que ya salió bien.
    func store(_ candidates: [AlbumCoverSearch.Candidate], for key: Key) {
        guard !candidates.isEmpty else { return }
        let folder = folderURL(for: key)
        try? FileManager.default.removeItem(at: folder)
        guard let _ = try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) else { return }

        var stored: [StoredCandidate] = []
        for (index, candidate) in candidates.enumerated() {
            let file = "\(index).jpg"
            guard let _ = try? candidate.data.write(to: folder.appendingPathComponent(file), options: .atomic) else { continue }
            stored.append(StoredCandidate(
                file: file, source: Self.name(of: candidate.source), detail: candidate.detail,
                score: candidate.score, isFrontCover: candidate.isFrontCover,
                isOfficial: candidate.isOfficial, releaseYear: candidate.releaseYear,
                discoveryOrder: candidate.discoveryOrder))
        }
        let search = StoredSearch(fetchedAt: now().timeIntervalSince1970, candidates: stored)
        if let data = try? JSONEncoder().encode(search) {
            try? data.write(to: folder.appendingPathComponent("candidates.json"), options: .atomic)
        }
    }

    // MARK: - Claves y conversiones

    /// Nombre de carpeta estable y corto: SHA-256 de la clave
    /// normalizada. Un hash evita tener que sanear títulos de álbum
    /// arbitrarios para el sistema de archivos.
    private func folderURL(for key: Key) -> URL {
        let raw = [key.album, key.artist ?? "", key.year ?? "", String(key.trackCount)]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "\u{1}")
        return directory.appendingPathComponent(CoverStore.hash(Data(raw.utf8)), isDirectory: true)
    }

    private static func name(of source: AlbumCoverSearch.Source) -> String {
        switch source {
        case .coverArtArchive: return "coverArtArchive"
        case .deezer: return "deezer"
        }
    }

    private static func source(from name: String) -> AlbumCoverSearch.Source? {
        switch name {
        case "coverArtArchive": return .coverArtArchive
        case "deezer": return .deezer
        default: return nil
        }
    }
}
