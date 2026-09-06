import Foundation

/// Metadata enriquecida de una pista, ya sea leida del archivo original
/// o completada via MusicBrainz/Cover Art Archive/LRCLIB (o Genius/
/// Musixmatch si el usuario cargo su propia API key, ver
/// APIKeySettings). `source` indica de donde vino cada pieza para que
/// la vista de revision pueda mostrar "esto lo completamos nosotros"
/// vs "esto ya lo tenia el archivo".
struct TrackMetadata: Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var year: String?
    var genre: String?
    /// Autor/compositor (TCOM en ID3, `tag_composer` en el tagcache de
    /// Rockbox) -- el firmware ya sabe organizar musica por "Autores"
    /// (AURA_SCREEN_MUSIC_COMPOSERS), este campo es lo que faltaba en
    /// Aura Studio para poblarlo.
    var composer: String?
    var trackNumber: Int?

    // MARK: - Carátula (PLAN-studio-rendimiento-2.md Fase 5, ST-185)
    //
    // La carátula ya NO vive en memoria. Antes era un `coverArtData:
    // Data?` con el JPEG entero por ítem -- unos 180 MB con 12 000
    // canciones, y repetido por cada pista del mismo álbum (§0.8). Los
    // archivos ya vivían en `.portadas/<id>.jpg`; lo que sobraba era la
    // copia en RAM.

    /// Dónde vive la carátula en disco. `nil` = no hay carátula.
    var coverURL: URL?
    /// SHA-256 de los bytes del archivo, hexadecimal en MAYÚSCULAS (ver
    /// `CoverStore`). `nil` = **no se sabe** (catálogo guardado antes de
    /// que el campo existiera), nunca "no hay". Invariante: sin
    /// `coverURL` no hay hash.
    var coverHash: String?
    /// Bytes recién producidos que TODAVÍA no se escribieron a disco --
    /// lo que acaba de leer `LocalTagReader`, bajar `LibraryEnricher` o
    /// elegir el usuario en el selector de carátulas.
    ///
    /// Es una escala, no un almacén: `CatalogPersister` los escribe en
    /// `.portadas/` fuera del hilo principal y `LibraryViewModel` los
    /// pone en `nil` al aplicar el resultado, dejando `coverURL` y
    /// `coverHash`. El pico de memoria queda acotado a lo que entre en
    /// una ventana de guardado (≤ 500 ms de rebote), no a la biblioteca
    /// entera para siempre.
    var pendingCoverData: Data?
    /// Letra en formato LRC. Normalmente con marcas `[mm:ss.xx]` (LRCLIB
    /// `syncedLyrics`); puede ser letra plana si solo habia esa (ST-012)
    /// -- el nombre se conserva por compatibilidad con `biblioteca.json`.
    var syncedLyrics: String?
    var musicBrainzRecordingID: String?
    var musicBrainzReleaseID: String?
    /// Duracion real del archivo (D-198, columna "Duración" de la tabla
    /// de biblioteca) -- medida best-effort con ffmpeg al procesar
    /// (`FFmpegTranscoder.probeDurationSeconds`), nunca bloquea el
    /// pipeline si ffmpeg no esta instalado (queda nil, la tabla
    /// muestra "--").
    var durationSeconds: Double?
    /// Calificacion 0-5 estrellas (D-199, encargo del dueno: "se
    /// sincronizaria con el iPod... en el reproductor tenemos
    /// oportunidad de elegir cuantas estrellas le damos a la cancion").
    /// nil = sin calificar (distinto de 0, que seria "0 estrellas"
    /// puesto a proposito).
    var rating: Int?
    /// Favorito (ST-030): marca binaria independiente de `rating`, la
    /// misma idea que el corazon/estrella de Music.app -- alimenta el
    /// filtro "Solo favoritos" y la columna/orden "Favorito". Vive solo
    /// en el catalogo de Studio (no hay frame ID3 estandar para esto).
    var isFavorite: Bool
    /// Numero de disco (TPOS / `disk` en MP4), para ordenar cajas de
    /// varios discos antes que por numero de pista.
    var discNumber: Int?

    init(title: String? = nil, artist: String? = nil, album: String? = nil,
         albumArtist: String? = nil, year: String? = nil, genre: String? = nil,
         composer: String? = nil,
         trackNumber: Int? = nil, coverURL: URL? = nil, coverHash: String? = nil,
         pendingCoverData: Data? = nil, coverArtData: Data? = nil, syncedLyrics: String? = nil,
         musicBrainzRecordingID: String? = nil, musicBrainzReleaseID: String? = nil,
         durationSeconds: Double? = nil, rating: Int? = nil,
         isFavorite: Bool = false, discNumber: Int? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.year = year
        self.genre = genre
        self.composer = composer
        self.trackNumber = trackNumber
        self.coverURL = coverURL
        // ST-185: `coverArtData:` es un atajo de conveniencia -- "acá
        // están los bytes, resuélvelo tú" -- que deja el hash calculado
        // y los bytes en la escala de `pendingCoverData`. Lo usan sobre
        // todo las pruebas, que arman metadata con una carátula sin
        // pasar por el guardado del catálogo.
        self.coverHash = coverArtData.map(CoverStore.hash) ?? coverHash
        self.pendingCoverData = coverArtData ?? pendingCoverData
        self.syncedLyrics = syncedLyrics
        self.musicBrainzRecordingID = musicBrainzRecordingID
        self.musicBrainzReleaseID = musicBrainzReleaseID
        self.durationSeconds = durationSeconds
        self.rating = rating
        self.isFavorite = isFavorite
        self.discNumber = discNumber
    }

    var isComplete: Bool {
        title != nil && artist != nil && album != nil
    }

    /// Pone (o quita) la carátula. Los bytes quedan en `pendingCoverData`
    /// hasta que `CatalogPersister` los escriba; el hash se calcula acá
    /// mismo, para que nadie tenga que recorrer los bytes de nuevo para
    /// compararlos o para nombrar una miniatura.
    mutating func setCover(_ data: Data?) {
        guard let data else {
            pendingCoverData = nil
            coverURL = nil
            coverHash = nil
            return
        }
        pendingCoverData = data
        coverHash = CoverStore.hash(data)
    }

    /// ¿Hay carátula? Sin leer nada de disco.
    var hasCover: Bool { coverURL != nil || pendingCoverData != nil }

    /// Los bytes de la carátula. **Toca el disco** si todavía no están
    /// en memoria, así que nunca se llama desde el `body` de una vista:
    /// las vistas piden miniaturas a `CoverThumbnailCache`, que lee en
    /// segundo plano (ST-183).
    func loadCoverData() -> Data? {
        pendingCoverData ?? CoverStore.read(coverURL)
    }

    /// Identidad de la carátula para la caché de miniaturas. Con hash,
    /// es el hash; sin él (catálogo viejo todavía sin migrar), la ruta.
    var coverCacheID: String? {
        if let coverHash { return coverHash }
        if let coverURL { return "ruta:\(coverURL.path)" }
        return nil
    }

    /// PLAN-studio-rendimiento-2.md Fase 5 (ST-185): `Equatable` a mano.
    ///
    /// El sintetizado comparaba los BYTES de la carátula, y esta
    /// comparación corre en cada `onChange(of: items)`, en cada
    /// `Equatable` de `LibraryItem` y en cada diffing de SwiftUI: 15 KB
    /// por ítem por comparación (§0.8). El hash identifica el contenido
    /// igual de bien en O(1).
    ///
    /// `pendingCoverData` se compara solo por presencia: si hay bytes
    /// sin escribir, `coverHash` ya los describe (quien los pone,
    /// calcula el hash en el mismo paso).
    static func == (a: TrackMetadata, b: TrackMetadata) -> Bool {
        a.title == b.title && a.artist == b.artist && a.album == b.album
            && a.albumArtist == b.albumArtist && a.year == b.year && a.genre == b.genre
            && a.composer == b.composer && a.trackNumber == b.trackNumber
            && a.coverURL == b.coverURL && a.coverHash == b.coverHash
            && (a.pendingCoverData == nil) == (b.pendingCoverData == nil)
            && a.syncedLyrics == b.syncedLyrics
            && a.musicBrainzRecordingID == b.musicBrainzRecordingID
            && a.musicBrainzReleaseID == b.musicBrainzReleaseID
            && a.durationSeconds == b.durationSeconds && a.rating == b.rating
            && a.isFavorite == b.isFavorite && a.discNumber == b.discNumber
    }
}
