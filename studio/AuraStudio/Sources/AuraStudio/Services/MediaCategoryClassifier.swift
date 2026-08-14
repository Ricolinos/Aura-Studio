import Foundation
import ImageIO

/// Lee el archivo real (EXIF de una foto, duracion de un video) y
/// delega la decision a `MediaCategoryHeuristics` (logica pura,
/// testeable sin tocar disco).
enum MediaCategoryClassifier {
    static func classifyPhoto(at url: URL) -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return "Imágenes"
        }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let softwareTag = (tiff?[kCGImagePropertyTIFFSoftware] as? String)
            ?? (exif?[kCGImagePropertyExifUserComment] as? String)
        let hasCameraExif = exif?[kCGImagePropertyExifLensModel] != nil
            || exif?[kCGImagePropertyExifFNumber] != nil
            || tiff?[kCGImagePropertyTIFFMake] != nil
        return MediaCategoryHeuristics.classifyPhoto(softwareTag: softwareTag, hasCameraExif: hasCameraExif)
    }

    /// La duracion se mide con el mismo `ffmpeg` que ya hace falta para
    /// transcodificar video (`FFmpegTranscoder.probeDurationSeconds`) en
    /// vez de sumar AVFoundation como dependencia nueva para un solo
    /// dato.
    static func classifyVideo(at url: URL) -> MediaCategory {
        guard let transcoder = try? FFmpegTranscoder(),
              let duration = try? FFmpegTranscoder.probeDurationSeconds(of: url, ffmpegURL: transcoder.ffmpegURL) else {
            return .videos
        }
        return MediaCategoryHeuristics.classifyVideo(durationSeconds: duration)
    }
}
