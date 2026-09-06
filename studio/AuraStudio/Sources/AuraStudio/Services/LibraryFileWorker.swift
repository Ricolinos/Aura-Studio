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
                .appendingPathComponent(request.sourceURL.deletingPathExtension().lastPathComponent)
                .appendingPathExtension("mp3")
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            let transcoder = try AudioTranscoder()
            try transcoder.transcodeToMP3(input: request.sourceURL, output: destination)
        } else {
            destination = request.stagingDirectory.appendingPathComponent(request.sourceURL.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: request.sourceURL, to: destination)
        }

        if destination.pathExtension.lowercased() == "mp3" {
            let embedCover = request.coverArtPolicy == .perTrack
            // ST-185: la carátula ya no vive en RAM -- se lee de
            // `.portadas/` acá, que es donde toca: este worker corre
            // fuera del actor principal.
            let embedded = embedCover ? request.metadata.loadCoverData().flatMap {
                try? ImageResizer.squareCrop(data: $0, side: LibrarySync.deviceCoverSide,
                                             quality: LibrarySync.deviceCoverQuality)
            } : nil
            let tag = ID3Writer.Tag(
                title: request.metadata.title, artist: request.metadata.artist, album: request.metadata.album,
                albumArtist: request.metadata.albumArtist, year: request.metadata.year, genre: request.metadata.genre,
                composer: request.metadata.composer,
                trackNumber: request.metadata.trackNumber,
                coverArtData: embedded
            )
            try ID3Writer.write(tag, toFileAt: destination)
        }

        if let lyrics = request.metadata.syncedLyrics {
            let lrcURL = destination.deletingPathExtension().appendingPathExtension("lrc")
            try lyrics.write(to: lrcURL, atomically: true, encoding: .utf8)
        }

        return destination
    }
}
