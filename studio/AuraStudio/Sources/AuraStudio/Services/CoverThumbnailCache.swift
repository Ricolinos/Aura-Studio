import AppKit
import ImageIO

/// Miniaturas de portadas para las cuadrículas de Álbumes/Artistas
/// (ST-031). Las carátulas se guardan a tamaño completo
/// (`TrackMetadata.coverArtData`, ~1000 px con fanart.tv); decodificar
/// eso por cada celda visible en cada scroll es lo que hace lentas
/// estas vistas. `CGImageSourceCreateThumbnailAtIndex` decodifica ya
/// reducido (mismo primitivo que `ImageResizer`), y `NSCache` se
/// encarga de soltar bajo presión de memoria. Clave = hash de los
/// bytes + tamaño, así que dos canciones con la misma carátula
/// comparten miniatura.
/// `NSCache` es seguro entre hilos y no hay mas estado: por eso
/// `@unchecked Sendable` es honesto (Swift 6 exige declararlo para el
/// `shared`).
final class CoverThumbnailCache: @unchecked Sendable {
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
        // Bug real (encargo del dueño, 2026-08-19: "las imágenes se ven
        // distorsionadas"): `kCGImageSourceThumbnailMaxPixelSize` solo
        // acota el lado MAYOR -- una foto 16:9 decodifica a, p.ej.,
        // 280×157, nunca 280×280. Forzar `size: (side, side)` acá
        // mentía sobre el aspecto real del `NSImage` (quedaba "1:1" de
        // metadata aunque el buffer de píxeles no lo fuera); SwiftUI
        // calcula `.aspectRatio(contentMode: .fill)` contra ESE tamaño
        // reportado, así que estiraba la imagen real para "llenar" un
        // cuadrado que el contenido nunca tuvo -- distorsión visible en
        // cualquier foto que no fuera ya cuadrada. El tamaño reportado
        // tiene que ser el aspecto REAL del `cgImage` para que `.fill`
        // recorte en vez de estirar.
        let size = NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
        return NSImage(cgImage: cgImage, size: size)
    }
}
