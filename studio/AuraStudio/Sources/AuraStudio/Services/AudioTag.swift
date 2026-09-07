import Foundation

/// ST-222 (PLAN-studio-ajustes-3.md, Fase A2): los campos que el
/// catálogo escribe **dentro del archivo de audio**, en la forma en que
/// los tres escritores nativos los entienden (ID3v2.3 para MP3,
/// VORBIS_COMMENT para FLAC, átomos `ilst` para M4A/ALAC).
///
/// Era `ID3Writer.Tag`, y vivir dentro del escritor de MP3 dejó de tener
/// sentido en cuanto hubo tres: el juego de campos es el mismo para los
/// tres formatos, lo que cambia es cómo se serializa. `ID3Writer.Tag`
/// sigue existiendo como alias, así que ningún sitio que ya lo usaba
/// tuvo que tocarse.
///
/// **La dirección es una sola: del catálogo al archivo.** Leer del
/// archivo para rellenar el catálogo es otra operación distinta ("Releer
/// etiquetas del archivo") y no pasa por acá.
///
/// **Lo que deliberadamente NO está**: rating, favorito, letra y
/// categoría. Son datos de Aura, no del archivo -- el rating viaja en
/// `ratings.cfg`, la letra como `.lrc` hermano y la categoría es
/// organización de la biblioteca. Reescribir un archivo de cincuenta
/// megabytes porque alguien puso una estrella es exactamente el defecto
/// que esta ronda vino a arreglar (ST-221, precisión 1).
struct AudioTag: Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var year: String?
    var genre: String?
    /// Autor/compositor. En MP3 es el frame TCOM, que es lo que lee
    /// `tag_composer` del tagcache de Rockbox
    /// (AURA_SCREEN_MUSIC_COMPOSERS).
    var composer: String?
    var trackNumber: Int?
    /// ST-222: número de disco. Ya estaba en `TrackMetadata` y en el
    /// escritor de Windows (ST-242); en la Mac no se escribía en ningún
    /// formato, así que un álbum doble perdía la separación de discos al
    /// llegar al iPod.
    var discNumber: Int?
    var coverArtData: Data?
    var coverArtMIMEType: String = "image/jpeg"

    init(title: String? = nil, artist: String? = nil, album: String? = nil,
         albumArtist: String? = nil, year: String? = nil, genre: String? = nil,
         composer: String? = nil, trackNumber: Int? = nil, discNumber: Int? = nil,
         coverArtData: Data? = nil, coverArtMIMEType: String = "image/jpeg") {
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.year = year
        self.genre = genre
        self.composer = composer
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.coverArtData = coverArtData
        self.coverArtMIMEType = coverArtMIMEType
    }

    /// `true` si no hay nada que escribir. Un archivo sin nada que
    /// cambiar **no se reescribe**: es lo que hace que el archivo
    /// conserve su fecha de modificación y sus bytes.
    var isEmpty: Bool {
        title == nil && artist == nil && album == nil && albumArtist == nil
            && year == nil && genre == nil && composer == nil
            && trackNumber == nil && discNumber == nil && coverArtData == nil
    }
}
