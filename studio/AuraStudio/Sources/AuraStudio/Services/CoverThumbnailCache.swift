import AppKit
import ImageIO

/// Miniaturas de portadas para las cuadrículas de Álbumes/Artistas
/// (ST-020). Las carátulas se guardan a tamaño completo
/// (`TrackMetadata.coverArtData`, ~1000 px con fanart.tv); decodificar
/// eso por cada celda visible en cada scroll es lo que hace lentas
/// estas vistas. `CGImageSourceCreateThumbnailAtIndex` decodifica ya
/// reducido (mismo primitivo que `ImageResizer`), y `NSCache` se
/// encarga de soltar bajo presión de memoria. Clave = hash de los
/// bytes + tamaño, así que dos canciones con la misma carátula
/// comparten miniatura.
final class CoverThumbnailCache {
    static let shared = CoverThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()

    init() {
        cache.countLimit = 600
    }

    func thumbnail(for data: Data?, side: CGFloat) -> NSImage? {
        guard let data, !data.isEmpty else { return nil }
        let key = "\(data.count)-\(data.hashValue)-\(Int(side))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = Self.decodeThumbnail(data, side: side) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    private static func decodeThumbnail(_ data: Data, side: CGFloat) -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(side * scale),
            kCGImageSourceShouldCache: false,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: side, height: side))
    }
}
