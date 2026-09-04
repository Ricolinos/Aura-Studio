import Foundation
import CoreGraphics

/// La política de "toda carátula de la biblioteca es cuadrada" (ST-141,
/// contrato v18 §A.1). Un solo lugar decide el lado y la calidad, y un
/// solo lugar decide si una imagen ya cumple -- las dos apps calcan
/// estos números (`AuraStudio.Core/Library/CoverArtNormalization.cs`).
///
/// **Por qué desde el origen y no al sincronizar**: lo que viaja al iPod
/// se deriva de la copia local (`.portadas/`), así que una copia local
/// 4:3 obliga a recortar en cada sync y deja la vista previa de la app
/// mostrando una imagen distinta a la del aparato. Guardándola cuadrada
/// una sola vez, la app, el iPod y la carátula embebida muestran
/// exactamente lo mismo.
///
/// **Lo que se pierde, dicho de frente**: la franja recortada no se
/// puede recuperar. Es lo pedido (cuadrado siempre) y por eso la
/// migración de bibliotecas existentes nunca toca el archivo original
/// del usuario -- solo la copia de `.portadas/`.
enum CoverArtNormalizer {
    /// Tope del lado en la biblioteca local. 1000 px es lo que entrega
    /// fanart.tv y sobra para cualquier pantalla del Mac; el iPod recibe
    /// 320 (ST-142), derivado de esta copia.
    static let maxSide = 1000

    /// Más alta que la del iPod (0.85): esta es la copia MAESTRA de la
    /// que se derivan las demás, y recomprimir sobre una fuente ya
    /// degradada acumula pérdida.
    static let quality: CGFloat = 0.92

    /// Versión del formato de la biblioteca local, escrita en
    /// `biblioteca.json` como `coversNormalized` al terminar la
    /// migración. `1` sería "sin normalizar" (nunca se escribe): la
    /// ausencia de la clave ya significa eso. `2` = carátulas cuadradas.
    static let normalizedVersion = 2

    /// `true` si la imagen NO cumple todavía: no es cuadrada, o excede
    /// el tope. Aritmética pura para poder probarla sin ImageIO.
    static func needsNormalizing(width: Int, height: Int) -> Bool {
        guard width > 0, height > 0 else { return false }
        return width != height || width > maxSide
    }

    /// La versión cuadrada de estos bytes.
    ///
    /// Devuelve el **mismo `data`** cuando ya cumple (no se recomprime
    /// de gratis: cada pasada por el codificador JPEG pierde algo) y
    /// también cuando la imagen no se puede leer o el recorte falla --
    /// perder una carátula por no poder normalizarla sería un mal
    /// negocio; el sync la recortará igual antes de escribirla al iPod.
    static func normalized(_ data: Data) -> Data {
        guard !data.isEmpty,
              let size = ImageResizer.orientedPixelSize(of: data),
              needsNormalizing(width: size.width, height: size.height),
              let square = try? ImageResizer.squareCrop(data: data, side: maxSide, quality: quality) else {
            return data
        }
        return square
    }

    /// Igual, para un archivo ya escrito. `true` si lo reescribió.
    /// Escribe de forma atómica: una interrupción a media pasada deja el
    /// archivo anterior intacto, nunca uno truncado.
    @discardableResult
    static func normalizeFile(at url: URL) -> Bool {
        guard let size = ImageResizer.orientedPixelSize(ofFileAt: url),
              needsNormalizing(width: size.width, height: size.height),
              let square = try? ImageResizer.squareCrop(sourceURL: url, side: maxSide, quality: quality),
              (try? square.write(to: url, options: .atomic)) != nil else {
            return false
        }
        return true
    }
}
