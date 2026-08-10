import Foundation

/// Adivina artista/titulo a partir de un nombre de archivo cuando no
/// hay tags previas -- el patron mas comun con diferencia es
/// "Artista - Titulo.ext". Si no matchea ese patron, se usa el nombre
/// completo (sin extension) como titulo y se busca solo por eso.
enum FilenameGuesser {
    static func guess(from url: URL) -> (artist: String?, title: String?) {
        let base = url.deletingPathExtension().lastPathComponent
        let parts = base.components(separatedBy: " - ")
        if parts.count >= 2 {
            return (parts[0].trimmingCharacters(in: .whitespaces), parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces))
        }
        return (nil, base.trimmingCharacters(in: .whitespaces))
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

    init(musicBrainz: MusicBrainzClient = MusicBrainzClient(),
         coverArt: CoverArtArchiveClient = CoverArtArchiveClient(),
         lrclib: LRCLIBClient = LRCLIBClient()) {
        self.musicBrainz = musicBrainz
        self.coverArt = coverArt
        self.lrclib = lrclib
    }

    func enrich(item: LibraryItem) async -> TrackMetadata {
        var existing = ID3Writer.Tag()
        if item.sourceURL.pathExtension.lowercased() == "mp3",
           let data = try? Data(contentsOf: item.sourceURL) {
            existing = ID3Writer.readTag(from: data) ?? ID3Writer.Tag()
        }

        let guess = FilenameGuesser.guess(from: item.sourceURL)
        let seedTitle = existing.title ?? guess.title
        let seedArtist = existing.artist ?? guess.artist

        var metadata = TrackMetadata(
            title: existing.title ?? guess.title,
            artist: existing.artist ?? guess.artist,
            album: existing.album,
            albumArtist: existing.albumArtist,
            year: existing.year,
            genre: existing.genre,
            trackNumber: existing.trackNumber,
            coverArtData: existing.coverArtData
        )

        guard let recording = try? await musicBrainz.searchRecording(title: seedTitle, artist: seedArtist) else {
            return metadata
        }

        metadata.title = metadata.title ?? recording.title
        metadata.artist = metadata.artist ?? recording.artistCredit?.first?.name
        metadata.musicBrainzRecordingID = recording.id

        if let release = recording.releases?.first {
            metadata.album = metadata.album ?? release.title
            metadata.year = metadata.year ?? release.date.map { String($0.prefix(4)) }
            metadata.musicBrainzReleaseID = release.id

            if metadata.coverArtData == nil {
                metadata.coverArtData = try? await coverArt.fetchFrontCover(releaseID: release.id)
            }
        }

        if let title = metadata.title, let artist = metadata.artist {
            metadata.syncedLyrics = try? await lrclib.fetchSyncedLyrics(title: title, artist: artist, album: metadata.album)
        }

        return metadata
    }
}
