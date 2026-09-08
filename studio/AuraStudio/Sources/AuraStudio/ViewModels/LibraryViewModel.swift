import AppKit
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

    @Published private(set) var items: [LibraryItem] = [] {
        didSet { catalogVersion &+= 1 }
    }

    /// PLAN-studio-rendimiento-2.md Fase 3 (ST-182): sube con cada
    /// cambio de `items`. Sirve para saber si un índice/derivado
    /// cacheado sigue valiendo, sin tener que comparar el catálogo
    /// entero (que compararía los bytes de todas las carátulas).
    private(set) var catalogVersion = 0

    private var cachedCatalogIndex: LibraryCatalogIndex?
    private var cachedCatalogIndexVersion = -1

    /// El índice de agrupación del catálogo -- ver `LibraryCatalogIndex`.
    ///
    /// **Perezoso a propósito**: construirlo son 12 000 claves
    /// normalizadas, y una biblioteca que nadie está mirando no tiene
    /// por qué pagarlas en cada cambio de `items`. Se arma la primera
    /// vez que alguien lo pide después de un cambio (típicamente, al
    /// abrir un menú contextual) y a partir de ahí toda consulta es una
    /// búsqueda en diccionario.
    var catalogIndex: LibraryCatalogIndex {
        let options = preferences.artistGrouping
        if let cachedCatalogIndex, cachedCatalogIndexVersion == catalogVersion,
           cachedCatalogIndex.options == options {
            return cachedCatalogIndex
        }
        let index = LibraryCatalogIndex(items: items, options: options)
        cachedCatalogIndex = index
        cachedCatalogIndexVersion = catalogVersion
        return index
    }

    private var catalogIndexWarmup: Task<Void, Never>?

    /// Arma el índice FUERA del hilo principal, si hace falta.
    ///
    /// Construirlo son 12 000 claves normalizadas -- del orden de lo que
    /// ST-180 (b) midió para `LibraryStats.albums` (76 ms). Hacerlo
    /// perezoso alcanza para que el menú deje de costar 81 s, pero
    /// dejaría ESA cuenta en el primer clic derecho después de cada
    /// cambio del catálogo, contra un objetivo de §A de 200 ms para
    /// abrir el menú. Las secciones que usan el índice lo piden acá
    /// cuando cambia el catálogo, y así el menú lo encuentra listo.
    ///
    /// Si nadie llama esto, no pasa nada: `catalogIndex` lo arma igual,
    /// en el hilo principal, la primera vez que se lo pide.
    func warmCatalogIndex() {
        let version = catalogVersion
        let options = preferences.artistGrouping
        if cachedCatalogIndexVersion == version, cachedCatalogIndex?.options == options { return }
        catalogIndexWarmup?.cancel()
        let snapshot = items
        catalogIndexWarmup = Task.detached(priority: .utility) { [weak self] in
            let index = LibraryCatalogIndex(items: snapshot, options: options)
            guard !Task.isCancelled else { return }
            await self?.adoptCatalogIndex(index, version: version)
        }
    }

    /// Solo si el catálogo no volvió a cambiar mientras se armaba.
    private func adoptCatalogIndex(_ index: LibraryCatalogIndex, version: Int) {
        guard catalogVersion == version else { return }
        cachedCatalogIndex = index
        cachedCatalogIndexVersion = version
    }

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
    /// ST-224: progreso de "Convertir referenciados en copias". `nil`
    /// cuando no hay ninguna corriendo, que es casi siempre.
    @Published private(set) var referenceConversion: ReferenceConversionProgress?
    private var coverNormalizationTask: Task<Void, Never>?
    private var stagingDirectory: URL { libraryRoot.appendingPathComponent(PersistedLibrary.preparedDirName, isDirectory: true) }
    private var coversDirectory: URL { libraryRoot.appendingPathComponent(PersistedLibrary.coversDirName, isDirectory: true) }
    // ST-221: las tres carpetas que la app CREA se resuelven contra lo
    // que ya haya en disco, comparando en NFC -- ver
    // `SharedCatalogPath.managedDirectory`. Solo se leen al armar el
    // esqueleto de la biblioteca y al copiar, así que el listado del
    // directorio no está en ningún camino caliente.
    private var musicDirectory: URL { SharedCatalogPath.managedDirectory(PersistedLibrary.musicDirName, in: libraryRoot) }
    private var imagesDirectory: URL { SharedCatalogPath.managedDirectory(PersistedLibrary.imagesDirName, in: libraryRoot) }
    private var videosDirectory: URL { SharedCatalogPath.managedDirectory(PersistedLibrary.videosDirName, in: libraryRoot) }
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
        // ST-188: bajo una prueba de interfaz, la biblioteca es la que
        // diga el entorno -- y NO se guarda en Ajustes, así que la
        // carpeta configurada de verdad queda intacta.
        let configuredPath = UITestEnvironment.libraryPath ?? prefs.libraryFolderPath
        let root = libraryRoot ?? URL(fileURLWithPath: configuredPath, isDirectory: true)
        self.libraryRoot = root
        self.artistImages = ArtistImageStore(libraryRoot: root)
        // ST-189: **antes** de tocar el disco. Con el volumen ausente,
        // `ensureLibraryStructure()` crearía la biblioteca entera como
        // carpetas comunes dentro de `/Volumes`, tapando el punto de
        // montaje del disco de verdad -- ver `LibraryRoot`.
        self.libraryAvailability = LibraryRoot.availability(of: root)
        prepareLibraryIfAvailable()
        observeVolumeChanges()

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
        // ST-223: deduplicación POR RUTA, comparando en NFC.
        //
        // Soltar dos veces la misma carpeta metía la misma canción dos
        // veces, con dos ids, dos copias en la biblioteca y dos
        // entradas en el iPod. Por ruta y no por contenido a propósito:
        // dos archivos iguales en carpetas distintas pueden ser
        // deliberados (una recopilación y el álbum), y ese caso se avisa
        // sin borrar nada -- es el detector de parecidos, que va en A5.
        //
        // Se comparan las rutas ya conocidas Y el destino que tendría en
        // la biblioteca: un archivo que ya se copió adentro se vuelve a
        // soltar con SU ruta original, que ya no es la que el catálogo
        // tiene anotada.
        var known = Set(items.map { SharedCatalogPath.catalogNormalized($0.sourceURL.standardizedFileURL.path) })
        var duplicates = 0
        var new: [LibraryItem] = []
        for url in Self.importableURLs(from: expandedURLs, into: target) {
            let key = SharedCatalogPath.catalogNormalized(url.standardizedFileURL.path)
            guard known.insert(key).inserted else {
                duplicates += 1
                continue
            }
            var item = LibraryItem(sourceURL: url)
            item.category = category
            item.photoAlbum = photoAlbum
            new.append(item)
        }
        items.append(contentsOf: new)
        // ST-225: esto NO es un error -- es lo que pasó al importar, y
        // por eso deja de ir a `lastError`. Un aviso normal presentado
        // como error enseña a ignorar los errores.
        lastImportNotice = ImportNotice(duplicatesSkipped: duplicates, similarGroups: 0)
        if !new.isEmpty { detectSimilarAmongNewlyImported(ids: Set(new.map(\.id))) }

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
        let destinationURL = destinationURL(forRelativePath: relativePath)
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
    /// ST-221: el derivado de `.preparados/` se llama **por el id del
    /// elemento**, no por el nombre del archivo original.
    ///
    /// El nombre por nombre base obligaba a un sufijo (`Canción 2.mp3`)
    /// para dos canciones homónimas de álbumes distintos, y ese sufijo
    /// se decidía en la primera creación y quedaba guardado en el
    /// catálogo para siempre: el nombre no identificaba nada y las
    /// colisiones eran estructurales. Con el id no hay colisión posible,
    /// y `.preparados/` queda alineado con `.portadas/`, que ya nombraba
    /// así (`<ID>.jpg`).
    ///
    /// **No se renombra nada al cargar**: el catálogo guarda
    /// `preparedRelativePath`, así que un derivado viejo con nombre base
    /// se sigue resolviendo tal cual. El nombre nuevo llega cuando el
    /// derivado se regenera, y en bloque en la migración de §0.3.
    /// Renombrar miles de archivos al abrir la app sería justo el
    /// trabajo silencioso al arrancar que esta ronda quiere quitar.
    private func stagingDestination(forItem id: UUID, existingPreparedURL: URL?, ext: String) -> URL {
        if let existingPreparedURL, FileManager.default.fileExists(atPath: existingPreparedURL.path) {
            return existingPreparedURL
        }
        let name = ext.isEmpty ? id.uuidString : "\(id.uuidString).\(ext)"
        return stagingDirectory.appendingPathComponent(name)
    }

    /// ST-221: `relativePath` empieza por una de las tres carpetas
    /// gestionadas (`Música/…`), y ese primer componente se resuelve
    /// contra lo que ya haya en disco comparando en NFC -- si no, una
    /// biblioteca en exFAT o en red que ya tenga `Música` descompuesta
    /// recibiría una segunda `Música` compuesta al lado, idéntica a la
    /// vista. Los componentes siguientes (artista, álbum) los crea esta
    /// app y no vienen del otro lado, así que se dejan como están.
    private func destinationURL(forRelativePath relativePath: String) -> URL {
        var components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count > 1 else { return libraryRoot.appendingPathComponent(relativePath) }
        let first = components.removeFirst()
        var url = SharedCatalogPath.managedDirectory(first, in: libraryRoot)
        for component in components { url = url.appendingPathComponent(component) }
        return url
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
        guard preferences.copyMediaIntoLibrary else { return }
        guard !isInsideLibrary(items[index].sourceURL) else {
            // Ya estaba dentro: no hay nada que copiar, pero SÍ hay que
            // dejar dicho el modo (ST-221) -- antes esto salía sin
            // registrar nada y el modo quedaba a merced de la
            // inferencia por ruta en cada arranque.
            items[index].storage = LibraryStorageMode.infer(
                sourceURL: items[index].sourceURL, libraryRoot: libraryRoot)
            return
        }
        let item = items[index]
        let fileName = item.sourceURL.lastPathComponent
        let relativePath = LibrarySync.localLibraryRelativePath(
            for: item, kind: item.kind, fileName: fileName,
            organizePhotosByCategory: preferences.organizePhotosByCategory,
            organizeVideosByCategory: preferences.organizeVideosByCategory)
        do {
            items[index].sourceURL = try copyIntoLibrary(item.sourceURL, relativePath: relativePath)
            // ST-221: el modo lo fija QUIEN COPIA, en el momento de
            // copiar. Es la única forma de que sea un hecho y no una
            // deducción -- a partir de acá nadie mira la forma de la
            // ruta para saberlo.
            items[index].storage = .copy
        } catch {
            lastError = "No se pudo copiar \(fileName) a la biblioteca: \(error.localizedDescription)"
        }
    }

    /// ST-223: el camino de música al entrar a la biblioteca.
    ///
    /// **En modo copia el archivo de la biblioteca ES el preparado.** Se
    /// copia (o se convierte, según `AudioConversionRule`) a
    /// `Música/<Artista>/<Álbum>/`, se le escriben las etiquetas del
    /// catálogo adentro y `preparedURL == sourceURL`. `.preparados/` no
    /// interviene: hasta acá TODA canción tenía una tercera copia ahí, y
    /// cualquier edición la reescribía entera.
    ///
    /// En modo referencia no cambia nada: el original no se toca y el
    /// derivado por id vive en `.preparados/`.
    private func importOrPrepareMusic(itemAt index: Int, metadata: TrackMetadata) async throws {
        if preferences.copyMediaIntoLibrary, !isInsideLibrary(items[index].sourceURL) {
            try await importMusicIntoLibrary(itemAt: index, metadata: metadata)
            return
        }
        if preferences.copyMediaIntoLibrary {
            // Ya estaba dentro: no hay nada que copiar, pero sí hay que
            // dejar dicho el modo (ST-221).
            items[index].storage = LibraryStorageMode.infer(
                sourceURL: items[index].sourceURL, libraryRoot: libraryRoot)
        }
        items[index].preparedURL = await refreshMusicFile(for: items[index], metadata: metadata)
    }

    private func importMusicIntoLibrary(itemAt index: Int, metadata: TrackMetadata) async throws {
        var item = items[index]
        item.metadata = metadata
        let sourceExtension = item.sourceURL.pathExtension
        let decision = AudioConversionRule.decide(sourceExtension: sourceExtension,
                                                  audioQuality: preferences.audioQuality)
        let destinationExtension = AudioConversionRule.destinationExtension(
            sourceExtension: sourceExtension, audioQuality: preferences.audioQuality)
        // "El mismo criterio de nombre que usa el iPod": en modo copia
        // los dos archivos son el mismo, así que no tiene sentido que se
        // llamen distinto.
        let baseName = LibrarySync.musicFileName(for: item, filenameFormat: preferences.musicFilenameFormat)
        let relativePath = LibrarySync.localLibraryRelativePath(
            for: item, kind: .music, fileName: "\(baseName).\(destinationExtension)")

        do {
            let destination = try resolveNonCollidingDestination(relativePath: relativePath)
            let imported = try await fileWorker.importMusic(
                LibraryFileWorker.ImportMusicRequest(
                    sourceURL: item.sourceURL,
                    destinationURL: destination,
                    decision: decision,
                    metadata: metadata,
                    coverArtPolicy: preferences.coverArtPolicy))
            items[index].sourceURL = imported.url
            // El archivo de la biblioteca ES el que viaja al iPod.
            items[index].preparedURL = imported.url
            items[index].storage = .copy
            items[index].fileSizeBytes = imported.byteSize
            if !imported.tagResult.written, let reason = imported.tagResult.reason {
                lastError = "\(imported.url.lastPathComponent): \(reason)"
            }
        } catch {
            // No se pudo copiar ni convertir. El elemento se queda
            // apuntando a su original y se dice por qué -- lo que NO se
            // hace es dejar en la biblioteca un archivo sin convertir
            // como si nada hubiera pasado.
            items[index].status = .failed(error.localizedDescription)
            lastError = "No se pudo importar \(item.sourceURL.lastPathComponent): \(error.localizedDescription)"
            throw error
        }
    }

    /// ST-223: el archivo que viaja al iPod, después de un cambio de
    /// metadata.
    ///
    /// En modo copia **se reescriben las etiquetas en el sitio** y no se
    /// copia nada: es la diferencia central con lo que había, donde
    /// cualquier edición -- incluida una que ni siquiera va en una
    /// etiqueta -- recopiaba el archivo entero a `.preparados/`.
    ///
    /// En modo referencia sigue regenerándose el derivado por id.
    private func refreshMusicFile(for item: LibraryItem, metadata: TrackMetadata) async -> URL? {
        guard item.storage == .copy else {
            // ST-224: en modo referencia el derivado se arma **solo
            // cuando hace falta**, y `nil` es un estado válido: quiere
            // decir que el archivo del usuario ya sirve tal como está y
            // al iPod viaja él. Nunca se rellena por inferencia.
            let result = await fileWorker.ensurePreparedMusic(
                LibraryFileWorker.EnsurePreparedMusicRequest(
                    itemID: item.id,
                    sourceURL: item.sourceURL,
                    previousPreparedURL: item.preparedURL,
                    catalogSourceSize: item.fileSizeBytes,
                    stagingDirectory: stagingDirectory,
                    metadata: metadata,
                    audioQuality: preferences.audioQuality,
                    coverArtPolicy: preferences.coverArtPolicy))
            if let failure = result.failure {
                lastError = "No se pudo preparar \(item.sourceURL.lastPathComponent): \(failure)"
            }
            return result.url
        }
        let result = await fileWorker.rewriteTags(metadata: metadata,
                                                  coverArtPolicy: preferences.coverArtPolicy,
                                                  at: item.sourceURL)
        // ST-227 (A7c cierre 2): la pregunta es tipada, no un prefijo de
        // una frase en español. Traducir ese mensaje apagaba el aviso.
        if result.isFailure, let reason = result.reason {
            lastError = reason
        }
        return item.sourceURL
    }

    // MARK: - Convertir referenciados en copias (ST-224)

    /// Cómo va la conversión, para la barra de progreso.
    struct ReferenceConversionProgress: Equatable {
        var completed: Int
        var total: Int

        var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
        var label: String { "Convirtiendo en copias… \(completed) de \(total)" }
    }

    /// Cómo terminó. Los no disponibles se cuentan **aparte** de los
    /// fallos a propósito: un disco desconectado no es un error del
    /// usuario ni de la app, y decir "3 fallaron" cuando lo que pasó es
    /// que un disco no estaba conectado manda a buscar el problema al
    /// lugar equivocado.
    struct ReferenceConversionSummary: Equatable {
        var converted: Int = 0
        var skippedUnavailable: Int = 0
        var failed: Int = 0
        var cancelled: Bool = false

        var message: String {
            var parts: [String] = []
            parts.append(LSf("library-view-model.plural.convertidas", converted))
            if skippedUnavailable > 0 {
                parts.append(LSf("library-view-model.plural.saltadas", skippedUnavailable))
            }
            if failed > 0 { parts.append(LSf("library-view-model.plural.fallaron", failed)) }
            if cancelled { parts.append(LS("library-view-model.cancelado")) }
            return Sentence.ended(Sentence.clauses(parts))
        }
    }

    /// ST-224: pasa canciones de modo referencia a modo copia.
    ///
    /// **Copia; nunca mueve ni borra el original.** El archivo del
    /// usuario es del usuario: esta acción le agrega una copia a la
    /// biblioteca, no le quita nada de donde lo tenga.
    ///
    /// El derivado por id que hubiera quedado en `.preparados/` **no se
    /// borra acá**: pasa a ser un huérfano, y borrarlo es trabajo de
    /// "Limpiar huérfanos" (A5), que le muestra al usuario qué va a
    /// borrar antes de hacerlo.
    @discardableResult
    func convertReferencedToCopies(ids: Set<UUID>? = nil) async -> ReferenceConversionSummary {
        let targets = items.filter {
            $0.kind == .music && $0.storage == .reference && (ids?.contains($0.id) ?? true)
        }
        var summary = ReferenceConversionSummary()
        guard !targets.isEmpty else { return summary }

        referenceConversion = ReferenceConversionProgress(completed: 0, total: targets.count)
        defer { referenceConversion = nil }

        for (offset, target) in targets.enumerated() {
            if Task.isCancelled {
                summary.cancelled = true
                break
            }
            defer { referenceConversion = ReferenceConversionProgress(completed: offset + 1, total: targets.count) }

            guard let index = items.firstIndex(where: { $0.id == target.id }) else { continue }
            guard FileManager.default.fileExists(atPath: items[index].sourceURL.path) else {
                summary.skippedUnavailable += 1
                items[index].isAvailable = false
                continue
            }
            do {
                try await importMusicIntoLibrary(itemAt: index,
                                                 metadata: items[index].metadata ?? TrackMetadata())
                summary.converted += 1
            } catch {
                summary.failed += 1
            }
        }
        persistCatalog()
        return summary
    }

    private func isInsideLibrary(_ url: URL) -> Bool {
        // ST-221: compara en NFC -- ver `SharedCatalogPath.catalogNormalized`.
        SharedCatalogPath.isInside(url, root: libraryRoot)
    }

    func processAll() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        // ST-221: un elemento no disponible (su archivo está en un disco
        // que no está conectado) no se procesa -- no hay de dónde leer.
        // No se toca su estado: cuando el archivo vuelva, vuelve a estar
        // en cola como estaba.
        for index in items.indices
        where items[index].status == .queued && items[index].isAvailable {
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
                //
                // ST-223: en modo copia, importar y preparar son UNA sola
                // operación -- el archivo que entra a la biblioteca ya es
                // el que viaja al iPod. En modo referencia sigue habiendo
                // dos cosas distintas: el original, que no se toca, y el
                // derivado de `.preparados/`.
                try await importOrPrepareMusic(itemAt: index, metadata: metadata)
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
                let output = stagingDestination(
                    forItem: items[index].id,
                    existingPreparedURL: items[index].preparedURL, ext: "mpg")
                /// El callback de ffmpeg corre en el hilo de lectura del
                /// pipe (readabilityHandler), no en el MainActor -- hay
                /// que saltar de vuelta explicitamente para tocar
                /// `items`, que ObservableObject espera mutar solo desde
                /// el actor principal.
                // PLAN-studio-rendimiento-2.md Fase 6 (ST-186): la
                // transcodificación y el póster se van al worker
                // (`ffmpeg` corriendo síncrono en el `@MainActor`
                // congelaba la ventana lo que durara el video). El
                // progreso sigue llegando por el mismo callback, que
                // salta de vuelta al actor principal para tocar `items`.
                let poster = output.deletingPathExtension().appendingPathExtension("jpg")
                let itemID = items[index].id
                try await fileWorker.prepareVideo(
                    LibraryFileWorker.PrepareVideoRequest(
                        sourceURL: sourceURL,
                        destinationURL: output,
                        sourceFrameRate: info?.frameRate,
                        posterURL: poster,
                        downloadedPoster: items[index].metadata?.loadCoverData(),
                        posterMaxDimension: Self.videoPosterMaxDimension),
                    onProgress: { fraction in
                        Task { @MainActor [weak self] in
                            guard let self,
                                  let current = self.items.firstIndex(where: { $0.id == itemID }) else { return }
                            self.items[current].status = .transcoding(progress: fraction)
                        }
                    })
                items[index].preparedURL = output
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
                let output = stagingDestination(
                    forItem: items[index].id,
                    existingPreparedURL: items[index].preparedURL, ext: "jpg")
                // ST-186: redimensionar una foto de cámara es medio
                // segundo largo por foto -- importar una carpeta
                // congelaba la ventana una vez por cada una.
                try await fileWorker.preparePhoto(
                    LibraryFileWorker.PreparePhotoRequest(
                        sourceURL: sourceURL, destinationURL: output,
                        maxDimension: preferences.photoQuality.maxDimension))
                // ST-183: la miniatura de una foto se cachea por id +
                // ruta del archivo preparado. Reprocesar suele escribir
                // en la MISMA ruta (cambiar la calidad de imagen, por
                // ejemplo), así que la clave no cambiaría sola y la
                // cuadrícula seguiría mostrando la versión anterior.
                CoverThumbnailCache.shared.remove(id: PhotoThumbnailID.make(for: items[index]))
                items[index].preparedURL = output
                CoverThumbnailCache.shared.remove(id: PhotoThumbnailID.make(for: items[index]))
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
            let embedded = embedCover ? metadata.loadCoverData().flatMap {
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
    /// PLAN-studio-rendimiento.md Fase 4 paso 5: `prepareMusic` corre en
    /// `fileWorker` -- mismo criterio que los pasos 1-4.
    func applyReview(id: UUID, metadata: TrackMetadata) async {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].metadata = metadata
        items[index].metadataEditedByUser = true
        let item = items[index]
        // ST-224: `refreshMusicFile` ya no lanza -- un fallo se reporta
        // en `lastError` y devuelve lo que había. Y `nil` no es un fallo:
        // en modo referencia significa que el archivo del usuario ya
        // sirve tal como está.
        let prepared = await refreshMusicFile(for: item, metadata: metadata)
        guard let currentIndex = items.firstIndex(where: { $0.id == id }) else { return }
        items[currentIndex].preparedURL = prepared
        items[currentIndex].status = metadata.isComplete ? .ready : .needsReview
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
    /// `PhotoCollection.photos`, la que pone `MediaCategoryClassifier`)
    /// nunca es candidata, aunque se llame `cover.jpg`.
    func coverContaminationCandidates() -> [CoverContaminationCandidate] {
        let context = CoverArtAssets.DropContext(urls: items.filter { $0.kind != .photo }.map(\.sourceURL))
        var out: [CoverContaminationCandidate] = []
        for item in items where item.kind == .photo {
            // La categoría real que pone `MediaCategoryClassifier` a una
            // foto con EXIF de cámara es `PhotoCollection.photos`. Acá
            // decía `"Fotografías"`, que el clasificador no devuelve
            // nunca: la guarda no se cumplía jamás y una fotografía de
            // cámara llamada `cover.jpg` sí se ofrecía como candidata,
            // justo lo que el comentario de arriba promete que no pasa.
            if item.category == PhotoCollection.photos { continue }
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
        // ST-225: acá NO se pide confirmación otra vez, y no es una
        // excepción a "ningún borrado sin confirmar" sino lo contrario.
        // Esta acción ya viene de la hoja de revisión con vista previa
        // (regla del repo: quitar una carátula de Imágenes nunca es
        // silencioso), que es una confirmación más fuerte que un
        // diálogo -- el usuario vio la imagen. Encadenar un segundo
        // diálogo genérico detrás de una revisión que ya se hizo es
        // cómo se enseña a confirmar sin leer.
        //
        // Y no hay archivo del usuario en juego: lo que se quita es la
        // ENTRADA de Imágenes, nunca el archivo, que sigue siendo la
        // carátula del álbum.
        performDeletion(ids: ids)
        dismissCoverContaminationOffer()
    }

    /// ST-225: **pide confirmación**; no borra nada todavía.
    ///
    /// Lo que había borraba con `removeItem` -- definitivo, sin
    /// confirmación y sin vuelta atrás -- el archivo copiado dentro de la
    /// biblioteca. Un clic mal dado en una tabla de doce mil canciones y
    /// el archivo no estaba en ningún lado.
    ///
    /// La confirmación vive **acá y no en las vistas**. Hay nueve sitios
    /// que eliminan (álbumes, artistas, fotos, similares, la tabla…), y
    /// una regla que dice "ningún borrado sin confirmar" no se sostiene
    /// si depende de que nueve sitios se acuerden. Acá no hay forma de
    /// saltársela.
    func deleteItems(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let doomed = items.filter { ids.contains($0.id) }
        guard !doomed.isEmpty else { return }
        let plan = LibraryDeletionPlan.plan(deleting: doomed,
                                            survivors: items.filter { !ids.contains($0.id) },
                                            libraryRoot: libraryRoot,
                                            coversDirectory: coversDirectory)
        let existingTrash = plan.toTrash.filter { FileManager.default.fileExists(atPath: $0.path) }
        let bytes = existingTrash.reduce(0) { $0 + (LibraryFileWorker.byteSize(of: $1) ?? 0) }
        pendingDeletion = PendingDeletion(ids: ids,
                                          itemCount: doomed.count,
                                          filesToTrash: existingTrash.count,
                                          bytesToTrash: bytes)
    }

    /// Lo que el diálogo de confirmación tiene que poder decir. Los
    /// números son de archivos que de verdad están en disco: prometer
    /// "se moverán 3 archivos" y mover uno es peor que no decir nada.
    struct PendingDeletion: Equatable {
        var ids: Set<UUID>
        var itemCount: Int
        var filesToTrash: Int
        var bytesToTrash: Int

        var title: String {
            LSf("library-view-model.plural.eliminar-titulo", itemCount)
        }

        var message: String {
            guard filesToTrash > 0 else {
                return itemCount == 1
                    ? LS("library-view-model.eliminar-referencia-uno")
                    : LS("library-view-model.eliminar-referencia-varios")
            }
            let size = ByteCountFormatter.string(fromByteCount: Int64(bytesToTrash), countStyle: .file)
            let files = LSf("library-view-model.plural.archivos", filesToTrash)
            // ST-225 (addendum): era el único texto de esta confirmación
            // que seguía escrito en español dentro del código. Con
            // posicionales, porque el japonés y el alemán necesitan
            // poder mover el tamaño de sitio.
            return LSf("library-view-model.eliminar-copia-papelera", files, size)
        }
    }

    @Published private(set) var pendingDeletion: PendingDeletion?

    func cancelPendingDeletion() {
        pendingDeletion = nil
    }

    /// Ejecuta la eliminación que se confirmó.
    ///
    /// Los archivos del usuario van a la **Papelera** (`trashItem`), los
    /// derivados nuestros se borran. Un fallo al mover uno no cancela el
    /// resto -- pero se cuenta y se dice: eliminar a medias en silencio
    /// deja al usuario creyendo que ya está.
    @discardableResult
    func confirmPendingDeletion() -> DeletionOutcome {
        guard let pending = pendingDeletion else { return DeletionOutcome() }
        pendingDeletion = nil
        return performDeletion(ids: pending.ids)
    }

    /// El borrado en sí, sin diálogo. Existe aparte para las pruebas y
    /// para la migración de A6, que ya confirmó una vez y no vuelve a
    /// preguntar por cada archivo.
    /// Qué se hizo. `trashed` trae la ruta **dentro de la Papelera** de
    /// cada archivo movido: es la única prueba de que fue a la Papelera y
    /// no a `removeItem`, y es lo que permite decírselo al usuario sin
    /// suponerlo.
    struct DeletionOutcome: Equatable {
        var itemsRemoved: Int = 0
        var trashed: [URL] = []
        var failures: Int = 0
    }

    @discardableResult
    func performDeletion(ids: Set<UUID>) -> DeletionOutcome {
        guard !ids.isEmpty else { return DeletionOutcome() }
        let fm = FileManager.default
        let doomed = items.filter { ids.contains($0.id) }
        let plan = LibraryDeletionPlan.plan(deleting: doomed,
                                            survivors: items.filter { !ids.contains($0.id) },
                                            libraryRoot: libraryRoot,
                                            coversDirectory: coversDirectory)

        var outcome = DeletionOutcome(itemsRemoved: doomed.count)
        for url in plan.toTrash where fm.fileExists(atPath: url.path) {
            do {
                var resulting: NSURL?
                try fm.trashItem(at: url, resultingItemURL: &resulting)
                if let resulting = resulting as URL? { outcome.trashed.append(resulting) }
            } catch {
                outcome.failures += 1
            }
        }
        let failures = outcome.failures
        for url in plan.toDelete {
            try? fm.removeItem(at: url)
        }
        if failures > 0 {
            lastError = failures == 1
                ? "No se pudo mover 1 archivo a la Papelera; el elemento sí se quitó de la biblioteca."
                : "No se pudieron mover \(failures) archivos a la Papelera; los elementos sí se quitaron de la biblioteca."
        }

        items.removeAll { ids.contains($0.id) }
        for index in playlists.indices {
            playlists[index].trackItemIDs.removeAll { ids.contains($0) }
        }
        persistCatalog()
        return outcome
    }

    // MARK: - Aviso de importación (ST-225)

    /// Lo que pasó en la última importación: repetidos que no se
    /// volvieron a agregar, y parecidos que sí se agregaron **pero
    /// conviene mirar**.
    ///
    /// La diferencia entre los dos es deliberada. Un archivo con la
    /// **misma ruta** ya es el mismo archivo, y volver a meterlo no
    /// aporta nada: se salta. Dos archivos **parecidos** en carpetas
    /// distintas pueden ser lo mismo o pueden ser deliberados -- una
    /// recopilación y el álbum, dos calidades de la misma canción -- y
    /// eso lo decide el usuario. Así que **no se descarta nada solo**:
    /// se importan y se avisa.
    struct ImportNotice: Equatable {
        var duplicatesSkipped: Int
        var similarGroups: Int

        var isEmpty: Bool { duplicatesSkipped == 0 && similarGroups == 0 }

        var message: String {
            var parts: [String] = []
            if duplicatesSkipped > 0 {
                parts.append(LSf("library-view-model.plural.duplicados-saltados", duplicatesSkipped))
            }
            if similarGroups > 0 {
                parts.append(LSf("library-view-model.plural.grupos-parecidos", similarGroups))
            }
            return Sentence.ended(Sentence.clauses(parts))
        }
    }

    @Published private(set) var lastImportNotice: ImportNotice?

    func dismissImportNotice() {
        lastImportNotice = nil
    }

    /// Busca parecidos **sin bloquear la importación**: corre aparte y
    /// actualiza el aviso cuando termina. El detector mira toda la
    /// biblioteca (es la única forma de encontrar el parecido), así que
    /// no puede correr en el camino del usuario.
    private func detectSimilarAmongNewlyImported(ids: Set<UUID>) {
        let snapshot = items
        let ignored = Set(preferences.ignoredSimilarGroups)
        Task.detached(priority: .utility) {
            let groups = SimilarItemsDetector.detect(in: snapshot, ignoredGroupIDs: ignored)
                .filter { group in group.items.contains { ids.contains($0.id) } }
            await MainActor.run { [weak self] in
                guard let self, var notice = self.lastImportNotice else { return }
                notice.similarGroups = groups.count
                self.lastImportNotice = notice.isEmpty ? nil : notice
            }
        }
    }

    // MARK: - Migración de bibliotecas anteriores (ST-226)

    /// Por qué conviene migrar, o `nil` si no hace falta. Lo calcula la
    /// carga, **solo con el catálogo**.
    @Published private(set) var migrationNeed: LibraryMigrationNeed?

    /// Cómo va la migración mientras corre.
    struct MigrationProgress: Equatable {
        var completed: Int
        var total: Int
        var currentTitle: String

        var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
        var label: String { "Migrando biblioteca… \(completed) de \(total)" }
    }

    @Published private(set) var migration: MigrationProgress?
    @Published private(set) var lastMigrationSummary: LibraryMigrationSummary?
    private var migrationTask: Task<Void, Never>?

    var isMigrating: Bool { migration != nil }

    func cancelMigration() {
        migrationTask?.cancel()
    }

    func dismissMigrationSummary() {
        lastMigrationSummary = nil
    }

    /// ST-226: pone al día una biblioteca de una versión anterior.
    ///
    /// **Nunca corre sola.** Abrir una biblioteca vieja no escribe ni un
    /// archivo: solo cuenta lo que encontró y lo dice. Migrar es una
    /// acción del usuario, y por una razón concreta -- esto reescribe
    /// etiquetas dentro de sus archivos y renombra derivados; hacerlo a
    /// espaldas de alguien que solo quería abrir la app es exactamente lo
    /// que no puede pasar.
    ///
    /// **El orden importa y no es arbitrario:**
    /// 1. Etiquetas en las copias de `Música/` -- no-op si ya coinciden.
    /// 2. Renombrar los derivados viejos a `.preparados/<ID>`, con su
    ///    póster hermano. Se **renombra**, no se recopia: el archivo ya
    ///    está bien, lo que está mal es su nombre, y recopiarlo serían
    ///    gigabytes movidos para nada.
    /// 3. Asegurar el derivado de los referenciados con la regla de A4,
    ///    **solo si hace falta**.
    /// 4. Huérfanos al final, cuando los renombrados ya dejaron de
    ///    apuntar a los nombres viejos. Hacerlo antes borraría el archivo
    ///    que el paso siguiente iba a renombrar.
    func migrateLibrary() {
        guard migrationTask == nil else { return }
        migrationTask = Task { [weak self] in
            await self?.runMigration()
            await MainActor.run { [weak self] in self?.migrationTask = nil }
        }
    }

    private func runMigration() async {
        let targets = items
        var summary = LibraryMigrationSummary()
        migration = MigrationProgress(completed: 0, total: targets.count, currentTitle: "")
        defer { migration = nil }

        for (offset, target) in targets.enumerated() {
            if Task.isCancelled { summary.cancelled = true; break }
            migration = MigrationProgress(completed: offset, total: targets.count,
                                          currentTitle: target.metadata?.title ?? target.sourceURL.lastPathComponent)
            guard let index = items.firstIndex(where: { $0.id == target.id }) else { continue }

            if renamePreparedToIdentifier(itemAt: index) { summary.preparedRenamed += 1 }
            guard items[index].kind == .music else { continue }
            let metadata = items[index].metadata ?? TrackMetadata()

            if items[index].storage == .copy {
                let result = await fileWorker.rewriteTags(metadata: metadata,
                                                          coverArtPolicy: preferences.coverArtPolicy,
                                                          at: items[index].sourceURL)
                // Solo cuenta si el archivo CAMBIÓ: decir "1 con
                // etiquetas nuevas" cuando ya decía lo mismo es contarle
                // al usuario algo que no pasó, y rompe la idempotencia
                // que la segunda corrida tiene que poder demostrar.
                if result.changed {
                    summary.tagged += 1
                } else if result.isFailure, let reason = result.reason {
                    summary.errors.append(reason)
                }
                items[index].preparedURL = items[index].sourceURL
                continue
            }

            let item = items[index]
            let result = await fileWorker.ensurePreparedMusic(
                LibraryFileWorker.EnsurePreparedMusicRequest(
                    itemID: item.id, sourceURL: item.sourceURL,
                    previousPreparedURL: item.preparedURL,
                    catalogSourceSize: item.fileSizeBytes,
                    stagingDirectory: stagingDirectory,
                    metadata: metadata,
                    audioQuality: preferences.audioQuality,
                    coverArtPolicy: preferences.coverArtPolicy))
            if let failure = result.failure {
                summary.errors.append("\(item.sourceURL.lastPathComponent): \(failure)")
            }
            if result.action == .build { summary.preparedBuilt += 1 }
            if let current = items.firstIndex(where: { $0.id == item.id }) {
                items[current].preparedURL = result.url
            }
        }
        // Y una vez más al salir: cancelar durante el ÚLTIMO elemento no
        // lo ve la comprobación de arriba -- el bucle ya no da otra
        // vuelta -- y el resumen diría "terminé" cuando el usuario pidió
        // parar.
        if Task.isCancelled { summary.cancelled = true }

        // Los huérfanos, al final y solo si no se canceló: con la lista a
        // medias se borraría un archivo que el paso que no llegó a correr
        // todavía iba a renombrar.
        if !summary.cancelled {
            let scan = OrphanScan.scan(items: items, libraryRoot: libraryRoot)
            for file in scan.files where (try? FileManager.default.removeItem(at: file.url)) != nil {
                summary.orphansDeleted += 1
            }
        }

        persistCatalog()
        // Las señales se apagan solas: `storage` quedó escrito y los
        // derivados renombrados. No hay marca de "migrada" que pueda
        // mentir.
        migrationNeed = LibraryMigrationScanner.detect(items: items, itemsWithoutStorage: 0)
        if migrationNeed?.isNeeded != true { migrationNeed = nil }
        lastMigrationSummary = summary
    }

    /// Renombra el derivado al identificador, con su póster hermano.
    ///
    /// Si el destino ya está ocupado no se toca nada: eso significa que
    /// ya hay un derivado con el nombre bueno, y el viejo es un huérfano
    /// que el paso final se lleva.
    private func renamePreparedToIdentifier(itemAt index: Int) -> Bool {
        guard LibraryMigrationScanner.hasLegacyPreparedName(items[index]) else { return false }
        guard let old = items[index].preparedURL,
              FileManager.default.fileExists(atPath: old.path) else { return false }
        let destination = stagingDirectory
            .appendingPathComponent(items[index].id.uuidString)
            .appendingPathExtension(old.pathExtension)
        guard !FileManager.default.fileExists(atPath: destination.path) else { return false }
        do {
            try FileManager.default.moveItem(at: old, to: destination)
        } catch {
            return false
        }
        for sidecar in ["lrc", "jpg"] {
            let from = old.deletingPathExtension().appendingPathExtension(sidecar)
            let to = destination.deletingPathExtension().appendingPathExtension(sidecar)
            if FileManager.default.fileExists(atPath: from.path),
               !FileManager.default.fileExists(atPath: to.path) {
                try? FileManager.default.moveItem(at: from, to: to)
            }
        }
        items[index].preparedURL = destination
        return true
    }

    // MARK: - Huérfanos (ST-225)

    /// Lo que encontró la última búsqueda de huérfanos, para que Ajustes
    /// pueda mostrar cuántos son y cuánto ocupan **antes** de borrar.
    @Published private(set) var orphanScan: OrphanScanResult?

    func scanForOrphans() {
        orphanScan = OrphanScan.scan(items: items, libraryRoot: libraryRoot)
    }

    func dismissOrphanScan() {
        orphanScan = nil
    }

    /// Borra exactamente lo que la búsqueda encontró, y nada más -- ni
    /// siquiera lo que haya aparecido entre medio. Si algo cambió, se
    /// vuelve a buscar.
    @discardableResult
    func deleteFoundOrphans() -> Int {
        guard let scan = orphanScan else { return 0 }
        orphanScan = nil
        var deleted = 0
        for file in scan.files where FileManager.default.fileExists(atPath: file.url.path) {
            if (try? FileManager.default.removeItem(at: file.url)) != nil { deleted += 1 }
        }
        return deleted
    }

    /// "Cambiar nombre" del menu contextual -- solo el TITULO mostrado/
    /// usado al armar la ruta de sincronizacion (`LibrarySync`), nunca
    /// el nombre del archivo original en disco.
    /// PLAN-studio-rendimiento.md Fase 4 paso 5: `prepareMusic` corre en
    /// `fileWorker` -- mismo criterio que los pasos 1-4.
    func renameItem(id: UUID, title: String) async {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var metadata = items[index].metadata ?? TrackMetadata()
        metadata.title = trimmed
        items[index].metadata = metadata
        items[index].metadataEditedByUser = true
        if items[index].kind == .music {
            let item = items[index]
            let prepared = await refreshMusicFile(for: item, metadata: metadata)
            guard let currentIndex = items.firstIndex(where: { $0.id == id }) else { return }
            items[currentIndex].preparedURL = prepared
            if items[currentIndex].status == .ready || items[currentIndex].status == .needsReview {
                items[currentIndex].status = metadata.isComplete ? .ready : .needsReview
            }
        }
        persistCatalog()
    }

    /// Calificacion de 0 a 5 estrellas (D-199), editable desde "Más
    /// información..." -- `nil` la borra (distinto de 0 estrellas).
    /// PLAN-studio-rendimiento.md Fase 4 paso 4: la calificación misma
    /// nunca viaja en el ID3 (va aparte en `ratings.cfg`, ver
    /// `LibrarySync.import_ratings_from_studio`) -- se ve pintada al
    /// instante con solo actualizar `metadata` en el hilo principal.
    /// ST-223: y por eso poner una estrella **no toca el archivo de
    /// audio en absoluto**.
    ///
    /// Hasta acá sí lo tocaba, y era el ejemplo más claro del defecto
    /// que esta ronda vino a arreglar: `setRating` llamaba a
    /// `prepareMusic`, que copiaba el archivo entero y reescribía el
    /// ID3 -- para escribir **exactamente los mismos bytes de etiqueta
    /// que ya tenía**, porque ninguna etiqueta tiene campo de rating.
    /// No era trabajo de más: era trabajo enteramente inútil, y en un
    /// FLAC de cincuenta megabytes se sentía.
    func setRating(_ rating: Int?, forItem id: UUID) async {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].kind == .music else { return }
        var metadata = items[index].metadata ?? TrackMetadata()
        metadata.rating = rating.map { max(0, min(5, $0)) }
        items[index].metadata = metadata
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
        // PLAN-studio-rendimiento-2.md Fase 6 (ST-186): al centro de
        // tareas, como el resto de las operaciones largas. Buscar
        // pósters es una consulta de red POR VIDEO: con veinte
        // seleccionados, el botón se quedaba gris un rato largo sin
        // decir cuántos faltaban ni dejar parar (§0.9, pendiente de la
        // ronda 1 -- ST-156 lo dejó anotado y nadie lo retomó).
        var cancelled = false
        let ordered = Array(ids)
        let handle = taskCenter.begin(
            title: LSf("library-view-model.plural.buscando-posters", ordered.count),
            kind: .artwork,
            progress: .determinate(completed: 0, total: ordered.count),
            onCancelRequested: { cancelled = true })
        defer { taskCenter.finish(handle) }
        var found = 0
        var missing: [String] = []
        var missingKey = false
        for (completed, id) in ordered.enumerated() {
            if cancelled { break }
            handle.update(.determinate(completed: completed, total: ordered.count))
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
                metadata.setCover(result.data)
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
            var parts = [LSf("library-view-model.plural.posters-encontrados", found)]
            if !missing.isEmpty {
                let ejemplos = Sentence.commaList(Array(missing.prefix(3)))
                    + (missing.count > 3 ? "…" : "")
                parts.append(LSf("library-view-model.sin-resultado-ejemplos",
                                 LSf("library-view-model.plural.sin-resultado", missing.count),
                                 ejemplos))
            }
            lastEnrichmentSummary = Sentence.ended(Sentence.commaList(parts))
        }
        if found > 0 { persistCatalog() }
    }

    /// Escribe `<preparado>.jpg` desde la carátula (JPEG baseline,
    /// lado mayor <= 640) si el video ya esta preparado; si no, se
    /// escribira al procesarlo (`process(itemAt:)`).
    private func writeVideoPoster(forItemAt index: Int) {
        guard let prepared = items[index].preparedURL,
              let data = items[index].metadata?.loadCoverData() else { return }
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
        metadata.setCover(nil)
        items[index].metadata = metadata
        CoverStore.remove(forItem: items[index].id, in: libraryRoot)
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
        // ST-186: al centro de tareas. `ArtistImageResolver` va a
        // MusicBrainz, que está limitado a 1 pedido por segundo: con 250
        // artistas esto son minutos, y hasta ahora la única señal era un
        // spinner en un botón.
        var cancelled = false
        let handle = taskCenter.begin(
            title: LSf("library-view-model.plural.buscando-artistas", artists.count),
            kind: .artwork,
            progress: .determinate(completed: 0, total: artists.count),
            onCancelRequested: { cancelled = true })
        defer { taskCenter.finish(handle) }
        var found = 0
        var missing = 0
        var skipped = 0
        for (completed, artist) in artists.enumerated() {
            if cancelled { break }
            handle.update(.determinate(completed: completed, total: artists.count),
                          statusText: artist.name)
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
            var parts = [LSf("library-view-model.plural.fotos-encontradas", found)]
            if missing > 0 { parts.append(LSf("library-view-model.plural.sin-resultado", missing)) }
            if skipped > 0 { parts.append(LSf("library-view-model.plural.ya-tenian-foto", skipped)) }
            lastEnrichmentSummary = Sentence.ended(Sentence.commaList(parts))
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
    func clearCoverArt(id: UUID) async {
        await clearCoverArt(ids: [id])
    }

    /// PLAN-studio-rendimiento.md Fase 3 punto 4: igual que
    /// `clearCoverArt(id:)` pero para una selección múltiple completa,
    /// con una sola llamada a `persistCatalog()` al final -- antes, el
    /// menú contextual sobre varias canciones llamaba
    /// `clearCoverArt(id:)` una vez POR ÍTEM (`MediaSectionView.
    /// clearCoverArtMenuAction` o equivalente), y cada una reescribía el
    /// catálogo entero.
    /// Fase 4 paso 5: `prepareMusic` corre en `fileWorker`, en lotes --
    /// mismo patrón que `applyBatchEdit` (paso 2).
    func clearCoverArt(ids: Set<UUID>) async {
        let targets = items.filter { ids.contains($0.id) && $0.kind == .music }
        guard !targets.isEmpty else { return }

        var pendingResults: [UUID: (metadata: TrackMetadata, preparedURL: URL?)] = [:]
        var lastFlush = Date()

        for (completed, item) in targets.enumerated() {
            var metadata = item.metadata ?? TrackMetadata()
            metadata.setCover(nil)
            let prepared = await refreshMusicFile(for: item, metadata: metadata)
            pendingResults[item.id] = (metadata, prepared)
            CoverStore.remove(forItem: item.id, in: libraryRoot)

            let shouldFlush = pendingResults.count >= Self.batchApplySize
                || Date().timeIntervalSince(lastFlush) >= Self.batchApplyInterval
                || completed == targets.count - 1
            if shouldFlush, !pendingResults.isEmpty {
                applyPendingClearCoverArtResults(pendingResults)
                pendingResults.removeAll(keepingCapacity: true)
                lastFlush = Date()
            }
        }
        persistCatalog()
    }

    private func applyPendingClearCoverArtResults(_ results: [UUID: (metadata: TrackMetadata, preparedURL: URL?)]) {
        for index in items.indices where results[items[index].id] != nil {
            let result = results[items[index].id]!
            items[index].metadata = result.metadata
            items[index].metadataEditedByUser = true
            items[index].preparedURL = result.preparedURL
        }
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
        // ST-185: comparar por hash y no por bytes -- antes, aplicar una
        // carátula a un álbum comparaba los ~15 KB contra los de cada
        // una de sus pistas.
        let normalizedHash = CoverStore.hash(normalized)
        let targets = items.filter {
            ids.contains($0.id) && $0.kind == .music && $0.metadata?.coverHash != normalizedHash
        }
        guard !targets.isEmpty else { return 0 }

        let handle = taskCenter.begin(title: LSf("library-view-model.plural.aplicando-caratula", targets.count),
                                      progress: .determinate(completed: 0, total: targets.count))
        defer { taskCenter.finish(handle) }

        var pendingResults: [UUID: (metadata: TrackMetadata, preparedURL: URL?)] = [:]
        var lastFlush = Date()

        for (completed, item) in targets.enumerated() {
            var metadata = item.metadata ?? TrackMetadata()
            metadata.setCover(normalized)
            let prepared = await refreshMusicFile(for: item, metadata: metadata)
            // ST-224: `nil` no es "no se pudo", es "no hace falta
            // ninguno". Rellenarlo con el anterior dejaría el catálogo
            // apuntando a un derivado que ya no corresponde.
            pendingResults[item.id] = (metadata, prepared)

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

        // PLAN-studio-rendimiento-2.md Fase 3 (ST-182): la acción es
        // ahora PLURAL de verdad -- puede tocar los 1 000 álbumes de la
        // biblioteca, con una búsqueda en red por álbum. Eso no puede
        // ser un botón que se queda gris sin decir nada: va al centro de
        // tareas con progreso "N de M" y cancelación, como el resto de
        // las operaciones largas (§A: "todas con indicador y cancelación
        // en el centro de tareas").
        var cancelled = false
        let handle = taskCenter.begin(
            title: requests.count == 1
                ? "Buscando carátula recomendada…"
                : "Buscando carátulas de \(requests.count) álbumes…",
            kind: .artwork,
            progress: .determinate(completed: 0, total: requests.count),
            onCancelRequested: { cancelled = true })
        defer { taskCenter.finish(handle) }

        var applied = 0
        var needsChoice: [AlbumCoverRequest] = []
        var withoutResults = 0
        var skippedByCancel = 0

        for (completed, request) in requests.enumerated() {
            // Cancelar NO deshace lo ya aplicado (cada álbum es una
            // operación terminada en sí misma): deja de empezar los que
            // faltan y lo dice en el resumen.
            if cancelled {
                skippedByCancel = requests.count - completed
                break
            }
            handle.update(.determinate(completed: completed, total: requests.count),
                          statusText: "«\(request.albumTitle)» — \(completed + 1) de \(requests.count)")

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
        handle.update(.determinate(completed: requests.count - skippedByCancel, total: requests.count))

        var parts = [LSf("library-view-model.plural.caratulas-aplicadas", applied)]
        if !needsChoice.isEmpty {
            parts.append(LSf("library-view-model.plural.sin-opcion-segura", needsChoice.count))
        }
        if withoutResults > 0 { parts.append(LSf("library-view-model.plural.sin-resultado", withoutResults)) }
        if skippedByCancel > 0 { parts.append(LSf("library-view-model.plural.sin-revisar-cancelaste", skippedByCancel)) }
        lastEnrichmentSummary = Sentence.ended(Sentence.commaList(parts))
        // Cancelar tampoco encola pickers de lo que sí alcanzó a
        // revisarse: si el usuario paró, paró.
        return cancelled ? [] : needsChoice
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

        let handle = taskCenter.begin(title: LSf("library-view-model.plural.editando", targets.count),
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

            let preparedURL = await refreshMusicFile(for: item, metadata: metadata)
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

        let handle = taskCenter.begin(title: LSf("library-view-model.plural.corrigiendo", targets.count),
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
                let prepared = await refreshMusicFile(for: item, metadata: metadata)
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
    /// Fase 4 paso 5: `prepareMusic` corre en `fileWorker`, en lotes --
    /// mismo patrón que `applyBatchEdit` (paso 2).
    func reenrichOnline(ids: Set<UUID>, fetchAlbumInfo: Bool, fetchLyrics: Bool) async {
        let targets = items.filter { ids.contains($0.id) && $0.kind == .music }
        guard !targets.isEmpty else { return }
        // PLAN-studio-rendimiento-2.md Fase 6 (ST-186): una búsqueda en
        // línea a la vez. Nada impedía disparar dos -- desde Álbumes y
        // desde Canciones, por ejemplo -- y las dos se repartían el mismo
        // cupo de 1 pedido/segundo de MusicBrainz: el doble de espera
        // para cada una, sin que nada terminara antes.
        guard !taskCenter.isRunning(.enrichment) else { return }

        var found = 0
        var withoutResult = 0
        var networkErrors: [String] = []

        // PLAN-studio-rendimiento.md Fase 4: primera operación real
        // conectada al centro de tareas -- "N de M" en vez del banner
        // fijo de siempre. El límite de 1 pedido/segundo de MusicBrainz
        // ya lo aplica `enricher` por dentro; el centro solo muestra el
        // progreso, no lo acelera.
        let handle = taskCenter.begin(title: "Buscando información en línea…", kind: .enrichment,
                                      progress: .determinate(completed: 0, total: targets.count))
        defer { taskCenter.finish(handle) }

        var pendingResults: [UUID: (metadata: TrackMetadata, preparedURL: URL?, status: LibraryItemStatus)] = [:]
        var lastFlush = Date()

        for (completed, item) in targets.enumerated() {
            let current = item.metadata ?? TrackMetadata()
            let (updated, outcome) = await enricher.reenrich(
                item: item, currentMetadata: current,
                fetchAlbumInfo: fetchAlbumInfo, fetchLyrics: fetchLyrics,
                coverArtOrder: preferences.coverArtProviderOrder,
                deezerEnabled: preferences.deezerEnabled)
            let prepared = await refreshMusicFile(for: item, metadata: updated)
            pendingResults[item.id] = (updated, prepared, updated.isComplete ? .ready : .needsReview)

            handle.update(.determinate(completed: completed + 1, total: targets.count),
                          statusText: "\(completed + 1) de \(targets.count)")

            if let message = outcome.networkErrorMessage {
                networkErrors.append(message)
            } else if outcome.albumInfoFound || outcome.lyricsFound {
                found += 1
            } else {
                withoutResult += 1
            }

            let shouldFlush = pendingResults.count >= Self.batchApplySize
                || Date().timeIntervalSince(lastFlush) >= Self.batchApplyInterval
                || completed == targets.count - 1
            if shouldFlush, !pendingResults.isEmpty {
                applyPendingReenrichResults(pendingResults)
                pendingResults.removeAll(keepingCapacity: true)
                lastFlush = Date()
            }
        }
        persistCatalog()

        let attempted = targets.count
        if !networkErrors.isEmpty {
            lastError = "No se pudo completar la busqueda para \(networkErrors.count) de \(attempted) cancion(es): \(networkErrors[0])"
        }
        lastEnrichmentSummary = found == 0
            ? "No se encontro informacion nueva para ninguna de las \(attempted) cancion(es) seleccionadas."
            : "Se encontro informacion nueva para \(found) de \(attempted) cancion(es)."
    }

    private func applyPendingReenrichResults(_ results: [UUID: (metadata: TrackMetadata, preparedURL: URL?, status: LibraryItemStatus)]) {
        for index in items.indices where results[items[index].id] != nil {
            let result = results[items[index].id]!
            items[index].metadata = result.metadata
            items[index].preparedURL = result.preparedURL
            items[index].status = result.status
        }
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
    /// Fase 4 paso 5: `prepareMusic` corre en `fileWorker`, en lotes --
    /// mismo patrón que `applyBatchEdit` (paso 2).
    func rereadLocalTags(ids: Set<UUID>, respectUserEdits: Bool = false) async {
        let targets = items.filter {
            ids.contains($0.id) && $0.kind == .music && !(respectUserEdits && $0.metadataEditedByUser)
        }
        guard !targets.isEmpty else { return }

        var updated = 0
        var pendingResults: [UUID: (metadata: TrackMetadata, preparedURL: URL?, status: LibraryItemStatus)] = [:]
        var lastFlush = Date()

        for (completed, item) in targets.enumerated() {
            let fresh = await LocalTagReader.readTag(from: item.sourceURL)
            let current = item.metadata ?? TrackMetadata()
            let merged = mergingLocalTags(fresh, into: current)
            if merged != current { updated += 1 }
            let prepared = await refreshMusicFile(for: item, metadata: merged)
            pendingResults[item.id] = (merged, prepared, merged.isComplete ? .ready : .needsReview)

            let shouldFlush = pendingResults.count >= Self.batchApplySize
                || Date().timeIntervalSince(lastFlush) >= Self.batchApplyInterval
                || completed == targets.count - 1
            if shouldFlush, !pendingResults.isEmpty {
                applyPendingRereadLocalTagsResults(pendingResults)
                pendingResults.removeAll(keepingCapacity: true)
                lastFlush = Date()
            }
        }
        persistCatalog()

        let attempted = targets.count
        lastEnrichmentSummary = updated == 0
            ? "No habia nada que actualizar en \(attempted) cancion(es): ya tenian lo que traen sus archivos."
            : "Se actualizaron \(updated) de \(attempted) cancion(es) con lo que traen sus archivos."
    }

    private func applyPendingRereadLocalTagsResults(_ results: [UUID: (metadata: TrackMetadata, preparedURL: URL?, status: LibraryItemStatus)]) {
        for index in items.indices where results[items[index].id] != nil {
            let result = results[items[index].id]!
            items[index].metadata = result.metadata
            items[index].preparedURL = result.preparedURL
            items[index].status = result.status
        }
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
        // ST-185: `fresh` viene de leer el archivo, así que su carátula
        // (si trae) está en `pendingCoverData`; si no trae, se conserva
        // la que ya está guardada en `.portadas/`.
        if let freshCover = fresh.pendingCoverData {
            merged.setCover(CoverArtNormalizer.normalized(freshCover))
        } else {
            merged.coverURL = current.coverURL
            merged.coverHash = current.coverHash
            merged.pendingCoverData = current.pendingCoverData
        }
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

    /// ST-189: el estado del volumen de la biblioteca.
    @Published private(set) var libraryAvailability: LibraryAvailability = .available

    /// Lo que se hace al arrancar, al cambiar de carpeta y al volver el
    /// disco. Con el volumen ausente **no se toca nada**: ni se crea la
    /// estructura, ni se lee el catálogo, ni se saca ninguna conclusión
    /// sobre una biblioteca que no se pudo leer.
    private func prepareLibraryIfAvailable() {
        guard libraryAvailability == .available else {
            items = []
            playlists = []
            return
        }
        ensureLibraryStructure()
        migrateLegacyLibraryLayoutIfNeeded()
        loadCatalog()
    }

    /// ST-189: montar y desmontar son EVENTOS, no algo que haya que ir a
    /// preguntar. Windows (ST-171) sondea cada 5 s porque una unidad de
    /// red puede tardar en responder; en macOS `NSWorkspace` avisa, así
    /// que no hace falta ninguna barrida periódica.
    private func observeVolumeChanges() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            center.publisher(for: name)
                .sink { [weak self] _ in self?.refreshLibraryAvailability() }
                .store(in: &cancellables)
        }
    }

    /// Vuelve a mirar si el volumen está, y recarga si acaba de volver.
    /// También es lo que hace el botón "Reintentar" de la pantalla.
    func refreshLibraryAvailability() {
        let now = LibraryRoot.availability(of: libraryRoot)
        guard now != libraryAvailability else { return }
        libraryAvailability = now
        if now == .available {
            prepareLibraryIfAvailable()
        } else {
            // Se fue el disco con la app abierta: no se borra nada de lo
            // que ya estaba en pantalla por las malas, pero tampoco se
            // sigue escribiendo (ver las guardias de abajo).
            cancelCoverNormalization()
        }
    }

    private func ensureLibraryStructure() {
        guard libraryAvailability == .available else { return }
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
        items = []
        playlists = []
        // La carpeta cambió: el hash de la última carátula escrita era
        // de la carpeta anterior, ya no dice nada de ésta.
        lastWrittenCoverHash = [:]
        // ST-189: la carpeta nueva puede estar en un disco que no está
        // conectado -- se evalúa antes de tocarla, igual que al arrancar.
        libraryAvailability = LibraryRoot.availability(of: libraryRoot)
        prepareLibraryIfAvailable()
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
        // ST-189: con el volumen ausente, "no encontré carátulas que
        // normalizar" NO significa "ya está todo normalizado" -- es
        // exactamente el camino por el que Windows terminaba escribiendo
        // esa conclusión sobre una biblioteca que no pudo leer.
        guard libraryAvailability == .available else { return }
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

    /// ST-141: tras la migración de carátulas, los archivos de
    /// `.portadas/` cambiaron en disco.
    /// ST-185: ya no hay que recargar bytes a memoria -- lo único que
    /// cambia es el HASH, que es lo que identifica la miniatura. Se
    /// recalcula leyendo cada archivo una vez (esto corre una sola vez
    /// en la vida de la biblioteca, al terminar la migración).
    private func reloadCoversFromDisk() {
        for index in items.indices where items[index].kind == .music {
            let url = CoverStore.url(forItem: items[index].id, in: libraryRoot)
            guard let hash = CoverStore.hashOfFile(at: url),
                  var metadata = items[index].metadata, metadata.coverHash != hash else { continue }
            metadata.coverURL = url
            metadata.coverHash = hash
            metadata.pendingCoverData = nil
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
            metadata: LibraryPersistenceMapper.liveMetadata(persistedItem.metadata),
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
            audioQuality: preferences.audioQuality, coverArtPolicy: preferences.coverArtPolicy,
            itemID: item.id, previousPreparedURL: item.preparedURL)
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
        adoptStoredCovers(result.storedCovers)
        if let error = result.errorDescription {
            lastError = error
        }
    }

    /// PLAN-studio-rendimiento-2.md Fase 5 (ST-185): **acá es donde los
    /// JPEG salen de la memoria.**
    ///
    /// El guardado del catálogo escribió estas carátulas en `.portadas/`
    /// (fuera del hilo principal, que es donde ya corría). Al anotar
    /// dónde quedaron y con qué hash, `pendingCoverData` deja de hacer
    /// falta y se suelta: a partir de ahí, quien necesite los bytes los
    /// lee del archivo, y quien solo necesite identificarlos —las
    /// miniaturas, el `Equatable`— usa el hash.
    ///
    /// Es un `for` sobre `items`, pero solo entra a las que de verdad
    /// cambiaron: `storedCovers` trae únicamente las que este guardado
    /// escribió, no las 12 000.
    private func adoptStoredCovers(_ storedCovers: [UUID: CatalogPersister.StoredCover]) {
        guard !storedCovers.isEmpty else { return }
        for index in items.indices {
            guard let stored = storedCovers[items[index].id],
                  var metadata = items[index].metadata else { continue }
            // Si mientras se guardaba entró una carátula MÁS nueva, no
            // se pisa: el hash de la que está en memoria ya no es el que
            // se acaba de escribir, y el próximo guardado la escribirá.
            guard metadata.coverHash == stored.hash else { continue }
            metadata.coverURL = stored.url
            metadata.pendingCoverData = nil
            items[index].metadata = metadata
        }
    }

    /// PLAN-studio-rendimiento.md Fase 3 punto 1: para ediciones rápidas
    /// individuales (una estrella, una categoría) -- varias seguidas
    /// coalescen en un solo guardado real, con la escritura fuera del
    /// hilo principal. `persistCatalog()` sigue siendo el guardado
    /// inmediato de siempre (acciones en lote, y cualquier sitio que
    /// necesite la garantía de que ya quedó en disco al volver).
    func schedulePersistCatalog() {
        // ST-189: sin el volumen no se escribe. Con la biblioteca en un
        // disco desmontado, escribir el catálogo crearía la carpeta como
        // carpeta común dentro de `/Volumes` y dejaría ahí un catálogo
        // que no es el del usuario.
        guard libraryAvailability == .available else { return }
        catalogPersister.schedule(makeCatalogSnapshot()) { [weak self] result in
            self?.applyCatalogWriteResult(result)
        }
    }

    /// Guardado inmediato y síncrono -- para salir de la app o pasar a
    /// segundo plano, donde hace falta la garantía de que el archivo
    /// quedó escrito antes de que el proceso pueda morir (un guardado
    /// programado que sigue corriendo por detrás no sirve ahí).
    func flushPendingPersistence() {
        // ST-189: sin el volumen no se escribe. Con la biblioteca en un
        // disco desmontado, escribir el catálogo crearía la carpeta como
        // carpeta común dentro de `/Volumes` y dejaría ahí un catálogo
        // que no es el del usuario.
        guard libraryAvailability == .available else { return }
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
        // ST-189: ver la nota en `schedulePersistCatalog()`.
        guard libraryAvailability == .available else { return }
        applyCatalogWriteResult(catalogPersister.writeNow(makeCatalogSnapshot()))
    }

    /// PLAN-studio-rendimiento.md Fase 4 paso 6 (Fase 5.1): medido en
    /// `testLoadCatalogCold` -- ~1.9 s en frío con 12 000 ítems, TODO
    /// en el hilo principal dentro de `init()`. El costo es real e
    /// inherente (3 `fileExists` + 1 lectura de ~15 KB por ítem, cada
    /// canción tiene su PROPIA carátula en `.portadas/<UUID>.jpg` --
    /// no hay una ruta compartida que deduplicar aunque el contenido
    /// se repita dentro de un álbum), así que se resuelve cada ítem en
    /// paralelo (`DispatchQueue.concurrentPerform`, un hilo por
    /// núcleo) en vez de uno a la vez. Sigue siendo SÍNCRONA de cara a
    /// quien llama -- `loadCatalog()`/`init()` no cambian de firma,
    /// cero impacto en los 70+ sitios de prueba que hoy leen `.items`
    /// justo después de construir el ViewModel.
    private func loadCatalog() {
        guard let data = try? Data(contentsOf: catalogURL),
              let persisted = try? JSONDecoder().decode(PersistedLibrary.self, from: data) else { return }

        let fm = FileManager.default
        let root = libraryRoot
        let persistedItems = persisted.items
        // ST-226: **este es el único sitio donde se ve el valor crudo.**
        // Un elemento sin `storage` es señal de biblioteca anterior a
        // 0.4.0, y para cuando termine esta carga ya estará inferido y no
        // quedará rastro de que faltaba. Se cuenta acá o no se cuenta.
        // Es una lectura del catálogo que ya está en memoria: no toca
        // disco, que es lo que las rondas anteriores sacaron de la carga.
        let itemsWithoutStorage = persistedItems.filter { $0.storage == nil }.count
        var resolved = [LibraryItem?](repeating: nil, count: persistedItems.count)
        resolved.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: persistedItems.count) { index in
                let p = persistedItems[index]
                // ST-102: `SharedCatalogPath` resuelve la ruta con
                // tolerancia -- ruta absoluta de macOS tal cual (modo
                // "sin copiar medios", D-192), separadores `\` de un
                // catalogo escrito por Aura Studio en Windows
                // (biblioteca COMPARTIDA), y las dos normalizaciones
                // Unicode. Devuelve `nil` cuando NINGUNA forma existe.
                //
                // ST-221 (paridad con Windows): que no exista **ya no
                // borra el elemento**. Hasta acá se omitía en silencio y
                // el siguiente guardado lo perdía para siempre: bastaba
                // abrir la app con el disco de los originales
                // desconectado para que la biblioteca se vaciara sola.
                // Ahora se conserva con la ruta que el catálogo nombra y
                // marcado como **no disponible**; no se puede preparar ni
                // sincronizar, pero sigue existiendo y vuelve solo cuando
                // el archivo vuelve.
                let existingURL = SharedCatalogPath.resolve(p.sourceRelativePath, in: root, fileManager: fm)
                guard let sourceURL = existingURL
                        ?? SharedCatalogPath.recordedURL(p.sourceRelativePath, in: root)
                else { return }
                let isAvailable = existingURL != nil

                // PLAN-studio-rendimiento-2.md Fase 5 (ST-185): acá se
                // leía el JPEG ENTERO de cada carátula al catálogo, y de
                // ahí no salía más -- unos 180 MB con 12 000 canciones
                // (§0.8). Ahora solo se guarda dónde está y su hash.
                //
                // Si el catálogo es viejo y no trae `coverHash`, se
                // calcula leyendo el archivo UNA vez: es la migración, y
                // corre acá porque este bucle ya es paralelo y fuera del
                // hilo principal (ST-157). Nunca se recorre `.portadas/`
                // -- solo se leen los archivos que el catálogo nombra.
                let coverURL = SharedCatalogPath
                    .coverURL(recorded: p.coverRelativePath, itemID: p.id, in: root, fileManager: fm)
                let coverHash = coverURL.flatMap { url in
                    p.coverHash ?? CoverStore.hashOfFile(at: url)
                }
                let preparedURL = p.preparedRelativePath
                    .flatMap { SharedCatalogPath.resolve($0, in: root, fileManager: fm) }
                // ST-224: que NO haya derivado es un estado válido en
                // modo referencia -- quiere decir que el archivo del
                // usuario ya sirve tal como está. Lo que sí es un
                // problema es que el catálogo NOMBRE uno que ya no está.
                let preparedIsMissing = p.preparedRelativePath != nil && preparedURL == nil

                var status = LibraryPersistenceMapper.liveStatus(p.status)
                if status == .ready && preparedIsMissing {
                    // "Listo" sin su archivo preparado no es listo: se
                    // vuelve a encolar y el proximo procesamiento lo
                    // regenera.
                    status = .queued
                }

                buffer[index] = LibraryItem(
                    id: p.id,
                    sourceURL: sourceURL,
                    kind: LibraryPersistenceMapper.liveKind(p.kind),
                    status: status,
                    metadata: LibraryPersistenceMapper.liveMetadata(p.metadata, coverURL: coverURL, coverHash: coverHash),
                    preparedURL: preparedURL,
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
                    addedAt: p.addedAt,
                    fileSizeBytes: p.fileSizeBytes,
                    // ST-221: el modo viene del catálogo; si no está
                    // (biblioteca anterior a 0.4.0) se infiere UNA vez y
                    // el siguiente guardado lo deja escrito.
                    storage: LibraryStorageMode.fromPersisted(p.storage)
                        ?? LibraryStorageMode.infer(sourceURL: sourceURL, libraryRoot: root),
                    isAvailable: isAvailable
                )
            }
        }
        // El orden importa (Library.items se muestra tal cual en
        // varias vistas sin reordenar) -- `compactMap` sobre el buffer
        // preserva el orden original del catálogo pese a resolverse
        // en paralelo.
        items = resolved.compactMap { $0 }
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
        // ST-226: la detección es solo del catálogo, sin tocar disco.
        migrationNeed = LibraryMigrationScanner.detect(items: items,
                                                       itemsWithoutStorage: itemsWithoutStorage)
        evaluateLegacyMetadataRereadOffer()
        evaluateCoverContaminationOffer()
        startCoverNormalizationIfNeeded()
        measureMissingFileSizes()
    }

    private var fileSizeMeasurementTask: Task<Void, Never>?

    /// PLAN-studio-rendimiento-2.md Fase 6 (ST-186), punto 1.4: rellena
    /// `fileSizeBytes` de lo que todavía no lo tenga.
    ///
    /// Corre **fuera del hilo principal y por lotes**, y publica una sola
    /// vez al final: medir 12 000 archivos es rápido en un disco local y
    /// lento en uno de red, y en los dos casos no tiene por qué notarse.
    /// Nada depende de que termine -- mientras tanto, quien necesite un
    /// tamaño lo mide con la caché por ruta de `LibraryStats`.
    ///
    /// Se guarda **una vez**, al final: es el mismo criterio que Windows
    /// (ST-201) y evita que el relleno dispare doce mil guardados.
    func measureMissingFileSizes() {
        fileSizeMeasurementTask?.cancel()
        let pending = items.filter { $0.fileSizeBytes == nil }
            .map { (id: $0.id, path: $0.sourceURL.path) }
        guard !pending.isEmpty else { return }

        fileSizeMeasurementTask = Task.detached(priority: .utility) { [weak self] in
            var measured: [UUID: Int] = [:]
            measured.reserveCapacity(pending.count)
            for entry in pending {
                if Task.isCancelled { return }
                let size = LibraryStats.fileSize(atPath: entry.path)
                if size > 0 { measured[entry.id] = Int(size) }
            }
            guard !Task.isCancelled else { return }
            await self?.applyMeasuredFileSizes(measured)
        }
    }

    private func applyMeasuredFileSizes(_ measured: [UUID: Int]) {
        guard !measured.isEmpty else { return }
        var changed = false
        for index in items.indices {
            guard items[index].fileSizeBytes == nil,
                  let size = measured[items[index].id] else { continue }
            items[index].fileSizeBytes = size
            changed = true
        }
        // Un solo guardado por todo el relleno.
        if changed { schedulePersistCatalog() }
    }

    private func relativePath(of url: URL) -> String {
        SharedCatalogPath.relativePath(of: url, in: libraryRoot)
    }
}
