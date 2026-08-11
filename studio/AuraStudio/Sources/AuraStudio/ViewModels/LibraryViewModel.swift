import Foundation
import Combine

/// Orquesta el flujo completo de la biblioteca: recibe archivos
/// arrastrados, los clasifica, los procesa (enriquecer musica,
/// transcodificar video, redimensionar fotos) y despues los sincroniza
/// al iPod. El flujo por defecto es automatico de punta a punta
/// ("arrastrar y listo", como pide el brief); `itemsNeedingReview`
/// existe para el caso opcional en que el usuario quiera corregir algo
/// antes de sincronizar.
@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var items: [LibraryItem] = []
    @Published private(set) var isProcessing = false
    @Published private(set) var lastSyncSummary: String?
    @Published var lastError: String?
    @Published private(set) var playlists: [Playlist] = []

    private let enricher: LibraryEnricher
    private let stagingDirectory: URL
    private let preferences: AppPreferences

    /// `preferences` es opcional y no `= .shared` como default: un valor
    /// por defecto se evalua en contexto nonisolated, y `.shared` esta
    /// aislado al MainActor -- error bajo Swift 6 (que es lo que compila
    /// xcodebuild, D-034). Resolverlo dentro del init, que si es
    /// MainActor, evita el problema sin cambiar la ergonomia.
    init(enricher: LibraryEnricher = LibraryEnricher(),
         stagingDirectory: URL? = nil,
         preferences: AppPreferences? = nil) {
        self.enricher = enricher
        self.preferences = preferences ?? .shared
        self.stagingDirectory = stagingDirectory ?? FileManager.default.temporaryDirectory.appendingPathComponent("AuraStudioStaging", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.stagingDirectory, withIntermediateDirectories: true)
    }

    var itemsNeedingReview: [LibraryItem] {
        items.filter { $0.status == .needsReview }
    }

    func addDroppedFiles(_ urls: [URL]) {
        let new = urls
            .filter { LibraryItemKind.classify(url: $0) != .unsupported }
            .map { LibraryItem(sourceURL: $0) }
        items.append(contentsOf: new)
    }

    func processAll() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        for index in items.indices where items[index].status == .queued {
            await process(itemAt: index)
        }
    }

    private func process(itemAt index: Int) async {
        let item = items[index]
        do {
            switch item.kind {
            case .music:
                items[index].status = .enriching
                let metadata = await enricher.enrich(item: item,
                                                      online: preferences.enrichOnline,
                                                      lyrics: preferences.fetchSyncedLyrics)
                items[index].metadata = metadata
                items[index].preparedURL = try prepareMusic(item: item, metadata: metadata)
                items[index].status = metadata.isComplete ? .ready : .needsReview

            case .video:
                items[index].status = .transcoding(progress: 0)
                let output = stagingDirectory.appendingPathComponent(item.sourceURL.deletingPathExtension().lastPathComponent + ".mpg")
                let transcoder = try FFmpegTranscoder()
                /// El callback de ffmpeg corre en el hilo de lectura del
                /// pipe (readabilityHandler), no en el MainActor -- hay
                /// que saltar de vuelta explicitamente para tocar
                /// `items`, que ObservableObject espera mutar solo desde
                /// el actor principal.
                try transcoder.transcode(input: item.sourceURL, output: output) { fraction in
                    Task { @MainActor [weak self] in
                        guard let self, index < self.items.count else { return }
                        self.items[index].status = .transcoding(progress: fraction)
                    }
                }
                items[index].preparedURL = output

                // Fase 24: poster (`<video>.jpg` junto al .mpg, D-066)
                // para el panel derecho del navegador de video -- si
                // ffmpeg no puede generarlo (formato raro, sin frames
                // legibles) no se aborta el item entero por esto, el
                // video ya quedo listo para sincronizar sin poster.
                let poster = output.deletingPathExtension().appendingPathExtension("jpg")
                try? transcoder.generatePoster(input: output, output: poster)

                items[index].status = .ready

            case .photo:
                let output = stagingDirectory.appendingPathComponent(item.sourceURL.deletingPathExtension().lastPathComponent + ".jpg")
                try ImageResizer.resizeToLCDOptimal(sourceURL: item.sourceURL, destinationURL: output)
                items[index].preparedURL = output
                items[index].status = .ready

            case .unsupported:
                items[index].status = .failed("Formato no soportado")
            }
        } catch {
            items[index].status = .failed(error.localizedDescription)
        }
    }

    /// Copia el archivo original a staging, le escribe la tag ID3 (solo
    /// para MP3, ver D-037) y deja la letra como sidecar junto a el -- el
    /// mismo formato que Aura ya sabe leer en el dispositivo
    /// (find_albumart/aura_lrc, Fases 4-6 del firmware).
    ///
    /// La caratula depende de la preferencia del usuario:
    ///   - "Una por cancion": se embebe en la tag del archivo.
    ///   - "Una por album": NO se embebe aca; la escribe LibrarySync una
    ///     sola vez en la carpeta del album, que es donde el firmware la
    ///     busca primero. Escribirla en staging no serviria: staging es
    ///     un unico directorio plano compartido por TODOS los albumes, asi
    ///     que un `cover.jpg` ahi lo pisaria el album siguiente (y encima
    ///     LibrarySync solo copia `preparedURL`, nunca lo habria subido al
    ///     iPod).
    private func prepareMusic(item: LibraryItem, metadata: TrackMetadata) throws -> URL {
        let destination = stagingDirectory.appendingPathComponent(item.sourceURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: item.sourceURL, to: destination)

        if destination.pathExtension.lowercased() == "mp3" {
            let embedCover = preferences.coverArtPolicy == .perTrack
            let tag = ID3Writer.Tag(
                title: metadata.title, artist: metadata.artist, album: metadata.album,
                albumArtist: metadata.albumArtist, year: metadata.year, genre: metadata.genre,
                trackNumber: metadata.trackNumber,
                coverArtData: embedCover ? metadata.coverArtData : nil
            )
            try ID3Writer.write(tag, toFileAt: destination)
        }

        if let lyrics = metadata.syncedLyrics {
            let lrcURL = destination.deletingPathExtension().appendingPathExtension("lrc")
            try lyrics.write(to: lrcURL, atomically: true, encoding: .utf8)
        }

        return destination
    }

    /// Aplica la metadata corregida a mano en la pantalla de revision
    /// (Fase 23, PLAN-UX.md -- este metodo ya existia pero ninguna vista
    /// lo llamaba). Vuelve a correr `prepareMusic` para que el archivo
    /// en staging (y su tag ID3/sidecars) reflejen la correccion -- sin
    /// esto, el archivo que se sincroniza al iPod seguiria teniendo la
    /// metadata vieja/incompleta que el usuario acaba de corregir.
    func applyReview(id: UUID, metadata: TrackMetadata) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].metadata = metadata
        do {
            items[index].preparedURL = try prepareMusic(item: items[index], metadata: metadata)
            items[index].status = metadata.isComplete ? .ready : .needsReview
        } catch {
            items[index].status = .failed(error.localizedDescription)
        }
    }

    func sync(toVolumeAt volumeRoot: URL) async {
        let readyItems = items.filter { $0.status == .ready }
        do {
            let sync = LibrarySync(volumeRoot: volumeRoot)
            let result = try sync.sync(items: readyItems, playlists: playlists,
                                        coverArtPolicy: preferences.coverArtPolicy)
            let playlistsNote = result.playlistsWritten > 0 ? " \(result.playlistsWritten) playlist(s) actualizada(s)." : ""
            lastSyncSummary = result.filesCopied == 0
                ? "Ya estaba todo sincronizado, no habia nada nuevo.\(playlistsNote)"
                : "Se copiaron \(result.filesCopied) de \(readyItems.count) archivo(s). El indice de la biblioteca se va a reconstruir la proxima vez que arranque Aura.\(playlistsNote)"
        } catch {
            // El mensaje de Cocoa viene en ingles y sin contexto ("You
            // can't save the file X because the volume is read only"):
            // se conserva porque dice el motivo real, pero se antepone
            // a donde se estaba escribiendo, que es la informacion que
            // permite darse cuenta de que se apunto al disco equivocado.
            lastError = "No se pudo sincronizar en \(volumeRoot.path): \(error.localizedDescription)"
        }
    }

    // MARK: - Playlists (Fase 24)

    @discardableResult
    func addPlaylist(name: String) -> UUID {
        let playlist = Playlist(name: name)
        playlists.append(playlist)
        return playlist.id
    }

    func removePlaylist(id: UUID) {
        playlists.removeAll { $0.id == id }
    }

    func addTrack(_ itemID: UUID, toPlaylist playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }),
              !playlists[index].trackItemIDs.contains(itemID) else { return }
        playlists[index].trackItemIDs.append(itemID)
    }

    func removeTrack(_ itemID: UUID, fromPlaylist playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].trackItemIDs.removeAll { $0 == itemID }
    }

    func moveTracks(inPlaylist playlistID: UUID, from offsets: IndexSet, to destination: Int) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].trackItemIDs.move(fromOffsets: offsets, toOffset: destination)
    }
}
