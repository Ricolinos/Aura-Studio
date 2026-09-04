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

        try encodeBaselineJPEG(thumbnail, quality: quality).write(to: destinationURL)
    }

    // MARK: - Recorte cuadrado (contrato v18, ST-140)

    /// El JPEG cuadrado de lado `side`, recortado al centro desde el lado
    /// corto de la fuente (fill + center-crop, nunca estirado ni con
    /// bandas). Es la primitiva que usan la biblioteca local y el sync:
    /// carátulas de álbum (`cover.jpg` 320), fotos de artista (128) y la
    /// copia local de `.portadas/` (lado corto, tope 1000).
    ///
    /// Nunca escala hacia arriba: una fuente cuyo lado corto sea menor que
    /// `side` sale con ese lado corto. La orientación EXIF se respeta y se
    /// hornea en los píxeles, igual que en `resizeToLCDOptimal`.
    static func squareCrop(data: Data, side: Int, quality: CGFloat = 0.85) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ResizeError.cannotReadImage
        }
        return try squareCrop(source: source, side: side, quality: quality)
    }

    static func squareCrop(sourceURL: URL, side: Int, quality: CGFloat = 0.85) throws -> Data {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw ResizeError.cannotReadImage
        }
        return try squareCrop(source: source, side: side, quality: quality)
    }

    static func squareCrop(data: Data, destinationURL: URL, side: Int, quality: CGFloat = 0.85) throws {
        try squareCrop(data: data, side: side, quality: quality).write(to: destinationURL)
    }

    static func squareCrop(sourceURL: URL, destinationURL: URL, side: Int, quality: CGFloat = 0.85) throws {
        try squareCrop(sourceURL: sourceURL, side: side, quality: quality).write(to: destinationURL)
    }

    private static func squareCrop(source: CGImageSource, side: Int, quality: CGFloat) throws -> Data {
        guard let (width, height) = orientedPixelSize(of: source) else {
            throw ResizeError.cannotReadImage
        }

        let plan = SquareCropPlan(width: width, height: height, maxSide: side)
        guard !plan.isEmpty else { throw ResizeError.cannotReadImage }

        // ImageIO limita el lado MAYOR de la miniatura; lo que aca hay que
        // fijar es el lado CORTO (el que sobrevive al recorte). Se pide el
        // mayor proporcional, redondeado hacia arriba para que el corto
        // nunca quede por debajo de lo pedido y el recorte no tenga que
        // agrandar nada.
        let longSide = max(width, height), shortSide = min(width, height)
        let maxPixelSize = plan.needsResize
            ? Int((Double(longSide) * Double(plan.outputSide) / Double(shortSide)).rounded(.up))
            : longSide

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ResizeError.cannotReadImage
        }

        // El recorte se replantea sobre lo que ImageIO devolvio de verdad
        // (su redondeo puede diferir en un pixel del calculado arriba).
        let crop = SquareCropPlan(width: thumbnail.width, height: thumbnail.height, maxSide: plan.outputSide)
        guard !crop.isEmpty else { throw ResizeError.cannotReadImage }

        let square: CGImage
        if crop.needsCrop {
            guard let cropped = thumbnail.cropping(to: CGRect(x: crop.cropX, y: crop.cropY,
                                                              width: crop.cropSide, height: crop.cropSide)) else {
                throw ResizeError.cannotEncodeOutput
            }
            square = cropped
        } else {
            square = thumbnail
        }

        // El lado final es SIEMPRE el del plan sobre la fuente: el contrato
        // v18 fija medidas exactas (320x320, 128x128) y un pixel de menos
        // por el redondeo de la miniatura seria un incumplimiento.
        let resized = square.width == plan.outputSide ? square : try scale(square, toSide: plan.outputSide)
        return try encodeBaselineJPEG(resized, quality: quality)
    }

    /// Medidas de la imagen **ya orientadas** -- una foto vertical de
    /// camara viene guardada horizontal con la rotacion en EXIF, y el
    /// recorte tiene que planearse sobre lo que se ve.
    private static func orientedPixelSize(of source: CGImageSource) -> (width: Int, height: Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else {
            return nil
        }
        // Orientaciones 5-8: la imagen guardada esta girada 90 grados, asi
        // que lo que se ve tiene los lados intercambiados.
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return (5...8).contains(orientation) ? (height, width) : (width, height)
    }

    private static func scale(_ image: CGImage, toSide side: Int) throws -> CGImage {
        guard side > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side,
                                       bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ResizeError.cannotEncodeOutput
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let scaled = context.makeImage() else { throw ResizeError.cannotEncodeOutput }
        return scaled
    }

    /// El JPEG de `image`, aplanado sobre blanco y garantizado baseline.
    private static func encodeBaselineJPEG(_ image: CGImage, quality: CGFloat) throws -> Data {
        // PLAN-sync-media-hardening.md PARTE 2A: una fuente PNG/GIF con
        // canal alfa (transparencia) llegaba tal cual al codificador de
        // JPEG -- que no tiene canal alfa, asi que el RGB debajo de los
        // pixeles transparentes queda a su criterio (con frecuencia
        // negro/indefinido en vez del fondo blanco esperado). Se aplana
        // sobre blanco ANTES de codificar, sin excepcion (para una
        // imagen ya opaca esto no cambia nada visible).
        let flattened = flattenOntoWhite(image) ?? image

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
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
        return output as Data
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
