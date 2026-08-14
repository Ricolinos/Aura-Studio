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
    private let preferences: AppPreferences
    private var cancellables: Set<AnyCancellable> = []

    /// Carpeta de la biblioteca Aura (D-180): raiz elegida en Ajustes.
    /// Todo lo que entra a la biblioteca se COPIA a `Originales/` (los
    /// archivos del usuario jamas se tocan), lo preparado vive en
    /// `Preparados/` (antes era un directorio temporal que macOS podia
    /// purgar), y el catalogo (`biblioteca.json`) hace que la
    /// biblioteca sobreviva reinicios de la app -- con o sin iPod.
    private(set) var libraryRoot: URL
    private var stagingDirectory: URL { libraryRoot.appendingPathComponent(PersistedLibrary.preparedDirName, isDirectory: true) }
    private var originalsDirectory: URL { libraryRoot.appendingPathComponent(PersistedLibrary.originalsDirName, isDirectory: true) }
    private var coversDirectory: URL { libraryRoot.appendingPathComponent(PersistedLibrary.coversDirName, isDirectory: true) }
    private var catalogURL: URL { libraryRoot.appendingPathComponent(PersistedLibrary.catalogFileName) }

    /// `preferences` es opcional y no `= .shared` como default: un valor
    /// por defecto se evalua en contexto nonisolated, y `.shared` esta
    /// aislado al MainActor -- error bajo Swift 6 (que es lo que compila
    /// xcodebuild, D-034). Resolverlo dentro del init, que si es
    /// MainActor, evita el problema sin cambiar la ergonomia.
    init(enricher: LibraryEnricher = LibraryEnricher(),
         libraryRoot: URL? = nil,
         preferences: AppPreferences? = nil) {
        self.enricher = enricher
        let prefs = preferences ?? .shared
        self.preferences = prefs
        self.libraryRoot = libraryRoot ?? URL(fileURLWithPath: prefs.libraryFolderPath, isDirectory: true)
        ensureLibraryStructure()
        loadCatalog()

        // Cambiar la carpeta en Ajustes recarga la biblioteca desde el
        // catalogo de la carpeta nueva (o arranca vacia si no hay uno).
        prefs.$libraryFolderPath
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] newPath in
                self?.switchLibraryFolder(to: newPath)
            }
            .store(in: &cancellables)
    }

    var itemsNeedingReview: [LibraryItem] {
        items.filter { $0.status == .needsReview }
    }

    /// Con `copyMediaIntoLibrary` activo (default): copia cada archivo a
    /// `Originales/` y la biblioteca referencia LA COPIA -- el archivo
    /// original del usuario queda intacto donde estaba (encargo del
    /// dueño: "para no modificar nuestros archivos originales").
    /// Colisiones de nombre se resuelven con sufijo numerico, nunca
    /// pisando lo que ya estaba.
    ///
    /// Con el ajuste apagado (encargo del dueño, 2026-08-13): el item
    /// referencia el archivo original DIRECTO, sin copiarlo -- nada se
    /// duplica en disco. `relativePath(of:)` ya sabe guardar una ruta
    /// absoluta en el catalogo cuando el archivo no vive dentro de la
    /// biblioteca (ver `loadCatalog`, que la reconoce de vuelta).
    func addDroppedFiles(_ urls: [URL]) {
        ensureLibraryStructure()
        var new: [LibraryItem] = []
        for url in urls where LibraryItemKind.classify(url: url) != .unsupported {
            if preferences.copyMediaIntoLibrary {
                do {
                    let copy = try copyToOriginals(url)
                    new.append(LibraryItem(sourceURL: copy))
                } catch {
                    lastError = "No se pudo copiar \(url.lastPathComponent) a la biblioteca: \(error.localizedDescription)"
                }
            } else {
                new.append(LibraryItem(sourceURL: url))
            }
        }
        items.append(contentsOf: new)
        persistCatalog()
    }

    private func copyToOriginals(_ url: URL) throws -> URL {
        let fm = FileManager.default
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var candidate = originalsDirectory.appendingPathComponent(url.lastPathComponent)
        var counter = 2
        while fm.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = originalsDirectory.appendingPathComponent(name)
            counter += 1
        }
        try fm.copyItem(at: url, to: candidate)
        return candidate
    }

    func processAll() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        for index in items.indices where items[index].status == .queued {
            await process(itemAt: index)
        }
        persistCatalog()
    }

    private func process(itemAt index: Int) async {
        let item = items[index]
        do {
            switch item.kind {
            case .music:
                items[index].status = .enriching
                var metadata = await enricher.enrich(item: item,
                                                      online: preferences.enrichOnline,
                                                      lyrics: preferences.fetchSyncedLyrics)
                // Duracion real (D-198, columna "Duración" de la tabla de
                // biblioteca) -- best-effort con ffmpeg, nunca bloquea el
                // pipeline si no esta instalado (a diferencia de video, la
                // musica en formato original nunca necesito ffmpeg antes
                // de esto).
                if let probe = try? FFmpegTranscoder(),
                   let duration = try? FFmpegTranscoder.probeDurationSeconds(of: item.sourceURL, ffmpegURL: probe.ffmpegURL) {
                    metadata.durationSeconds = duration
                }
                items[index].metadata = metadata
                items[index].preparedURL = try prepareMusic(item: item, metadata: metadata)
                items[index].status = metadata.isComplete ? .ready : .needsReview

            case .video:
                items[index].status = .transcoding(progress: 0)
                let transcoder = try FFmpegTranscoder()
                let duration = try? FFmpegTranscoder.probeDurationSeconds(of: item.sourceURL, ffmpegURL: transcoder.ffmpegURL)
                if items[index].category == nil {
                    items[index].category = MediaCategoryHeuristics.classifyVideo(durationSeconds: duration ?? nil)
                }
                items[index].metadata = TrackMetadata(durationSeconds: duration ?? nil)
                let output = stagingDirectory.appendingPathComponent(item.sourceURL.deletingPathExtension().lastPathComponent + ".mpg")
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
                if items[index].category == nil {
                    items[index].category = MediaCategoryClassifier.classifyPhoto(at: item.sourceURL)
                }
                let output = stagingDirectory.appendingPathComponent(item.sourceURL.deletingPathExtension().lastPathComponent + ".jpg")
                try ImageResizer.resizeToLCDOptimal(sourceURL: item.sourceURL, destinationURL: output,
                                                     maxDimension: preferences.photoQuality.maxDimension)
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
        // "Comprimir a buena calidad" (D-192): siempre se transcodifica
        // a MP3 256kbps, sin importar el formato de origen -- incluso un
        // MP3 de origen se re-encodifica, para que el bitrate resultante
        // sea predecible. "Mantener original" (default) sigue copiando
        // el archivo tal cual, como siempre hizo esta funcion.
        let destination: URL
        if preferences.audioQuality == .compressed {
            destination = stagingDirectory
                .appendingPathComponent(item.sourceURL.deletingPathExtension().lastPathComponent)
                .appendingPathExtension("mp3")
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            let transcoder = try AudioTranscoder()
            try transcoder.transcodeToMP3(input: item.sourceURL, output: destination)
        } else {
            destination = stagingDirectory.appendingPathComponent(item.sourceURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: item.sourceURL, to: destination)
        }

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
        persistCatalog()
    }

    /// Correccion manual de la categoria sugerida (Imagenes/Fotos/
    /// Hechas con IA, Caseros/Videos/Peliculas) desde la vista de
    /// biblioteca (Fase 1B) -- la heuristica automatica de
    /// `MediaCategoryClassifier` es solo un punto de partida.
    func setCategory(_ category: MediaCategory, forItem id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].category = category
        persistCatalog()
    }

    // MARK: - Menu contextual de la tabla de biblioteca (D-198)

    /// Quita items de la biblioteca -- borra tambien lo que Aura Studio
    /// escribio para ellos (`Preparados/`/`Portadas/`, y `Originales/`
    /// si `copyMediaIntoLibrary` copio el archivo) para no dejar huerfanos.
    /// El original del usuario NUNCA se toca si esta fuera de la
    /// biblioteca (modo "sin copiar medios", D-192). Tambien los saca de
    /// cualquier playlist que los referenciara.
    func deleteItems(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let fm = FileManager.default
        let rootPath = libraryRoot.standardizedFileURL.path

        for id in ids {
            guard let item = items.first(where: { $0.id == id }) else { continue }
            if let prepared = item.preparedURL { try? fm.removeItem(at: prepared) }
            let coverURL = coversDirectory.appendingPathComponent("\(item.id.uuidString).jpg")
            try? fm.removeItem(at: coverURL)
            let sourcePath = item.sourceURL.standardizedFileURL.path
            if sourcePath.hasPrefix(rootPath + "/") {
                try? fm.removeItem(at: item.sourceURL)
            }
        }

        items.removeAll { ids.contains($0.id) }
        for index in playlists.indices {
            playlists[index].trackItemIDs.removeAll { ids.contains($0) }
        }
        persistCatalog()
    }

    /// "Cambiar nombre" del menu contextual -- solo el TITULO mostrado/
    /// usado al armar la ruta de sincronizacion (`LibrarySync`), nunca
    /// el nombre del archivo original en disco.
    func renameItem(id: UUID, title: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var metadata = items[index].metadata ?? TrackMetadata()
        metadata.title = trimmed
        items[index].metadata = metadata
        if items[index].kind == .music {
            items[index].preparedURL = try? prepareMusic(item: items[index], metadata: metadata)
            if items[index].status == .ready || items[index].status == .needsReview {
                items[index].status = metadata.isComplete ? .ready : .needsReview
            }
        }
        persistCatalog()
    }

    /// "Eliminar carátula" del menu contextual -- solo tiene sentido
    /// para musica (fotos/video no tienen caratula embebida propia).
    func clearCoverArt(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].kind == .music else { return }
        var metadata = items[index].metadata ?? TrackMetadata()
        metadata.coverArtData = nil
        items[index].metadata = metadata
        items[index].preparedURL = try? prepareMusic(item: items[index], metadata: metadata)
        let coverURL = coversDirectory.appendingPathComponent("\(items[index].id.uuidString).jpg")
        try? FileManager.default.removeItem(at: coverURL)
        persistCatalog()
    }

    /// "Buscar información en línea"/"Buscar letra" del menu contextual
    /// -- reintenta contra MusicBrainz/Cover Art Archive/LRCLIB partiendo
    /// de la metadata YA resuelta (`LibraryEnricher.reenrich`, no
    /// `enrich`), asi que no pisa una correccion manual ya hecha. Solo
    /// aplica a musica.
    func reenrichOnline(ids: Set<UUID>, fetchAlbumInfo: Bool, fetchLyrics: Bool) async {
        for id in ids {
            guard let index = items.firstIndex(where: { $0.id == id }), items[index].kind == .music else { continue }
            let item = items[index]
            let current = item.metadata ?? TrackMetadata()
            let updated = await enricher.reenrich(item: item, currentMetadata: current,
                                                    fetchAlbumInfo: fetchAlbumInfo, fetchLyrics: fetchLyrics)
            guard index < items.count else { continue }
            items[index].metadata = updated
            items[index].preparedURL = try? prepareMusic(item: items[index], metadata: updated)
            items[index].status = updated.isComplete ? .ready : .needsReview
        }
        persistCatalog()
    }

    func sync(toVolumeAt volumeRoot: URL) async {
        let readyItems = items.filter { $0.status == .ready }
        do {
            let sync = LibrarySync(volumeRoot: volumeRoot)
            let result = try sync.sync(items: readyItems, playlists: playlists,
                                        coverArtPolicy: preferences.coverArtPolicy,
                                        musicOrganization: preferences.musicOrganization,
                                        musicFilenameFormat: preferences.musicFilenameFormat)
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
        persistCatalog()
        return playlist.id
    }

    func removePlaylist(id: UUID) {
        playlists.removeAll { $0.id == id }
        persistCatalog()
    }

    func addTrack(_ itemID: UUID, toPlaylist playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }),
              !playlists[index].trackItemIDs.contains(itemID) else { return }
        playlists[index].trackItemIDs.append(itemID)
        persistCatalog()
    }

    func removeTrack(_ itemID: UUID, fromPlaylist playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].trackItemIDs.removeAll { $0 == itemID }
        persistCatalog()
    }

    func moveTracks(inPlaylist playlistID: UUID, from offsets: IndexSet, to destination: Int) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].trackItemIDs.move(fromOffsets: offsets, toOffset: destination)
        persistCatalog()
    }

    /// Resultado de importar una playlist M3U/M3U8 de otro programa
    /// (D-193): cuantas pistas se pudieron ligar a algo que ya esta en
    /// ESTA biblioteca de Aura -- una playlist puede referenciar
    /// musica que el usuario todavia no soltó en la app, y eso no
    /// deberia fallar la importacion entera, solo esas pistas puntuales.
    struct PlaylistImportResult {
        let playlistID: UUID
        let matchedCount: Int
        let unmatchedPaths: [String]
    }

    /// Empareja cada ruta primero por ruta absoluta exacta y, si no
    /// hay match, por nombre de archivo (una playlist exportada desde
    /// otra maquina/servicio casi nunca tiene la misma ruta absoluta,
    /// pero el nombre de archivo suele sobrevivir).
    @discardableResult
    func importPlaylist(name: String, trackPaths: [String]) -> PlaylistImportResult {
        var matchedIDs: [UUID] = []
        var unmatched: [String] = []
        for path in trackPaths {
            let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
            if let match = items.first(where: { $0.kind == .music && $0.sourceURL.standardizedFileURL.path == standardized }) {
                matchedIDs.append(match.id)
                continue
            }
            let filename = URL(fileURLWithPath: path).lastPathComponent
            if let match = items.first(where: { $0.kind == .music && $0.sourceURL.lastPathComponent == filename }) {
                matchedIDs.append(match.id)
            } else {
                unmatched.append(path)
            }
        }
        let playlist = Playlist(name: name, trackItemIDs: matchedIDs)
        playlists.append(playlist)
        persistCatalog()
        return PlaylistImportResult(playlistID: playlist.id, matchedCount: matchedIDs.count, unmatchedPaths: unmatched)
    }

    // MARK: - Persistencia de la biblioteca (D-180)

    private func ensureLibraryStructure() {
        let fm = FileManager.default
        for dir in [libraryRoot, originalsDirectory, stagingDirectory, coversDirectory] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func switchLibraryFolder(to newPath: String) {
        libraryRoot = URL(fileURLWithPath: newPath, isDirectory: true)
        ensureLibraryStructure()
        items = []
        playlists = []
        loadCatalog()
    }

    /// Serializa el catalogo completo. Las portadas se escriben como
    /// archivos aparte (`Portadas/<id>.jpg`) -- ver PersistedLibrary.
    private func persistCatalog() {
        var persisted = PersistedLibrary()
        for item in items {
            var coverRelative: String?
            if let cover = item.metadata?.coverArtData {
                let coverURL = coversDirectory.appendingPathComponent("\(item.id.uuidString).jpg")
                if (try? cover.write(to: coverURL, options: .atomic)) != nil {
                    coverRelative = "\(PersistedLibrary.coversDirName)/\(item.id.uuidString).jpg"
                }
            }
            persisted.items.append(PersistedLibraryItem(
                id: item.id,
                sourceRelativePath: relativePath(of: item.sourceURL),
                kind: LibraryPersistenceMapper.persistedKind(item.kind),
                status: LibraryPersistenceMapper.persistedStatus(item.status),
                metadata: LibraryPersistenceMapper.persistedMetadata(item.metadata),
                preparedRelativePath: item.preparedURL.map { relativePath(of: $0) },
                coverRelativePath: coverRelative,
                category: item.category?.rawValue
            ))
        }
        persisted.playlists = playlists.map {
            PersistedPlaylist(id: $0.id, name: $0.name, trackItemIDs: $0.trackItemIDs)
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(persisted).write(to: catalogURL, options: .atomic)
        } catch {
            lastError = "No se pudo guardar el catalogo de la biblioteca: \(error.localizedDescription)"
        }
    }

    private func loadCatalog() {
        guard let data = try? Data(contentsOf: catalogURL),
              let persisted = try? JSONDecoder().decode(PersistedLibrary.self, from: data) else { return }

        let fm = FileManager.default
        var restored: [LibraryItem] = []
        for p in persisted.items {
            // `relativePath(of:)` guarda una ruta ABSOLUTA cuando el
            // archivo no vive dentro de la biblioteca (modo "sin copiar
            // medios", D-192) -- reconstruirla con `appendingPathComponent`
            // la trataria como un componente literal en vez de una ruta
            // absoluta real, rompiendo la referencia.
            let sourceURL = p.sourceRelativePath.hasPrefix("/")
                ? URL(fileURLWithPath: p.sourceRelativePath)
                : libraryRoot.appendingPathComponent(p.sourceRelativePath)
            // Si el archivo (la copia en Originales/, o el original
            // referenciado sin copiar) ya no existe, el item se omite en
            // silencio: no hay nada que preparar ni sincronizar desde un
            // archivo ausente.
            guard fm.fileExists(atPath: sourceURL.path) else { continue }

            let coverData = p.coverRelativePath
                .map { libraryRoot.appendingPathComponent($0) }
                .flatMap { try? Data(contentsOf: $0) }
            let preparedURL = p.preparedRelativePath
                .map { libraryRoot.appendingPathComponent($0) }
            let preparedExists = preparedURL.map { fm.fileExists(atPath: $0.path) } ?? false

            var status = LibraryPersistenceMapper.liveStatus(p.status)
            if status == .ready && !preparedExists {
                // "Listo" sin su archivo preparado no es listo: se
                // vuelve a encolar y el proximo procesamiento lo
                // regenera.
                status = .queued
            }

            restored.append(LibraryItem(
                id: p.id,
                sourceURL: sourceURL,
                kind: LibraryPersistenceMapper.liveKind(p.kind),
                status: status,
                metadata: LibraryPersistenceMapper.liveMetadata(p.metadata, coverArtData: coverData),
                preparedURL: preparedExists ? preparedURL : nil,
                category: p.category.flatMap(MediaCategory.init(rawValue:))
            ))
        }
        items = restored
        playlists = persisted.playlists.map {
            Playlist(id: $0.id, name: $0.name, trackItemIDs: $0.trackItemIDs)
        }
    }

    private func relativePath(of url: URL) -> String {
        let rootPath = libraryRoot.standardizedFileURL.path
        let fullPath = url.standardizedFileURL.path
        if fullPath.hasPrefix(rootPath + "/") {
            return String(fullPath.dropFirst(rootPath.count + 1))
        }
        return fullPath
    }
}
