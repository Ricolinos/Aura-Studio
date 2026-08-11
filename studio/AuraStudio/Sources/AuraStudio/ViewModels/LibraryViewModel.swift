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

    private let enricher: LibraryEnricher
    private let stagingDirectory: URL

    init(enricher: LibraryEnricher = LibraryEnricher(), stagingDirectory: URL? = nil) {
        self.enricher = enricher
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
                let metadata = await enricher.enrich(item: item)
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
    /// para MP3, ver D-037) y deja caratula/letra como sidecars junto a
    /// el -- el mismo formato que Aura ya sabe leer en el dispositivo
    /// (find_albumart/aura_lrc, Fases 4-6 del firmware).
    private func prepareMusic(item: LibraryItem, metadata: TrackMetadata) throws -> URL {
        let destination = stagingDirectory.appendingPathComponent(item.sourceURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: item.sourceURL, to: destination)

        if destination.pathExtension.lowercased() == "mp3" {
            let tag = ID3Writer.Tag(
                title: metadata.title, artist: metadata.artist, album: metadata.album,
                albumArtist: metadata.albumArtist, year: metadata.year, genre: metadata.genre,
                trackNumber: metadata.trackNumber, coverArtData: metadata.coverArtData
            )
            try ID3Writer.write(tag, toFileAt: destination)
        } else if let cover = metadata.coverArtData {
            let coverURL = destination.deletingLastPathComponent().appendingPathComponent("cover.jpg")
            try cover.write(to: coverURL)
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
            let copied = try sync.sync(items: readyItems)
            lastSyncSummary = copied == 0
                ? "Ya estaba todo sincronizado, no habia nada nuevo."
                : "Se copiaron \(copied) de \(readyItems.count) archivo(s). El indice de la biblioteca se va a reconstruir la proxima vez que arranque Aura."
        } catch {
            lastError = error.localizedDescription
        }
    }
}
