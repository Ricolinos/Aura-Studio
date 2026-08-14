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
    /// D-203: resultado de "Buscar información en línea"/"Buscar letra"
    /// (ver `reenrichOnline`) -- antes esta accion no dejaba ningun
    /// rastro visible en la interfaz.
    @Published private(set) var lastEnrichmentSummary: String?
    @Published var lastError: String?
    @Published private(set) var playlists: [Playlist] = []
    /// D-217: progreso de un `sync(toVolumeAt:)` en curso -- `nil`
    /// cuando no se esta sincronizando. `estimatedSecondsRemaining` sale
    /// del ritmo REAL de esta misma sesion de sync (bytes/segundo no
    /// hace falta, con archivos copiados/segundo alcanza) -- con pocos
    /// archivos el numero es poco preciso, pero es honesto (viene de una
    /// medicion real) en vez de un estimado inventado.
    @Published private(set) var syncProgress: SyncProgress?

    private let enricher: LibraryEnricher
    private let preferences: AppPreferences
    private var cancellables: Set<AnyCancellable> = []

    /// Carpeta de la biblioteca Aura (D-180): raiz elegida en Ajustes.
    /// Todo lo que entra a la biblioteca se COPIA, organizada por tipo
    /// (D-228: `Música/<Artista>/<Álbum>/`, `Imágenes/<Colección>/`,
    /// `Videos/<Categoría>/` -- los archivos del usuario jamas se
    /// tocan), lo preparado vive en `.preparados/` (antes era un
    /// directorio temporal que macOS podia purgar), y el catalogo
    /// (`biblioteca.json`) hace que la biblioteca sobreviva reinicios de
    /// la app -- con o sin iPod.
    private(set) var libraryRoot: URL
    private var stagingDirectory: URL { libraryRoot.appendingPathComponent(PersistedLibrary.preparedDirName, isDirectory: true) }
    private var coversDirectory: URL { libraryRoot.appendingPathComponent(PersistedLibrary.coversDirName, isDirectory: true) }
    private var musicDirectory: URL { libraryRoot.appendingPathComponent(PersistedLibrary.musicDirName, isDirectory: true) }
    private var imagesDirectory: URL { libraryRoot.appendingPathComponent(PersistedLibrary.imagesDirName, isDirectory: true) }
    private var videosDirectory: URL { libraryRoot.appendingPathComponent(PersistedLibrary.videosDirName, isDirectory: true) }
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
        migrateLegacyLibraryLayoutIfNeeded()
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

    /// D-228: el item SIEMPRE arranca apuntando al archivo original de
    /// donde vino -- ya no se copia aca. Con `copyMediaIntoLibrary`
    /// activo, la copia a la biblioteca (organizada por artista/album o
    /// categoria) pasa a `process(itemAt:)`, DESPUES de resolver esa
    /// metadata/categoria (ver comentario ahi): antes de eso todavia no
    /// se sabe en que carpeta va a terminar. Con el ajuste apagado
    /// (encargo del dueño, 2026-08-13), el item sigue referenciando el
    /// original para siempre, sin copiarlo -- `relativePath(of:)` ya
    /// sabe guardar una ruta absoluta en el catalogo cuando el archivo
    /// no vive dentro de la biblioteca (ver `loadCatalog`, que la
    /// reconoce de vuelta).
    func addDroppedFiles(_ urls: [URL]) {
        ensureLibraryStructure()
        let new = urls
            .filter { LibraryItemKind.classify(url: $0) != .unsupported }
            .map { LibraryItem(sourceURL: $0) }
        items.append(contentsOf: new)
        persistCatalog()
    }

    /// Resuelve un destino sin colisiones para `relativePath` (creando
    /// las carpetas intermedias que hagan falta) -- compartido por
    /// `copyIntoLibrary`/`moveIntoLibrary` de abajo, que solo difieren
    /// en si copian o mueven. Mismo esquema de sufijo numerico de
    /// siempre ("nombre 2.ext", "nombre 3.ext"...), ahora dentro de la
    /// carpeta final del item en vez de una unica carpeta plana
    /// compartida por toda la biblioteca.
    private func resolveNonCollidingDestination(relativePath: String) throws -> URL {
        let fm = FileManager.default
        let destinationURL = libraryRoot.appendingPathComponent(relativePath)
        let destinationDir = destinationURL.deletingLastPathComponent()
        try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        let base = destinationURL.deletingPathExtension().lastPathComponent
        let ext = destinationURL.pathExtension
        var candidate = destinationURL
        var counter = 2
        while fm.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = destinationDir.appendingPathComponent(name)
            counter += 1
        }
        return candidate
    }

    /// Copia `url` a su carpeta final en la biblioteca (D-228) --
    /// reemplaza el viejo `copyToOriginals`, que copiaba TODO a una
    /// unica carpeta plana ANTES de saber tipo/artista/album/categoria.
    private func copyIntoLibrary(_ url: URL, relativePath: String) throws -> URL {
        let destination = try resolveNonCollidingDestination(relativePath: relativePath)
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    /// Variante que MUEVE en vez de copiar -- solo para la migracion del
    /// esquema viejo (D-228, ver `migrateLegacyLibraryLayoutIfNeeded`),
    /// que reubica archivos que YA estaban en la biblioteca (copiarlos
    /// dejaria un duplicado huerfano atras).
    private func moveIntoLibrary(_ url: URL, relativePath: String) throws -> URL {
        let destination = try resolveNonCollidingDestination(relativePath: relativePath)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }

    /// Copia el original a su carpeta final (Música/Imágenes/Videos,
    /// D-228) la PRIMERA vez que el item se procesa -- nunca en
    /// `addDroppedFiles`, porque recien aca existe la metadata/
    /// categoria que decide esa carpeta. El guard de "ya esta adentro"
    /// evita que reprocesar un item ya copiado (`applyReview`/
    /// `reenrichOnline`, que vuelven a llamar a `prepareMusic` por
    /// `process`) lo copie de nuevo o lo duplique. Un fallo de copia
    /// (disco lleno, permisos) no aborta el procesamiento: el item
    /// sigue preparandose/sincronizandose desde el original externo,
    /// solo se queda sin copia local (mismo estilo de mensaje que el
    /// `catch` que tenia `addDroppedFiles` antes de este cambio).
    private func copyIntoLibraryIfNeeded(itemAt index: Int) {
        guard preferences.copyMediaIntoLibrary, !isInsideLibrary(items[index].sourceURL) else { return }
        let item = items[index]
        let fileName = item.sourceURL.lastPathComponent
        let relativePath = LibrarySync.localLibraryRelativePath(
            for: item, kind: item.kind, fileName: fileName,
            organizePhotosByCategory: preferences.organizePhotosByCategory,
            organizeVideosByCategory: preferences.organizeVideosByCategory)
        do {
            items[index].sourceURL = try copyIntoLibrary(item.sourceURL, relativePath: relativePath)
        } catch {
            lastError = "No se pudo copiar \(fileName) a la biblioteca: \(error.localizedDescription)"
        }
    }

    private func isInsideLibrary(_ url: URL) -> Bool {
        let rootPath = libraryRoot.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path.hasPrefix(rootPath + "/")
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
                                                      lyrics: preferences.fetchSyncedLyrics,
                                                      coverArtOrder: preferences.coverArtProviderOrder,
                                                      deezerEnabled: preferences.deezerEnabled)
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
                // D-228: recien aca existe la metadata que decide la
                // carpeta (Música/<Artista>/<Álbum>/) -- por eso la copia
                // a la biblioteca pasa por aca y no por `addDroppedFiles`.
                copyIntoLibraryIfNeeded(itemAt: index)
                items[index].preparedURL = try prepareMusic(item: items[index], metadata: metadata)
                items[index].status = metadata.isComplete ? .ready : .needsReview

            case .video:
                items[index].status = .transcoding(progress: 0)
                let transcoder = try FFmpegTranscoder()
                let duration = try? FFmpegTranscoder.probeDurationSeconds(of: item.sourceURL, ffmpegURL: transcoder.ffmpegURL)
                if items[index].category == nil {
                    items[index].category = MediaCategoryHeuristics.classifyVideo(durationSeconds: duration ?? nil).displayName
                }
                items[index].metadata = TrackMetadata(durationSeconds: duration ?? nil)
                // D-228: la categoria ya esta resuelta -- copia a
                // Videos/<Categoría>/ (o Videos/ plano si el ajuste esta
                // apagado) antes de transcodificar.
                copyIntoLibraryIfNeeded(itemAt: index)
                let sourceURL = items[index].sourceURL
                let output = stagingDirectory.appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent + ".mpg")
                /// El callback de ffmpeg corre en el hilo de lectura del
                /// pipe (readabilityHandler), no en el MainActor -- hay
                /// que saltar de vuelta explicitamente para tocar
                /// `items`, que ObservableObject espera mutar solo desde
                /// el actor principal.
                try transcoder.transcode(input: sourceURL, output: output) { fraction in
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
                // D-228: la coleccion ya esta resuelta -- copia a
                // Imágenes/<Colección>/ (o Imágenes/ plano si el ajuste
                // esta apagado) antes de redimensionar.
                copyIntoLibraryIfNeeded(itemAt: index)
                let sourceURL = items[index].sourceURL
                let output = stagingDirectory.appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent + ".jpg")
                try ImageResizer.resizeToLCDOptimal(sourceURL: sourceURL, destinationURL: output,
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
                composer: metadata.composer,
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

    /// Correccion manual de la categoria/coleccion sugerida (foto: una
    /// de `AppPreferences.photoCollections`; video: uno de los 3
    /// nombres fijos de `MediaCategory`) desde la vista de biblioteca
    /// (Fase 1B) -- la heuristica automatica de `MediaCategoryClassifier`/
    /// `MediaCategoryHeuristics` es solo un punto de partida.
    func setCategory(_ category: String, forItem id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].category = category
        persistCatalog()
    }

    // MARK: - Menu contextual de la tabla de biblioteca (D-198)

    /// Quita items de la biblioteca -- borra tambien lo que Aura Studio
    /// escribio para ellos (`.preparados/`/`.portadas/`, y la copia
    /// dentro de `Música`/`Imágenes`/`Videos` si `copyMediaIntoLibrary`
    /// copio el archivo) para no dejar huerfanos.
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

    /// Calificacion de 0 a 5 estrellas (D-199), editable desde "Más
    /// información..." -- `nil` la borra (distinto de 0 estrellas).
    func setRating(_ rating: Int?, forItem id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].kind == .music else { return }
        var metadata = items[index].metadata ?? TrackMetadata()
        metadata.rating = rating.map { max(0, min(5, $0)) }
        items[index].metadata = metadata
        items[index].preparedURL = try? prepareMusic(item: items[index], metadata: metadata)
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

    /// D-218: aplica `BatchMediaInfoView` sobre varias canciones a la
    /// vez -- solo toca los campos que `changes` trae con valor real
    /// (`nil` = no tocar), nunca el título ni el numero de pista (esos
    /// ni siquiera son parte de `BatchMetadataChanges`, ver ese tipo).
    func applyBatchEdit(ids: Set<UUID>, changes: BatchMetadataChanges) {
        guard !changes.isEmpty else { return }
        for id in ids {
            guard let index = items.firstIndex(where: { $0.id == id }), items[index].kind == .music else { continue }
            var metadata = items[index].metadata ?? TrackMetadata()
            if let artist = changes.artist { metadata.artist = artist }
            if let album = changes.album { metadata.album = album }
            if let albumArtist = changes.albumArtist { metadata.albumArtist = albumArtist }
            if let year = changes.year { metadata.year = year }
            if let genre = changes.genre { metadata.genre = genre }
            if let composer = changes.composer { metadata.composer = composer }
            if let rating = changes.rating { metadata.rating = rating }
            items[index].metadata = metadata
            items[index].preparedURL = try? prepareMusic(item: items[index], metadata: metadata)
            items[index].status = metadata.isComplete ? .ready : .needsReview
        }
        persistCatalog()
    }

    /// "Buscar información en línea"/"Buscar letra" del menu contextual
    /// -- reintenta contra MusicBrainz/Cover Art Archive/fanart.tv/
    /// Deezer/LRCLIB partiendo de la metadata YA resuelta
    /// (`LibraryEnricher.reenrich`, no `enrich`), asi que no pisa una
    /// correccion manual ya hecha. Solo aplica a musica.
    ///
    /// D-203: publica `lastEnrichmentSummary`/`lastError` con lo que de
    /// verdad paso -- antes esto no daba ningun resultado visible en
    /// pantalla, asi que un fallo silencioso (o un exito que no
    /// encontraba nada porque el archivo ya tenia titulo/artista) se
    /// veian exactamente igual: nada.
    func reenrichOnline(ids: Set<UUID>, fetchAlbumInfo: Bool, fetchLyrics: Bool) async {
        var found = 0
        var withoutResult = 0
        var networkErrors: [String] = []
        var attempted = 0

        for id in ids {
            guard let index = items.firstIndex(where: { $0.id == id }), items[index].kind == .music else { continue }
            attempted += 1
            let item = items[index]
            let current = item.metadata ?? TrackMetadata()
            let (updated, outcome) = await enricher.reenrich(
                item: item, currentMetadata: current,
                fetchAlbumInfo: fetchAlbumInfo, fetchLyrics: fetchLyrics,
                coverArtOrder: preferences.coverArtProviderOrder,
                deezerEnabled: preferences.deezerEnabled)
            guard index < items.count else { continue }
            items[index].metadata = updated
            items[index].preparedURL = try? prepareMusic(item: items[index], metadata: updated)
            items[index].status = updated.isComplete ? .ready : .needsReview

            if let message = outcome.networkErrorMessage {
                networkErrors.append(message)
            } else if outcome.albumInfoFound || outcome.lyricsFound {
                found += 1
            } else {
                withoutResult += 1
            }
        }
        persistCatalog()

        if attempted == 0 { return }
        if !networkErrors.isEmpty {
            lastError = "No se pudo completar la busqueda para \(networkErrors.count) de \(attempted) cancion(es): \(networkErrors[0])"
        }
        lastEnrichmentSummary = found == 0
            ? "No se encontro informacion nueva para ninguna de las \(attempted) cancion(es) seleccionadas."
            : "Se encontro informacion nueva para \(found) de \(attempted) cancion(es)."
    }

    /// D-217: `LibrarySync.sync()` es sincrona (copia archivos con
    /// `FileManager` uno por uno) -- si corriera directo en este metodo
    /// `@MainActor`, bloquearia el hilo principal de punta a punta y la
    /// barra de progreso nunca tendria oportunidad de repintarse hasta
    /// que todo terminara (el mismo problema, en el fondo, que D-034 ya
    /// encontro con otro callback de progreso). Se corre en un
    /// `Task.detached` -- `LibrarySync`/`LibraryItem`/`Playlist` son
    /// structs Sendable de por si -- y cada tick de `onProgress` salta
    /// de vuelta al MainActor para actualizar `syncProgress`.
    func sync(toVolumeAt volumeRoot: URL) async {
        let readyItems = items.filter { $0.status == .ready }
        let playlistsSnapshot = playlists
        let coverArtPolicy = preferences.coverArtPolicy
        let musicOrganization = preferences.musicOrganization
        let musicFilenameFormat = preferences.musicFilenameFormat
        let startedAt = Date()
        syncProgress = nil

        do {
            let sync = LibrarySync(volumeRoot: volumeRoot)
            let result = try await Task.detached(priority: .userInitiated) { [weak self] in
                try sync.sync(items: readyItems, playlists: playlistsSnapshot,
                              coverArtPolicy: coverArtPolicy,
                              musicOrganization: musicOrganization,
                              musicFilenameFormat: musicFilenameFormat) { copied, total in
                    guard let self else { return }
                    let elapsed = Date().timeIntervalSince(startedAt)
                    let remaining: Double? = (copied > 0 && copied < total)
                        ? (elapsed / Double(copied)) * Double(total - copied)
                        : nil
                    Task { @MainActor in
                        self.syncProgress = SyncProgress(copied: copied, total: total, estimatedSecondsRemaining: remaining)
                    }
                }
            }.value
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
        syncProgress = nil
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
        for dir in [libraryRoot, musicDirectory, imagesDirectory, videosDirectory, stagingDirectory, coversDirectory] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func switchLibraryFolder(to newPath: String) {
        libraryRoot = URL(fileURLWithPath: newPath, isDirectory: true)
        ensureLibraryStructure()
        migrateLegacyLibraryLayoutIfNeeded()
        items = []
        playlists = []
        loadCatalog()
    }

    // MARK: - Migracion del esquema viejo (D-228)

    /// Bibliotecas armadas ANTES de D-228 tienen todo plano en
    /// `Originales/`/`Preparados/`/`Portadas/`. Se corre UNA SOLA VEZ,
    /// antes de que el resto de la app empiece a leer el catalogo
    /// (`ensureLibraryStructure` ya creo las carpetas nuevas para
    /// cuando esto corre), para que nunca convivan las dos estructuras.
    /// Idempotente (si ninguna de las tres carpetas viejas existe, no
    /// hace nada -- seguro de llamar en cada arranque) y best-effort de
    /// punta a punta: nada de esto deberia poder tirar la app abajo por
    /// una biblioteca vieja con algun archivo raro.
    private func migrateLegacyLibraryLayoutIfNeeded() {
        let fm = FileManager.default
        let legacyOriginals = libraryRoot.appendingPathComponent(PersistedLibrary.legacyOriginalsDirName, isDirectory: true)
        let legacyPrepared = libraryRoot.appendingPathComponent(PersistedLibrary.legacyPreparedDirName, isDirectory: true)
        let legacyCovers = libraryRoot.appendingPathComponent(PersistedLibrary.legacyCoversDirName, isDirectory: true)
        guard fm.fileExists(atPath: legacyOriginals.path)
            || fm.fileExists(atPath: legacyPrepared.path)
            || fm.fileExists(atPath: legacyCovers.path) else { return }

        // Se lee/escribe el `PersistedLibrary` crudo directo del disco
        // (no `self.items`, que todavia esta vacio a esta altura --
        // `loadCatalog()` corre DESPUES de esto) para no duplicar la
        // logica de lectura/escritura del catalogo.
        guard let data = try? Data(contentsOf: catalogURL),
              var persisted = try? JSONDecoder().decode(PersistedLibrary.self, from: data) else { return }

        var changed = false
        let originalsPrefix = "\(PersistedLibrary.legacyOriginalsDirName)/"
        let preparedPrefix = "\(PersistedLibrary.legacyPreparedDirName)/"
        let coversPrefix = "\(PersistedLibrary.legacyCoversDirName)/"

        for index in persisted.items.indices {
            let item = persisted.items[index]

            if item.sourceRelativePath.hasPrefix(originalsPrefix),
               let newPath = migrateLegacySourceFile(item) {
                persisted.items[index].sourceRelativePath = newPath
                changed = true
            }

            if let prepared = item.preparedRelativePath, prepared.hasPrefix(preparedPrefix) {
                let suffix = String(prepared.dropFirst(preparedPrefix.count))
                let newRelative = "\(PersistedLibrary.preparedDirName)/\(suffix)"
                if moveLegacyFlatFile(fromRelative: prepared, toRelative: newRelative) {
                    persisted.items[index].preparedRelativePath = newRelative
                    changed = true
                }
            }

            if let cover = item.coverRelativePath, cover.hasPrefix(coversPrefix) {
                let suffix = String(cover.dropFirst(coversPrefix.count))
                let newRelative = "\(PersistedLibrary.coversDirName)/\(suffix)"
                if moveLegacyFlatFile(fromRelative: cover, toRelative: newRelative) {
                    persisted.items[index].coverRelativePath = newRelative
                    changed = true
                }
            }
        }

        // Best-effort: si quedo algo adentro (p.ej. un `.DS_Store` que
        // Finder dejo caer), se deja la carpeta en paz -- no es un
        // `rm -rf`, es "borrar solo si ya esta vacia".
        removeLegacyDirectoryIfEmpty(legacyOriginals)
        removeLegacyDirectoryIfEmpty(legacyPrepared)
        removeLegacyDirectoryIfEmpty(legacyCovers)

        guard changed else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(persisted) {
            try? data.write(to: catalogURL, options: .atomic)
        }
    }

    /// Mueve el original de un item (`Originales/...` viejo) a su
    /// carpeta nueva por tipo/artista/album/categoria -- misma logica
    /// de ruta que la copia en vivo (`LibrarySync.
    /// localLibraryRelativePath`), pero con la metadata/categoria YA
    /// resuelta que trae el catalogo persistido, sin re-clasificar
    /// nada. `nil` si el archivo de origen ya no esta ahi o algo falla
    /// al moverlo -- el item se deja tal cual esta (se reintenta en el
    /// proximo arranque, mientras `Originales/` siga existiendo).
    private func migrateLegacySourceFile(_ persistedItem: PersistedLibraryItem) -> String? {
        let fm = FileManager.default
        let oldURL = libraryRoot.appendingPathComponent(persistedItem.sourceRelativePath)
        guard fm.fileExists(atPath: oldURL.path) else { return nil }

        let kind = LibraryPersistenceMapper.liveKind(persistedItem.kind)
        let category = persistedItem.category.map(LibraryPersistenceMapper.liveCategory)
        let tempItem = LibraryItem(
            id: persistedItem.id, sourceURL: oldURL, kind: kind, status: .queued,
            metadata: LibraryPersistenceMapper.liveMetadata(persistedItem.metadata, coverArtData: nil),
            preparedURL: nil, category: category)

        let relative = LibrarySync.localLibraryRelativePath(
            for: tempItem, kind: kind, fileName: oldURL.lastPathComponent,
            organizePhotosByCategory: preferences.organizePhotosByCategory,
            organizeVideosByCategory: preferences.organizeVideosByCategory)

        guard let newURL = try? moveIntoLibrary(oldURL, relativePath: relative) else { return nil }
        return relativePath(of: newURL)
    }

    /// `.preparados/`/`.portadas/` son renombres planos de `Preparados/`/
    /// `Portadas/` -- sin reorganizar nada adentro, a diferencia de
    /// `Originales/` -- asi que no hace falta resolver colisiones, es
    /// un mkdir + move directo. `false` si el origen no existe o el
    /// move falla (p.ej. ya habia algo con ese nombre en el destino).
    private func moveLegacyFlatFile(fromRelative old: String, toRelative new: String) -> Bool {
        let fm = FileManager.default
        let oldURL = libraryRoot.appendingPathComponent(old)
        guard fm.fileExists(atPath: oldURL.path) else { return false }
        let newURL = libraryRoot.appendingPathComponent(new)
        guard (try? fm.createDirectory(at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)) != nil else { return false }
        return (try? fm.moveItem(at: oldURL, to: newURL)) != nil
    }

    private func removeLegacyDirectoryIfEmpty(_ url: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path),
              let contents = try? fm.contentsOfDirectory(atPath: url.path),
              contents.isEmpty else { return }
        try? fm.removeItem(at: url)
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
                category: item.category
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
            // Si el archivo (la copia en Música/Imágenes/Videos, o el
            // original referenciado sin copiar) ya no existe, el item se
            // omite en silencio: no hay nada que preparar ni sincronizar
            // desde un archivo ausente.
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
                // D-228: catalogos viejos guardaban `MediaCategory.
                // rawValue` -- `liveCategory` traduce esos valores
                // conocidos al string de display nuevo y deja pasar
                // cualquier otro tal cual (ver su doc-comment).
                category: p.category.map(LibraryPersistenceMapper.liveCategory)
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
