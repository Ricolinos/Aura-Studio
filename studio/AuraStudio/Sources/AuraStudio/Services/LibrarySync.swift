import Foundation

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
}

struct SyncManifest: Codable, Equatable {
    var records: [String: SyncRecord] // key = sourcePath

    static let empty = SyncManifest(records: [:])
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
    static let playlistsRelativePath = "Playlists"
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
              onProgress: (_ copied: Int, _ toCopy: Int) -> Void = { _, _ in }) throws -> SyncResult {
        var manifest = loadManifest()
        var copied = 0
        var destinationByItemID: [UUID: String] = [:]
        var summary = CatalogSummary()

        let currentFiles = try items.compactMap { item -> (sourcePath: String, size: Int64, modifiedAt: TimeInterval, destinationRelativePath: String)? in
            guard let prepared = item.preparedURL else { return nil }
            let attrs = try fileManager.attributesOfItem(atPath: prepared.path)
            let size = (attrs[.size] as? Int64) ?? 0
            let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let destRelative = destinationRelativePath(for: item, musicOrganization: musicOrganization,
                                                         musicFilenameFormat: musicFilenameFormat)
            destinationByItemID[item.id] = destRelative

            switch item.kind {
            case .music: summary.music.count += 1; summary.music.bytes += size
            case .video: summary.video.count += 1; summary.video.bytes += size
            case .photo: summary.photo.count += 1; summary.photo.bytes += size
            case .unsupported: break
            }

            return (item.sourceURL.path, size, modified, destRelative)
        }

        let plan = SyncPlanner.plan(current: currentFiles, previousManifest: manifest)
        // D-217: total real de archivos que este sync va a copiar de
        // verdad (los que SyncPlanner ya decidio saltear no cuentan) --
        // asi la barra de progreso mide contra lo que efectivamente va a
        // pasar, no contra el total de la biblioteca completa.
        let toCopy = plan.filter { $0.action == .copy }.count

        for planItem in plan {
            guard planItem.action == .copy else { continue }
            guard let item = items.first(where: { $0.sourceURL.path == planItem.sourcePath }),
                  let prepared = item.preparedURL else { continue }

            if let stale = planItem.staleDestinationRelativePath {
                try? fileManager.removeItem(at: volumeRoot.appendingPathComponent(stale))
            }

            let destination = volumeRoot.appendingPathComponent(planItem.destinationRelativePath)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: prepared, to: destination)
            copied += 1
            onProgress(copied, toCopy)

            // Fase 24: el poster de un video (`<video>.jpg`, generado
            // por FFmpegTranscoder.generatePoster) viaja pegado a su
            // video -- no tiene entrada propia en el manifiesto, sigue
            // el mismo diferencial que el archivo principal (D-066).
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
            manifest.records[planItem.sourcePath] = SyncRecord(
                sourcePath: planItem.sourcePath,
                sourceSize: (attrs[.size] as? Int64) ?? 0,
                sourceModifiedAt: (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0,
                destinationRelativePath: planItem.destinationRelativePath
            )
        }

        try saveManifest(manifest)

        if coverArtPolicy == .albumOnly {
            writeAlbumCovers(items: items, destinationByItemID: destinationByItemID)
        }

        let playlistsWritten = try writePlaylists(playlists, destinationByItemID: destinationByItemID,
                                                   items: items, libraryRoot: libraryRoot)
        summary.playlistCount = playlistsWritten
        try writeSummary(summary)
        try writeRatings(items: items, destinationByItemID: destinationByItemID)

        if copied > 0 {
            triggerFirmwareDBRebuild()
        }
        return SyncResult(filesCopied: copied, playlistsWritten: playlistsWritten)
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
            let paths = playlist.trackItemIDs.compactMap { destinationByItemID[$0] }
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
            return "/\(relative): \(nativeRating)"
        }

        let url = volumeRoot.appendingPathComponent(Self.ratingsRelativePath)
        guard !lines.isEmpty else {
            try? fileManager.removeItem(at: url)
            return
        }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
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

    private func destinationRelativePath(
        for item: LibraryItem,
        musicOrganization: AppPreferences.MusicOrganization,
        musicFilenameFormat: AppPreferences.MusicFilenameFormat
    ) -> String {
        let filename = item.preparedURL?.lastPathComponent ?? item.sourceURL.lastPathComponent
        switch item.kind {
        case .music: return Self.musicDestinationRelativePath(for: item, organization: musicOrganization,
                                                                filenameFormat: musicFilenameFormat)
        case .video: return "Videos/\(filename)"
        case .photo: return "Photos/\(filename)"
        case .unsupported: return "Unsupported/\(filename)"
        }
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
