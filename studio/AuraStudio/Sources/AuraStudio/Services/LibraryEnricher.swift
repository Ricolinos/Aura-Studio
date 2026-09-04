import Foundation

/// Adivina artista/titulo a partir de un nombre de archivo cuando no
/// hay tags previas -- el patron mas comun con diferencia es
/// "Artista - Titulo.ext". Si no matchea ese patron, se usa el nombre
/// completo (sin extension) como titulo y se busca solo por eso.
enum FilenameGuesser {
    static func guess(from url: URL) -> (artist: String?, title: String?) {
        let base = url.deletingPathExtension().lastPathComponent
        let parts = base.components(separatedBy: " - ")
        if parts.count >= 2, !looksLikeTrackNumberPrefix(parts[0]) {
            return (parts[0].trimmingCharacters(in: .whitespaces), parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces))
        }
        return (nil, base.trimmingCharacters(in: .whitespaces))
    }

    /// PLAN-sync-media-hardening.md PARTE 1A: el primer segmento antes de
    /// " - " a veces es en realidad el NUMERO DE PISTA pegado al nombre
    /// del archivo ("1 - Titulo.m4a", "01 Lil Dub Chefin - Version...
    /// m4a"), no el artista -- visto en produccion: decenas de canciones
    /// sin tags de artista terminaron en carpetas del iPod literalmente
    /// llamadas "1".."20" (una por numero de pista, mezclando canciones
    /// de artistas distintos), en vez de "Desconocido". Un segmento que
    /// arranca con 1-3 digitos seguidos de un espacio (o que es
    /// puramente numerico) no es un nombre de artista plausible --
    /// heuristica imperfecta a proposito (un artista real como "21
    /// Savage" cae a "Desconocido" en vez de a su nombre), pero muchisimo
    /// mejor que agrupar decenas de artistas bajo una carpeta "1".
    static func looksLikeTrackNumberPrefix(_ segment: String) -> Bool {
        let trimmed = segment.trimmingCharacters(in: .whitespaces)
        guard let firstNonDigitIndex = trimmed.firstIndex(where: { !$0.isNumber }) else {
            return !trimmed.isEmpty
        }
        let digitCount = trimmed.distance(from: trimmed.startIndex, to: firstNonDigitIndex)
        guard digitCount >= 1 && digitCount <= 3 else { return false }
        return trimmed[firstNonDigitIndex] == " "
    }
}

/// Orquesta el flujo "arrastrar y listo" para un LibraryItem de musica:
/// parte de lo que ya tenga el archivo (tags ID3 existentes, si es
/// MP3), completa lo que falte via MusicBrainz/Cover Art Archive/LRCLIB,
/// y devuelve metadata lista para escribir. No copia nada al iPod
/// (eso es tarea de LibrarySync, despues de que el usuario revise/
/// confirme si quiere).
struct LibraryEnricher {
    let musicBrainz: MusicBrainzClient
    let coverArt: CoverArtArchiveClient
    let lrclib: LRCLIBClient
    let fanartTV: FanartTVClient
    let deezer: DeezerClient

    init(musicBrainz: MusicBrainzClient = MusicBrainzClient(),
         coverArt: CoverArtArchiveClient = CoverArtArchiveClient(),
         lrclib: LRCLIBClient = LRCLIBClient(),
         fanartTV: FanartTVClient = FanartTVClient(),
         deezer: DeezerClient = DeezerClient()) {
        self.musicBrainz = musicBrainz
        self.coverArt = coverArt
        self.lrclib = lrclib
        self.fanartTV = fanartTV
        self.deezer = deezer
    }

    /// D-203: prueba los proveedores de portada en el orden que eligio
    /// el usuario (Ajustes > Servicios) y devuelve la primera imagen que
    /// aparezca. `fanartTV`/`deezer` ya devuelven nil solos cuando no
    /// corresponde intentarlos (sin key, o busqueda sin resultado) --
    /// aca solo hace falta saltear Deezer si el usuario lo apago, y
    /// tragar cualquier error de red con `try?` para que un proveedor
    /// que falla no tumbe a los demas.
    private func resolveCoverArt(releaseID: String, releaseGroupID: String?,
                                  title: String?, artist: String?,
                                  order: [CoverArtProvider], deezerEnabled: Bool) async -> Data? {
        for provider in order {
            switch provider {
            case .coverArtArchive:
                if let data = try? await coverArt.fetchFrontCover(releaseID: releaseID) { return data }
            case .fanartTV:
                guard let releaseGroupID else { continue }
                if let data = try? await fanartTV.fetchAlbumCover(releaseGroupID: releaseGroupID) { return data }
            case .deezer:
                guard deezerEnabled, let title, let artist else { continue }
                if let data = try? await deezer.fetchAlbumCover(title: title, artist: artist) { return data }
            }
        }
        return nil
    }

    /// Umbral minimo de `score` de MusicBrainz (0-100) para aceptar una
    /// `Recording` como fuente de album/año -- `MusicBrainzClient.
    /// searchRecording` siempre devuelve el resultado de mayor score
    /// aunque sea bajo (o `nil`), y `enrich()`/`reenrich()` lo usaban
    /// sin piso: dos canciones del mismo album real podian terminar con
    /// albumes distintos si MusicBrainz devolvia un release equivocado
    /// con score bajo. Sin tags locales, es mejor dejar "Sin album"
    /// (revisable) que inventar uno. Un `score` ausente (`nil`) se trata
    /// como 0 -- por debajo del umbral, se rechaza.
    static let minimumMusicBrainzScore = 70

    /// `online` y `lyrics` salen de las preferencias del usuario
    /// (AppPreferences): con `online` en false no se toca la red y solo
    /// se usa lo que ya trae el archivo mas lo que se adivine del nombre.
    func enrich(item: LibraryItem, online: Bool = true, lyrics: Bool = true,
                coverArtOrder: [CoverArtProvider] = CoverArtProvider.defaultOrder,
                deezerEnabled: Bool = true) async -> TrackMetadata {
        var metadata = await LocalTagReader.readTag(from: item.sourceURL)

        let guess = FilenameGuesser.guess(from: item.sourceURL)
        metadata.title = metadata.title ?? guess.title
        metadata.artist = metadata.artist ?? guess.artist

        guard online else { return normalizingCover(metadata) }

        guard let recording = try? await musicBrainz.searchRecording(title: metadata.title, artist: metadata.artist),
              (recording.score ?? 0) >= Self.minimumMusicBrainzScore else {
            return normalizingCover(metadata)
        }

        metadata.title = metadata.title ?? recording.title
        metadata.artist = metadata.artist ?? recording.artistCredit?.first?.name
        metadata.musicBrainzRecordingID = recording.id

        if let release = recording.releases?.first {
            metadata.album = metadata.album ?? release.title
            metadata.year = metadata.year ?? release.date.map { String($0.prefix(4)) }
            metadata.musicBrainzReleaseID = release.id

            if metadata.coverArtData == nil {
                metadata.coverArtData = await resolveCoverArt(
                    releaseID: release.id, releaseGroupID: release.releaseGroup?.id,
                    title: metadata.title, artist: metadata.artist,
                    order: coverArtOrder, deezerEnabled: deezerEnabled)
            }
        }

        if lyrics, let title = metadata.title, let artist = metadata.artist {
            metadata.syncedLyrics = try? await lrclib.fetchSyncedLyrics(title: title, artist: artist, album: metadata.album)
        }

        return normalizingCover(metadata)
    }

    /// ST-141: toda carátula que entra a la biblioteca queda cuadrada,
    /// venga de la etiqueta del archivo (`LocalTagReader`, incluido el
    /// `cover.jpg` de la carpeta) o de la red. Acá está el único punto
    /// por el que pasan las dos.
    private func normalizingCover(_ metadata: TrackMetadata) -> TrackMetadata {
        guard let cover = metadata.coverArtData else { return metadata }
        var normalized = metadata
        normalized.coverArtData = CoverArtNormalizer.normalized(cover)
        return normalized
    }

    /// D-198: "Buscar información"/"Buscar letra" del menú contextual de
    /// la biblioteca -- a diferencia de `enrich()` (que parte de las
    /// tags CRUDAS del archivo original), esto parte de la metadata YA
    /// resuelta del item (`currentMetadata`), para no pisar una
    /// corrección manual que el usuario ya hizo en la pantalla de
    /// revisión. Solo llena huecos (nunca reemplaza un campo que ya
    /// tiene valor) -- mismo criterio que `enrich()`.
    ///
    /// D-203: a diferencia de la version anterior, esto YA NO traga los
    /// errores de red en silencio -- devuelve un `EnrichmentOutcome`
    /// junto con la metadata para que quien llama (`LibraryViewModel`)
    /// le pueda mostrar al usuario "no se encontro nada" vs "fallo la
    /// conexion" en vez de que ambos casos se vean identicos (la causa
    /// mas probable de que el dueño reportara que esto "no sirve para
    /// nada": un error de red silencioso es indistinguible de que de
    /// verdad no habia informacion que agregar).
    func reenrich(item: LibraryItem, currentMetadata: TrackMetadata,
                  fetchAlbumInfo: Bool, fetchLyrics: Bool,
                  coverArtOrder: [CoverArtProvider] = CoverArtProvider.defaultOrder,
                  deezerEnabled: Bool = true) async -> (metadata: TrackMetadata, outcome: EnrichmentOutcome) {
        var metadata = currentMetadata
        var outcome = EnrichmentOutcome()
        let guess = FilenameGuesser.guess(from: item.sourceURL)
        let seedTitle = metadata.title ?? guess.title
        let seedArtist = metadata.artist ?? guess.artist

        if fetchAlbumInfo {
            do {
                if let recording = try await musicBrainz.searchRecording(title: seedTitle, artist: seedArtist),
                   (recording.score ?? 0) >= Self.minimumMusicBrainzScore {
                    outcome.albumInfoFound = true
                    metadata.title = metadata.title ?? recording.title
                    metadata.artist = metadata.artist ?? recording.artistCredit?.first?.name
                    metadata.musicBrainzRecordingID = metadata.musicBrainzRecordingID ?? recording.id

                    if let release = recording.releases?.first {
                        metadata.album = metadata.album ?? release.title
                        metadata.year = metadata.year ?? release.date.map { String($0.prefix(4)) }
                        metadata.musicBrainzReleaseID = metadata.musicBrainzReleaseID ?? release.id

                        if metadata.coverArtData == nil {
                            metadata.coverArtData = await resolveCoverArt(
                                releaseID: release.id, releaseGroupID: release.releaseGroup?.id,
                                title: metadata.title, artist: metadata.artist,
                                order: coverArtOrder, deezerEnabled: deezerEnabled)
                        }
                    }
                }
            } catch {
                outcome.networkErrorMessage = error.localizedDescription
            }
        }

        if fetchLyrics, let title = metadata.title, let artist = metadata.artist {
            do {
                metadata.syncedLyrics = try await lrclib.fetchSyncedLyrics(title: title, artist: artist, album: metadata.album)
                outcome.lyricsFound = metadata.syncedLyrics != nil
            } catch {
                outcome.networkErrorMessage = outcome.networkErrorMessage ?? error.localizedDescription
            }
        }

        return (normalizingCover(metadata), outcome)
    }
}

/// Resultado de `reenrich()` para un item -- que tanto encontro, y si
/// algo salio mal a nivel de red (vs. simplemente "no habia nada que
/// encontrar", que no es un error).
struct EnrichmentOutcome: Equatable {
    var albumInfoFound = false
    var lyricsFound = false
    var networkErrorMessage: String?
}
