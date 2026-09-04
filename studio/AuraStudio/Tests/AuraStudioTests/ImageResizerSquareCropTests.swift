import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import AuraStudio

/// ST-140 / contrato v18: la carátula que va al iPod es cuadrada, recortada
/// al centro (fill + center-crop). Estas pruebas no comprueban solo el
/// tamaño: pintan bandas de colores en los márgenes que el recorte DEBE
/// tirar y verifican en las esquinas del resultado que esas bandas ya no
/// están -- un recorte descentrado, o un "ajuste" con bandas en vez de un
/// relleno, se ve inmediatamente acá.
final class ImageResizerSquareCropTests: XCTestCase {
    // MARK: - Imágenes sintéticas

    /// PNG con tres franjas verticales: rojo `[0, left)`, verde
    /// `[left, right)`, azul `[right, width)`. El recorte centrado tiene
    /// que quedarse exactamente con la franja verde.
    private func verticalBandsPNG(width: Int, height: Int, left: Int, right: Int) throws -> Data {
        try png(width: width, height: height) { x, _ in
            if x < left { return (255, 0, 0) }
            if x < right { return (0, 190, 0) }
            return (0, 0, 255)
        }
    }

    /// Lo mismo en horizontal, para una fuente más alta que ancha.
    private func horizontalBandsPNG(width: Int, height: Int, top: Int, bottom: Int) throws -> Data {
        try png(width: width, height: height) { _, y in
            if y < top { return (255, 0, 0) }
            if y < bottom { return (0, 190, 0) }
            return (0, 0, 255)
        }
    }

    private func png(width: Int, height: Int,
                     color: (Int, Int) -> (UInt8, UInt8, UInt8)) throws -> Data {
        // Se escribe el búfer de píxeles directo (un `fill` por píxel sobre
        // una fuente de 1600x1200 tardaría más que toda la suite).
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let (red, green, blue) = color(x, y)
                let i = (y * width + x) * 4
                pixels[i] = red; pixels[i + 1] = green; pixels[i + 2] = blue; pixels[i + 3] = 255
            }
        }
        guard let context = pixels.withUnsafeMutableBytes({ buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }), let image = context.makeImage() else {
            throw XCTSkip("no se pudo generar la imagen de prueba")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw XCTSkip("no se pudo codificar el PNG de prueba")
        }
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    // MARK: - Lectura del resultado

    private struct Decoded {
        let width: Int
        let height: Int
        let pixels: [UInt8]   // RGBA, fila-contigua

        func at(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            let i = (y * width + x) * 4
            return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
        }
    }

    private func decode(_ data: Data) throws -> Decoded {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw XCTSkip("no se pudo leer el JPEG generado")
        }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = pixels.withUnsafeMutableBytes({ buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }) else {
            throw XCTSkip("no se pudo leer los píxeles del JPEG generado")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Decoded(width: width, height: height, pixels: pixels)
    }

    private func assertGreenish(_ pixel: (r: Int, g: Int, b: Int), _ message: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(pixel.g > 120 && pixel.r < 110 && pixel.b < 110,
                      "\(message): salió (r:\(pixel.r) g:\(pixel.g) b:\(pixel.b))", file: file, line: line)
    }

    /// El marcador SOF del JPEG (0xC0/0xC1 = baseline, 0xC2 = progresivo).
    private func sofMarker(of data: Data) -> UInt8? {
        let bytes = [UInt8](data)
        var i = 2
        while i + 3 < bytes.count {
            guard bytes[i] == 0xFF else { i += 1; continue }
            let marker = bytes[i + 1]
            if marker == 0x00 || marker == 0xFF { i += 1; continue }
            if (0xD0...0xD9).contains(marker) || marker == 0x01 { i += 2; continue }
            if (0xC0...0xCF).contains(marker) && marker != 0xC4 && marker != 0xC8 && marker != 0xCC {
                return marker
            }
            let length = Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            guard length >= 2 else { break }
            i += 2 + length
        }
        return nil
    }

    // MARK: - Pruebas

    func testAFourThreeCoverComesOutSquareWithoutItsSideBands() throws {
        // 1600x1200: el recorte se queda con las columnas 200..1399.
        let source = try verticalBandsPNG(width: 1600, height: 1200, left: 200, right: 1400)
        let jpeg = try ImageResizer.squareCrop(data: source, side: 320)
        let image = try decode(jpeg)

        XCTAssertEqual(image.width, 320)
        XCTAssertEqual(image.height, 320)

        // Las cuatro esquinas son verdes: ni una franja lateral sobrevivió.
        for (x, y) in [(6, 6), (313, 6), (6, 313), (313, 313), (160, 160)] {
            assertGreenish(image.at(x, y), "esquina (\(x),\(y))")
        }

        // Y en ninguna parte del resultado domina el rojo o el azul.
        for y in stride(from: 4, to: 316, by: 4) {
            for x in stride(from: 4, to: 316, by: 4) {
                let p = image.at(x, y)
                XCTAssertFalse(p.r > 140 && p.r > p.g, "quedó rojo en (\(x),\(y))")
                XCTAssertFalse(p.b > 140 && p.b > p.g, "quedó azul en (\(x),\(y))")
            }
        }
    }

    func testASixteenNineCoverLosesMuchMoreOfItsSides() throws {
        // 1920x1080: el recorte se queda con las columnas 420..1499.
        let source = try verticalBandsPNG(width: 1920, height: 1080, left: 420, right: 1500)
        let jpeg = try ImageResizer.squareCrop(data: source, side: 320)
        let image = try decode(jpeg)

        XCTAssertEqual(image.width, 320)
        XCTAssertEqual(image.height, 320)
        for (x, y) in [(6, 6), (313, 6), (6, 313), (313, 313)] {
            assertGreenish(image.at(x, y), "esquina (\(x),\(y))")
        }
    }

    func testATallSourceIsCroppedTopAndBottom() throws {
        // 300x1200 (1:4): sobrevive la franja de filas 450..749.
        let source = try horizontalBandsPNG(width: 300, height: 1200, top: 450, bottom: 750)
        let jpeg = try ImageResizer.squareCrop(data: source, side: 128)
        let image = try decode(jpeg)

        XCTAssertEqual(image.width, 128)
        XCTAssertEqual(image.height, 128)
        for (x, y) in [(4, 4), (123, 4), (4, 123), (123, 123)] {
            assertGreenish(image.at(x, y), "esquina (\(x),\(y))")
        }
    }

    func testAnAlreadySquareCoverIsOnlyResized() throws {
        let source = try verticalBandsPNG(width: 1000, height: 1000, left: 0, right: 1000)
        let image = try decode(try ImageResizer.squareCrop(data: source, side: 320))
        XCTAssertEqual(image.width, 320)
        XCTAssertEqual(image.height, 320)
        assertGreenish(image.at(160, 160), "centro")
    }

    func testASourceSmallerThanAskedIsNeverBlownUp() throws {
        // Lado corto 200 < 320: sale de 200, no de 320.
        let source = try verticalBandsPNG(width: 400, height: 200, left: 100, right: 300)
        let image = try decode(try ImageResizer.squareCrop(data: source, side: 320))
        XCTAssertEqual(image.width, 200)
        XCTAssertEqual(image.height, 200)
    }

    func testTheArtistSideOfTheContract() throws {
        // §D.3: las fotos de artista van a 128x128 cuadradas.
        let source = try verticalBandsPNG(width: 1200, height: 800, left: 200, right: 1000)
        let image = try decode(try ImageResizer.squareCrop(data: source, side: 128))
        XCTAssertEqual(image.width, 128)
        XCTAssertEqual(image.height, 128)
        assertGreenish(image.at(64, 64), "centro")
    }

    func testTheOutputIsBaselineJPEG() throws {
        // D-291: un progresivo aparece en el iPod como "Formato no soportado".
        let source = try verticalBandsPNG(width: 1600, height: 1200, left: 200, right: 1400)
        let marker = sofMarker(of: try ImageResizer.squareCrop(data: source, side: 320))
        XCTAssertNotNil(marker)
        XCTAssertTrue(marker == 0xC0 || marker == 0xC1, "SOF inesperado: \(String(describing: marker))")
    }

    func testTransparencyIsFlattenedOntoWhiteNotBlack() throws {
        // Un PNG totalmente transparente: el JPEG no tiene canal alfa, así
        // que lo que quede debajo tiene que ser BLANCO, no negro.
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.clear(CGRect(x: 0, y: 0, width: 600, height: 400))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let image = try decode(try ImageResizer.squareCrop(data: output as Data, side: 128))
        let pixel = image.at(64, 64)
        XCTAssertTrue(pixel.r > 240 && pixel.g > 240 && pixel.b > 240,
                      "transparente debería quedar blanco, salió (r:\(pixel.r) g:\(pixel.g) b:\(pixel.b))")
    }

    func testAPhotoWithExifOrientationIsCroppedOnWhatIsSeen() throws {
        // Una foto vertical de cámara viene guardada horizontal con la
        // rotación en EXIF: 400x200 con orientación 6 se VE 200x400, y el
        // recorte se planea sobre eso (lado corto 200).
        let flat = try verticalBandsPNG(width: 400, height: 200, left: 100, right: 300)
        let source = CGImageSourceCreateWithData(flat as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let rotated = NSMutableData()
        let destination = CGImageDestinationCreateWithData(rotated, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let result = try decode(try ImageResizer.squareCrop(data: rotated as Data, side: 320))
        XCTAssertEqual(result.width, 200)    // lado corto de lo que se ve, sin agrandar
        XCTAssertEqual(result.height, 200)
    }

    func testGarbageIsRejectedWithAClearError() throws {
        XCTAssertThrowsError(try ImageResizer.squareCrop(data: Data([1, 2, 3, 4]), side: 320)) { error in
            XCTAssertEqual(error as? ImageResizer.ResizeError, .cannotReadImage)
        }
    }

    func testWritingToDiskLeavesTheSquareJPEG() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("cover.jpg")
        let source = try verticalBandsPNG(width: 1600, height: 1200, left: 200, right: 1400)
        try ImageResizer.squareCrop(data: source, destinationURL: destination, side: 320)

        let image = try decode(try Data(contentsOf: destination))
        XCTAssertEqual(image.width, 320)
        XCTAssertEqual(image.height, 320)
    }
}
