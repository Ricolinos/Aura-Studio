import Foundation

/// Bandera de cancelacion thread-safe: `LibrarySync.sync()` corre
/// sincrono dentro de un `Task.detached` (D-217) y consulta
/// `isCancelled` desde ese hilo de fondo; `cancel()` se llama desde el
/// MainActor cuando el usuario pulsa "Cancelar". `NSLock` en vez de un
/// `actor` a proposito: `sync()` no es `async`, no puede `await` en
/// medio de cada bloque de 4 MB sin reescribir todo el metodo como
/// asincrono -- una lectura/escritura protegida por lock es instantanea
/// y alcanza para esto.
final class SyncCancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flagged = false

    func cancel() {
        lock.lock()
        flagged = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flagged
    }
}

/// Registro de un archivo ya sincronizado, para decidir en la proxima
/// pasada si hace falta copiarlo de nuevo. Se compara por tamaño +
/// fecha de modificacion (igual que rsync por defecto) en vez de
/// hashear cada archivo entero en cada sync -- con bibliotecas de miles
/// de canciones, hashear todo cada vez seria demasiado lento para algo
/// que en la gran mayoria de los casos no cambio.
struct SyncRecord: Codable, Equatable {
    let sourcePath: String
    let sourceSize: Int64
    let sourceModifiedAt: TimeInterval
    let destinationRelativePath: String
    /// PLAN-general-sync.md §4.2/§9 (v2 del manifiesto, opcionales para
    /// que un manifiesto v1 -- sin estas claves -- siga decodificando:
    /// un `Codable` sintetizado con un campo no-opcional exigiria la
    /// clave, y `try? JSONDecoder().decode` tiraria el manifiesto
    /// ENTERO si faltara una sola). `destinationSize`/
    /// `destinationModifiedAt` son la huella del archivo TAL COMO QUEDO
    /// en el iPod justo despues de copiarlo -- comparada contra un
    /// `stat()` real del destino, es lo que distingue "sincronizado" de
    /// "modificado en el iPod fuera de Aura Studio". Un registro v1 sin
    /// estos campos se trata como no verificable (ver
    /// PLAN-general-sync.md §4.2: "se rellenan en el primer sync").
    var destinationSize: Int64?
    var destinationModifiedAt: TimeInterval?
    /// `AppPreferences.installationID` de la Mac que escribio este
    /// registro -- dos Macs sincronizando el mismo iPod no se pisan:
    /// cada una solo trata como "propios" los registros con su propio
    /// id (P7).
    var writtenBy: String?
    var syncedAt: TimeInterval?

    init(sourcePath: String, sourceSize: Int64, sourceModifiedAt: TimeInterval,
         destinationRelativePath: String, destinationSize: Int64? = nil,
         destinationModifiedAt: TimeInterval? = nil, writtenBy: String? = nil,
         syncedAt: TimeInterval? = nil) {
        self.sourcePath = sourcePath
        self.sourceSize = sourceSize
        self.sourceModifiedAt = sourceModifiedAt
        self.destinationRelativePath = destinationRelativePath
        self.destinationSize = destinationSize
        self.destinationModifiedAt = destinationModifiedAt
        self.writtenBy = writtenBy
        self.syncedAt = syncedAt
    }
}

struct SyncManifest: Codable, Equatable {
    var records: [String: SyncRecord] // key = sourcePath
    /// `nil` = manifiesto v1 (de antes de este campo). PLAN-general-sync.md §9.
    var contractVersion: Int?

    static let currentContractVersion = 2

    static let empty = SyncManifest(records: [:], contractVersion: currentContractVersion)

    init(records: [String: SyncRecord], contractVersion: Int? = currentContractVersion) {
        self.records = records
        self.contractVersion = contractVersion
    }
}

enum SyncPlanAction: Equatable {
    case copy
    case skip
}

struct SyncPlanItem: Equatable {
    let sourcePath: String
    let destinationRelativePath: String
    let action: SyncPlanAction
    /// Fase 24: no-nil cuando `destinationRelativePath` cambio desde el
    /// ultimo sync (p. ej. la migracion de rutas planas a
    /// `Music/<Artista>/<Album>/...`) -- LibrarySync usa esto para
    /// borrar el archivo viejo en vez de dejarlo huerfano en el iPod.
    let staleDestinationRelativePath: String?

    init(sourcePath: String, destinationRelativePath: String, action: SyncPlanAction, staleDestinationRelativePath: String? = nil) {
        self.sourcePath = sourcePath
        self.destinationRelativePath = destinationRelativePath
        self.action = action
        self.staleDestinationRelativePath = staleDestinationRelativePath
    }
}

/// Logica pura de diferenciacion: dado un manifiesto anterior y el
/// estado actual de los archivos preparados, decide que copiar y que
/// saltear. Separada de LibrarySync (que hace la copia real) para que
/// se pueda testear sin tocar disco ni un iPod de verdad.
enum SyncPlanner {
    static func plan(
        current: [(sourcePath: String, size: Int64, modifiedAt: TimeInterval, destinationRelativePath: String)],
        previousManifest: SyncManifest
    ) -> [SyncPlanItem] {
        current.map { file in
            let previous = previousManifest.records[file.sourcePath]
            if let previous,
               previous.sourceSize == file.size,
               previous.sourceModifiedAt == file.modifiedAt,
               previous.destinationRelativePath == file.destinationRelativePath {
                return SyncPlanItem(sourcePath: file.sourcePath, destinationRelativePath: file.destinationRelativePath, action: .skip)
            }
            let stale: String?
            if let previous, previous.destinationRelativePath != file.destinationRelativePath {
                stale = previous.destinationRelativePath
            } else {
                stale = nil
            }
            return SyncPlanItem(sourcePath: file.sourcePath, destinationRelativePath: file.destinationRelativePath, action: .copy, staleDestinationRelativePath: stale)
        }
    }
}

/// Ejecuta la sincronizacion real contra el volumen montado del iPod:
/// copia solo lo que `SyncPlanner` marco como `.copy`, actualiza el
/// manifiesto, y borra el indice de tagcache del dispositivo para que
/// Aura lo reconstruya solo en el proximo arranque -- reusa la misma
/// logica de reconstruccion ya verificada en el firmware (D-021/D-023
/// en DECISIONS.md), en vez de intentar hablarle al formato binario de
/// tagcache directamente desde macOS.
/// Resultado de un `sync()`, para que la UI pueda distinguir "no habia
/// nada nuevo" de "se copio musica pero ninguna playlist tenia pistas
/// ya sincronizadas" en vez de un unico numero ambiguo.
struct SyncResult: Equatable {
    let filesCopied: Int
    let playlistsWritten: Int
    /// PLAN-general-sync.md §8.3: `true` cuando `isCancelled` corto la
    /// copia antes de terminar el plan -- `finalize` (portadas,
    /// playlists, resumen, indice) igual corrio para lo que SI se
    /// alcanzo a copiar, asi que el iPod queda consistente.
    var wasCancelled: Bool = false
    var filesRemaining: Int = 0
    /// ST-012: `true` si este sync dejo `/.aura/sync-pending.json` para
    /// que el firmware reconstruya sus indices al arrancar (contrato
    /// `docs/contracts/library-layout-v1.md` SS4). `false` si no se toco
    /// ningun archivo de contenido (nada que reconstruir).
    var syncMarkerWritten: Bool = false
    /// PLAN-sync-media-hardening.md PARTE 1A: archivos que no se
    /// pudieron copiar (nombre invalido para FAT32, corrupto, etc.) --
    /// el resto del plan sigue de largo, y `finalize` (portadas,
    /// playlists, resumen, marcador) corre igual con lo que SI se
    /// copio. Antes, el primer error de un solo archivo abortaba
    /// `sync()` entero via `throw` -- lo copiado hasta ahi quedaba en el
    /// disco (por eso el uso real subia) pero `writeSummary`/
    /// `writeAlbumCovers`/`writeSyncMarkerIfNeeded` nunca corrian, asi
    /// que Studio seguia mostrando "Todavia no sincronizaste" y "Otro"
    /// en vez de "Musica", y el firmware seguia sin ver la sincronizacion.
    var failures: [SyncFailure] = []
}

/// Un item que `SyncPlanner` marco `.copy` pero que no se pudo escribir
/// en el disco del iPod -- ver nota en `SyncResult.failures`.
struct SyncFailure: Equatable {
    let sourcePath: String
    let destinationRelativePath: String
    let message: String
}

/// D-217: progreso incremental de un sync en curso, publicado por
/// `LibraryViewModel.syncProgress` para la barra de progreso de la UI.
struct SyncProgress: Equatable {
    var copied: Int
    var total: Int
    var estimatedSecondsRemaining: Double?
}

struct LibrarySync {
    static let manifestRelativePath = ".rockbox/aura/sync_manifest.json"
    static let summaryRelativePath = ".rockbox/aura/sync_summary.cfg"
    static let ratingsRelativePath = ".rockbox/aura/ratings.cfg"
    /// PLAN-biblioteca-medios-v2.md §3.5 / CONTRATO-firmware-studio.md
    /// §D.2 (D-316): índices de categoría por archivo que alimentan
    /// las filas Películas/Series/Videoclips y Fotos/Imágenes/IA del
    /// firmware, y el pool de Movie Flow.
    static let videoCategoriesRelativePath = ".rockbox/aura/video_categories.cfg"
    static let photoCategoriesRelativePath = ".rockbox/aura/photo_categories.cfg"
    /// PLAN-biblioteca-medios-v2.md §3.5 / CONTRATO-firmware-studio.md
    /// §D.3 (contrato v6, D-322): fotos de artista reales -- el
    /// firmware ya sabe leerlas (Tanda 3, aura_artist_images), esto es
    /// lo que las pone en el disco por primera vez (Tanda 5).
    static let artistImagesDirRelativePath = ".rockbox/aura/artists"
    static let artistImagesIndexRelativePath = ".rockbox/aura/artist_images.cfg"
    static let playlistsRelativePath = "Playlists"
    /// PLAN-general-sync.md §8.2: presente mientras un sync esta en
    /// curso; ausente = ultimo sync cerro limpio (termino o se cancelo
    /// de forma deliberada, que igual corre `finalize`). Si sigue
    /// presente al conectar, el sync anterior se interrumpio de golpe
    /// (desconexion, cierre de la app, cuelgue) -- ver
    /// `sweepOrphanedTempFiles()`.
    static let inProgressMarkerRelativePath = ".rockbox/aura/sync_in_progress"
    /// Sufijo de los archivos temporales de la copia transaccional
    /// (§8.1): extension DESCONOCIDA para el firmware
    /// (`probe_file_format()` por extension, `tagcache.c`) -- un
    /// `.aura-tmp` a medio escribir nunca se indexa, a diferencia de un
    /// `.mp3` truncado (que si se indexaria con metadata basura).
    static let temporaryFileExtension = "aura-tmp"
    /// Tamaño de bloque de la copia interrumpible (§8.1) -- lo bastante
    /// chico para que cancelar/pausar responda rapido, lo bastante
    /// grande para no ahogar la copia en overhead de syscalls sobre
    /// USB 2.0.
    static let copyBlockSize = 4 * 1024 * 1024
    /// Carpetas del dispositivo que Aura Studio escribe -- donde puede
    /// haber quedado un `.aura-tmp` huerfano de un sync interrumpido.
    static let deviceContentDirectories = ["Music", "Videos", "Photos", "Playlists"]
    /// Mecanismo PREVIO a ST-012 para forzar la reconstruccion del
    /// indice de musica: borrar la base de tagcache y dejar que el
    /// firmware la levante de cero al arrancar. Desde ST-012 solo se usa
    /// con firmwares que no anuncian `sync_marker_supported` en aura.cfg
    /// (anteriores a D-293); con los nuevos basta el marcador de
    /// `SyncPendingMarker` y la base vieja sigue usable mientras tanto.
    static let tagcacheFilesToClear = [
        ".rockbox/database_idx.tcd",
        ".rockbox/database_0.tcd",
        ".rockbox/database_1.tcd",
        ".rockbox/database_2.tcd",
        ".rockbox/database_3.tcd",
        ".rockbox/database_4.tcd",
        ".rockbox/database_5.tcd",
        ".rockbox/database_6.tcd",
    ]

    let volumeRoot: URL
    private let fileManager = FileManager.default

    func loadManifest() -> SyncManifest {
        let url = volumeRoot.appendingPathComponent(Self.manifestRelativePath)
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(SyncManifest.self, from: data) else {
            return .empty
        }
        return manifest
    }

    func saveManifest(_ manifest: SyncManifest) throws {
        let url = volumeRoot.appendingPathComponent(Self.manifestRelativePath)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Marcador de sync en curso y barrido (§8.2)

    func hasInProgressMarker() -> Bool {
        fileManager.fileExists(atPath: volumeRoot.appendingPathComponent(Self.inProgressMarkerRelativePath).path)
    }

    private func writeInProgressMarker(startedAt: Date) throws {
        let url = volumeRoot.appendingPathComponent(Self.inProgressMarkerRelativePath)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let content = "started_at: \(startedAt.timeIntervalSince1970)\n"
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func removeInProgressMarker() {
        try? fileManager.removeItem(at: volumeRoot.appendingPathComponent(Self.inProgressMarkerRelativePath))
    }

    /// Borra cualquier `.aura-tmp` que haya quedado de un sync
    /// interrumpido de golpe (desconexion, cierre de la app) antes de
    /// empezar uno nuevo -- nunca deja basura acumulandose, y nunca
    /// toca nada que no sea un temporal propio.
    func sweepOrphanedTempFiles() {
        for directoryName in Self.deviceContentDirectories {
            let root = volumeRoot.appendingPathComponent(directoryName, isDirectory: true)
            guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator where url.pathExtension == Self.temporaryFileExtension {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    // MARK: - Copia transaccional (§8.1)

    enum CopyOutcome {
        case completed
        case cancelled
    }

    enum LibrarySyncError: Error, LocalizedError {
        case cannotCreateTempFile(String)

        var errorDescription: String? {
            switch self {
            case .cannotCreateTempFile(let path):
                return "No se pudo crear el archivo temporal en \(path)"
            }
        }
    }

    /// Copia `source` a `destination` por bloques, escribiendo primero
    /// a `<destino>.aura-tmp` y renombrando al final -- el firmware
    /// nunca ve un archivo final a medio escribir (ni siquiera durante
    /// una copia larga), y una cancelacion o una desconexion a mitad de
    /// bloque deja como mucho un `.aura-tmp` huerfano, nunca un
    /// `.mp3`/`.mpg`/`.jpg` final truncado. `isCancelled` se consulta
    /// antes de cada bloque -- responde en como mucho `copyBlockSize`
    /// bytes (4 MB), rapido incluso sobre USB 2.0.
    func copyFileTransactionally(from source: URL, to destination: URL,
                                  isCancelled: () -> Bool = { false },
                                  onBytesCopied: (Int64) -> Void = { _ in }) throws -> CopyOutcome {
        let tempURL = destination.appendingPathExtension(Self.temporaryFileExtension)
        if fileManager.fileExists(atPath: tempURL.path) {
            try fileManager.removeItem(at: tempURL)
        }
        guard fileManager.createFile(atPath: tempURL.path, contents: nil) else {
            throw LibrarySyncError.cannotCreateTempFile(tempURL.path)
        }

        do {
            let inHandle = try FileHandle(forReadingFrom: source)
            let outHandle = try FileHandle(forWritingTo: tempURL)
            defer { try? inHandle.close(); try? outHandle.close() }

            while true {
                if isCancelled() {
                    try? outHandle.close()
                    try? fileManager.removeItem(at: tempURL)
                    return .cancelled
                }
                guard let chunk = try inHandle.read(upToCount: Self.copyBlockSize), !chunk.isEmpty else {
                    break
                }
                try outHandle.write(contentsOf: chunk)
                onBytesCopied(Int64(chunk.count))
            }
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw error
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: tempURL, to: destination)
        return .completed
    }

    /// `items` son los LibraryItem ya procesados (metadata escrita,
    /// video transcodificado, foto redimensionada) con `preparedURL`
    /// listo para copiar; `playlists` (Fase 24) se resuelven a rutas
    /// reales del dispositivo usando esos mismos items y se escriben
    /// como `.m3u8` en `/Playlists`, cada uno con su sidecar `.jpg` de
    /// portada (encargo del dueno, 2026-08-14: imagen custom si
    /// `Playlist.imageRelativePath` apunta a algo real, si no un colage/
    /// tile generado, ver `writePlaylistArt`). `libraryRoot` es la
    /// carpeta LOCAL de Aura Studio (no `volumeRoot`, el iPod) -- solo
    /// hace falta para resolver esa imagen custom, que se cachea ahi
    /// (`.portadas/playlist-<id>.jpg`); `nil` (tests que no la pasan)
    /// simplemente se comporta como si ninguna playlist tuviera imagen
    /// propia, siempre cae al default generado. Devuelve cuantos
    /// archivos se copiaron de verdad y cuantas playlists se
    /// escribieron.
    @discardableResult
    func sync(items: [LibraryItem], playlists: [Playlist] = [],
              libraryRoot: URL? = nil,
              coverArtPolicy: AppPreferences.CoverArtPolicy = .albumOnly,
              musicOrganization: AppPreferences.MusicOrganization = .artistAlbum,
              musicFilenameFormat: AppPreferences.MusicFilenameFormat = .titleOnly,
              /// PLAN-general-sync.md §6: `nil` = copiar todo lo que
              /// `SyncPlanner` marque `.copy` (comportamiento de
              /// siempre). No-nil = "sincronizar solo la selección" --
              /// `items`/`playlists` siguen siendo la biblioteca
              /// COMPLETA (asi el resumen/las listas/el indice del
              /// firmware reflejan lo que de verdad hay en el
              /// dispositivo), pero solo se copian los `sourcePath` de
              /// este conjunto; el resto queda pendiente para el
              /// proximo sync sin perderse.
              restrictCopyToSourcePaths: Set<String>? = nil,
              /// PLAN-general-sync.md §0.1/§1.2, la hoja de conflictos:
              /// archivos que `DeviceSyncIndex` marco `.modifiedOnDevice`
              /// y que el usuario eligio "Reemplazar con la biblioteca"
              /// -- por defecto SyncPlanner los saltea (nunca mira el
              /// lado del dispositivo, solo si el preparado local
              /// cambio), asi que "conservar en el iPod" no necesita
              /// ningun codigo especial: YA es lo que pasa sin hacer
              /// nada. Esto es la unica forma de forzar la recopia.
              forceRecopySourcePaths: Set<String> = [],
              /// Registros huerfanos (`DeviceSyncIndex.orphanedRecords`)
              /// que el usuario eligio explicitamente borrar del iPod
              /// -- nunca automatico (§0.1: "nunca borra sin
              /// confirmacion"). Borra el archivo del dispositivo y su
              /// entrada del manifiesto.
              removeOrphanedSourcePaths: Set<String> = [],
              installationID: String? = nil,
              isCancelled: () -> Bool = { false },
              onProgress: (_ copied: Int, _ toCopy: Int) -> Void = { _, _ in }) throws -> SyncResult {
        sweepOrphanedTempFiles()
        try writeInProgressMarker(startedAt: Date())

        var manifest = loadManifest()
        manifest.contractVersion = SyncManifest.currentContractVersion
        var copied = 0
        var wasCancelled = false
        var failures: [SyncFailure] = []
        var destinationByItemID: [UUID: String] = [:]
        var summary = CatalogSummary()
        // ST-012: que secciones del iPod toco ESTE sync (copias,
        // reemplazos, reubicaciones y borrados) -- va al marcador de
        // reconstruccion del firmware, por seccion (contrato SS4).
        var touched = SyncPendingMarker.Changes(music: false, video: false, images: false)
        func markTouched(kind: LibraryItemKind) {
            switch kind {
            case .music: touched.music = true
            case .video: touched.video = true
            case .photo: touched.images = true
            case .unsupported: break
            }
        }
        func markTouched(deviceRelativePath: String) {
            if deviceRelativePath.hasPrefix("Music/") { touched.music = true }
            else if deviceRelativePath.hasPrefix("Videos/") { touched.video = true }
            else if deviceRelativePath.hasPrefix("Photos/") { touched.images = true }
        }

        let currentFiles = try items.compactMap { item -> (sourcePath: String, size: Int64, modifiedAt: TimeInterval, destinationRelativePath: String)? in
            guard let prepared = item.preparedURL else { return nil }
            let attrs = try fileManager.attributesOfItem(atPath: prepared.path)
            let size = (attrs[.size] as? Int64) ?? 0
            let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let destRelative = Self.destinationRelativePath(for: item, musicOrganization: musicOrganization,
                                                              musicFilenameFormat: musicFilenameFormat)
            destinationByItemID[item.id] = destRelative

            switch item.kind {
            case .music: summary.music.count += 1; summary.music.bytes += size
            case .video:
                summary.video.count += 1; summary.video.bytes += size
                // D-283: item.category para video se guarda como el
                // displayName LOCALIZADO (LibraryViewModel.swift:242) --
                // compara contra los dos idiomas para que un item
                // clasificado con la app en ingles siga contando bien
                // aunque el usuario luego cambie a español (o viceversa).
                switch item.category {
                case MediaCategory.movies.displayNameSpanish, MediaCategory.movies.displayNameEnglish:
                    summary.videoMovies += 1
                case MediaCategory.series.displayNameSpanish, MediaCategory.series.displayNameEnglish:
                    summary.videoSeries += 1
                default:
                    summary.videoClips += 1
                }
            case .photo:
                summary.photo.count += 1; summary.photo.bytes += size
                // MediaCategoryHeuristics.classifyPhoto() siempre devuelve
                // uno de estos 3 nombres fijos en español (no depende del
                // idioma de la app, a diferencia de video) -- coincide con
                // AppPreferences.defaultPhotoCollections a proposito.
                switch item.category {
                case "IA": summary.photoAI += 1
                case "Fotos": summary.photoPhotos += 1
                default: summary.photoImages += 1
                }
            case .unsupported: break
            }

            return (item.sourceURL.path, size, modified, destRelative)
        }

        var fullPlan = SyncPlanner.plan(current: currentFiles, previousManifest: manifest)
        // Hoja de conflictos, "Reemplazar con la biblioteca": fuerza a
        // `.copy` lo que SyncPlanner habia decidido `.skip` (el
        // preparado local no cambio, asi que sin esto nunca se
        // recopiaria) para los `sourcePath` que el usuario eligio
        // explicitamente.
        if !forceRecopySourcePaths.isEmpty {
            fullPlan = fullPlan.map { item in
                guard item.action == .skip, forceRecopySourcePaths.contains(item.sourcePath) else { return item }
                return SyncPlanItem(sourcePath: item.sourcePath, destinationRelativePath: item.destinationRelativePath, action: .copy)
            }
        }
        // "Sincronizar solo la selección": los archivos fuera de la
        // restriccion se tratan como si SyncPlanner los hubiera
        // marcado `.skip` en ESTA pasada -- siguen `.copy` en el plan
        // real (para que el proximo sync sin restriccion los copie),
        // simplemente esta pasada no los toca.
        let plan = restrictCopyToSourcePaths.map { allowed in
            fullPlan.filter { $0.action == .skip || allowed.contains($0.sourcePath) }
        } ?? fullPlan
        // D-217: total real de archivos que este sync va a copiar de
        // verdad (los que SyncPlanner ya decidio saltear no cuentan) --
        // asi la barra de progreso mide contra lo que efectivamente va a
        // pasar, no contra el total de la biblioteca completa.
        let toCopy = plan.filter { $0.action == .copy }.count

        planLoop: for planItem in plan {
            guard planItem.action == .copy else { continue }
            guard let item = items.first(where: { $0.sourceURL.path == planItem.sourcePath }),
                  let prepared = item.preparedURL else { continue }

            // §8.3: la cancelacion se revisa en la frontera de archivo
            // (ademas de dentro de cada copia, por bloque) -- si ya se
            // pidio antes de empezar este archivo, ni siquiera se toca
            // el disco para el.
            if isCancelled() {
                wasCancelled = true
                break planLoop
            }

            // PARTE 1A (PLAN-sync-media-hardening.md): un archivo con
            // nombre invalido para FAT32/msdosfs (visto en produccion:
            // ruta con un componente de artista de ~90 caracteres --
            // el credito de composicion completo metido en el tag,
            // sin ningun limite de largo aplicado -- ver
            // PathSanitizer.sanitize) u otra falla de un solo archivo
            // (corrupto, permisos, desconexion parcial) YA NO aborta el
            // resto del plan: se registra en `failures` y el loop sigue
            // con el siguiente item. `finalize` (portadas, playlists,
            // resumen, marcador del firmware) corre siempre despues del
            // loop, con o sin fallos parciales -- antes, un `throw` aca
            // saltaba TODO eso, aunque el 99% de los archivos ya
            // estuvieran copiados en el disco (ver SyncResult.failures).
            do {
                if let stale = planItem.staleDestinationRelativePath {
                    try? fileManager.removeItem(at: volumeRoot.appendingPathComponent(stale))
                    removeLyricsSidecar(forDeviceRelativePath: stale)
                    markTouched(deviceRelativePath: stale)
                }

                let destination = volumeRoot.appendingPathComponent(planItem.destinationRelativePath)
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

                let outcome = try copyFileTransactionally(from: prepared, to: destination, isCancelled: isCancelled)
                guard case .completed = outcome else {
                    wasCancelled = true
                    break planLoop
                }
                copied += 1
                markTouched(kind: item.kind)
                onProgress(copied, toCopy)

                // Fase 24: el poster de un video (`<video>.jpg`, generado
                // por FFmpegTranscoder.generatePoster) viaja pegado a su
                // video -- no tiene entrada propia en el manifiesto, sigue
                // el mismo diferencial que el archivo principal (D-066).
                // Best-effort (no transaccional): es contenido derivado y
                // regenerable, no dato del usuario -- ver PLAN-general-sync.md §8.1.
                if item.kind == .video {
                    let posterSource = prepared.deletingPathExtension().appendingPathExtension("jpg")
                    if fileManager.fileExists(atPath: posterSource.path) {
                        let posterDestination = destination.deletingPathExtension().appendingPathExtension("jpg")
                        if fileManager.fileExists(atPath: posterDestination.path) {
                            try? fileManager.removeItem(at: posterDestination)
                        }
                        try? fileManager.copyItem(at: posterSource, to: posterDestination)
                    }
                }

                let attrs = try fileManager.attributesOfItem(atPath: prepared.path)
                let destAttrs = try fileManager.attributesOfItem(atPath: destination.path)
                manifest.records[planItem.sourcePath] = SyncRecord(
                    sourcePath: planItem.sourcePath,
                    sourceSize: (attrs[.size] as? Int64) ?? 0,
                    sourceModifiedAt: (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0,
                    destinationRelativePath: planItem.destinationRelativePath,
                    destinationSize: (destAttrs[.size] as? Int64) ?? 0,
                    destinationModifiedAt: (destAttrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0,
                    writtenBy: installationID,
                    syncedAt: Date().timeIntervalSince1970
                )
                // §8.1: el manifiesto se guarda tras CADA archivo (antes
                // solo al final) -- es lo que hace que pausar, cancelar, o
                // una desconexion fisica conserven el progreso ya copiado
                // en vez de perderlo si el resto del sync no llega a correr.
                try saveManifest(manifest)
            } catch {
                failures.append(SyncFailure(sourcePath: planItem.sourcePath,
                                             destinationRelativePath: planItem.destinationRelativePath,
                                             message: error.localizedDescription))
            }
        }

        // Hoja de conflictos, "Quitar del iPod los N elementos que ya
        // no están en tu biblioteca" (§0.1/§1.2) -- SOLO estos
        // `sourcePath`, elegidos explicitamente por el usuario. Nunca
        // automatico: un registro huerfano que nadie marco para borrar
        // se queda en el iPod y en el manifiesto para siempre, como
        // hoy.
        if !removeOrphanedSourcePaths.isEmpty {
            for orphanSourcePath in removeOrphanedSourcePaths {
                guard let record = manifest.records[orphanSourcePath] else { continue }
                try? fileManager.removeItem(at: volumeRoot.appendingPathComponent(record.destinationRelativePath))
                removeLyricsSidecar(forDeviceRelativePath: record.destinationRelativePath)
                markTouched(deviceRelativePath: record.destinationRelativePath)
                manifest.records.removeValue(forKey: orphanSourcePath)
            }
            try saveManifest(manifest)
        }

        // ST-012 / contrato SS3: letras como sidecar `.lrc` junto al
        // audio, mismo nombre base -- la UNICA ruta que el firmware
        // intenta (aura_nowplaying.c, derive_sibling_path()). Se
        // sincroniza el ESTADO en cada pasada (no solo con lo recien
        // copiado): una letra que llego por enriquecimiento despues de
        // que la cancion ya estaba en el iPod tiene que llegar igual, y
        // una letra borrada en Studio se va del iPod. Solo se escribe
        // si el contenido cambio (no rehace el archivo en cada sync).
        writeLyricsSidecars(items: items, destinationByItemID: destinationByItemID,
                            onlyForSourcePaths: restrictCopyToSourcePaths)

        if coverArtPolicy == .albumOnly {
            writeAlbumCovers(items: items, destinationByItemID: destinationByItemID)
        }

        let playlistsWritten = try writePlaylists(playlists, destinationByItemID: destinationByItemID,
                                                   items: items, libraryRoot: libraryRoot)
        summary.playlistCount = playlistsWritten
        try writeSummary(summary)
        try writeRatings(items: items, destinationByItemID: destinationByItemID)
        try writeCategoryIndexes(items: items, destinationByItemID: destinationByItemID)
        writeSeasonPosters(items: items)
        if writeArtistImages(items: items, libraryRoot: libraryRoot) {
            touched.music = true
        }

        // ST-056 / contrato v10: los archivos del contrato que acaba de
        // escribir este sync en `.rockbox/aura/` se copian tambien a cada
        // arbol DORMIDO presente, para que el firmware que despierte no
        // despierte desactualizado. No es fatal si falla: el dormido se
        // pondra al dia en el primer sync despues de despertar.
        try? FirmwareSwitcher.mirrorContractFilesToDormantTrees(volumeRoot: volumeRoot, fileManager: fileManager)

        // ST-012 / contrato SS4: si este sync toco algo (tambien si se
        // cancelo a medias -- lo copiado ya esta en el disco y el
        // firmware tiene que verlo), se deja el marcador para que el
        // firmware reconstruya SOLO las secciones tocadas al arrancar.
        // Con un firmware anterior a D-293 (sin `sync_marker_supported`
        // en aura.cfg) se conserva ademas el mecanismo previo -- borrar
        // la base de tagcache para forzar la reconstruccion al arrancar
        // (SS4.4: ninguna combinacion de versiones rompe). El marcador
        // se escribe igual: un firmware viejo lo ignora, y uno nuevo
        // instalado despues lo aplica en su primer arranque.
        let markerWritten = writeSyncMarkerIfNeeded(touched)
        if copied > 0 && FirmwareCapabilities.supportedSyncMarkerVersion(volumeRoot: volumeRoot) == nil {
            triggerFirmwareDBRebuild()
        }

        // §8.2: `finalize` (arriba) corrio igual aunque se haya
        // cancelado -- el marcador solo sobrevive cuando el sync se
        // interrumpe DE GOLPE (una excepcion real, p. ej. desconexion,
        // que no pasa por aca) y nunca llega a este punto.
        removeInProgressMarker()

        let remaining = wasCancelled ? max(toCopy - copied, 0) : 0
        return SyncResult(filesCopied: copied, playlistsWritten: playlistsWritten,
                           wasCancelled: wasCancelled, filesRemaining: remaining,
                           syncMarkerWritten: markerWritten, failures: failures)
    }

    /// Encargo del dueño (General → "Eliminar todos los archivos, o por
    /// tipos de medios"): borra TODO el contenido de las secciones
    /// elegidas directo del disco -- fuera del flujo normal de
    /// `sync()`, para cuando el usuario quiere vaciar el iPod sin
    /// tocar su biblioteca local. Limpia también el manifiesto (sin
    /// esto, el próximo `sync()` vería el mismo `sourcePath`/tamaño/
    /// fecha de siempre en el registro viejo y decidiría `.skip` --
    /// "ya está copiado" -- aunque el archivo real ya no exista) y deja
    /// el marcador para que el firmware reconstruya sus índices, igual
    /// que un sync real. Devuelve cuántos archivos se borraron.
    @discardableResult
    func deleteAllDeviceContent(kinds: Set<LibraryItemKind>) throws -> Int {
        let directoryByKind: [LibraryItemKind: String] = [.music: "Music", .video: "Videos", .photo: "Photos"]
        var manifest = loadManifest()
        var touched = SyncPendingMarker.Changes(music: false, video: false, images: false)
        var deletedCount = 0

        for kind in kinds {
            guard let dirName = directoryByKind[kind] else { continue }
            let dir = volumeRoot.appendingPathComponent(dirName, isDirectory: true)
            if let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for item in contents {
                    try? fileManager.removeItem(at: item)
                    deletedCount += 1
                }
            }

            let prefix = "\(dirName)/"
            manifest.records = manifest.records.filter { !$0.value.destinationRelativePath.hasPrefix(prefix) }

            switch kind {
            case .music:
                touched.music = true
                // PLAN-biblioteca-medios-v2.md §3.5: fotos de artista e
                // índice no tienen registro propio en el manifiesto
                // (igual que los .cfg de categoría de video/foto) --
                // "Eliminar toda la música" los deja huérfanos si no se
                // borran acá.
                try? fileManager.removeItem(at: volumeRoot.appendingPathComponent(Self.artistImagesIndexRelativePath))
                try? fileManager.removeItem(at: volumeRoot.appendingPathComponent(Self.artistImagesDirRelativePath))
            case .video:
                touched.video = true
                try? fileManager.removeItem(at: volumeRoot.appendingPathComponent(Self.videoCategoriesRelativePath))
            case .photo:
                touched.images = true
                try? fileManager.removeItem(at: volumeRoot.appendingPathComponent(Self.photoCategoriesRelativePath))
            case .unsupported: break
            }
        }

        try saveManifest(manifest)
        _ = writeSyncMarkerIfNeeded(touched)
        if FirmwareCapabilities.supportedSyncMarkerVersion(volumeRoot: volumeRoot) == nil {
            triggerFirmwareDBRebuild()
        }
        return deletedCount
    }

    /// Ver contrato SS4. Si ya habia un marcador (el firmware no alcanzo
    /// a procesar el sync anterior), las secciones se ACUMULAN: el
    /// firmware tiene que reconstruir la union de lo que cambio en
    /// ambos syncs. `attempts` vuelve a 0: es un marcador nuevo.
    private func writeSyncMarkerIfNeeded(_ touched: SyncPendingMarker.Changes) -> Bool {
        var changes = touched
        if let previous = SyncPendingMarker.read(from: volumeRoot, fileManager: fileManager) {
            changes.music = changes.music || previous.changes.music
            changes.video = changes.video || previous.changes.video
            changes.images = changes.images || previous.changes.images
        }
        guard !changes.isEmpty else { return false }
        do {
            try SyncPendingMarker(changes: changes).write(to: volumeRoot, fileManager: fileManager)
            // ST-059 / contrato v12: un sync que toca musica renueva el
            // sello de biblioteca -- es lo que hace que un cambio de
            // firmware posterior SI reconstruya (y que los cambios sin
            // sync de por medio no lo hagan).
            if changes.music {
                FirmwareSwitcher.bumpLibraryStamp(volumeRoot: volumeRoot, fileManager: fileManager)
            }
            return true
        } catch {
            return false
        }
    }

    /// Con la politica "una caratula por album", la imagen no va embebida
    /// en cada archivo sino una sola vez como `cover.jpg` en la carpeta
    /// del album -- exactamente donde la busca `find_albumart` del
    /// firmware (`apps/recorder/albumart.c`, que prueba `cover.*` y
    /// `folder.jpg` en el directorio de la pista). Un album de 15 pistas
    /// pasa de 15 copias de la portada a una sola.
    ///
    /// Se escribe siempre que haya una imagen disponible, aunque las
    /// pistas se hayan salteado por el diferencial: el `cover.jpg` no
    /// tiene entrada propia en el manifiesto, asi que esta es la unica
    /// oportunidad de crearlo si falta.
    /// Ruta del `.lrc` hermano de un archivo de audio del iPod: mismo
    /// directorio, mismo nombre base, extension `.lrc` -- exactamente lo
    /// que hace `derive_sibling_path()` en el firmware.
    static func lyricsSidecarRelativePath(forDeviceRelativePath relative: String) -> String {
        (relative as NSString).deletingPathExtension + ".lrc"
    }

    private func removeLyricsSidecar(forDeviceRelativePath relative: String) {
        guard relative.hasPrefix("Music/") else { return }
        let url = volumeRoot.appendingPathComponent(Self.lyricsSidecarRelativePath(forDeviceRelativePath: relative))
        try? fileManager.removeItem(at: url)
    }

    /// Ver llamada en `sync()`. Sincronizada (`[mm:ss.xx]`) si LRCLIB la
    /// dio asi; plana si solo hay plana (el firmware define que hacer sin
    /// marcas de tiempo -- hoy la ignora, contrato SS3). Sin letra en
    /// Studio: sin archivo -- y si habia uno de una pasada anterior, se
    /// borra (nunca huerfanos). Best-effort, como las caratulas: es
    /// contenido derivado, no el dato del usuario.
    private func writeLyricsSidecars(items: [LibraryItem],
                                     destinationByItemID: [UUID: String],
                                     onlyForSourcePaths: Set<String>?) {
        for item in items where item.kind == .music {
            guard let relative = destinationByItemID[item.id] else { continue }
            if let onlyForSourcePaths, !onlyForSourcePaths.contains(item.sourceURL.path) { continue }
            let audioURL = volumeRoot.appendingPathComponent(relative)
            // Sin la cancion en el iPod (todavia no copiada, o pendiente
            // por "solo la seleccion") no se deja un .lrc suelto.
            guard fileManager.fileExists(atPath: audioURL.path) else { continue }

            let lrcURL = volumeRoot.appendingPathComponent(Self.lyricsSidecarRelativePath(forDeviceRelativePath: relative))
            let lyrics = item.metadata?.syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if lyrics.isEmpty {
                try? fileManager.removeItem(at: lrcURL)
                continue
            }
            let content = lyrics + "\n"
            if let existing = try? String(contentsOf: lrcURL, encoding: .utf8), existing == content {
                continue
            }
            try? content.write(to: lrcURL, atomically: true, encoding: .utf8)
        }
    }

    private func writeAlbumCovers(items: [LibraryItem],
                                   destinationByItemID: [UUID: String]) {
        var written = Set<String>()

        for item in items where item.kind == .music {
            guard let cover = item.metadata?.coverArtData,
                  let relative = destinationByItemID[item.id] else { continue }

            // Bug real (encontrado 2026-08-14 comparando simulador vs.
            // hardware): `relative` es una ruta RELATIVA ("Music/Artista/
            // Álbum/Cancion.mp3") -- envolverla sola en
            // `URL(fileURLWithPath:)` la resuelve contra el directorio de
            // trabajo del PROCESO (no contra `volumeRoot`), así que el
            // "álbum" resultante terminaba siendo una ruta absoluta
            // ajena (el cwd de quien corriera el sync), y al pegarla
            // sobre `volumeRoot` con `appendingPathComponent` quedaba un
            // path anidado sin sentido -- las portadas de álbum NUNCA
            // llegaban a la carpeta real, en ningún sync, tampoco al
            // dispositivo real (mismo código). Resolver `relative` contra
            // `volumeRoot` PRIMERO, después quitar el nombre de archivo,
            // da la carpeta de álbum real.
            let albumDestination = volumeRoot.appendingPathComponent(relative).deletingLastPathComponent()
            let albumFolder = albumDestination.path
            guard !written.contains(albumFolder) else { continue }
            written.insert(albumFolder)

            let coverURL = albumDestination.appendingPathComponent("cover.jpg")
            try? fileManager.createDirectory(at: albumDestination, withIntermediateDirectories: true)
            try? cover.write(to: coverURL)
        }
    }

    /// Escribe siempre las playlists (son archivos de texto de unos
    /// pocos KB cada una -- no vale la pena un manifiesto diferencial
    /// solo para esto, ver D-066). Pistas que todavia no tienen destino
    /// resuelto (no vinieron en `items`, p. ej. se borraron de la
    /// sesion) se omiten en silencio en vez de fallar todo el sync.
    private func writePlaylists(_ playlists: [Playlist], destinationByItemID: [UUID: String],
                                 items: [LibraryItem], libraryRoot: URL?) throws -> Int {
        guard !playlists.isEmpty else { return 0 }
        let dir = volumeRoot.appendingPathComponent(Self.playlistsRelativePath)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var written = 0
        for playlist in playlists {
            /* ST-062: rutas en NFC -- el firmware abre estas rutas
             * byte a byte contra los LFN del FAT (ver String.firmwareNFC). */
            let paths = playlist.trackItemIDs.compactMap { destinationByItemID[$0]?.firmwareNFC }
            guard !paths.isEmpty else { continue }
            let url = dir.appendingPathComponent(PlaylistExporter.fileName(for: playlist.name))
            let contents = PlaylistExporter.m3u8Contents(trackDestinationPaths: paths)
            try contents.write(to: url, atomically: true, encoding: .utf8)
            written += 1

            writePlaylistArt(playlist, itemsByID: itemsByID, libraryRoot: libraryRoot, destinationDir: dir)
        }
        return written
    }

    /// Portada de playlist (encargo del dueno, 2026-08-14): mismo nombre
    /// base que el `.m3u8` recien escrito, con ".jpg" en vez de la
    /// extension (`PlaylistExporter.imageFileName`) -- ahi es donde
    /// `aura_playlist_art_load()` del firmware ya sabe buscarla. Si el
    /// usuario eligio una imagen propia se copia esa (cache local
    /// `.portadas/playlist-<id>.jpg`); si no, se genera un colage/tile
    /// default (`PlaylistArtGenerator`) con las caratulas que ya tengan
    /// las pistas de la playlist. Best-effort de punta a punta: un fallo
    /// aca (imagen corrupta, disco lleno) no debe tirar abajo el sync de
    /// la playlist entera, que ya escribio su .m3u8 con exito -- el
    /// firmware igual tiene su propio tile generico de respaldo si el
    /// sidecar termina faltando.
    private func writePlaylistArt(_ playlist: Playlist, itemsByID: [UUID: LibraryItem],
                                   libraryRoot: URL?, destinationDir: URL) {
        let imageURL = destinationDir.appendingPathComponent(PlaylistExporter.imageFileName(for: playlist.name))

        if let relative = playlist.imageRelativePath, let libraryRoot {
            let sourceURL = libraryRoot.appendingPathComponent(relative)
            if fileManager.fileExists(atPath: sourceURL.path) {
                if fileManager.fileExists(atPath: imageURL.path) {
                    try? fileManager.removeItem(at: imageURL)
                }
                if (try? fileManager.copyItem(at: sourceURL, to: imageURL)) != nil {
                    return
                }
            }
        }

        let covers = playlist.trackItemIDs.compactMap { itemsByID[$0]?.metadata?.coverArtData }
        try? PlaylistArtGenerator.generateDefault(coverArtCandidates: covers, destinationURL: imageURL)
    }

    /// Formato plano `key: value` (no JSON) a proposito -- el firmware
    /// ya sabe leer ese formato para `aura.cfg`
    /// (`aura_settings_load`/`settings_parseline`) y no tiene parser de
    /// JSON; reusarlo evita escribir uno en C para un solo archivo.
    private func writeSummary(_ summary: CatalogSummary) throws {
        let url = volumeRoot.appendingPathComponent(Self.summaryRelativePath)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try CatalogSummaryWriter.serialize(summary).write(to: url, atomically: true, encoding: .utf8)
    }

    /// D-199/D-200: la calificacion NO vive en ningún tag del archivo
    /// de audio (no hay POPM en este arbol) -- es un dato de runtime
    /// de tagcache (`tag_rating`), y `triggerFirmwareDBRebuild()` de
    /// aquí abajo BORRA ese índice en cada sync para forzar una
    /// reconstrucción. Sin este sidecar, cualquier calificación (la
    /// puesta en Aura Studio o la puesta en el propio iPod) se
    /// perdería en el siguiente sync. `import_ratings_from_studio()`
    /// (`apps/aura/aura_music.c`) lo lee cada arranque y aplica cada
    /// línea contra tagcache -- mismo formato `key: value` que
    /// `sync_summary.cfg`, la clave es la ruta ABSOLUTA en el
    /// dispositivo (para que calce con `tag_filename`) y el valor es
    /// la calificación en la escala nativa de Rockbox (0-10, la
    /// estrella 1-5 de Aura Studio se multiplica x2 -- mismo mapeo que
    /// ya usa `aura_nowplaying.c` en el propio aparato).
    ///
    /// Es sincronización de UNA VÍA (Aura Studio -> iPod): leer de
    /// vuelta una calificación puesta en el aparato requeriría parsear
    /// el formato binario de tagcache desde macOS, que D-199 descartó
    /// por riesgo de corromper la base de datos completa. Si las dos
    /// calificaciones difieren, la de Aura Studio gana en el próximo
    /// arranque -- una limitación conocida, no un bug.
    private func writeRatings(items: [LibraryItem], destinationByItemID: [UUID: String]) throws {
        let lines = items.compactMap { item -> String? in
            guard item.kind == .music, let rating = item.metadata?.rating, rating > 0,
                  let relative = destinationByItemID[item.id] else { return nil }
            let nativeRating = min(10, max(0, rating * 2))
            return "/\(relative.firmwareNFC): \(nativeRating)"
        }

        let url = volumeRoot.appendingPathComponent(Self.ratingsRelativePath)
        guard !lines.isEmpty else {
            try? fileManager.removeItem(at: url)
            return
        }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// PLAN-biblioteca-medios-v2.md §3.5 / CONTRATO-firmware-studio.md
    /// §D.2: le da al firmware, por primera vez, la categoría de cada
    /// archivo individual de `/Videos`/`/Photos` -- hasta ahora Studio
    /// solo emitía 3 contadores agregados (`sync_summary.cfg`, D-283),
    /// insuficiente para que las filas Películas/Series/Videoclips y
    /// Fotos/Imágenes/IA del firmware (D-316) tuvieran contenido real.
    /// Mismo patrón que `writeRatings`: solo items REALMENTE presentes
    /// en el iPod tras este sync (los que tienen destino resuelto),
    /// nunca todo el catálogo; sin entradas -> se borra el archivo
    /// (nunca deja un índice viejo apuntando a nada).
    private func writeCategoryIndexes(items: [LibraryItem], destinationByItemID: [UUID: String]) throws {
        let videoLines = items.compactMap { item -> String? in
            guard item.kind == .video, let relative = destinationByItemID[item.id] else { return nil }
            let code: String
            switch item.category {
            case MediaCategory.movies.displayNameSpanish, MediaCategory.movies.displayNameEnglish: code = "movie"
            case MediaCategory.series.displayNameSpanish, MediaCategory.series.displayNameEnglish: code = "series"
            default: code = "clip"
            }
            return "\((relative as NSString).lastPathComponent.firmwareNFC): \(code)"
        }
        try writeCategoryIndex(lines: videoLines, header: "# aura-video-categories v1",
                                relativePath: Self.videoCategoriesRelativePath)

        let photoLines = items.compactMap { item -> String? in
            guard item.kind == .photo, let relative = destinationByItemID[item.id] else { return nil }
            let code: String
            switch item.category {
            case "IA": code = "ai"
            case "Fotos": code = "photo"
            default: code = "image"
            }
            return "\((relative as NSString).lastPathComponent.firmwareNFC): \(code)"
        }
        try writeCategoryIndex(lines: photoLines, header: "# aura-photo-categories v1",
                                relativePath: Self.photoCategoriesRelativePath)
    }

    private func writeCategoryIndex(lines: [String], header: String, relativePath: String) throws {
        let url = volumeRoot.appendingPathComponent(relativePath)
        guard !lines.isEmpty else {
            try? fileManager.removeItem(at: url)
            return
        }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let contents = header + "\n" + lines.joined(separator: "\n") + "\n"
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// PLAN-biblioteca-medios-v2.md §3.5 (Tanda 5) / CONTRATO-firmware-
    /// studio.md §D.3: fotos de artista reales al iPod -- `ArtistImageStore`
    /// (ST-032) ya las descarga y las guarda en la biblioteca local,
    /// nunca las sincronizaba. Reducidas a 128px (contrato), mismo
    /// nombre de archivo que ya usa la caché local
    /// (`ArtistImageStore.fileName(forArtistKey:)`) para que un mismo
    /// artista comparta un solo archivo entre ambos lados. El índice se
    /// reescribe COMPLETO en cada sync (no diferencial, como
    /// `writeCategoryIndexes`); sin ninguna foto -> se borra, nunca deja
    /// uno viejo apuntando a nada. Devuelve `true` si escribió o borró
    /// algo (para el marcador `sync-pending.json`, `changes.music`).
    @discardableResult
    private func writeArtistImages(items: [LibraryItem], libraryRoot: URL?) -> Bool {
        guard let libraryRoot else { return false }
        let store = ArtistImageStore(libraryRoot: libraryRoot)
        let artistsDir = volumeRoot.appendingPathComponent(Self.artistImagesDirRelativePath)
        let indexURL = volumeRoot.appendingPathComponent(Self.artistImagesIndexRelativePath)

        var lines: [String] = []
        var writtenFiles = Set<String>()
        for artist in LibraryGrouping.artists(from: items) {
            guard let data = store.image(forArtistKey: artist.id) else { continue }
            let fileName = ArtistImageStore.fileName(forArtistKey: artist.id)
            if !writtenFiles.contains(fileName) {
                try? fileManager.createDirectory(at: artistsDir, withIntermediateDirectories: true)
                try? ImageResizer.resizeToLCDOptimal(data: data, destinationURL: artistsDir.appendingPathComponent(fileName), maxDimension: 128)
                writtenFiles.insert(fileName)
            }
            // Contrato §D.3: una línea por cada valor CRUDO distinto de
            // `metadata.artist` entre las pistas del grupo -- solo trim
            // de espacios extremos, SIN folding (el firmware compara
            // byte a byte contra el tag real, D-322).
            var seenRaw = Set<String>()
            for item in artist.items {
                guard let raw = item.metadata?.artist?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
                      !seenRaw.contains(raw) else { continue }
                seenRaw.insert(raw)
                lines.append("\(fileName): \(raw)")
            }
        }

        let existedBefore = fileManager.fileExists(atPath: indexURL.path)
        guard !lines.isEmpty else {
            if existedBefore { try? fileManager.removeItem(at: indexURL) }
            return existedBefore
        }
        try? fileManager.createDirectory(at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? ("# aura-artist-images v1\n" + lines.joined(separator: "\n") + "\n").write(to: indexURL, atomically: true, encoding: .utf8)
        return true
    }

    /// PLAN-biblioteca-medios-v2.md §3.5: por cada (seriesName, season)
    /// presente en `items`, escribe "Videos/<seriesName> S%02d.jpg" --
    /// el mismo prefijo saneado que `seriesEpisodeFilename` usa para
    /// sus episodios, para que `aura_movieflow.c` (que solo concatena
    /// el nombre de programa que ya extrajo con " S%02d.jpg") encuentre
    /// el archivo exacto. Toma el póster del primer episodio (por
    /// número) de cada temporada que tenga `coverArtData`; solo
    /// reescribe si el contenido cambió (compara bytes, no vale la pena
    /// un manifiesto aparte para unos pocos KB por temporada).
    private func writeSeasonPosters(items: [LibraryItem]) {
        var bestByseason: [String: (episode: Int, cover: Data)] = [:]
        for item in items {
            guard item.kind == .video, Self.isSeriesCategory(item.category),
                  let seriesName = item.seriesName, let season = item.season, let episode = item.episode,
                  let cover = item.metadata?.coverArtData else { continue }
            let key = "\(seriesName)\u{1}\(season)"
            if let existing = bestByseason[key], existing.episode <= episode { continue }
            bestByseason[key] = (episode, cover)
        }
        for (key, best) in bestByseason {
            let parts = key.split(separator: "\u{1}", maxSplits: 1)
            guard parts.count == 2, let season = Int(parts[1]) else { continue }
            let seriesName = String(parts[0])
            let relative = Self.seasonPosterRelativePath(seriesName: seriesName, season: season)
            let url = volumeRoot.appendingPathComponent(relative)
            if let existing = try? Data(contentsOf: url), existing == best.cover { continue }
            try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? ImageResizer.resizeToLCDOptimal(data: best.cover, destinationURL: url, maxDimension: 640)
        }
    }

    /// Fase 24: la musica pasa a vivir en `Music/<Artista>/<Album>/NN
    /// Titulo.ext` (la convencion que Rockbox espera de cualquier
    /// biblioteca real) en vez de un `Music/<archivo>` plano -- video y
    /// foto se quedan flat a proposito (D-066: agruparlas exige que el
    /// navegador de fotos del firmware recorra subcarpetas, algo que
    /// D-062 ya identifico como su propia feature, no una migracion de
    /// rutas). `PathSanitizer` cubre los caracteres que FAT32 no acepta.
    ///
    /// `organization`/`filenameFormat` (D-192) son ajustes del usuario:
    /// el tagcache de Rockbox escanea el volumen entero sin importar la
    /// profundidad de carpetas, asi que a diferencia de foto/video no
    /// hay ninguna limitacion del firmware que respetar aca. Los
    /// parametros tienen default para no romper los llamados existentes
    /// (tests, y `sync()` cuando no se pasa nada).
    static func musicDestinationRelativePath(
        for item: LibraryItem,
        organization: AppPreferences.MusicOrganization = .artistAlbum,
        filenameFormat: AppPreferences.MusicFilenameFormat = .titleOnly
    ) -> String {
        let ext = (item.preparedURL ?? item.sourceURL).pathExtension
        let meta = item.metadata
        let artist = PathSanitizer.sanitize(meta?.albumArtist ?? meta?.artist ?? "Desconocido")
        let album = PathSanitizer.sanitize(meta?.album ?? "Desconocido")
        let rawTitle = meta?.title ?? item.sourceURL.deletingPathExtension().lastPathComponent
        let title = PathSanitizer.sanitize(rawTitle)

        let folder: String
        switch organization {
        case .artistAlbum: folder = "\(artist)/\(album)"
        case .album: folder = album
        case .artist: folder = artist
        }

        let filename: String
        switch filenameFormat {
        case .titleOnly:
            filename = title
        case .trackNumberTitle:
            if let track = meta?.trackNumber, track > 0 {
                filename = String(format: "%02d %@", track, title)
            } else {
                filename = title
            }
        case .titleArtist:
            filename = "\(title) - \(artist)"
        case .titleAlbum:
            filename = "\(title) - \(album)"
        }

        return "Music/\(folder)/\(filename).\(ext)"
    }

    /// D-228: ruta dentro de la carpeta LOCAL de la biblioteca (Finder),
    /// distinta de `musicDestinationRelativePath` de arriba -- esa es
    /// la ruta de SYNC al iPod (usa `musicFilenameFormat` para renombrar
    /// el archivo y parte de `item.preparedURL`). Aca la copia local
    /// conserva el nombre ORIGINAL (`fileName`, resuelto por el llamador
    /// -- ya con el sufijo de colision si hacia falta, ver
    /// `LibraryViewModel.copyIntoLibrary`), porque es "el mismo archivo
    /// que soltaste, solo que organizado", no una preparacion para el
    /// dispositivo.
    ///
    /// Musica va por artista/album (mismo criterio que el sync, sin el
    /// ajuste de organizacion -- adentro de la biblioteca siempre es
    /// jerarquico, D-228). Foto/video van por categoria SOLO si el
    /// ajuste correspondiente esta activo (`organizePhotosByCategory`/
    /// `organizeVideosByCategory`) y el item ya tiene una asignada;
    /// si no, quedan planos en la raiz de su tipo.
    static func localLibraryRelativePath(
        for item: LibraryItem,
        kind: LibraryItemKind,
        fileName: String,
        organizePhotosByCategory: Bool = true,
        organizeVideosByCategory: Bool = true
    ) -> String {
        switch kind {
        case .music:
            let meta = item.metadata
            let artist = PathSanitizer.sanitize(meta?.albumArtist ?? meta?.artist ?? "Desconocido")
            let album = PathSanitizer.sanitize(meta?.album ?? "Desconocido")
            return "\(PersistedLibrary.musicDirName)/\(artist)/\(album)/\(fileName)"
        case .photo:
            if organizePhotosByCategory, let category = item.category, !category.isEmpty {
                // PLAN-biblioteca-medios-v2.md §3.3: con álbum, un nivel
                // más adentro de la categoría -- el álbum es un
                // subconjunto DE la colección, nunca vive suelto al
                // mismo nivel. Solo local (Finder); el iPod nunca ve
                // esta jerarquía (D-192, /Photos sigue plano).
                if let album = item.photoAlbum, !album.isEmpty {
                    return "\(PersistedLibrary.imagesDirName)/\(PathSanitizer.sanitize(category))/\(PathSanitizer.sanitize(album))/\(fileName)"
                }
                return "\(PersistedLibrary.imagesDirName)/\(PathSanitizer.sanitize(category))/\(fileName)"
            }
            return "\(PersistedLibrary.imagesDirName)/\(fileName)"
        case .video:
            if organizeVideosByCategory, let category = item.category, !category.isEmpty {
                return "\(PersistedLibrary.videosDirName)/\(PathSanitizer.sanitize(category))/\(fileName)"
            }
            return "\(PersistedLibrary.videosDirName)/\(fileName)"
        case .unsupported:
            return fileName
        }
    }

    /// No-privado y `static` (sin estado de `self`) a proposito: lo
    /// reusa `DeviceSyncIndexBuilder` (PLAN-general-sync.md §4) para
    /// saber a que ruta del dispositivo corresponde cada item de la
    /// biblioteca sin reimplementar este switch -- la unica fuente de
    /// verdad de "donde va cada tipo de archivo" sigue siendo esta.
    static func destinationRelativePath(
        for item: LibraryItem,
        musicOrganization: AppPreferences.MusicOrganization,
        musicFilenameFormat: AppPreferences.MusicFilenameFormat
    ) -> String {
        let filename = item.preparedURL?.lastPathComponent ?? item.sourceURL.lastPathComponent
        switch item.kind {
        case .music: return Self.musicDestinationRelativePath(for: item, organization: musicOrganization,
                                                                filenameFormat: musicFilenameFormat)
        // PLAN-sync-media-hardening.md PARTE 2A: /Videos/ y /Photos/ son
        // planos -- el nombre del archivo preparado viajaba tal cual,
        // sin sanear ni acotar (a diferencia de musica, que ya pasaba
        // por PathSanitizer). deviceFilenameMaxBytes coincide con
        // VIDEO_NAME_LEN/PHOTO_NAME_LEN del firmware (96 con el NUL).
        case .video:
            // PLAN-biblioteca-medios-v2.md §3.5: un episodio de Series
            // con seriesName/season/episode resueltos viaja como
            // "<seriesName> SxxEyy.<ext>" -- el espacio+SxxEyy es lo que
            // `parse_sxxeyy()` del firmware busca para agrupar episodios
            // por temporada (aura_movieflow.c). Cualquier otro video
            // (película suelta, videoclip, o una Serie sin esos tres
            // campos resueltos) sigue el nombre preparado tal cual.
            if isSeriesCategory(item.category),
               let seriesName = item.seriesName, let season = item.season, let episode = item.episode {
                let ext = (filename as NSString).pathExtension
                return "Videos/\(Self.seriesEpisodeFilename(seriesName: seriesName, season: season, episode: episode, ext: ext))"
            }
            return "Videos/\(PathSanitizer.sanitizeFilename(filename, maxBytes: Self.deviceFilenameMaxBytes))"
        case .photo: return "Photos/\(PathSanitizer.sanitizeFilename(filename, maxBytes: Self.deviceFilenameMaxBytes))"
        case .unsupported: return "Unsupported/\(filename)"
        }
    }

    /// D-283: `item.category` para video se guarda como el displayName
    /// LOCALIZADO -- comparar contra los dos idiomas para que un item
    /// clasificado con la app en un idioma siga contando bien si el
    /// usuario luego cambia el idioma de la app (mismo criterio que
    /// `sync()` más abajo).
    static func isSeriesCategory(_ category: String?) -> Bool {
        category == MediaCategory.series.displayNameSpanish || category == MediaCategory.series.displayNameEnglish
    }

    /// docs/contracts/library-layout-v1.md §1: "nombre ≤ 95 bytes UTF-8
    /// incluyendo la extensión" para `/Videos/` y `/Photos/` --
    /// `VIDEO_NAME_LEN`/`PHOTO_NAME_LEN` del firmware son 96 con el NUL.
    static let deviceFilenameMaxBytes = 95

    /// "<seriesName> S%02dE%02d.<ext>", saneado y acotado a `maxBytes`
    /// SIN tocar el sufijo ` SxxEyy.<ext>` -- a diferencia de
    /// `PathSanitizer.sanitizeFilename` (que recorta desde el final del
    /// nombre completo, lo que mutilaría justo el sufijo que
    /// `parse_sxxeyy()` necesita), acá el presupuesto de bytes se
    /// calcula ANTES y solo `seriesName` se trunca.
    static func seriesEpisodeFilename(seriesName: String, season: Int, episode: Int, ext: String, maxBytes: Int = deviceFilenameMaxBytes) -> String {
        let suffix = String(format: " S%02dE%02d", season, episode)
        let extSuffix = ext.isEmpty ? "" : ".\(ext)"
        let budget = max(1, maxBytes - suffix.utf8.count - extSuffix.utf8.count)
        // Reusa PathSanitizer.sanitize (caracteres ilegales de FAT32 -> "_",
        // trim de espacios/puntos finales) antes de acotar por bytes.
        var base = PathSanitizer.sanitize(seriesName, maxLength: Int.max)
        while base.utf8.count > budget, !base.isEmpty {
            base.removeLast()
        }
        while let last = base.last, last == "." || last == " " {
            base.removeLast()
        }
        if base.isEmpty { base = "_" }
        return base + suffix + extSuffix
    }

    /// "Videos/<seriesName saneado> S%02d.jpg" -- mismo prefijo saneado
    /// que `seriesEpisodeFilename` (garantiza que el firmware, que solo
    /// concatena el nombre de programa que ya parseó de un episodio con
    /// " S%02d.jpg", encuentre el archivo exacto que Studio escribió).
    /// Inversa aproximada de `seriesEpisodeFilename`: dado el destino ya
    /// escrito de un episodio ("Videos/<seriesName> SxxEyy.mpg"), la
    /// ruta del póster de temporada que le corresponde -- usado por
    /// `DeviceSyncIndexBuilder.ownedDevicePaths` para que ese póster
    /// (sin registro propio en el manifiesto, igual que el póster por
    /// video) no aparezca como "solo en el iPod". `nil` si `relative`
    /// no tiene la forma esperada (no es un episodio de Series).
    static func seasonPosterRelativePath(fromEpisodeDestinationRelativePath relative: String) -> String? {
        guard relative.hasPrefix("Videos/") else { return nil }
        let base = ((relative as NSString).lastPathComponent as NSString).deletingPathExtension
        guard let regex = try? NSRegularExpression(pattern: #"^(.*) S(\d{2})E\d{2,3}$"#) else { return nil }
        let range = NSRange(base.startIndex..., in: base)
        guard let match = regex.firstMatch(in: base, range: range),
              let nameRange = Range(match.range(at: 1), in: base),
              let seasonRange = Range(match.range(at: 2), in: base),
              let season = Int(base[seasonRange]) else { return nil }
        return seasonPosterRelativePath(seriesName: String(base[nameRange]), season: season)
    }

    static func seasonPosterRelativePath(seriesName: String, season: Int, maxBytes: Int = deviceFilenameMaxBytes) -> String {
        let suffix = String(format: " S%02d", season)
        let extSuffix = ".jpg"
        let budget = max(1, maxBytes - suffix.utf8.count - extSuffix.utf8.count)
        var base = PathSanitizer.sanitize(seriesName, maxLength: Int.max)
        while base.utf8.count > budget, !base.isEmpty {
            base.removeLast()
        }
        while let last = base.last, last == "." || last == " " {
            base.removeLast()
        }
        if base.isEmpty { base = "_" }
        return "Videos/\(base)\(suffix)\(extSuffix)"
    }

    /// Borra el indice de tagcache del dispositivo. No es destructivo
    /// para la musica en si (solo el indice de busqueda, que Aura
    /// reconstruye solo en el proximo arranque, ver D-021) -- es la
    /// forma mas simple y robusta de decirle al firmware "hay archivos
    /// nuevos" sin reimplementar el formato binario de tagcache.
    private func triggerFirmwareDBRebuild() {
        for relativePath in Self.tagcacheFilesToClear {
            let url = volumeRoot.appendingPathComponent(relativePath)
            try? fileManager.removeItem(at: url)
        }
    }
}

/// ST-062: los LFN de FAT32 los guarda el driver msdosfs de macOS
/// PRECOMPUESTOS (NFC), aunque FileManager los reporte DESCOMPUESTOS
/// (NFD) al leerlos de vuelta. El firmware lee el UTF-16 del disco tal
/// cual y compara byte a byte (aura_media_categories.c, ratings, rutas
/// de .m3u8), así que todo nombre o ruta que viaje dentro de un archivo
/// del contrato debe serializarse en NFC -- si no, cualquier nombre con
/// acento ("último", "canción") no empareja JAMÁS con lo que el
/// firmware ve en el disco. Bug real: "Avatar Aang el último maestro
/// del aire.mpg" categorizado como `movie` en el cfg pero invisible en
/// Películas/Movie Flow, mientras su vecino 100% ASCII sí aparecía.
extension String {
    var firmwareNFC: String { precomposedStringWithCanonicalMapping }
}
