import Foundation

/// "Buscar carátulas del álbum" (ST-104): junta VARIAS tapas candidatas
/// para un álbum y deja que el usuario elija, en vez de imponer la
/// primera.
///
/// Es la contracara de lo que ya hacía `reenrichOnline(fetchAlbumInfo:)`,
/// que baja una sola tapa sin preguntar: eso está bien para enriquecer
/// cientos de canciones de un tirón, pero cuando el usuario mira un
/// álbum concreto y la tapa está mal, no tiene forma de pedir otra. El
/// mismo problema y la misma solución que "buscar póster" para
/// películas y series.
///
/// Usa los clientes que ya existen, sin fuentes nuevas:
/// - **Cover Art Archive** vía MusicBrainz. Se buscan varias EDICIONES
///   del álbum (`searchReleases`) y se pide la tapa de cada una: las
///   ediciones distintas de un mismo disco suelen tener arte distinto, y
///   ahí está la variedad real que se le ofrece al usuario.
/// - **Deezer** (D-203, solo si está habilitado en Ajustes), que
///   devuelve tapas de 1000×1000 sin API key.
///
/// Mejor esfuerzo de punta a punta: cada fuente va con `try?` y una que
/// falle no cancela a la otra. Sin resultados devuelve una lista vacía,
/// que la vista dice en pantalla -- nunca falla en silencio.
struct AlbumCoverSearch {
    var musicBrainz = MusicBrainzClient()
    var coverArtArchive = CoverArtArchiveClient()
    var deezer = DeezerClient()
    /// D-203: Deezer es opcional y se apaga desde Ajustes › Servicios.
    var deezerEnabled = true
    /// Cuántas ediciones pedirle a MusicBrainz (una llamada a Cover Art
    /// Archive por cada una).
    var releasesToTry = 5
    var maximumCandidates = 10

    enum Source: Equatable {
        case coverArtArchive
        case deezer

        var displayName: String {
            switch self {
            case .coverArtArchive: return "Cover Art Archive"
            case .deezer: return "Deezer"
            }
        }
    }

    /// Una tapa concreta, ya descargada, lista para previsualizar.
    struct Candidate: Identifiable, Equatable {
        let id = UUID()
        let data: Data
        let source: Source
        /// De qué edición/álbum salió, para que el usuario pueda
        /// distinguir dos tapas parecidas ("Signos · 1986").
        let detail: String?
        /// R2-3: puntaje de `AlbumCoverScoring` (0…110).
        var score: Int = 0
        /// Lo que se usa para desempatar, en orden, cuando dos
        /// candidatas puntúan igual. Ver `docs/caratula-recomendada.md`.
        var isFrontCover = false
        var isOfficial = false
        /// Año de la edición, para preferir la original sobre las
        /// reediciones a igualdad de todo lo demás.
        var releaseYear: String?
        /// Posición en que la devolvió la fuente -- el último desempate,
        /// el que garantiza que el resultado sea el MISMO en las dos
        /// apps y en dos corridas.
        var discoveryOrder = 0

        /// `true` si aplicarla sin preguntar es defendible.
        var reachesAutomaticThreshold: Bool { score >= AlbumCoverScoring.automaticThreshold }
    }

    /// Orden de recomendación: mayor puntaje primero y, a igualdad,
    /// la cadena de desempates de la spec. Es un orden TOTAL y
    /// determinista a propósito: dos apps distintas, o la misma dos
    /// veces, tienen que recomendar exactamente la misma tapa.
    static func isBetter(_ a: Candidate, _ b: Candidate) -> Bool {
        if a.score != b.score { return a.score > b.score }
        if a.isFrontCover != b.isFrontCover { return a.isFrontCover }
        if a.isOfficial != b.isOfficial { return a.isOfficial }
        // La edición más antigua antes que las reediciones. Sin año se
        // va al final (no se puede afirmar que sea la original).
        let ya = a.releaseYear ?? "9999", yb = b.releaseYear ?? "9999"
        if ya != yb { return ya < yb }
        if a.source != b.source { return a.source == .coverArtArchive }
        return a.discoveryOrder < b.discoveryOrder
    }

    /// La recomendada: la mejor según `isBetter`, o `nil` si no hay
    /// ninguna candidata. Puede NO alcanzar el umbral automático -- eso
    /// lo decide quien la use (`reachesAutomaticThreshold`).
    static func recommended(from candidates: [Candidate]) -> Candidate? {
        candidates.min(by: isBetter)
    }

    /// Las candidatas para el álbum, **ya ordenadas por recomendación**
    /// (`isBetter`): la primera es la que se marca "Recomendada" en el
    /// picker y la que usa la acción automática si alcanza el umbral.
    ///
    /// `facts` es lo que la biblioteca sabe del álbum (título, año,
    /// número de pistas) y es contra eso que se puntúa cada edición.
    func candidates(for facts: AlbumCoverScoring.AlbumFacts, artist: String?) async -> [Candidate] {
        let albumTitle = facts.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !albumTitle.isEmpty, albumTitle != LibraryGrouping.unknownAlbumTitle else { return [] }
        let artistName = artist.flatMap { name -> String? in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed == LibraryGrouping.unknownArtistName ? nil : trimmed
        }

        var result: [Candidate] = []
        var seen: Set<Data> = []

        func append(_ candidate: Candidate) {
            guard !candidate.data.isEmpty, result.count < maximumCandidates,
                  seen.insert(candidate.data).inserted else { return }
            var scored = candidate
            scored.discoveryOrder = result.count
            result.append(scored)
        }

        let releases = (try? await musicBrainz.searchReleases(album: albumTitle,
                                                             artist: artistName,
                                                             limit: releasesToTry)) ?? []
        for release in releases {
            guard result.count < maximumCandidates else { break }
            guard let cover = try? await coverArtArchive.fetchCover(releaseID: release.id) else { continue }
            let releaseYear = Self.year(from: release.date)
            let isOfficial = release.status?.caseInsensitiveCompare("Official") == .orderedSame
            let score = AlbumCoverScoring.score(
                album: facts,
                release: AlbumCoverScoring.ReleaseFacts(
                    title: release.title, year: releaseYear, trackCount: release.trackCount,
                    status: release.status, country: release.country,
                    isFrontCover: cover.isFront))
            append(Candidate(data: cover.data, source: .coverArtArchive,
                             detail: Self.detail(title: release.title, year: releaseYear),
                             score: score, isFrontCover: cover.isFront,
                             isOfficial: isOfficial, releaseYear: releaseYear))
        }

        if deezerEnabled, result.count < maximumCandidates,
           let matches = try? await deezer.searchAlbumCovers(title: albumTitle, artist: artistName) {
            for match in matches {
                guard result.count < maximumCandidates else { break }
                guard let data = try? await deezer.fetchImage(at: match.coverURL) else { continue }
                // Deezer no es una EDICIÓN: no trae año, ni número de
                // pistas, ni estatus. Solo puede puntuar el título, así
                // que por construcción nunca llega sola al umbral
                // automático -- aplicar sin preguntar exige que
                // MusicBrainz lo respalde.
                let score = AlbumCoverScoring.score(
                    album: facts,
                    release: AlbumCoverScoring.ReleaseFacts(
                        title: match.title, year: nil, trackCount: nil,
                        status: nil, country: nil, isFrontCover: false))
                append(Candidate(data: data, source: .deezer,
                                 detail: Self.detail(title: match.title,
                                                     year: match.artist.isEmpty ? nil : match.artist),
                                 score: score))
            }
        }

        return result.sorted(by: Self.isBetter)
    }

    /// Compatibilidad con quien solo tiene título y artista (no puede
    /// puntuar año ni número de pistas).
    func candidates(album: String, artist: String?) async -> [Candidate] {
        await candidates(for: AlbumCoverScoring.AlbumFacts(title: album, year: nil, trackCount: 0),
                         artist: artist)
    }

    /// "Signos · 1986" -- las dos partes son opcionales porque
    /// MusicBrainz y Deezer no siempre traen las dos.
    static func detail(title: String?, year: String?) -> String? {
        let parts = [title, year].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// MusicBrainz da la fecha completa (`1986-11-25`) o solo el año.
    static func year(from date: String?) -> String? {
        guard let date, date.count >= 4 else { return nil }
        let year = String(date.prefix(4))
        return year.allSatisfy(\.isNumber) ? year : nil
    }
}
