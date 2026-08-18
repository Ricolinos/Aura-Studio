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
        try write(source: source, destinationURL: destinationURL, maxDimension: maxDimension, quality: quality)
    }

    /// ST-033: misma conversion, desde bytes en memoria (poster de video
    /// descargado). Salida JPEG baseline con el lado mayor <= `maxDimension`
    /// (640 = maximo que admite el firmware, CONTRATO-firmware-studio.md).
    static func resizeToLCDOptimal(data: Data, destinationURL: URL,
                                    maxDimension: CGFloat = maxDimension, quality: CGFloat = 0.85) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ResizeError.cannotReadImage
        }
        try write(source: source, destinationURL: destinationURL, maxDimension: maxDimension, quality: quality)
    }

    private static func write(source: CGImageSource, destinationURL: URL,
                              maxDimension: CGFloat, quality: CGFloat) throws {

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ResizeError.cannotReadImage
        }

        // PLAN-sync-media-hardening.md PARTE 2A: una fuente PNG/GIF con
        // canal alfa (transparencia) llegaba tal cual al codificador de
        // JPEG -- que no tiene canal alfa, asi que el RGB debajo de los
        // pixeles transparentes queda a su criterio (con frecuencia
        // negro/indefinido en vez del fondo blanco esperado). Se aplana
        // sobre blanco ANTES de codificar, sin excepcion (para una
        // imagen ya opaca esto no cambia nada visible).
        let flattened = flattenOntoWhite(thumbnail) ?? thumbnail

        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ResizeError.cannotEncodeOutput
        }

        // D-291 en Aura-Firmware (aura_photos.c:171-259): el visor solo
        // decodifica JPEG BASELINE -- un progresivo (marcador SOF2) sale
        // como "Formato no soportado". El codificador de ImageIO no
        // garantiza baseline por defecto para toda entrada; forzarlo
        // explicito (en vez de dejarlo a su criterio) es la unica forma
        // de asegurarlo siempre.
        let jfifProperties: [CFString: Any] = [kCGImagePropertyJFIFIsProgressive: false]
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyJFIFDictionary: jfifProperties,
        ]
        CGImageDestinationAddImage(destination, flattened, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw ResizeError.cannotEncodeOutput
        }
    }

    /// Compone `image` sobre un fondo blanco opaco, del mismo tamaño,
    /// descartando cualquier canal alfa. `nil` si CoreGraphics no pudo
    /// armar el contexto (fuente exotica) -- el llamador sigue de largo
    /// con la imagen original en vez de fallar el sync entero por esto.
    private static func flattenOntoWhite(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                       bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                       bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return nil
        }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }
}
