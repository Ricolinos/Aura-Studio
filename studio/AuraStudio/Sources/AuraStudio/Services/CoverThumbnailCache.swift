import AppKit
import ImageIO

/// Miniaturas de portadas para las cuadrículas de Álbumes/Artistas/
/// Películas/Series/Fotos (ST-031). Las carátulas se guardan a tamaño
/// completo (`TrackMetadata.coverArtData`, ~1000 px con fanart.tv);
/// decodificar eso por cada celda visible en cada scroll es lo que hace
/// lentas estas vistas. `CGImageSourceCreateThumbnailAtIndex` decodifica
/// ya reducido (mismo primitivo que `ImageResizer`), y `NSCache` se
/// encarga de soltar bajo presión de memoria.
///
/// PLAN-studio-rendimiento-2.md Fase 2 (ST-183) cambia tres cosas del
/// diagnóstico §0.5:
///
/// 1. **La clave ya no es `Data.hashValue`.** Hashear un `Data` recorre
///    sus bytes: con carátulas de ~15 KB, cada consulta —acierto
///    incluido— hasheaba 15 KB **antes** de saber que la miniatura ya
///    estaba en memoria. Ahora la clave la pone quien pide (el id del
///    álbum, del video o de la foto) más una **huella O(1)** del blob
///    (`fingerprint`), que es lo que hace que cambiarle la carátula a un
///    álbum no siga mostrando la vieja.
/// 2. **Decodifica fuera del hilo principal**, con `async`; las celdas
///    la piden desde `.task(id:)`, que cancela sola al salir de
///    pantalla. Antes se decodificaba dentro del `body`.
/// 3. **`totalCostLimit`**, no solo `countLimit`: el tope real que
///    interesa es de MEMORIA (§A: "sin JPEG completos en RAM, solo
///    miniaturas cacheadas, tope 64 MB"). Un `countLimit` de 600 no dice
///    nada sobre cuánta RAM son esas 600.
///
/// La escala de pantalla se captura UNA vez (`captureScreenScale()`,
/// desde el hilo principal al arrancar la app): `NSScreen.main` no se
/// puede tocar desde la cola de decodificación.
///
/// `NSCache` es seguro entre hilos y el resto del estado va bajo
/// candado: por eso `@unchecked Sendable` es honesto (Swift 6 exige
/// declararlo para el `shared`).
final class CoverThumbnailCache: @unchecked Sendable {
    static let shared = CoverThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()
    /// Concurrente: varias celdas decodifican a la vez, cada una la suya.
    private let decodeQueue = DispatchQueue(label: "com.ricolinos.aurastudio.thumbnails",
                                            qos: .utility, attributes: .concurrent)
    private let scaleLock = NSLock()
    private var storedScale: CGFloat = 2

    init(countLimit: Int = 1_200, totalCostLimit: Int = 64 * 1024 * 1024) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    /// Se llama una vez al arrancar, desde el hilo principal.
    @MainActor
    func captureScreenScale() {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        scaleLock.lock()
        storedScale = scale
        scaleLock.unlock()
    }

    private var scale: CGFloat {
        scaleLock.lock()
        defer { scaleLock.unlock() }
        return storedScale
    }

    // MARK: - Consulta

    /// Lo que ya está en memoria. **Nunca decodifica ni toca disco**, así
    /// que se puede llamar desde un `body` sin costo: es una búsqueda en
    /// `NSCache` con una clave que se arma en O(1).
    func cached(id: String, side: CGFloat) -> NSImage? {
        cache.object(forKey: Self.key(id: id, side: side))
    }

    /// La miniatura, decodificándola fuera del hilo principal si hace
    /// falta. `load` se llama SOLO si no está en memoria, y desde la
    /// cola de decodificación -- por eso puede leer del disco (las fotos
    /// no viven en RAM, se leen de su archivo preparado).
    func thumbnail(id: String, side: CGFloat,
                   load: @escaping @Sendable () -> Data?) async -> NSImage? {
        let key = Self.key(id: id, side: side)
        if let cached = cache.object(forKey: key) { return cached }

        let scale = self.scale
        let image: NSImage? = await withCheckedContinuation { continuation in
            decodeQueue.async {
                guard let data = load(), !data.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: Self.decodeThumbnail(data, side: side, scale: scale))
            }
        }
        guard let image else { return nil }
        // Se guarda aunque quien la pidió ya se haya ido de pantalla: el
        // trabajo ya está hecho y la celda vuelve al desplazarse.
        cache.setObject(image, forKey: key, cost: Self.cost(of: image, scale: scale))
        return image
    }

    /// Camino síncrono, para las pocas vistas que muestran UNA portada
    /// grande y ya tienen los bytes a mano (la cabecera de un álbum
    /// abierto, el avatar de un artista en una fila). Nunca para una
    /// cuadrícula: ahí decodificar en el `body` es el problema que ST-183
    /// vino a resolver.
    @discardableResult
    func thumbnail(id: String, side: CGFloat, data: Data?) -> NSImage? {
        let key = Self.key(id: id, side: side)
        if let cached = cache.object(forKey: key) { return cached }
        guard let data, !data.isEmpty,
              let image = Self.decodeThumbnail(data, side: side, scale: scale) else { return nil }
        cache.setObject(image, forKey: key, cost: Self.cost(of: image, scale: scale))
        return image
    }

    /// Compatibilidad: la forma vieja, sin id. Sigue existiendo para las
    /// pruebas y para quien tenga los bytes y ninguna identidad estable
    /// a mano; la clave sale de la **huella O(1)**, no de `hashValue`,
    /// así que ya no hashea 15 KB por consulta.
    func thumbnail(for data: Data?, side: CGFloat) -> NSImage? {
        guard let data, !data.isEmpty else { return nil }
        return thumbnail(id: Self.fingerprint(data), side: side, data: data)
    }

    // MARK: - Invalidación

    func remove(id: String) {
        // `NSCache` no enumera sus claves, así que se borra por lado
        // conocido. Son los tamaños que piden las vistas.
        for side in Self.knownSides {
            cache.removeObject(forKey: Self.key(id: id, side: side))
        }
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    /// Los lados que piden las vistas de la app. Solo los usa
    /// `remove(id:)`; una miniatura de un lado no listado se queda en
    /// memoria hasta que `NSCache` la suelte, que no es un problema de
    /// corrección (la clave lleva la huella del contenido) sino de un
    /// poco de RAM.
    private static let knownSides: [CGFloat] = [40, 60, 128, 140, 160, 180, 210, 270, 320]

    // MARK: - Claves

    private static func key(id: String, side: CGFloat) -> NSString {
        "\(id)@\(Int(side))" as NSString
    }

    /// Huella **O(1)** de un blob: su tamaño más cuatro bytes tomados
    /// siempre de las mismas posiciones relativas.
    ///
    /// No es criptográfica y no pretende serlo. Lo único que tiene que
    /// hacer es cambiar cuando el usuario le cambia la carátula a un
    /// álbum, para que la miniatura vieja no sobreviva a la nueva. Dos
    /// JPEG distintos con exactamente el mismo tamaño en bytes Y los
    /// mismos cuatro bytes en esas posiciones colisionarían; el caso no
    /// se da con imágenes reales, y el precio de descartarlo del todo
    /// sería volver a recorrer los 15 KB en cada consulta, que es
    /// justamente el defecto que se está arreglando.
    ///
    /// (F5 traerá `coverHash` — el SHA-256 del archivo, ya calculado y
    /// persistido — y entonces esta huella sobra: la clave será el hash.)
    static func fingerprint(_ data: Data?) -> String {
        guard let data, !data.isEmpty else { return "vacio" }
        let count = data.count
        let offsets = [0, count / 3, 2 * count / 3, count - 1]
        var digest: UInt32 = 0
        for offset in offsets {
            digest = (digest << 8) | UInt32(data[data.startIndex + offset])
        }
        return "\(count)-\(digest)"
    }

    // MARK: - Decodificación

    private static func cost(of image: NSImage, scale: CGFloat) -> Int {
        let pixels = image.size.width * scale * image.size.height * scale
        return Int(pixels * 4)
    }

    private static func decodeThumbnail(_ data: Data, side: CGFloat, scale: CGFloat) -> NSImage? {
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
