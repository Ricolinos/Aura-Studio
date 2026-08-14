import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Genera la imagen "default" de una playlist cuando el usuario no eligio
/// una propia (encargo del dueno, 2026-08-14: "quiero que las playlists
/// tengan una imagen... Aura Studio tambien necesita generar una imagen
/// default"). Aura Studio SIEMPRE deja un sidecar `.jpg` junto al `.m3u8`
/// al sincronizar -- el firmware tambien tiene su propio tile generico de
/// respaldo (`aura_albumart_load_default`) para el caso raro de una
/// playlist agregada a mano sin pasar por Studio, pero cuando Studio SI
/// sincroniza, mejor mostrar algo mas util que el tile generico repetido
/// en las 20 playlists del usuario.
///
/// Estrategia elegida: colage 2x2 de hasta 4 caratulas de album de las
/// pistas ya en la playlist (variedad visual real por playlist, no un
/// mismo tile para todas) -- si no hay ninguna caratula disponible
/// (playlist vacia, o con pistas sin arte conocido), un tile plano con un
/// glyph generico de "lista", en los mismos grises que la caratula
/// Default del firmware (docs/aura-design-system, D-231) para que ambos
/// casos no desentonen entre si si el usuario los ve uno al lado del
/// otro. Un colage con crop/aspect-fill simple (sin rotar, sin marcos) es
/// la version mas chica de "esto se ve mejor que un tile plano" -- no hay
/// necesidad de un algoritmo de layout mas elaborado para un cuadrado de
/// lista chico.
enum PlaylistArtGenerator {
    enum GenerationError: Error {
        case cannotCreateContext
        case cannotEncodeOutput
    }

    /// 128px: el mismo tope que `LibraryViewModel.setPlaylistImage` usa
    /// para una imagen elegida a mano -- una fila de lista chica (el
    /// firmware la dibuja a ALBUM_ART_SIZE=48px), no una portada hero.
    static let dimension: CGFloat = 128

    /// Fondo/tinta del tile placeholder -- literal de
    /// design-system/tokens.json (`color.light.selection_fill` /
    /// blend de `shell_rail`+`text_secondary`), mismos tokens que usa
    /// `aura_albumart_default_tile()` en el firmware. El sidecar es un
    /// JPEG estatico (no puede leer el tema activo del dispositivo en
    /// tiempo real como si hace el C), asi que se fija al tema claro,
    /// el mismo criterio que ya uso ese tile de referencia del dueno
    /// del diseno.
    private static let placeholderBackground = CGColor(red: 0xE5 / 255, green: 0xE5 / 255, blue: 0xEA / 255, alpha: 1)
    private static let placeholderInk = CGColor(red: 0x9A / 255, green: 0x9A / 255, blue: 0x9E / 255, alpha: 1)

    /// `coverArtCandidates` son los `TrackMetadata.coverArtData` (en el
    /// orden de la playlist) de las pistas que ya tengan una conocida --
    /// el llamador (LibrarySync) ya filtro los `nil`. Escribe siempre un
    /// JPEG valido en `destinationURL` (colage o placeholder), nunca deja
    /// el archivo a medio escribir.
    static func generateDefault(coverArtCandidates: [Data], destinationURL: URL) throws {
        let size = Int(dimension)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: size, height: size,
                                       bitsPerComponent: 8, bytesPerRow: 0,
                                       space: colorSpace,
                                       bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw GenerationError.cannotCreateContext
        }

        let covers = decodeCovers(from: coverArtCandidates, limit: 4)
        if covers.isEmpty {
            drawPlaceholder(in: context, size: size)
        } else {
            drawCollage(covers: covers, in: context, size: size)
        }

        guard let composed = context.makeImage() else {
            throw GenerationError.cannotEncodeOutput
        }
        try write(image: composed, to: destinationURL)
    }

    private static func decodeCovers(from candidates: [Data], limit: Int) -> [CGImage] {
        var result: [CGImage] = []
        for data in candidates {
            guard result.count < limit,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
            result.append(image)
        }
        return result
    }

    /// Cuadrantes en coordenadas de CGContext (origen abajo-izquierda).
    /// Con menos de 4 caratulas disponibles se recicla desde el
    /// principio -- llena el colage entero en vez de dejar cuadrantes en
    /// blanco, mejor variedad visual que un unico cuadrante ocupado.
    private static func drawCollage(covers: [CGImage], in context: CGContext, size: Int) {
        let half = CGFloat(size) / 2
        let quadrants = (0..<4).map { covers[$0 % covers.count] }
        let rects = [
            CGRect(x: 0, y: half, width: half, height: half),
            CGRect(x: half, y: half, width: half, height: half),
            CGRect(x: 0, y: 0, width: half, height: half),
            CGRect(x: half, y: 0, width: half, height: half),
        ]
        for (image, rect) in zip(quadrants, rects) {
            context.saveGState()
            context.clip(to: rect)
            context.draw(image, in: aspectFillRect(for: image, in: rect))
            context.restoreGState()
        }
    }

    /// Escala `image` para llenar `rect` sin deformarlo (recorta lo que
    /// sobre, centrado) -- mismo criterio "aspect fill" que
    /// `kCGImageSourceCreateThumbnailWithTransform` usa en `ImageResizer`
    /// para portadas normales, aca a mano porque el destino es un
    /// cuadrante, no la imagen completa.
    private static func aspectFillRect(for image: CGImage, in rect: CGRect) -> CGRect {
        let imageSize = CGSize(width: image.width, height: image.height)
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: rect.midX - scaledSize.width / 2, y: rect.midY - scaledSize.height / 2)
        return CGRect(origin: origin, size: scaledSize)
    }

    /// Sin ninguna caratula disponible: tres barras redondeadas
    /// (glyph generico de "lista/playlist") sobre un tile plano -- ver
    /// el comentario de `placeholderBackground`/`placeholderInk` arriba
    /// para de donde salen los grises.
    private static func drawPlaceholder(in context: CGContext, size: Int) {
        let sizeF = CGFloat(size)
        context.setFillColor(placeholderBackground)
        context.fill(CGRect(x: 0, y: 0, width: sizeF, height: sizeF))

        context.setFillColor(placeholderInk)
        let barHeight = sizeF * 0.09
        let gap = sizeF * 0.16
        let widths: [CGFloat] = [0.56, 0.44, 0.32].map { sizeF * $0 }
        let startX = sizeF * 0.22
        let centerY = sizeF / 2

        for (index, width) in widths.enumerated() {
            let y = centerY + (CGFloat(index - 1) * gap) - barHeight / 2
            let rect = CGRect(x: startX, y: y, width: width, height: barHeight)
            let path = CGPath(roundedRect: rect, cornerWidth: barHeight / 2, cornerHeight: barHeight / 2, transform: nil)
            context.addPath(path)
            context.fillPath()
        }
    }

    private static func write(image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw GenerationError.cannotEncodeOutput
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw GenerationError.cannotEncodeOutput
        }
    }
}
