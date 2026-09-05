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
    /// PLAN-studio-rendimiento.md Fase 4 punto 1: fuente única de verdad
    /// de qué corre en segundo plano ahora mismo. Primera integración
    /// real, en esta ronda: `reenrichOnline` (abajo). El resto de las
    /// operaciones largas listadas en el plan (edición en lote, aplicar
    /// carátula, fotos de artista, pósters, carátulas recomendadas,
    /// eliminar, verificar dispositivo, carga inicial) TODAVÍA usan sus
    /// booleanos sueltos de siempre -- migrarlas es trabajo aparte,
    /// documentado como pendiente en DECISIONS.md (ST-156).
    let taskCenter = BackgroundTaskCenter()

    @Published private(set) var items: [LibraryItem] = []

    /// PLAN-studio-rendimiento.md Fase 0: inyecta un catálogo ya armado
    /// (ítems `.ready`, con metadata) sin pasar por `addDroppedFiles`/
    /// `process(itemAt:)` -- ese pipeline copia el archivo, corre
    /// `ffmpeg` y espera por ítem, que es exactamente el costo que NO se
    /// quiere medir en las pruebas de rendimiento de la biblioteca ya
    /// cargada (selección, orden, `persistCatalog`). Nunca se llama
    /// desde la UI.
    func replaceItemsForPerformanceTesting(_ newItems: [LibraryItem]) {
        items = newItems
    }
    @Published private(set) var isProcessing = false
    @Published private(set) var lastSyncSummary: String?
    /// D-203: resultado de "Buscar información en línea"/"Buscar letra"
    /// (ver `reenrichOnline`) -- antes esta accion no dejaba ningun
    /// rastro visible en la interfaz.
    @Published private(set) var lastEnrichmentSummary: String?
    /// ST-032: "Buscar fotos de artistas" en curso (deshabilita el
    /// boton, muestra el spinner en ArtistsView).
    @Published private(set) var isFetchingArtistImages = false
    /// Cuantas canciones de la biblioteca YA CARGADA podrian beneficiarse
    /// de `rereadLocalTags` -- `nil` si no corresponde ofrecerlo (ya se
    /// ofrecio antes, o no hay musica). PLAN-studio-ux.md §2/P1: se
    /// ofrece UNA sola vez por instalacion de Aura Studio, la primera
    /// vez que se carga un catalogo con musica despues de este cambio.
    @Published private(set) var legacyMetadataRereadOfferCount: Int?
    /// ST-012: cuantas entradas de Imagenes parecen caratulas de album
    /// (ver `coverContaminationCandidates()`); nil = nada que ofrecer.
    @Published private(set) var coverContaminationOfferCount: Int?
    /// PLAN-studio-rendimiento.md Fase 1: la selección de la vista de
    /// biblioteca activa vivía acá (`selectionForSync`) -- un `@Published`
    /// de este ViewModel, que `ContentView` observa entero, así que
    /// publicar la selección en cada clic re-renderizaba toda la ventana
    /// (diagnóstico §0.1). Se movió a `SelectionStore`, chico y aparte,
    /// observado solo por quien de verdad consume la selección
    /// (`DeviceGeneralView`, `AlbumsView`, `MoviesView`).
    @Published var lastError: String?
    @Published private(set) var playlists: [Playlist] = []
    /// D-217: progreso de un `sync(toVolumeAt:)` en curso -- `nil`
    /// cuando no se esta sincronizando. `estimatedSecondsRemaining` sale
    /// del ritmo REAL de esta misma sesion de sync (bytes/segundo no
    /// hace falta, con archivos copiados/segundo alcanza) -- con pocos
    /// archivos el numero es poco preciso, pero es honesto (viene de una
    /// medicion real) en vez de un estimado inventado.
    @Published private(set) var syncProgress: SyncProgress?
    /// Comparación de la biblioteca contra el iPod conectado
    /// (PLAN-general-sync.md §4) -- `nil` sin dispositivo o antes de la
    /// primera verificación. Se recalcula al conectar, al pulsar
    /// "Actualizar", y al terminar (o cancelar) un sync -- nunca decide
    /// sobre un índice viejo (§4.2: "se recalcula justo antes, siempre").
    @Published private(set) var deviceSyncIndex: DeviceSyncIndex?
    /// `true` mientras `verifyDevice` recorre `Music/`/`Videos/`/
    /// `Photos/`/`Playlists/` del dispositivo -- es la única operación
    /// de esta pantalla que hace I/O real de verificación, así que
    /// tiene su propio indicador ("Verificando el iPod…" en
    /// `DeviceActivityBar`).
    @Published private(set) var isVerifyingDevice = false

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
    private(set) var libraryRoot: URL {
        didSet { artistImages = ArtistImageStore(libraryRoot: libraryRoot) }
    }
    /// ST-031: fotos de artista de la biblioteca actual (`.portadas/
    /// artistas/`). Se recrea al cambiar de carpeta.
    private(set) var artistImages: ArtistImageStore

    /// ST-141: version de `coversNormalized` que trae el catalogo en
    /// disco. `nil` = biblioteca anterior al recorte cuadrado.
    private var coversNormalizedVersion: Int?
    /// Progreso de la migracion de caratulas mientras corre; `nil`
    /// cuando no hay ninguna (que es casi siempre). Lo dibuja
    /// `ContentView` sobre la barra de estado.
    @Published private(set) var coverNormalization: CoverNormalizationProgress?
    private var coverNormalizationTask: Task<Void, Never>?
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
        let root = libraryRoot ?? URL(fileURLWithPath: prefs.libraryFolderPath, isDirectory: true)
        self.libraryRoot = root
        self.artistImages = ArtistImageStore(libraryRoot: root)
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
    ///
    /// Encargo del dueño (2026-08-14): soltar una CARPETA (no un archivo
    /// suelto) tambien funciona -- `DroppedURLExpander` la reemplaza por
    /// la lista plana de archivos que contiene (cualquier profundidad)
    /// ANTES de que corra el filtro de siempre por extension, asi que el
    /// resto de esta funcion (y de `process(itemAt:)`) no se entera de
    /// que el origen fue una carpeta, cada archivo adentro sigue
    /// exactamente el mismo camino que si se hubiera soltado solo. Con
    /// `copyMediaIntoLibrary` apagado, ademas se registra la carpeta
    /// soltada como "biblioteca vinculada" (ver
    /// `AppPreferences.linkedLibraryFolders`) -- con el ajuste prendido
    /// no hace falta, porque los archivos ya terminan copiados DENTRO de
    /// la biblioteca de Aura, no hay una carpeta externa que recordar.
    ///
    /// ST-012 (contrato `docs/contracts/library-layout-v1.md` SS2):
    /// ingesta por MODULO, no por extension. `into` es la seccion que
    /// recibio el drop (Musica/Video/Fotos): solo se importan archivos
    /// de ESE tipo -- un `cover.jpg` que venia dentro del album no es una
    /// foto, es la caratula del album (asset asociado, ver
    /// `LocalTagReader.readTag`), y un video soltado en Musica no se
    /// cuela en Videos por la puerta de atras. Con `into: nil` (p. ej. la
    /// reimportacion desde el iPod, `ForeignContentSheet`) se importa de
    /// todo, pero las imagenes que son caratulas (`CoverArtAssets`) igual
    /// se quedan afuera de Imagenes.
    /// `category`/`photoAlbum` (PLAN-biblioteca-medios-v2.md §3.2/§3.3):
    /// la subsección de la barra lateral (o la hoja de importación) ya
    /// resolvió la categoría/álbum ANTES de llamar aquí -- se asignan al
    /// item recién creado para que `process(itemAt:)` los respete (su
    /// heurística automática solo corre cuando `category == nil`).
    func addDroppedFiles(_ urls: [URL], into target: LibraryItemKind? = nil,
                          category: String? = nil, photoAlbum: String? = nil) {
        ensureLibraryStructure()
        let expandedURLs = DroppedURLExpander.expand(urls)
        let new = Self.importableURLs(from: expandedURLs, into: target)
            .map { url -> LibraryItem in
                var item = LibraryItem(sourceURL: url)
                item.category = category
                item.photoAlbum = photoAlbum
                return item
            }
        items.append(contentsOf: new)

        if !preferences.copyMediaIntoLibrary {
            for url in urls where DroppedURLExpander.isDirectory(url) {
                preferences.addLinkedLibraryFolder(url)
            }
        }

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

    /// PLAN-sync-media-hardening.md PARTE 2A: `stagingDirectory`
    /// (`.preparados/`) es una unica carpeta PLANA compartida por toda
    /// la biblioteca -- dos fotos con el mismo nombre base de carpetas
    /// distintas (dos `IMG_1.jpg`, camaras distintas) se pisaban en
    /// silencio, y lo mismo un poster de video vs. una foto homonima.
    /// Mismo esquema de sufijo que `resolveNonCollidingDestination`
    /// ("nombre 2.ext", "nombre 3.ext"...), pero con una diferencia
    /// clave: si `existingPreparedURL` (el `preparedURL` que este MISMO
    /// item ya tenia de una pasada anterior) sigue existiendo en disco,
    /// se reutiliza tal cual -- reprocesar un item (p.ej. cambiar la
    /// calidad de foto y volver a soltar) tiene que sobrescribir su
    /// propio preparado en el mismo lugar, no acumular " 2", " 3" cada
    /// vez que se reprocesa.
    private func resolveNonCollidingStagingDestination(existingPreparedURL: URL?, baseName: String, ext: String) -> URL {
        let fm = FileManager.default
        if let existingPreparedURL, fm.fileExists(atPath: existingPreparedURL.path) {
            return existingPreparedURL
        }
        var candidate = stagingDirectory.appendingPathComponent(ext.isEmpty ? baseName : "\(baseName).\(ext)")
        var counter = 2
        while fm.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(baseName) \(counter)" : "\(baseName) \(counter).\(ext)"
            candidate = stagingDirectory.appendingPathComponent(name)
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
                let info = try? FFmpegTranscoder.probeVideoInfo(of: item.sourceURL, ffmpegURL: transcoder.ffmpegURL)
                let duration = info?.duration
                // PLAN-biblioteca-medios-v2.md §3.4, decisión C: un
                // nombre con SxxEyy/1x02 es señal suficiente para
                // clasificar como Series sola -- D-228 solo descartó la
                // heurística por DURACIÓN, nunca un patrón explícito
                // como este.
                let parsedTitle = VideoTitleParser.parse(item.sourceURL.deletingPathExtension().lastPathComponent)
                if items[index].category == nil {
                    items[index].category = parsedTitle.isEpisode
                        ? MediaCategory.series.displayName
                        : MediaCategoryHeuristics.classifyVideo(durationSeconds: duration ?? nil).displayName
                }
                if parsedTitle.isEpisode,
                   items[index].category == MediaCategory.series.displayNameSpanish
                    || items[index].category == MediaCategory.series.displayNameEnglish,
                   let seriesName = parsedTitle.seriesName, let season = parsedTitle.season, let episode = parsedTitle.episode {
                    items[index].seriesName = seriesName
                    items[index].season = season
                    items[index].episode = episode
                }
                items[index].metadata = TrackMetadata(durationSeconds: duration ?? nil)
                // D-228: la categoria ya esta resuelta -- copia a
                // Videos/<Categoría>/ (o Videos/ plano si el ajuste esta
                // apagado) antes de transcodificar.
                copyIntoLibraryIfNeeded(itemAt: index)
                let sourceURL = items[index].sourceURL
                let output = resolveNonCollidingStagingDestination(
                    existingPreparedURL: items[index].preparedURL,
                    baseName: sourceURL.deletingPathExtension().lastPathComponent, ext: "mpg")
                /// El callback de ffmpeg corre en el hilo de lectura del
                /// pipe (readabilityHandler), no en el MainActor -- hay
                /// que saltar de vuelta explicitamente para tocar
                /// `items`, que ObservableObject espera mutar solo desde
                /// el actor principal.
                try transcoder.transcode(input: sourceURL, output: output, sourceFrameRate: info?.frameRate) { fraction in
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
                if let downloaded = items[index].metadata?.coverArtData,
                   (try? ImageResizer.resizeToLCDOptimal(data: downloaded, destinationURL: poster,
                                                         maxDimension: Self.videoPosterMaxDimension)) != nil {
                    // ST-033: el poster descargado (TMDB / fanart.tv)
                    // manda sobre el fotograma.
                } else {
                    try? transcoder.generatePoster(input: output, output: poster)
                }

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
                let output = resolveNonCollidingStagingDestination(
                    existingPreparedURL: items[index].preparedURL,
                    baseName: sourceURL.deletingPathExtension().lastPathComponent, ext: "jpg")
                try ImageResizer.resizeToLCDOptimal(sourceURL: sourceURL, destinationURL: output,
                                                     maxDimension: preferences.photoQuality.maxDimension)
                items[index].preparedURL = output
                items[index].status = .ready

            case .unsupported:
                items[index].status = .failed("Formato no soportado")
            }
        } catch FFmpegTranscoder.TranscodeError.ffmpegNotFound {
            // PLAN-sync-media-hardening.md PARTE 3A: mensaje CORTO por
            // fila -- el párrafo largo con instrucciones vive en el
            // banner persistente de la sección Video (`videoFFmpegBanner`
            // en `MediaSectionView`, condicionado por
            // `hasVideosWaitingOnFFmpeg`). Antes, cada video en cola
            // repetía el mismo párrafo largo, uno por fila.
            items[index].status = .failed(Self.ffmpegMissingRowMessage)
        } catch {
            items[index].status = .failed(error.localizedDescription)
        }
    }

    /// Mensaje corto para la celda de estado de una fila -- ver nota en
    /// el `catch` de `process(itemAt:)`.
    static let ffmpegMissingRowMessage = "Falta ffmpeg"

    /// `true` cuando hay al menos un video en cola que no se pudo
    /// procesar por falta de ffmpeg -- condiciona el banner persistente
    /// de la sección Video (en vez de un mensaje repetido por fila).
    var hasVideosWaitingOnFFmpeg: Bool {
        items.contains { $0.kind == .video && $0.status == .failed(Self.ffmpegMissingRowMessage) }
    }

    /// "Volver a intentar" del banner: reencola solo los videos que
    /// fallaron por falta de ffmpeg (nunca otros `.failed`, que pueden
    /// tener una causa real distinta) y vuelve a procesar.
    func retryVideosWaitingOnFFmpeg() async {
        for index in items.indices
        where items[index].kind == .video && items[index].status == .failed(Self.ffmpegMissingRowMessage) {
            items[index].status = .queued
        }
        await processAll()
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
    /// PLAN-studio-rendimiento.md Fase 4 paso 1: visibilidad `internal`
    /// (no `private`) a propósito, para que
    /// `LibraryFileWorkerEquivalenceTests` (`@testable import`) pueda
    /// compararla byte a byte contra `LibraryFileWorker.prepareMusic` --
    /// mismo criterio que `persistCatalog()` desde la Fase 0.
    func prepareMusic(item: LibraryItem, metadata: TrackMetadata) throws -> URL {
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
            // ST-142 / contrato v18: la carátula EMBEBIDA es el mismo JPEG
            // de 320×320 que `cover.jpg`. Embeber la copia de biblioteca
            // (~1000 px) metía casi un megabyte en cada canción para que
            // el aparato la reescalara a 130 de todos modos.
            let embedCover = preferences.coverArtPolicy == .perTrack
            let embedded = embedCover ? metadata.coverArtData.flatMap {
                try? ImageResizer.squareCrop(data: $0, side: LibrarySync.deviceCoverSide,
                                             quality: LibrarySync.deviceCoverQuality)
            } : nil
            let tag = ID3Writer.Tag(
                title: metadata.title, artist: metadata.artist, album: metadata.album,
                albumArtist: metadata.albumArtist, year: metadata.year, genre: metadata.genre,
                composer: metadata.composer,
                trackNumber: metadata.trackNumber,
                coverArtData: embedded
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
        items[index].metadataEditedByUser = true
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
        setCategory(category, forItems: [id])
    }

    /// Igual que `setCategory(_:forItem:)` pero para una selección
    /// múltiple completa de una vez (encargo del dueño, 2026-08-19:
    /// "organizar de una forma más cómoda la biblioteca" arrastrando o
    /// reasignando varios álbumes/películas/fotos a la vez).
    func setCategory(_ category: String, forItems ids: Set<UUID>) {
        for index in items.indices where ids.contains(items[index].id) {
            items[index].category = category
        }
        // PLAN-studio-rendimiento.md Fase 3 punto 1: varias reasignaciones
        // rápidas seguidas (arrastrar ítems uno a uno) coalescen en un
        // solo guardado real, fuera del hilo principal.
        schedulePersistCatalog()
    }

    /// Renombra un álbum de fotos completo (encargo del dueño,
    /// 2026-08-18: cuadrícula de álbumes "similar en uso al iPod
    /// Classic original") -- reescribe `photoAlbum` en todos los items
    /// del grupo. `newName` vacío o solo espacios equivale a
    /// `dissolvePhotoAlbum` (pasa a "Sin álbum").
    func renamePhotoAlbum(items ids: Set<UUID>, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        for index in items.indices where ids.contains(items[index].id) {
            items[index].photoAlbum = trimmed.isEmpty ? nil : trimmed
        }
        persistCatalog()
    }

    /// "Disolver álbum": las fotos vuelven al cajón "Sin álbum" de su
    /// colección -- nunca se borran ni cambian de categoría.
    func dissolvePhotoAlbum(items ids: Set<UUID>) {
        for index in items.indices where ids.contains(items[index].id) {
            items[index].photoAlbum = nil
        }
        persistCatalog()
    }

    /// PLAN-biblioteca-medios-v2.md §3.4: título/serie/temporada/
    /// episodio corregidos a mano desde el inspector de un video. A
    /// diferencia de `applyReview` (música), no hace falta volver a
    /// preparar el archivo -- el nombre de destino en el iPod se
    /// recalcula solo en el próximo `sync()` (`LibrarySync.
    /// destinationRelativePath`, que ya lee estos campos).
    func updateVideoInfo(id: UUID, title: String?, seriesName: String?, season: Int?, episode: Int?) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if items[index].metadata == nil { items[index].metadata = TrackMetadata() }
        items[index].metadata?.title = title
        items[index].seriesName = seriesName
        items[index].season = season
        items[index].episode = episode
        items[index].metadataEditedByUser = true
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
    /// Filtro de importacion (puro, testeable sin ViewModel): quita lo no
    /// soportado, aplica el modulo destino y descarta las caratulas.
    nonisolated static func importableURLs(from expandedURLs: [URL], into target: LibraryItemKind?) -> [URL] {
        let context = CoverArtAssets.DropContext(urls: expandedURLs)
        return expandedURLs.filter { url in
            // Encargo del dueño (reporte en hardware real): fotos que
            // "no se ven" en el iPod resultaron ser sidecars AppleDouble
            // de macOS ("._Nombre.jpg", el resource fork/xattrs que
            // macOS deja junto al archivo real al copiar a un volumen
            // sin esos atributos -- FAT32, exFAT, o un ZIP/USB de
            // origen). `LibraryItemKind.classify` solo mira la
            // extensión, así que ".jpg" los clasificaba como foto real
            // -- `DroppedURLExpander.filesInsideDirectory` los filtra
            // vía `.skipsHiddenFiles` SOLO cuando el drop expande una
            // carpeta; un archivo suelto arrastrado directo (o ya
            // visible por venir de un origen que no preservó la
            // bandera de oculto) llegaba aquí sin filtrar. Nunca son
            // contenido real del usuario -- se descartan siempre, sin
            // aviso (no hay nada que "recuperar" de un sidecar).
            if url.lastPathComponent.hasPrefix("._") { return false }
            let kind = LibraryItemKind.classify(url: url)
            guard kind != .unsupported else { return false }
            if let target, kind != target { return false }
            if kind == .photo,
               CoverArtAssets.isCoverAsset(url, context: context, droppedIntoPhotos: target == .photo) {
                return false
            }
            return true
        }
    }

    // MARK: - Migracion: caratulas que cayeron a Imagenes (ST-012)

    /// Una entrada de Imagenes que en realidad es una caratula de album
    /// importada por el filtro viejo (por extension). Evidencia, de mas a
    /// menos fuerte -- se muestra al usuario, que decide; nunca se quita
    /// nada solo (el costo de equivocarse es perder una foto personal).
    struct CoverContaminationCandidate: Identifiable, Equatable {
        enum Evidence: Equatable {
            /// Convive con una cancion/video de la biblioteca en el mismo
            /// directorio de origen, o ese directorio tiene audio/video.
            case sharesFolderWithMedia
            /// Solo el nombre (`cover.jpg`, `folder.jpg`...).
            case coverLikeNameOnly
        }
        let item: LibraryItem
        let evidence: Evidence
        var id: UUID { item.id }
        var strong: Bool { evidence == .sharesFolderWithMedia }
    }

    /// Candidatas ordenadas: primero las de evidencia fuerte. Criterio
    /// conservador: una imagen con EXIF de camara (categoria
    /// "Fotografias", `MediaCategoryClassifier`) nunca es candidata,
    /// aunque se llame `cover.jpg`.
    func coverContaminationCandidates() -> [CoverContaminationCandidate] {
        let context = CoverArtAssets.DropContext(urls: items.filter { $0.kind != .photo }.map(\.sourceURL))
        var out: [CoverContaminationCandidate] = []
        for item in items where item.kind == .photo {
            if item.category == "Fotografías" { continue }
            guard CoverArtAssets.hasCoverLikeName(item.sourceURL) else { continue }
            let dir = item.sourceURL.deletingLastPathComponent().standardizedFileURL.path
            let strong = context.audioDirectories.contains(dir)
                || CoverArtAssets.directoryContainsAudio(item.sourceURL.deletingLastPathComponent())
            out.append(CoverContaminationCandidate(item: item, evidence: strong ? .sharesFolderWithMedia : .coverLikeNameOnly))
        }
        return out.sorted { $0.strong && !$1.strong }
    }

    /// Se ofrece UNA vez por instalacion (mismo patron que el banner de
    /// relectura de metadatos): al arrancar la version corregida, si hay
    /// candidatas, `coverContaminationOfferCount` las anuncia en Fotos.
    private func evaluateCoverContaminationOffer() {
        guard !preferences.coverContaminationReviewShown else {
            coverContaminationOfferCount = nil
            return
        }
        let count = coverContaminationCandidates().count
        coverContaminationOfferCount = count > 0 ? count : nil
    }

    func dismissCoverContaminationOffer() {
        preferences.coverContaminationReviewShown = true
        coverContaminationOfferCount = nil
    }

    /// "Quitar de Imagenes": quita la ENTRADA de la biblioteca (y la copia
    /// interna de la biblioteca si la hubiera), nunca el archivo original
    /// del usuario -- `deleteItems` ya distingue eso.
    func removeFromImages(ids: Set<UUID>) {
        deleteItems(ids: ids)
        dismissCoverContaminationOffer()
    }

    func deleteItems(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let fm = FileManager.default
        let rootPath = libraryRoot.standardizedFileURL.path

        // ST-064: `.preparados/` es plano y se nombra por el nombre del
        // archivo de origen, así que dos elementos con el mismo nombre
        // (justo el caso de los duplicados que se eliminan desde
        // "Elementos similares") COMPARTEN el preparado. Borrar el de
        // uno dejaba al que se conserva en "Listo" apuntando a un
        // archivo inexistente -- el sync fallaba con "no se encuentra".
        // Solo se borra un preparado (y su .lrc) si ningún sobreviviente
        // lo sigue usando.
        let survivingPreparedPaths = Set(items.filter { !ids.contains($0.id) }
            .compactMap { $0.preparedURL?.standardizedFileURL.path })

        for id in ids {
            guard let item = items.first(where: { $0.id == id }) else { continue }
            if let prepared = item.preparedURL,
               !survivingPreparedPaths.contains(prepared.standardizedFileURL.path) {
                try? fm.removeItem(at: prepared)
                try? fm.removeItem(at: prepared.deletingPathExtension().appendingPathExtension("lrc"))
            }
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
        items[index].metadataEditedByUser = true
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
        // PLAN-studio-rendimiento.md Fase 3 punto 1: poner varias
        // estrellas seguidas (fila por fila) coalesce en un solo
        // guardado real, fuera del hilo principal -- diagnóstico §0.4,
        // el ejemplo textual del dueño de por qué se sentía el
        // congelamiento en ediciones individuales, no solo en lote.
        schedulePersistCatalog()
    }

    // MARK: - Posters de video (ST-033)

    /// Lado mayor del poster que viaja al iPod (`<video>.jpg` hermano):
    /// 640 px es el maximo que admite el firmware para imagenes (ver
    /// CONTRATO-firmware-studio.md, seccion de imagenes).
    static let videoPosterMaxDimension: CGFloat = 640

    @Published private(set) var isFetchingVideoPosters = false

    /// "Buscar póster en línea" sobre videos: TMDB resuelve el titulo (por
    /// la categoria del video: Películas → pelicula, Series → serie,
    /// Videos → ambas), fanart.tv aporta el poster curado si lo tiene,
    /// TMDB el suyo si no (`VideoArtworkResolver`). El poster queda como
    /// `coverArtData` del item (se persiste en `.portadas/` como las
    /// caratulas) y se escribe ya reducido junto al `.mpg` preparado, que
    /// es exactamente lo que `LibrarySync` copia al iPod. Sin key de
    /// TMDB no se puede buscar: se dice claro en `lastError`.
    func fetchVideoPosters(ids: Set<UUID>, resolver: VideoArtworkResolver? = nil) async {
        guard !isFetchingVideoPosters else { return }
        isFetchingVideoPosters = true
        defer { isFetchingVideoPosters = false }
        lastError = nil
        let resolver = resolver ?? VideoArtworkResolver()
        var found = 0
        var missing: [String] = []
        var missingKey = false
        for id in ids {
            guard let index = items.firstIndex(where: { $0.id == id }), items[index].kind == .video else { continue }
            let item = items[index]
            let rawTitle = item.metadata?.title ?? item.sourceURL.deletingPathExtension().lastPathComponent
            let kind: VideoArtworkResolver.Kind
            switch item.category {
            case MediaCategory.movies.displayName: kind = .movie
            case MediaCategory.series.displayName: kind = .series
            default: kind = .unknown
            }
            switch await resolver.resolve(rawTitle: rawTitle, kind: kind) {
            case .success(let result):
                var metadata = items[index].metadata ?? TrackMetadata()
                metadata.coverArtData = result.data
                if metadata.title == nil || metadata.title == rawTitle {
                    // Un titulo limpio de TMDB en vez del nombre de archivo
                    // crudo -- solo si el usuario no lo habia editado.
                    if !items[index].metadataEditedByUser { metadata.title = result.matchedTitle }
                }
                if metadata.year == nil { metadata.year = result.year }
                items[index].metadata = metadata
                writeVideoPoster(forItemAt: index)
                found += 1
            case .failure(.missingTMDBKey):
                missingKey = true
            case .failure:
                missing.append(rawTitle)
            }
            if missingKey { break }
        }
        if missingKey {
            lastError = "Para buscar pósters hace falta una API key de TMDB (gratuita). Agrégala en Ajustes › Servicios; con fanart.tv configurado además se usará su póster curado cuando exista."
        } else {
            var parts = ["Pósters: \(found) \(found == 1 ? "encontrado" : "encontrados")"]
            if !missing.isEmpty { parts.append("\(missing.count) sin resultado (\(missing.prefix(3).joined(separator: ", "))\(missing.count > 3 ? "…" : ""))") }
            lastEnrichmentSummary = parts.joined(separator: ", ") + "."
        }
        if found > 0 { persistCatalog() }
    }

    /// Escribe `<preparado>.jpg` desde `coverArtData` (JPEG baseline,
    /// lado mayor <= 640) si el video ya esta preparado; si no, se
    /// escribira al procesarlo (`process(itemAt:)`).
    private func writeVideoPoster(forItemAt index: Int) {
        guard let prepared = items[index].preparedURL, let data = items[index].metadata?.coverArtData else { return }
        let poster = prepared.deletingPathExtension().appendingPathExtension("jpg")
        do {
            try ImageResizer.resizeToLCDOptimal(data: data, destinationURL: poster, maxDimension: Self.videoPosterMaxDimension)
        } catch {
            lastError = "No se pudo guardar el póster de \(items[index].sourceURL.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// "Quitar póster" de un video: vuelve al fotograma de ffmpeg si se
    /// puede generar; si no, el video queda sin poster.
    func clearVideoPoster(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].kind == .video else { return }
        var metadata = items[index].metadata ?? TrackMetadata()
        metadata.coverArtData = nil
        items[index].metadata = metadata
        try? FileManager.default.removeItem(at: coversDirectory.appendingPathComponent("\(items[index].id.uuidString).jpg"))
        if let prepared = items[index].preparedURL {
            let poster = prepared.deletingPathExtension().appendingPathExtension("jpg")
            try? FileManager.default.removeItem(at: poster)
            if let transcoder = try? FFmpegTranscoder() {
                try? transcoder.generatePoster(input: prepared, output: poster)
            }
        }
        persistCatalog()
    }

    /// ST-032: descarga fotos de artista para los grupos que aun no la
    /// tienen (fanart.tv via MusicBrainz, Deezer de respaldo -- ver
    /// `ArtistImageResolver`). Secuencial a proposito: MusicBrainz limita
    /// a 1 pedido/s. Publica el resultado en `lastEnrichmentSummary`,
    /// igual que las demas busquedas en linea.
    func fetchArtistImages(for artists: [ArtistGroup], resolver: ArtistImageResolver? = nil) async {
        guard !isFetchingArtistImages else { return }
        isFetchingArtistImages = true
        defer { isFetchingArtistImages = false }
        let resolver = resolver ?? ArtistImageResolver(deezerEnabled: preferences.deezerEnabled)
        var found = 0
        var missing = 0
        var skipped = 0
        for artist in artists {
            if artist.isUnknown || artistImages.hasImage(forArtistKey: artist.id) {
                skipped += 1
                continue
            }
            if let result = await resolver.resolve(artistName: artist.name) {
                do {
                    try artistImages.save(result.data, forArtistKey: artist.id)
                    found += 1
                } catch {
                    lastError = "No se pudo guardar la foto de \(artist.name): \(error.localizedDescription)"
                }
            } else {
                missing += 1
            }
            objectWillChange.send()
        }
        if found == 0 && missing == 0 {
            lastEnrichmentSummary = skipped > 0
                ? "Todos los artistas seleccionados ya tienen foto."
                : "No hay artistas para buscar."
        } else {
            var parts = ["Fotos de artista: \(found) \(found == 1 ? "encontrada" : "encontradas")"]
            if missing > 0 { parts.append("\(missing) sin resultado") }
            if skipped > 0 { parts.append("\(skipped) ya \(skipped == 1 ? "tenía" : "tenían") foto") }
            lastEnrichmentSummary = parts.joined(separator: ", ") + "."
        }
    }

    /// Favorito (ST-030): marca/desmarca varias canciones de una vez
    /// (menu contextual, columna "Favorito"). No toca el archivo
    /// preparado -- vive solo en el catalogo -- asi que no hay que
    /// re-preparar nada; se persiste y listo.
    func setFavorite(_ favorite: Bool, forItems ids: Set<UUID>) {
        var changed = false
        for index in items.indices where ids.contains(items[index].id) && items[index].kind == .music {
            var metadata = items[index].metadata ?? TrackMetadata()
            guard metadata.isFavorite != favorite else { continue }
            metadata.isFavorite = favorite
            items[index].metadata = metadata
            changed = true
        }
        if changed { persistCatalog() }
    }

    func toggleFavorite(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        setFavorite(!(item.metadata?.isFavorite ?? false), forItems: [id])
    }

    /// "Eliminar carátula" del menu contextual -- solo tiene sentido
    /// para musica (fotos/video no tienen caratula embebida propia).
    func clearCoverArt(id: UUID) {
        clearCoverArt(ids: [id])
    }

    /// PLAN-studio-rendimiento.md Fase 3 punto 4: igual que
    /// `clearCoverArt(id:)` pero para una selección múltiple completa,
    /// con una sola llamada a `persistCatalog()` al final -- antes, el
    /// menú contextual sobre varias canciones llamaba
    /// `clearCoverArt(id:)` una vez POR ÍTEM (`MediaSectionView.
    /// clearCoverArtMenuAction` o equivalente), y cada una reescribía el
    /// catálogo entero.
    func clearCoverArt(ids: Set<UUID>) {
        for index in items.indices where ids.contains(items[index].id) && items[index].kind == .music {
            var metadata = items[index].metadata ?? TrackMetadata()
            metadata.coverArtData = nil
            items[index].metadata = metadata
            items[index].metadataEditedByUser = true
            items[index].preparedURL = try? prepareMusic(item: items[index], metadata: metadata)
            let coverURL = coversDirectory.appendingPathComponent("\(items[index].id.uuidString).jpg")
            try? FileManager.default.removeItem(at: coverURL)
        }
        persistCatalog()
    }

    /// ST-104: aplica una carátula a todas las canciones del álbum.
    ///
    /// Vuelve a preparar cada canción para que la imagen quede embebida
    /// en el archivo que viaja al iPod, no solo en el catálogo. Si
    /// re-preparar falla, se conserva el archivo preparado que ya había:
    /// es preferible una canción sincronizable con la tapa vieja que una
    /// que se quedó sin nada listo.
    ///
    /// `markEdited` distingue las dos formas de llegar acá (R2-3):
    /// - **La eligió el usuario** en el picker → `true`. Una decisión
    ///   suya la respeta todo enriquecimiento posterior.
    /// - **La aplicó la recomendación automática** → `false`. Blindar
    ///   una tapa que nadie miró dejaría al álbum con ella para siempre,
    ///   incluso cuando después aparezca una mejor. `metadataEditedByUser`
    ///   significa "el usuario lo decidió", no "algo lo escribió".
    /// PLAN-studio-rendimiento.md Fase 4 paso 3: `prepareMusic` corre en
    /// `fileWorker`, resultados en lotes -- mismo patrón que
    /// `applyBatchEdit` (paso 2). Si re-preparar una canción falla, se
    /// conserva el archivo preparado que ya había (`item.preparedURL`,
    /// no `nil`) -- regla original sin cambios: es preferible una
    /// canción sincronizable con la tapa vieja que una que se quedó sin
    /// nada listo.
    @discardableResult
    func applyAlbumCover(_ data: Data, toItems ids: Set<UUID>, markEdited: Bool = true) async -> Int {
        guard !data.isEmpty else { return 0 }
        // ST-141: la elegida a mano, la arrastrada y la recomendada
        // entran todas por aca, y todas quedan cuadradas. Se normaliza
        // UNA vez, no una por cancion: es la misma imagen para todo el
        // album.
        let normalized = CoverArtNormalizer.normalized(data)
        let targets = items.filter {
            ids.contains($0.id) && $0.kind == .music && $0.metadata?.coverArtData != normalized
        }
        guard !targets.isEmpty else { return 0 }

        let handle = taskCenter.begin(title: "Aplicando carátula a \(targets.count) \(targets.count == 1 ? "canción" : "canciones")…",
                                      progress: .determinate(completed: 0, total: targets.count))
        defer { taskCenter.finish(handle) }

        var pendingResults: [UUID: (metadata: TrackMetadata, preparedURL: URL?)] = [:]
        var lastFlush = Date()

        for (completed, item) in targets.enumerated() {
            var metadata = item.metadata ?? TrackMetadata()
            metadata.coverArtData = normalized
            let prepared = try? await fileWorker.prepareMusic(makePrepareMusicRequest(for: item, metadata: metadata))
            pendingResults[item.id] = (metadata, prepared ?? item.preparedURL)

            handle.update(.determinate(completed: completed + 1, total: targets.count),
                          statusText: "\(completed + 1) de \(targets.count)")

            let shouldFlush = pendingResults.count >= Self.batchApplySize
                || Date().timeIntervalSince(lastFlush) >= Self.batchApplyInterval
                || completed == targets.count - 1
            if shouldFlush, !pendingResults.isEmpty {
                applyPendingAlbumCoverResults(pendingResults, markEdited: markEdited)
                pendingResults.removeAll(keepingCapacity: true)
                lastFlush = Date()
            }
        }

        let changed = targets.count
        if markEdited {
            lastEnrichmentSummary = changed == 1
                ? "Carátula aplicada a 1 canción."
                : "Carátula aplicada a \(changed) canciones."
        }
        persistCatalog()
        return changed
    }

    private func applyPendingAlbumCoverResults(_ results: [UUID: (metadata: TrackMetadata, preparedURL: URL?)], markEdited: Bool) {
        for index in items.indices where results[items[index].id] != nil {
            let result = results[items[index].id]!
            items[index].metadata = result.metadata
            if markEdited { items[index].metadataEditedByUser = true }
            items[index].preparedURL = result.preparedURL
        }
    }

    @Published private(set) var isApplyingRecommendedCovers = false

    /// R2-3: "Aplicar carátula recomendada" sobre uno o varios álbumes.
    ///
    /// Para cada álbum busca candidatas y aplica la recomendada **solo
    /// si supera el umbral** de `AlbumCoverScoring.automaticThreshold`.
    /// Lo que no lo supera **no se toca**: se cuenta y se dice, para que
    /// el usuario lo resuelva en el picker. Aplicar a ciegas una tapa
    /// dudosa a veinte álbumes es exactamente el daño que R2-3 evita.
    ///
    /// Con UN solo álbum que no alcance el umbral, se abre el picker
    /// (eso lo decide la vista con el `AlbumCoverRequest` devuelto).
    /// Con varios no: veinte pickers en fila no son una función.
    func applyRecommendedCovers(for requests: [AlbumCoverRequest],
                                search: AlbumCoverSearch) async -> [AlbumCoverRequest] {
        guard !isApplyingRecommendedCovers, !requests.isEmpty else { return [] }
        isApplyingRecommendedCovers = true
        defer { isApplyingRecommendedCovers = false }
        lastError = nil

        var applied = 0
        var needsChoice: [AlbumCoverRequest] = []
        var withoutResults = 0

        for request in requests {
            let candidates = await search.candidates(
                for: AlbumCoverScoring.AlbumFacts(title: request.albumTitle,
                                                  year: request.albumYear,
                                                  trackCount: request.trackCount),
                artist: request.albumArtist)
            guard let best = candidates.first else {
                withoutResults += 1
                continue
            }
            if best.reachesAutomaticThreshold {
                if await applyAlbumCover(best.data, toItems: request.trackIDs, markEdited: false) > 0 {
                    applied += 1
                }
            } else {
                needsChoice.append(request)
            }
        }

        var parts = ["Carátulas: \(applied) \(applied == 1 ? "aplicada" : "aplicadas")"]
        if !needsChoice.isEmpty {
            parts.append("\(needsChoice.count) sin una opción lo bastante segura (elígela tú)")
        }
        if withoutResults > 0 { parts.append("\(withoutResults) sin resultados") }
        lastEnrichmentSummary = parts.joined(separator: ", ") + "."
        return needsChoice
    }

    /// D-218: aplica `BatchMediaInfoView` sobre varias canciones a la
    /// vez -- solo toca los campos que `changes` trae con valor real
    /// (`nil` = no tocar), nunca el título ni el numero de pista (esos
    /// ni siquiera son parte de `BatchMetadataChanges`, ver ese tipo).
    /// PLAN-studio-rendimiento.md Fase 4 paso 2: `prepareMusic` corre en
    /// `fileWorker` (fuera del actor principal); los resultados vuelven
    /// a `items` en lotes de `batchApplySize` (o antes, si pasan
    /// `batchApplyInterval` desde el último lote) -- nunca una
    /// publicación de `items` por ítem. Diagnóstico §0.5.
    static let batchApplySize = 50
    static let batchApplyInterval: TimeInterval = 0.1

    func applyBatchEdit(ids: Set<UUID>, changes: BatchMetadataChanges) async {
        guard !changes.isEmpty else { return }
        let targets = items.filter { ids.contains($0.id) && $0.kind == .music }
        guard !targets.isEmpty else { return }

        let handle = taskCenter.begin(title: "Editando \(targets.count) \(targets.count == 1 ? "canción" : "canciones")…",
                                      progress: .determinate(completed: 0, total: targets.count))
        defer { taskCenter.finish(handle) }

        var pendingResults: [UUID: (metadata: TrackMetadata, preparedURL: URL?, status: LibraryItemStatus)] = [:]
        var lastFlush = Date()

        for (completed, item) in targets.enumerated() {
            var metadata = item.metadata ?? TrackMetadata()
            if let artist = changes.artist { metadata.artist = artist }
            if let album = changes.album { metadata.album = album }
            if let albumArtist = changes.albumArtist { metadata.albumArtist = albumArtist }
            if let year = changes.year { metadata.year = year }
            if let genre = changes.genre { metadata.genre = genre }
            if let composer = changes.composer { metadata.composer = composer }
            if let rating = changes.rating { metadata.rating = rating }

            let preparedURL = try? await fileWorker.prepareMusic(makePrepareMusicRequest(for: item, metadata: metadata))
            pendingResults[item.id] = (metadata, preparedURL, metadata.isComplete ? .ready : .needsReview)

            handle.update(.determinate(completed: completed + 1, total: targets.count),
                          statusText: "\(completed + 1) de \(targets.count)")

            let shouldFlush = pendingResults.count >= Self.batchApplySize
                || Date().timeIntervalSince(lastFlush) >= Self.batchApplyInterval
                || completed == targets.count - 1
            if shouldFlush, !pendingResults.isEmpty {
                applyPendingBatchEditResults(pendingResults)
                pendingResults.removeAll(keepingCapacity: true)
                lastFlush = Date()
            }
        }
        persistCatalog()
    }

    /// Un solo recorrido de `items.indices`, sin ningún `await` de por
    /// medio -- todas las mutaciones de este lote quedan en la misma
    /// pasada síncrona, así que SwiftUI las ve como un cambio, no
    /// `pendingResults.count` cambios sueltos.
    private func applyPendingBatchEditResults(_ results: [UUID: (metadata: TrackMetadata, preparedURL: URL?, status: LibraryItemStatus)]) {
        for index in items.indices where results[items[index].id] != nil {
            let result = results[items[index].id]!
            items[index].metadata = result.metadata
            items[index].metadataEditedByUser = true
            items[index].preparedURL = result.preparedURL
            items[index].status = result.status
        }
    }

    /// ST-063: aplica las ediciones que propuso `SimilarItemsDetector`
    /// (unificar artista/álbum al nombre canónico, quitar el número de
    /// pista del título). Mismo camino que una corrección manual:
    /// marca `metadataEditedByUser`, re-prepara la música y persiste.
    /// PLAN-studio-rendimiento.md Fase 4 paso 3: `prepareMusic` (solo
    /// para música -- fotos/video no lo necesitan) corre en `fileWorker`,
    /// resultados en lotes -- mismo patrón que `applyBatchEdit`/
    /// `applyAlbumCover`.
    func applySimilarityEdits(_ edits: [SimilarityProposedEdit]) async {
        guard !edits.isEmpty else { return }
        let byItem = Dictionary(grouping: edits, by: \.itemID)
        let targetIDs = Set(byItem.keys)
        let targets = items.filter { targetIDs.contains($0.id) }
        guard !targets.isEmpty else { return }

        let handle = taskCenter.begin(title: "Corrigiendo \(targets.count) \(targets.count == 1 ? "elemento" : "elementos")…",
                                      progress: .determinate(completed: 0, total: targets.count))
        defer { taskCenter.finish(handle) }

        var pendingResults: [UUID: (metadata: TrackMetadata, preparedURL: URL??, status: LibraryItemStatus?)] = [:]
        var lastFlush = Date()

        for (completed, item) in targets.enumerated() {
            guard let itemEdits = byItem[item.id] else { continue }
            var metadata = item.metadata ?? TrackMetadata()
            for edit in itemEdits {
                let value = edit.proposedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { continue }
                switch edit.field {
                case .title: metadata.title = value
                case .artist: metadata.artist = value
                case .album: metadata.album = value
                }
            }

            var preparedURL: URL??
            var status: LibraryItemStatus?
            if item.kind == .music {
                let prepared = try? await fileWorker.prepareMusic(makePrepareMusicRequest(for: item, metadata: metadata))
                preparedURL = .some(prepared)
                if item.status == .ready || item.status == .needsReview {
                    status = metadata.isComplete ? .ready : .needsReview
                }
            }
            pendingResults[item.id] = (metadata, preparedURL, status)

            handle.update(.determinate(completed: completed + 1, total: targets.count),
                          statusText: "\(completed + 1) de \(targets.count)")

            let shouldFlush = pendingResults.count >= Self.batchApplySize
                || Date().timeIntervalSince(lastFlush) >= Self.batchApplyInterval
                || completed == targets.count - 1
            if shouldFlush, !pendingResults.isEmpty {
                applyPendingSimilarityEditResults(pendingResults)
                pendingResults.removeAll(keepingCapacity: true)
                lastFlush = Date()
            }
        }
        persistCatalog()
    }

    /// `preparedURL`/`status` son `??`/`?` a propósito: `nil` de afuera
    /// significa "no era música, no se tocó" (conserva lo que ya
    /// había); `.some(nil)` significa "sí era música, pero
    /// `prepareMusic` falló" -- ahí SÍ hay que limpiar, igual que hacía
    /// el código síncrono de siempre (`preparedURL = try? ...` sin
    /// `if let`, que sobreescribe con `nil` si falla).
    private func applyPendingSimilarityEditResults(_ results: [UUID: (metadata: TrackMetadata, preparedURL: URL??, status: LibraryItemStatus?)]) {
        for index in items.indices where results[items[index].id] != nil {
            let result = results[items[index].id]!
            items[index].metadata = result.metadata
            items[index].metadataEditedByUser = true
            if let preparedURL = result.preparedURL {
                items[index].preparedURL = preparedURL
            }
            if let status = result.status {
                items[index].status = status
            }
        }
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

        // PLAN-studio-rendimiento.md Fase 4: primera operación real
        // conectada al centro de tareas -- "N de M" en vez del banner
        // fijo de siempre. El límite de 1 pedido/segundo de MusicBrainz
        // ya lo aplica `enricher` por dentro; el centro solo muestra el
        // progreso, no lo acelera.
        let handle = taskCenter.begin(title: "Buscando información en línea…",
                                      progress: .determinate(completed: 0, total: ids.count))
        defer { taskCenter.finish(handle) }

        for id in ids {
            guard let index = items.firstIndex(where: { $0.id == id }), items[index].kind == .music else { continue }
            attempted += 1
            handle.update(.determinate(completed: attempted, total: ids.count),
                          statusText: "\(attempted) de \(ids.count)")
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

    /// "Volver a leer etiquetas del archivo" del menu contextual, y lo
    /// que corre el banner de biblioteca existente (PLAN-studio-ux.md
    /// §2/P1) -- relee `sourceURL` (nunca `.preparados/`, que ya tiene
    /// la tag reescrita con lo que se leyo antes) con `LocalTagReader` y
    /// reemplaza los 9 campos que vienen del archivo (titulo/artista/
    /// album/album-artista/año/genero/compositor/pista/caratula) SOLO
    /// donde el archivo trae un valor -- un campo ausente en el archivo
    /// no borra lo que ya se habia completado por otra via
    /// (enriquecimiento remoto, correccion a mano). Calificacion y letra
    /// sincronizada nunca se tocan: no son tags del archivo.
    ///
    /// `respectUserEdits` (P2) -- con `true` (el banner), se saltea
    /// cualquier item que el usuario ya haya corregido a mano
    /// (`metadataEditedByUser`); con `false` (la accion explicita del
    /// menu contextual), siempre relee, sea cual sea ese valor.
    func rereadLocalTags(ids: Set<UUID>, respectUserEdits: Bool = false) async {
        var updated = 0
        var attempted = 0

        for id in ids {
            guard let index = items.firstIndex(where: { $0.id == id }), items[index].kind == .music else { continue }
            if respectUserEdits && items[index].metadataEditedByUser { continue }
            attempted += 1

            let item = items[index]
            let fresh = await LocalTagReader.readTag(from: item.sourceURL)
            let current = item.metadata ?? TrackMetadata()
            let merged = mergingLocalTags(fresh, into: current)
            guard index < items.count else { continue }
            if merged != current { updated += 1 }
            items[index].metadata = merged
            items[index].preparedURL = try? prepareMusic(item: items[index], metadata: merged)
            items[index].status = merged.isComplete ? .ready : .needsReview
        }
        persistCatalog()

        guard attempted > 0 else { return }
        lastEnrichmentSummary = updated == 0
            ? "No habia nada que actualizar en \(attempted) cancion(es): ya tenian lo que traen sus archivos."
            : "Se actualizaron \(updated) de \(attempted) cancion(es) con lo que traen sus archivos."
    }

    private func mergingLocalTags(_ fresh: TrackMetadata, into current: TrackMetadata) -> TrackMetadata {
        var merged = current
        merged.title = fresh.title ?? current.title
        merged.artist = fresh.artist ?? current.artist
        merged.album = fresh.album ?? current.album
        merged.albumArtist = fresh.albumArtist ?? current.albumArtist
        merged.year = fresh.year ?? current.year
        merged.genre = fresh.genre ?? current.genre
        merged.composer = fresh.composer ?? current.composer
        merged.trackNumber = fresh.trackNumber ?? current.trackNumber
        // ST-141: la carátula de la etiqueta (o el `cover.jpg` de la
        // carpeta) entra cuadrada, igual que la que baja de la red.
        merged.coverArtData = fresh.coverArtData.map(CoverArtNormalizer.normalized) ?? current.coverArtData
        return merged
    }

    /// Se evalua cada vez que se carga un catalogo (arranque, o cambio
    /// de carpeta de biblioteca) -- pero `legacyMetadataBannerShown`
    /// persiste en UserDefaults, asi que en la practica se ofrece una
    /// sola vez por instalacion, nunca de nuevo aunque haya varias
    /// bibliotecas o se reinicie la app.
    private func evaluateLegacyMetadataRereadOffer() {
        guard !preferences.legacyMetadataBannerShown else {
            legacyMetadataRereadOfferCount = nil
            return
        }
        let musicCount = items.filter { $0.kind == .music }.count
        legacyMetadataRereadOfferCount = musicCount > 0 ? musicCount : nil
    }

    /// "Ahora no" del banner -- no vuelve a preguntar (la accion sigue
    /// disponible a mano en el menu contextual, para siempre).
    func dismissLegacyMetadataRereadOffer() {
        preferences.legacyMetadataBannerShown = true
        legacyMetadataRereadOfferCount = nil
    }

    /// Aceptar el banner: relee TODA la musica de la biblioteca actual,
    /// respetando ediciones manuales previas (P2), y no vuelve a
    /// preguntar.
    func acceptLegacyMetadataRereadOffer() async {
        let musicIDs = Set(items.filter { $0.kind == .music }.map(\.id))
        await rereadLocalTags(ids: musicIDs, respectUserEdits: true)
        dismissLegacyMetadataRereadOffer()
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
    /// PLAN-general-sync.md §6: "Toda la biblioteca" (por defecto) o
    /// "Solo la selección" -- con una selección vacía, `sync(scope:)`
    /// no llega a tocar el dispositivo (ver el guard al principio).
    enum SyncScope: Equatable {
        case all
        case selection(Set<UUID>)
    }

    /// No-nil mientras hay un sync en curso -- `cancelSync()` lo usa
    /// para pedirle a `LibrarySync.sync()` (que corre en un
    /// `Task.detached`, no puede cancelarse con `Task.cancel()` porque
    /// no es asincrono) que pare en la proxima frontera segura
    /// (§8.1/§8.3 de PLAN-general-sync.md).
    private var currentSyncCancellationFlag: SyncCancellationFlag?

    var isSyncing: Bool { syncProgress != nil }

    /// Pide que el sync en curso se detenga en la proxima frontera seg
    /// ura (entre bloques de 4 MB, o entre archivos) -- no hace nada si
    /// no hay ningun sync corriendo. `LibrarySync.sync()` sigue
    /// corriendo `finalize` (portadas, playlists, resumen, indice) para
    /// lo que ya se alcanzo a copiar, asi que el iPod queda consistente.
    func cancelSync() {
        currentSyncCancellationFlag?.cancel()
    }

    /// `resolvedConflicts` (PLAN-general-sync.md §0.1/§1.2): las
    /// elecciones explícitas del usuario en la hoja de conflictos
    /// previa -- vacío por defecto, que es "conservar todo en el iPod,
    /// no borrar ningún huérfano" (los defaults seguros de la spec).
    struct ConflictResolution {
        var forceRecopySourcePaths: Set<String> = []
        var removeOrphanedSourcePaths: Set<String> = []
        static let none = ConflictResolution()
    }

    func sync(toVolumeAt volumeRoot: URL, scope: SyncScope = .all, resolvedConflicts: ConflictResolution = .none) async {
        let allReady = items.filter { $0.status == .ready }
        let restrictedSourcePaths: Set<String>?

        switch scope {
        case .all:
            restrictedSourcePaths = nil
        case .selection(let ids):
            // El boton/menu que llama con `.selection` ya deberia venir
            // deshabilitado sin nada elegido (§6: "nunca falla, no hay
            // camino a sincronizar nada") -- este guard es la ultima
            // linea de defensa si de todas formas se invoca vacio.
            guard !ids.isEmpty else {
                lastSyncSummary = "No hay ningún elemento seleccionado para sincronizar."
                return
            }
            let selectedReady = allReady.filter { ids.contains($0.id) }
            guard !selectedReady.isEmpty else {
                lastSyncSummary = "Los elementos seleccionados todavía no están listos para sincronizar."
                return
            }
            restrictedSourcePaths = Set(selectedReady.map { $0.sourceURL.path })
        }

        guard !allReady.isEmpty else {
            lastSyncSummary = "No hay nada listo para sincronizar."
            return
        }

        guard InstallerFlowRegistry.shared.beginWriting() else {
            lastError = "Hay otra operación en curso con el iPod -- espera a que termine antes de sincronizar."
            return
        }
        defer { InstallerFlowRegistry.shared.endWriting() }

        let cancellationFlag = SyncCancellationFlag()
        currentSyncCancellationFlag = cancellationFlag
        defer { currentSyncCancellationFlag = nil }

        let playlistsSnapshot = playlists
        let coverArtPolicy = preferences.coverArtPolicy
        let musicOrganization = preferences.musicOrganization
        let musicFilenameFormat = preferences.musicFilenameFormat
        // R2-4: se toma acá, en el hilo principal, para cruzar a la
        // tarea separada como valor (`ArtistGroupingOptions` es Sendable).
        let artistGroupingSnapshot = preferences.artistGrouping
        let libraryRootSnapshot = libraryRoot
        let installationIDSnapshot = preferences.installationID
        let startedAt = Date()
        syncProgress = nil

        do {
            let sync = LibrarySync(volumeRoot: volumeRoot)
            let result = try await Task.detached(priority: .userInitiated) { [weak self] in
                try sync.sync(items: allReady, playlists: playlistsSnapshot,
                              libraryRoot: libraryRootSnapshot,
                              coverArtPolicy: coverArtPolicy,
                              musicOrganization: musicOrganization,
                              musicFilenameFormat: musicFilenameFormat,
                              artistGrouping: artistGroupingSnapshot,
                              restrictCopyToSourcePaths: restrictedSourcePaths,
                              forceRecopySourcePaths: resolvedConflicts.forceRecopySourcePaths,
                              removeOrphanedSourcePaths: resolvedConflicts.removeOrphanedSourcePaths,
                              installationID: installationIDSnapshot,
                              isCancelled: { cancellationFlag.isCancelled }) { copied, total in
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
            if result.wasCancelled {
                lastSyncSummary = "Sincronización cancelada. Se copiaron \(result.filesCopied) archivo(s); \(result.filesRemaining) quedaron pendientes.\(playlistsNote)"
            } else {
                lastSyncSummary = result.filesCopied == 0
                    ? "Ya estaba todo sincronizado, no habia nada nuevo.\(playlistsNote)"
                    : "Se copiaron \(result.filesCopied) de \(allReady.count) archivo(s). El indice de la biblioteca se va a reconstruir la proxima vez que arranque Aura.\(playlistsNote)"
            }
            // PARTE 1A (PLAN-sync-media-hardening.md): antes, un solo
            // archivo con nombre invalido para FAT32 abortaba sync()
            // entero -- ahora esos archivos quedan en
            // `result.failures` y el resto de la biblioteca se
            // sincroniza igual. Se avisan aparte (sin tapar
            // `lastSyncSummary`, que sigue reportando lo que SI se
            // copio) para que el usuario sepa que hay algo pendiente de
            // revisar, no que "no pasó nada".
            if !result.failures.isEmpty {
                let shown = result.failures.prefix(5)
                let list = shown.map { "• \($0.destinationRelativePath): \($0.message)" }.joined(separator: "\n")
                let more = result.failures.count > shown.count ? "\n… y \(result.failures.count - shown.count) más." : ""
                lastError = "\(result.failures.count) archivo(s) no se pudieron copiar (el resto de la biblioteca sí se sincronizó):\n\(list)\(more)"
            }
        } catch {
            // El mensaje de Cocoa viene en ingles y sin contexto ("You
            // can't save the file X because the volume is read only"):
            // se conserva porque dice el motivo real, pero se antepone
            // a donde se estaba escribiendo, que es la informacion que
            // permite darse cuenta de que se apunto al disco equivocado.
            // Nota (§8.4): una desconexion fisica a media copia llega
            // aca tambien (EIO/ENOENT real de `copyFileTransactionally`)
            // -- el marcador `sync_in_progress` queda en el dispositivo
            // porque `finalize` nunca corrio, y el proximo sync lo
            // encuentra y continua desde donde quedo (el manifiesto ya
            // tiene registrado cada archivo que si se alcanzo a copiar,
            // guardado uno por uno).
            lastError = "No se pudo sincronizar en \(volumeRoot.path): \(error.localizedDescription)"
        }
        syncProgress = nil
        // §4.2: "fin de sync/cancelación" es uno de los momentos que
        // invalida el índice viejo -- si el dispositivo ya no responde
        // (desconexión real), `verifyDevice` simplemente no encuentra
        // nada que escanear y no falla.
        await verifyDevice(at: volumeRoot)
    }

    /// Encargo del dueño (General → "Eliminar todos los archivos, o por
    /// tipos de medios"): borra TODO el contenido sincronizado de los
    /// tipos elegidos, directo del iPod -- sin tocar la biblioteca
    /// local. La confirmación ("¿de verdad quieres borrar N archivos,
    /// esto no se puede deshacer?") vive en la vista que llama a esto
    /// (`DeviceGeneralView`, mismo criterio que `ForeignContentSheet`);
    /// esta función asume que ya se confirmó. Mismo guard de escritura
    /// concurrente que `sync()` -- nunca borrar mientras hay una
    /// instalación o sync en curso.
    func deleteAllDeviceContent(toVolumeAt volumeRoot: URL, kinds: Set<LibraryItemKind>) async {
        guard !kinds.isEmpty else { return }
        guard InstallerFlowRegistry.shared.beginWriting() else {
            lastError = "Hay otra operación en curso con el iPod -- espera a que termine antes de borrar."
            return
        }
        defer { InstallerFlowRegistry.shared.endWriting() }

        do {
            let sync = LibrarySync(volumeRoot: volumeRoot)
            let deleted = try await Task.detached(priority: .userInitiated) {
                try sync.deleteAllDeviceContent(kinds: kinds)
            }.value
            lastSyncSummary = deleted == 0
                ? "No había nada que borrar."
                : "Se eliminaron \(deleted) archivo(s) del iPod. El índice de la biblioteca se va a reconstruir la próxima vez que arranque Aura."
        } catch {
            lastError = "No se pudo borrar en \(volumeRoot.path): \(error.localizedDescription)"
        }
        await verifyDevice(at: volumeRoot)
    }

    /// Compara la biblioteca contra lo que de verdad hay en el iPod
    /// conectado -- PLAN-general-sync.md §4. Hace I/O real (una
    /// enumeración de `Music/`/`Videos/`/`Photos/`/`Playlists/`), por
    /// eso corre en un `Task.detached` fuera del hilo principal, igual
    /// que `sync()`.
    func verifyDevice(at volumeRoot: URL) async {
        guard !isVerifyingDevice else { return }
        isVerifyingDevice = true
        defer { isVerifyingDevice = false }

        let currentFiles: [DeviceSyncIndexBuilder.CurrentFile] = items.compactMap { item in
            guard let prepared = item.preparedURL,
                  let attrs = try? FileManager.default.attributesOfItem(atPath: prepared.path) else { return nil }
            let size = (attrs[.size] as? Int64) ?? 0
            let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            return DeviceSyncIndexBuilder.CurrentFile(sourcePath: item.sourceURL.path, size: size, modifiedAt: modified)
        }

        let index = await Task.detached(priority: .utility) {
            let sync = LibrarySync(volumeRoot: volumeRoot)
            let manifest = sync.loadManifest()
            return DeviceSyncIndexBuilder.scan(volumeRoot: volumeRoot, currentFiles: currentFiles, manifest: manifest)
        }.value

        deviceSyncIndex = index
    }

    /// Al desconectar el iPod (o cuando resulta no ser Aura) el índice
    /// viejo ya no significa nada -- mostrarlo seguiría diciendo
    /// "Sincronizado" de un dispositivo que ya no es el que está
    /// conectado.
    func clearDeviceSyncIndex() {
        deviceSyncIndex = nil
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
        if let playlist = playlists.first(where: { $0.id == id }), let relative = playlist.imageRelativePath {
            try? FileManager.default.removeItem(at: libraryRoot.appendingPathComponent(relative))
        }
        playlists.removeAll { $0.id == id }
        persistCatalog()
    }

    /// Imagen elegida a mano por el usuario para una playlist (encargo
    /// del dueno, 2026-08-14) -- se cachea igual que la caratula de una
    /// pista (`.portadas/`, ver `coversDirectory`), con el prefijo
    /// "playlist-" para no chocar con los ids de `LibraryItem` que
    /// conviven en la misma carpeta. Redimensionada chica (128px): el
    /// unico lugar donde se ve es el cuadrado de una fila de lista, no
    /// una portada grande (mismo criterio de tamano que
    /// `PlaylistArtGenerator.dimension`, del lado del default generado).
    func setPlaylistImage(id: UUID, sourceURL: URL) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        let relative = "\(PersistedLibrary.coversDirName)/playlist-\(id.uuidString).jpg"
        let destination = libraryRoot.appendingPathComponent(relative)
        do {
            try ImageResizer.resizeToLCDOptimal(sourceURL: sourceURL, destinationURL: destination,
                                                 maxDimension: PlaylistArtGenerator.dimension)
            playlists[index].imageRelativePath = relative
            persistCatalog()
        } catch {
            lastError = "No se pudo usar esa imagen para la playlist: \(error.localizedDescription)"
        }
    }

    /// "Quitar imagen" -- vuelve la playlist al default generado por
    /// LibrarySync en el proximo sync (colage de sus propias caratulas,
    /// o el tile generico si no tiene ninguna).
    func clearPlaylistImage(id: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        if let relative = playlists[index].imageRelativePath {
            try? FileManager.default.removeItem(at: libraryRoot.appendingPathComponent(relative))
        }
        playlists[index].imageRelativePath = nil
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
        // La migración en curso es de la biblioteca que se está
        // dejando: seguir reescribiendo archivos de una carpeta que ya
        // no es la activa no tiene sentido (y su marca se escribiría en
        // el catálogo equivocado). `loadCatalog` arranca la de la nueva.
        cancelCoverNormalization()
        libraryRoot = URL(fileURLWithPath: newPath, isDirectory: true)
        ensureLibraryStructure()
        migrateLegacyLibraryLayoutIfNeeded()
        items = []
        playlists = []
        // La carpeta cambió: el hash de la última carátula escrita era
        // de la carpeta anterior, ya no dice nada de ésta.
        lastWrittenCoverHash = [:]
        loadCatalog()
    }

    // MARK: - Migracion de caratulas a cuadradas (ST-141)

    /// Los archivos de `.portadas/` que la migración debe mirar: las
    /// carátulas de las CANCIONES y todas las fotos de artista.
    ///
    /// Lo que queda deliberadamente afuera:
    /// - **Los pósters de video**, que viven en la misma carpeta y con el
    ///   mismo nombre (`<id>.jpg`) pero son 3:4 por diseño (contrato
    ///   §A.1). Por eso esto se arma desde los items del catálogo, con su
    ///   `kind`, y no listando el directorio a ciegas.
    /// - **Las imágenes de las listas** (`playlist-<id>.jpg`), que ya las
    ///   genera cuadradas `PlaylistArtGenerator` (128×128).
    /// - **Los archivos originales del usuario**: la migración solo toca
    ///   la copia de la biblioteca.
    private func coverFilesToNormalize() -> [URL] {
        let fm = FileManager.default
        var files: [URL] = []

        for item in items where item.kind == .music {
            let url = coversDirectory.appendingPathComponent("\(item.id.uuidString).jpg")
            if fm.fileExists(atPath: url.path) { files.append(url) }
        }

        let artistsDirectory = coversDirectory.appendingPathComponent("artistas", isDirectory: true)
        if let contents = try? fm.contentsOfDirectory(at: artistsDirectory,
                                                      includingPropertiesForKeys: nil,
                                                      options: [.skipsHiddenFiles]) {
            files += contents.filter { $0.pathExtension.lowercased() == "jpg" }
        }

        return files
    }

    /// Arranca la pasada única si esta biblioteca todavía no la tuvo.
    /// Corre en segundo plano y a prioridad baja: la app se usa
    /// normalmente mientras tanto.
    private func startCoverNormalizationIfNeeded() {
        guard coverNormalizationTask == nil,
              coversNormalizedVersion != CoverArtNormalizer.normalizedVersion else { return }

        let files = coverFilesToNormalize()
        guard !files.isEmpty else {
            // Nada que migrar (biblioteca vacía, o sin carátulas): se
            // marca igual, para no volver a recorrer en cada apertura.
            markCoversNormalized()
            return
        }

        coverNormalization = CoverNormalizationProgress(completed: 0, total: files.count)

        // El avance se publica desde el hilo de la migración, así que
        // vuelve al MainActor por su cuenta. `[weak self]` una sola vez,
        // acá: capturarlo otra vez dentro del `Task` interno sería
        // capturar una variable en código concurrente (error en Swift 6,
        // que es con lo que compila `xcodebuild` -- D-034).
        let report: @Sendable (Int, Int) -> Void = { [weak self] completed, total in
            Task { @MainActor in
                // Si ya no hay migración (se canceló y se limpió el
                // estado) no se resucita la barra.
                guard let self, self.coverNormalization != nil else { return }
                self.coverNormalization = CoverNormalizationProgress(completed: completed, total: total)
            }
        }
        let finish: @Sendable (CoverNormalizationMigration.Result) -> Void = { [weak self] result in
            Task { @MainActor in self?.finishCoverNormalization(result) }
        }

        coverNormalizationTask = Task.detached(priority: .utility) {
            finish(CoverNormalizationMigration.run(files: files,
                                                   isCancelled: { Task.isCancelled },
                                                   onProgress: report))
        }
    }

    /// Cierra la pasada: la marca SOLO si terminó completa. Cancelada,
    /// la próxima apertura la retoma -- y como saltarse lo que ya está
    /// cuadrado es la regla, retomar cuesta leer cabeceras, no reescribir.
    private func finishCoverNormalization(_ result: CoverNormalizationMigration.Result) {
        coverNormalizationTask = nil
        coverNormalization = nil

        guard !result.cancelled else { return }
        markCoversNormalized()

        guard result.normalized > 0 else { return }
        // Lo que quedó en memoria es la versión vieja (rectangular): se
        // relee de disco para que la app muestre lo mismo que se va a
        // sincronizar. `artistImages` cachea por su cuenta, así que se le
        // avisa aparte.
        reloadCoversFromDisk()
        artistImages.invalidate()
        lastEnrichmentSummary = result.normalized == 1
            ? "Se normalizó 1 carátula: ahora es cuadrada."
            : "Se normalizaron \(result.normalized) carátulas: ahora son cuadradas."
    }

    private func markCoversNormalized() {
        coversNormalizedVersion = CoverArtNormalizer.normalizedVersion
        persistCatalog()
    }

    /// "Cancelar" de la barra de progreso. Lo hecho queda hecho; lo que
    /// falta se retoma la próxima vez que se abra la biblioteca.
    func cancelCoverNormalization() {
        coverNormalizationTask?.cancel()
        coverNormalizationTask = nil
        coverNormalization = nil
    }

    private func reloadCoversFromDisk() {
        for index in items.indices where items[index].kind == .music {
            let url = coversDirectory.appendingPathComponent("\(items[index].id.uuidString).jpg")
            guard let data = try? Data(contentsOf: url), !data.isEmpty,
                  var metadata = items[index].metadata, metadata.coverArtData != data else { continue }
            metadata.coverArtData = data
            items[index].metadata = metadata
        }
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
            // ST-102: los prefijos se comparan sobre la ruta con
            // separadores ya normalizados -- un catalogo que paso por
            // Windows trae `Originales\...`, y con la comparacion cruda
            // la migracion lo daria por ya migrado.
            var item = persisted.items[index]
            item.sourceRelativePath = SharedCatalogPath.withUnixSeparators(item.sourceRelativePath)
            item.preparedRelativePath = item.preparedRelativePath.map(SharedCatalogPath.withUnixSeparators)
            item.coverRelativePath = item.coverRelativePath.map(SharedCatalogPath.withUnixSeparators)

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
        guard let oldURL = SharedCatalogPath.resolve(persistedItem.sourceRelativePath, in: libraryRoot)
        else { return nil }

        let kind = LibraryPersistenceMapper.liveKind(persistedItem.kind)
        let category = persistedItem.category.map(LibraryPersistenceMapper.liveCategory)
        let tempItem = LibraryItem(
            id: persistedItem.id, sourceURL: oldURL, kind: kind, status: .queued,
            metadata: LibraryPersistenceMapper.liveMetadata(persistedItem.metadata, coverArtData: nil),
            preparedURL: nil, category: category, photoAlbum: persistedItem.photoAlbum)

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
        guard let oldURL = SharedCatalogPath.resolve(old, in: libraryRoot, fileManager: fm) else { return false }
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

    /// PLAN-studio-rendimiento.md Fase 3 punto 2: hash de la última
    /// carátula efectivamente ESCRITA por ítem -- `persistCatalog()` la
    /// vuelve a escribir solo si cambió desde la última vez. Vive tan
    /// solo mientras dure este `LibraryViewModel` (se pierde al
    /// relanzar la app o cambiar de carpeta de biblioteca): el peor
    /// caso de perderla es una reescritura de más, nunca una de menos.
    private var lastWrittenCoverHash: [UUID: Int] = [:]

    /// PLAN-studio-rendimiento.md Fase 3 punto 1 (addendum a ST-155):
    /// coalesce guardados de ediciones rápidas seguidas -- ver
    /// `CatalogPersister`.
    private let catalogPersister = CatalogPersister()

    /// PLAN-studio-rendimiento.md Fase 4 paso 2: `prepareMusic` fuera
    /// del actor principal -- ver `LibraryFileWorker`.
    private let fileWorker = LibraryFileWorker()

    /// Snapshot `Sendable` de lo que `fileWorker.prepareMusic` necesita
    /// de las preferencias -- se lee en el actor principal, antes de
    /// cruzar al worker (nunca se le pasa `AppPreferences` completo).
    private func makePrepareMusicRequest(for item: LibraryItem, metadata: TrackMetadata) -> LibraryFileWorker.PrepareMusicRequest {
        LibraryFileWorker.PrepareMusicRequest(
            sourceURL: item.sourceURL, stagingDirectory: stagingDirectory, metadata: metadata,
            audioQuality: preferences.audioQuality, coverArtPolicy: preferences.coverArtPolicy)
    }

    /// Solo para pruebas: `schedulePersistCatalog()` escribe de
    /// inmediato en vez de esperar el debounce de 500 ms, para el
    /// patrón "mutar con un ViewModel, cargar con otro sobre el mismo
    /// `libraryRoot`, verificar sin esperar nada" que ya usaban algunas
    /// pruebas escritas antes de que existiera este coalescer.
    func makePersistenceSynchronousForTesting() {
        catalogPersister.isSynchronousForTesting = true
    }

    private func makeCatalogSnapshot() -> CatalogPersister.Snapshot {
        CatalogPersister.Snapshot(items: items, playlists: playlists,
                                  coversNormalizedVersion: coversNormalizedVersion,
                                  libraryRoot: libraryRoot,
                                  lastWrittenCoverHash: lastWrittenCoverHash)
    }

    private func applyCatalogWriteResult(_ result: CatalogPersister.WriteResult) {
        lastWrittenCoverHash = result.lastWrittenCoverHash
        if let error = result.errorDescription {
            lastError = error
        }
    }

    /// PLAN-studio-rendimiento.md Fase 3 punto 1: para ediciones rápidas
    /// individuales (una estrella, una categoría) -- varias seguidas
    /// coalescen en un solo guardado real, con la escritura fuera del
    /// hilo principal. `persistCatalog()` sigue siendo el guardado
    /// inmediato de siempre (acciones en lote, y cualquier sitio que
    /// necesite la garantía de que ya quedó en disco al volver).
    func schedulePersistCatalog() {
        catalogPersister.schedule(makeCatalogSnapshot()) { [weak self] result in
            self?.applyCatalogWriteResult(result)
        }
    }

    /// Guardado inmediato y síncrono -- para salir de la app o pasar a
    /// segundo plano, donde hace falta la garantía de que el archivo
    /// quedó escrito antes de que el proceso pueda morir (un guardado
    /// programado que sigue corriendo por detrás no sirve ahí).
    func flushPendingPersistence() {
        catalogPersister.flushSynchronously { [weak self] result in
            self?.applyCatalogWriteResult(result)
        }
    }

    /// Serializa el catalogo completo, de inmediato -- para acciones en
    /// lote y cualquier sitio que necesite la garantía de que ya quedó
    /// en disco antes de seguir. Las portadas se escriben como archivos
    /// aparte (`Portadas/<id>.jpg`) -- ver PersistedLibrary.
    ///
    /// PLAN-studio-rendimiento.md Fase 0: visibilidad `internal` (no
    /// `private`) a propósito, para que las pruebas de rendimiento
    /// (`@testable import AuraStudio`) puedan medirla aislada. Sigue sin
    /// ser parte de ninguna API pública fuera del módulo.
    ///
    /// PLAN-studio-rendimiento.md Fase 3 punto 1 (addendum a ST-155): la
    /// escritura en sí vive en `CatalogPersister` (`writeNow`, mismo
    /// código que antes, ahora compartido con `schedulePersistCatalog()`)
    /// -- este método arma el snapshot y aplica el resultado de siempre,
    /// sin cambiar su comportamiento observable: sigue siendo síncrono,
    /// en el actor principal, exactamente como antes de esta ronda.
    func persistCatalog() {
        applyCatalogWriteResult(catalogPersister.writeNow(makeCatalogSnapshot()))
    }

    private func loadCatalog() {
        guard let data = try? Data(contentsOf: catalogURL),
              let persisted = try? JSONDecoder().decode(PersistedLibrary.self, from: data) else { return }

        let fm = FileManager.default
        var restored: [LibraryItem] = []
        for p in persisted.items {
            // ST-102: `SharedCatalogPath` resuelve la ruta con
            // tolerancia -- ruta absoluta de macOS tal cual (modo "sin
            // copiar medios", D-192), separadores `\` de un catalogo
            // escrito por Aura Studio en Windows (biblioteca COMPARTIDA),
            // y las dos normalizaciones Unicode. Devuelve `nil` cuando
            // NINGUNA forma existe: si el archivo (la copia en Música/
            // Imágenes/Videos, o el original referenciado sin copiar) ya
            // no esta, el item se omite en silencio -- no hay nada que
            // preparar ni sincronizar desde un archivo ausente.
            guard let sourceURL = SharedCatalogPath.resolve(p.sourceRelativePath, in: libraryRoot, fileManager: fm)
            else { continue }

            let coverData = SharedCatalogPath
                .coverURL(recorded: p.coverRelativePath, itemID: p.id, in: libraryRoot, fileManager: fm)
                .flatMap { try? Data(contentsOf: $0) }
            let preparedURL = p.preparedRelativePath
                .flatMap { SharedCatalogPath.resolve($0, in: libraryRoot, fileManager: fm) }
            let preparedExists = preparedURL != nil

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
                category: p.category.map(LibraryPersistenceMapper.liveCategory),
                seriesName: p.seriesName,
                season: p.season,
                episode: p.episode,
                photoAlbum: p.photoAlbum,
                metadataEditedByUser: p.metadataEditedByUser ?? false,
                addedAt: p.addedAt
            ))
        }
        items = restored
        playlists = persisted.playlists.map {
            // Igual que `preparedExists` arriba: una imagen que ya no
            // esta en disco (borrada a mano, biblioteca movida a medias)
            // no debe seguir referenciandose -- se trata como si nunca
            // hubiera existido, LibrarySync cae al default generado.
            //
            // ST-102: se guarda la forma que REALMENTE existe en disco
            // (`existingRelative`), no la que venia anotada -- asi el
            // resto de la app y el proximo guardado ya trabajan con la
            // ruta buena aunque el catalogo lo haya escrito Windows.
            let imageRelative = $0.imageRelativePath
                .flatMap { SharedCatalogPath.existingRelative($0, in: libraryRoot, fileManager: fm) }
            return Playlist(id: $0.id, name: $0.name, trackItemIDs: $0.trackItemIDs,
                             imageRelativePath: imageRelative)
        }
        coversNormalizedVersion = persisted.coversNormalized
        evaluateLegacyMetadataRereadOffer()
        evaluateCoverContaminationOffer()
        startCoverNormalizationIfNeeded()
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
