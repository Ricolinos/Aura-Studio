import CoreGraphics
import Foundation

/// PLAN-studio-rendimiento.md Fase 4 punto 2, paso 1: copiar/
/// transcodificar/recortar carátula/escribir ID3 fuera del actor
/// principal. Diagnóstico §0.5: `LibraryViewModel.prepareMusic` hacía
/// exactamente este trabajo -- copiar el audio completo, correr
/// `ffmpeg`, recortar la carátula y reescribir el ID3 -- síncrono, en
/// el `@MainActor`, en cada estrella/categoría/edición en lote.
///
/// Un `actor` (no `@MainActor`): sus métodos corren en un hilo del
/// grupo, nunca en el principal. Recibe todo lo que necesita como
/// parámetros `Sendable` (nunca `LibraryViewModel`/`AppPreferences`
/// completos, que son afines al actor principal) -- quien lo llama
/// arma el `PrepareMusicRequest` leyendo esas dos cosas ANTES de cruzar
/// al worker.
///
/// Es una copia deliberada de la lógica de `prepareMusic`, no una
/// reescritura: el mismo orden de pasos, las mismas reglas -- para que
/// la prueba de equivalencia (`LibraryFileWorkerEquivalenceTests`,
/// mismo resultado byte a byte que el camino viejo) tenga sentido como
/// prueba de que este refactor es seguro, no de que hace algo distinto
/// mejor.
actor LibraryFileWorker {
    struct PrepareMusicRequest: Sendable {
        var sourceURL: URL
        var stagingDirectory: URL
        var metadata: TrackMetadata
        var audioQuality: AppPreferences.AudioQuality
        var coverArtPolicy: AppPreferences.CoverArtPolicy
        /// ST-221: el derivado se llama por el id del elemento, no por
        /// el nombre del archivo original -- ver
        /// `LibraryViewModel.stagingDestination`.
        var itemID: UUID
        /// El derivado anterior, si lo había. Si el nombre cambió (es el
        /// caso al pasar del nombrado viejo por nombre base al nuevo por
        /// id), el anterior se borra en cuanto el nuevo quedó escrito:
        /// dejarlo sería un huérfano, y dejar huérfanos a propósito
        /// mientras existe una acción de "limpiar huérfanos" es
        /// exactamente la clase de basura que esta ronda viene a quitar.
        var previousPreparedURL: URL?
    }

    // MARK: - La etiqueta que sale del catálogo

    /// Los campos del catálogo, en la forma que entienden los tres
    /// escritores nativos (ST-222).
    ///
    /// Vive acá, en el worker, porque **recortar la carátula es caro** y
    /// este es el lado que corre fuera del actor principal: la imagen se
    /// lee de `.portadas/` y se recorta al tamaño del dispositivo. Antes
    /// esta construcción estaba escrita dentro de `prepareMusic`; con
    /// tres caminos que la necesitan (preparar, importar, reetiquetar)
    /// tenerla tres veces era la forma segura de que se separaran.
    static func audioTag(from metadata: TrackMetadata,
                         coverArtPolicy: AppPreferences.CoverArtPolicy) -> AudioTag {
        // ST-185: la carátula ya no vive en RAM -- se lee de
        // `.portadas/` acá, que es donde toca.
        let embedded = coverArtPolicy == .perTrack ? metadata.loadCoverData().flatMap {
            try? ImageResizer.squareCrop(data: $0, side: LibrarySync.deviceCoverSide,
                                         quality: LibrarySync.deviceCoverQuality)
        } : nil
        return AudioTag(
            title: metadata.title, artist: metadata.artist, album: metadata.album,
            albumArtist: metadata.albumArtist, year: metadata.year, genre: metadata.genre,
            composer: metadata.composer, trackNumber: metadata.trackNumber,
            discNumber: metadata.discNumber, coverArtData: embedded)
    }

    // MARK: - Importar a la biblioteca en modo copia (ST-223)

    /// Lo que hace falta para meter una canción en la biblioteca en modo
    /// copia. Todo `Sendable`: lo arma `LibraryViewModel` leyendo sus
    /// preferencias ANTES de cruzar al worker.
    struct ImportMusicRequest: Sendable {
        var sourceURL: URL
        /// El destino final, ya resuelto y sin colisiones, **con la
        /// extensión que corresponda al resultado** (`.m4a` si va a
        /// ALAC, `.mp3` si va a MP3, la del origen si se copia tal cual).
        var destinationURL: URL
        var decision: AudioConversionRule.Decision
        var metadata: TrackMetadata
        var coverArtPolicy: AppPreferences.CoverArtPolicy
    }

    struct ImportedMusic: Sendable {
        var url: URL
        var byteSize: Int
        /// Lo que el escritor de etiquetas dijo. Se sube al ViewModel en
        /// vez de tragárselo: un archivo importado al que no se le
        /// pudieron escribir las etiquetas es un archivo que va a llegar
        /// al iPod diciendo otra cosa, y eso tiene que poder verse.
        var tagResult: LocalTagWriter.Result
    }

    /// Mete el archivo en la biblioteca y le escribe las etiquetas del
    /// catálogo. En modo copia **este archivo ES el que viaja al iPod**:
    /// no hay derivado en `.preparados/` de por medio (ST-221/§2).
    ///
    /// **Atómico.** Se arma primero un temporal `<destino>.aura-tmp`
    /// junto al destino -- junto, para que el movimiento final sea dentro
    /// del mismo volumen y por lo tanto instantáneo e indivisible; y sin
    /// extensión de música, para que un archivo a medio escribir no
    /// parezca una canción importable si algo se corta en el medio. Solo
    /// cuando el contenido y las etiquetas están completos se renombra al
    /// nombre definitivo. Si algo falla, **se limpia el temporal y no
    /// queda nada en la biblioteca**.
    func importMusic(_ request: ImportMusicRequest) async throws -> ImportedMusic {
        let fileManager = FileManager.default
        let destination = request.destinationURL
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent("\(UUID().uuidString).aura-tmp")

        do {
            switch request.decision {
            case .copyAsIs:
                try fileManager.copyItem(at: request.sourceURL, to: temporary)
            case .convertToALAC:
                // El codificador escribe un contenedor MPEG-4 y elige el
                // muxer por la extensión, así que el archivo se produce
                // aparte, con su `.m4a`, y recién después entra a la
                // biblioteca como temporal.
                try await convert(request.sourceURL, into: temporary, scratchExtension: "m4a") { input, output in
                    try await AppleLosslessEncoder.encode(input: input, output: output)
                }
            case .convertToMP3:
                try await convert(request.sourceURL, into: temporary, scratchExtension: "mp3") { input, output in
                    // El sistema no codifica MP3 (comprobado enumerando
                    // los codificadores de AudioToolbox): acá sí hace
                    // falta ffmpeg, y si no está se dice (D-038).
                    let transcoder = try AudioTranscoder()
                    try transcoder.transcodeToMP3(input: input, output: output)
                }
            }

            let tagResult = LocalTagWriter.write(
                Self.audioTag(from: request.metadata, coverArtPolicy: request.coverArtPolicy),
                toFileAt: temporary, as: destination.pathExtension)
            let byteSize = (try? fileManager.attributesOfItem(atPath: temporary.path)[.size] as? Int) ?? nil

            try fileManager.moveItem(at: temporary, to: destination)

            // ST-012: la letra viaja como `.lrc` hermano del archivo,
            // nunca dentro del audio.
            if let lyrics = request.metadata.syncedLyrics, !lyrics.isEmpty {
                let lrcURL = destination.deletingPathExtension().appendingPathExtension("lrc")
                try? lyrics.write(to: lrcURL, atomically: true, encoding: .utf8)
            }

            return ImportedMusic(url: destination, byteSize: byteSize ?? 0, tagResult: tagResult)
        } catch {
            // Que no quede a medias: ni el temporal, ni un destino
            // parcial. Una importación que falló no puede dejar rastro en
            // la biblioteca.
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    /// Corre un codificador que necesita elegir su formato por la
    /// extensión del archivo de salida, y deja el resultado en
    /// `temporary`. El intermedio vive **fuera** de la biblioteca.
    private func convert(_ input: URL, into temporary: URL, scratchExtension: String,
                         using encode: (URL, URL) async throws -> Void) async throws {
        let fileManager = FileManager.default
        let scratch = fileManager.temporaryDirectory
            .appendingPathComponent("aura-import-\(UUID().uuidString).\(scratchExtension)")
        defer { try? fileManager.removeItem(at: scratch) }
        try await encode(input, scratch)
        try fileManager.moveItem(at: scratch, to: temporary)
    }

    /// Reescribe las etiquetas de un archivo que **ya está** en la
    /// biblioteca, sin copiarlo ni moverlo (ST-223).
    ///
    /// Es la diferencia central con lo que había: hasta acá, cambiar el
    /// título recopiaba el archivo entero a `.preparados/`. Un archivo de
    /// cincuenta megabytes reescrito para cambiar unos cientos de bytes
    /// de etiqueta.
    func rewriteTags(metadata: TrackMetadata, coverArtPolicy: AppPreferences.CoverArtPolicy,
                     at url: URL) -> LocalTagWriter.Result {
        let result = LocalTagWriter.write(Self.audioTag(from: metadata, coverArtPolicy: coverArtPolicy),
                                          toFileAt: url)
        let lrcURL = url.deletingPathExtension().appendingPathExtension("lrc")
        if let lyrics = metadata.syncedLyrics, !lyrics.isEmpty {
            try? lyrics.write(to: lrcURL, atomically: true, encoding: .utf8)
        } else {
            // ST-012: la letra se borra con la canción y no queda
            // huérfana -- tampoco cuando el usuario la quita.
            try? FileManager.default.removeItem(at: lrcURL)
        }
        return result
    }

    // MARK: - Fotos y video (PLAN-studio-rendimiento-2.md Fase 6, ST-186)
    //
    // La ronda 1 sacó del actor principal la rama de MÚSICA de
    // `process(itemAt:)` y dejó anotadas las de video y foto como
    // pendientes (§0.9). Son las dos que más pesan por elemento:
    // redimensionar una foto de cámara y, sobre todo, transcodificar un
    // video con `ffmpeg`. Hasta acá corrían síncronas en el
    // `@MainActor`, o sea que importar una carpeta de fotos congelaba la
    // ventana un rato por CADA foto.

    struct PreparePhotoRequest: Sendable {
        var sourceURL: URL
        var destinationURL: URL
        var maxDimension: CGFloat
    }

    func preparePhoto(_ request: PreparePhotoRequest) throws {
        try ImageResizer.resizeToLCDOptimal(sourceURL: request.sourceURL,
                                            destinationURL: request.destinationURL,
                                            maxDimension: request.maxDimension)
    }

    struct PrepareVideoRequest: Sendable {
        var sourceURL: URL
        var destinationURL: URL
        var sourceFrameRate: Double?
        var posterURL: URL
        /// Póster ya descargado (TMDB/fanart.tv). Si viene, manda sobre
        /// el fotograma que saca `ffmpeg` (ST-033).
        var downloadedPoster: Data?
        var posterMaxDimension: CGFloat
    }

    /// Transcodifica y deja el póster al lado. `onProgress` se llama
    /// desde el hilo de lectura del pipe de `ffmpeg`; quien lo pasa se
    /// encarga de saltar al actor principal si va a tocar la UI.
    func prepareVideo(_ request: PrepareVideoRequest,
                      onProgress: @escaping @Sendable (Double) -> Void) throws {
        let transcoder = try FFmpegTranscoder()
        try transcoder.transcode(input: request.sourceURL, output: request.destinationURL,
                                 sourceFrameRate: request.sourceFrameRate, onProgress: onProgress)
        // Que no se pueda generar el póster NO aborta el video: ya quedó
        // listo para sincronizar sin él (D-066).
        if let downloaded = request.downloadedPoster,
           (try? ImageResizer.resizeToLCDOptimal(data: downloaded, destinationURL: request.posterURL,
                                                 maxDimension: request.posterMaxDimension)) != nil {
            return
        }
        try? transcoder.generatePoster(input: request.destinationURL, output: request.posterURL)
    }

    /// Copia del archivo original a staging, con la tag ID3 (solo MP3,
    /// D-037) y la letra como sidecar -- ver `LibraryViewModel.
    /// prepareMusic` para el razonamiento completo de cada regla; acá
    /// se preserva tal cual.
    func prepareMusic(_ request: PrepareMusicRequest) throws -> URL {
        let fileManager = FileManager.default
        let destination: URL
        if request.audioQuality == .compressed {
            destination = request.stagingDirectory
                .appendingPathComponent(request.itemID.uuidString)
                .appendingPathExtension("mp3")
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            let transcoder = try AudioTranscoder()
            try transcoder.transcodeToMP3(input: request.sourceURL, output: destination)
        } else {
            destination = request.stagingDirectory
                .appendingPathComponent(request.itemID.uuidString)
                .appendingPathExtension(request.sourceURL.pathExtension)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: request.sourceURL, to: destination)
        }

        if destination.pathExtension.lowercased() == "mp3" {
            try ID3Writer.write(Self.audioTag(from: request.metadata,
                                              coverArtPolicy: request.coverArtPolicy),
                                toFileAt: destination)
        }

        if let lyrics = request.metadata.syncedLyrics {
            let lrcURL = destination.deletingPathExtension().appendingPathExtension("lrc")
            try lyrics.write(to: lrcURL, atomically: true, encoding: .utf8)
        }

        // ST-221: el derivado anterior queda huérfano si cambió de
        // nombre. Se borra ACÁ, con el nuevo ya escrito, y solo si estaba
        // dentro de `.preparados/` -- nunca se borra nada de fuera de la
        // carpeta de derivados, pase lo que pase con el catálogo.
        if let previous = request.previousPreparedURL,
           previous.standardizedFileURL != destination.standardizedFileURL,
           previous.standardizedFileURL.deletingLastPathComponent().path
             == request.stagingDirectory.standardizedFileURL.path {
            try? fileManager.removeItem(at: previous)
            let previousLRC = previous.deletingPathExtension().appendingPathExtension("lrc")
            try? fileManager.removeItem(at: previousLRC)
        }

        return destination
    }
}
