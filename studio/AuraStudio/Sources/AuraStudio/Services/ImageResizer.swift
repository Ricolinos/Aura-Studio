import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Redimensiona fotos a una resolucion optima para el LCD de 320x240
/// del iPod usando ImageIO/CoreGraphics -- nativo de macOS, sin
/// depender de ffmpeg para algo que el sistema ya resuelve bien.
/// Preserva aspecto (no recorta ni deforma) y siempre convierte a JPEG,
/// que es uno de los dos formatos que el visor de Aura decodifica
/// (D-028 en el firmware; el otro es BMP, mucho mas pesado sin
/// compresion, no tiene sentido para fotos).
struct ImageResizer {
    enum ResizeError: Error, LocalizedError {
        case cannotReadImage
        case cannotEncodeOutput

        var errorDescription: String? {
            switch self {
            case .cannotReadImage: return "No se pudo leer la imagen de origen."
            case .cannotEncodeOutput: return "No se pudo generar el JPEG de salida."
            }
        }
    }

    /// 320x240 es la resolucion nativa del LCD -- default cuando no se
    /// pasa `maxDimension` explicito (p.ej. desde tests). Con la
    /// preferencia de calidad de foto (D-191/D-192), el llamador real
    /// (`LibraryViewModel.process`) pasa 320 o 640 segun lo que haya
    /// elegido el usuario; en ambos casos se preserva aspecto sin
    /// escalar hacia arriba fotos que ya sean chicas.
    static let maxDimension: CGFloat = 320

    static func resizeToLCDOptimal(sourceURL: URL, destinationURL: URL,
                                    maxDimension: CGFloat = maxDimension, quality: CGFloat = 0.85) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw ResizeError.cannotReadImage
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ResizeError.cannotReadImage
        }

        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ResizeError.cannotEncodeOutput
        }

        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, thumbnail, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw ResizeError.cannotEncodeOutput
        }
    }
}
