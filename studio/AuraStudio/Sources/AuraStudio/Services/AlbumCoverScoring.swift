import Foundation

/// Puntaje de una carátula candidata (R2-3, ST-115).
///
/// **`docs/caratula-recomendada.md` es la especificación vinculante** —
/// los números de acá y los de allá tienen que coincidir, y la app de
/// Windows calca los mismos. Si cambia un peso, cambia en los tres
/// lugares o las dos apps recomiendan distinto para la misma biblioteca.
///
/// El orden de importancia lo fijó la planeadora: título del álbum >
/// año > número de pistas > estatus/país de la edición > tapa frontal.
/// Los pesos están elegidos para que ese orden se respete siempre: nada
/// de lo de abajo puede compensar la falta de algo de arriba.
enum AlbumCoverScoring {
    /// El título de la edición coincide con el del álbum (normalizado).
    /// Es lo único casi obligatorio: sin esto la edición probablemente
    /// no es este disco.
    static let titleMatch = 50
    /// El año de la edición coincide con el de las pistas.
    static let yearMatch = 25
    /// La edición tiene tantas pistas como el álbum en la biblioteca.
    static let trackCountMatch = 15
    /// `status == "Official"` (no bootleg, no promo).
    static let officialStatus = 6
    /// La edición declara país, y 2 puntos más si es uno de los
    /// habituales para esta biblioteca.
    static let hasCountry = 2
    static let preferredCountry = 2
    /// La imagen está marcada como TAPA FRONTAL en Cover Art Archive.
    /// Sin la marca puede ser la contratapa o el disco, que como
    /// carátula de álbum están mal.
    static let frontCover = 10

    /// Países preferidos, en el orden en que se prefieren. `XW` es
    /// "worldwide" en MusicBrainz.
    static let preferredCountries: Set<String> = ["XW", "MX", "US", "GB"]

    /// Máximo alcanzable: 110.
    static let maximum = titleMatch + yearMatch + trackCountMatch
        + officialStatus + hasCountry + preferredCountry + frontCover

    /// **Umbral de aplicación automática: 85 de 110.**
    ///
    /// Elegido para que aplicar sin preguntar exija el título MÁS una
    /// corroboración fuerte MÁS una tapa frontal de verdad. Las dos
    /// combinaciones mínimas que llegan son:
    /// - título + año + tapa frontal = 50 + 25 + 10 = 85
    /// - título + nº de pistas + oficial + país preferido + tapa
    ///   frontal = 50 + 15 + 6 + 4 + 10 = 85
    ///
    /// Un título que coincide y nada más suma 50 y NO alcanza, que es
    /// justo lo que se quiere: los discos con nombre común
    /// ("Greatest Hits") no se resuelven solos.
    static let automaticThreshold = 85

    /// Datos del álbum de la biblioteca contra los que se puntúa.
    struct AlbumFacts: Equatable {
        let title: String
        let year: String?
        let trackCount: Int
    }

    /// Datos de la edición candidata.
    struct ReleaseFacts: Equatable {
        let title: String?
        let year: String?
        let trackCount: Int?
        let status: String?
        let country: String?
        let isFrontCover: Bool

        init(title: String?, year: String?, trackCount: Int?,
             status: String?, country: String?, isFrontCover: Bool) {
            self.title = title
            self.year = year
            self.trackCount = trackCount
            self.status = status
            self.country = country
            self.isFrontCover = isFrontCover
        }
    }

    static func score(album: AlbumFacts, release: ReleaseFacts) -> Int {
        var total = 0
        if let title = release.title,
           LibraryGrouping.normalize(title) == LibraryGrouping.normalize(album.title),
           !LibraryGrouping.normalize(title).isEmpty {
            total += titleMatch
        }
        if let year = album.year, let releaseYear = release.year, year == releaseYear, !year.isEmpty {
            total += yearMatch
        }
        if let count = release.trackCount, count == album.trackCount, count > 0 {
            total += trackCountMatch
        }
        if release.status?.caseInsensitiveCompare("Official") == .orderedSame {
            total += officialStatus
        }
        if let country = release.country, !country.isEmpty {
            total += hasCountry
            if preferredCountries.contains(country.uppercased()) { total += preferredCountry }
        }
        if release.isFrontCover { total += frontCover }
        return total
    }
}
