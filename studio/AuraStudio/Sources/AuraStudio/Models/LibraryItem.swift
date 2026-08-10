import Foundation

enum LibraryItemKind: Equatable {
    case music
    case video
    case photo
    case unsupported

    static func classify(url: URL) -> LibraryItemKind {
        switch url.pathExtension.lowercased() {
        case "flac", "mp3", "m4a", "wav", "aiff", "aif":
            return .music
        case "mp4", "mov", "m4v", "avi", "mkv", "mpg", "mpeg":
            return .video
        case "jpg", "jpeg", "png", "gif", "bmp", "heic", "tiff":
            return .photo
        default:
            return .unsupported
        }
    }
}

enum LibraryItemStatus: Equatable {
    case queued
    case enriching
    case transcoding(progress: Double)
    case ready
    case needsReview
    case failed(String)
}

/// Un archivo que el usuario solto en Aura Studio, en algun punto de su
/// camino hacia el iPod: musica nativa que solo necesita metadata,
/// video que hay que transcodificar, o una foto que hay que
/// redimensionar. `sourceURL` es el archivo original del usuario;
/// `preparedURL` es el resultado final listo para copiar al dispositivo
/// (el mismo archivo para musica nativa, o la salida de ffmpeg/resize).
struct LibraryItem: Identifiable, Equatable {
    let id: UUID
    let sourceURL: URL
    let kind: LibraryItemKind
    var status: LibraryItemStatus
    var metadata: TrackMetadata?
    var preparedURL: URL?

    init(sourceURL: URL) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.kind = LibraryItemKind.classify(url: sourceURL)
        self.status = .queued
        self.metadata = nil
        self.preparedURL = nil
    }
}
