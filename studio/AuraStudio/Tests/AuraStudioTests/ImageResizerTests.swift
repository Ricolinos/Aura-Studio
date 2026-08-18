import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import AuraStudio

// PLAN-sync-media-hardening.md PARTE 2A: el visor de fotos del firmware
// (aura_photos.c:171-259, D-291) SOLO decodifica JPEG baseline (SOF0/
// SOF1) -- un progresivo (SOF2) sale como "Formato no soportado". Y
// como JPEG no tiene canal alfa, una fuente PNG/GIF con transparencia
// quedaba a criterio del codificador (con frecuencia negro debajo de
// los pixeles transparentes, en vez del blanco esperado).
final class ImageResizerTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func writeSolidPNG(to url: URL, size: Int, red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                       bytesPerRow: 0, space: colorSpace,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return XCTFail("no se pudo crear el contexto de prueba")
        }
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: alpha))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        guard let image = context.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return XCTFail("no se pudo escribir el PNG de prueba")
        }
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }

    /// Recorre los marcadores JPEG desde el SOI y devuelve el byte del
    /// marcador SOF encontrado (0xC0 = baseline, 0xC1 = baseline
    /// extendido, 0xC2 = progresivo -- el que el visor rechaza).
    private func sofMarker(of data: [UInt8]) -> UInt8? {
        var i = 2 // saltar SOI (FF D8)
        while i + 3 < data.count {
            guard data[i] == 0xFF else { i += 1; continue }
            let marker = data[i + 1]
            if marker == 0x00 || marker == 0xFF { i += 1; continue }
            if (0xD0...0xD9).contains(marker) || marker == 0x01 { i += 2; continue }
            let isSOF = (0xC0...0xCF).contains(marker) && marker != 0xC4 && marker != 0xC8 && marker != 0xCC
            if isSOF { return marker }
            let len = Int(data[i + 2]) << 8 | Int(data[i + 3])
            guard len >= 2 else { break }
            i += 2 + len
        }
        return nil
    }

    func testOutputIsBaselineJPEG() throws {
        let source = tempDir.appendingPathComponent("source.png")
        try writeSolidPNG(to: source, size: 64, red: 1, green: 0, blue: 0, alpha: 1)
        let destination = tempDir.appendingPathComponent("out.jpg")

        try ImageResizer.resizeToLCDOptimal(sourceURL: source, destinationURL: destination, maxDimension: 64)

        let data = [UInt8](try Data(contentsOf: destination))
        XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8], "debe empezar con el marcador SOI de JPEG")
        let sof = sofMarker(of: data)
        XCTAssertNotNil(sof)
        XCTAssertTrue(sof == 0xC0 || sof == 0xC1, "SOF0/SOF1 = baseline -- nunca 0xC2 (SOF2, progresivo), encontrado: \(String(describing: sof.map { String(format: "0x%02X", $0) }))")
    }

    func testTransparentPixelsAreFlattenedToWhiteNotBlack() throws {
        let source = tempDir.appendingPathComponent("transparent.png")
        // Completamente transparente: sin el aplanado, el RGB debajo
        // queda indefinido/negro segun el codificador.
        try writeSolidPNG(to: source, size: 8, red: 0, green: 0, blue: 0, alpha: 0)
        let destination = tempDir.appendingPathComponent("out.jpg")

        try ImageResizer.resizeToLCDOptimal(sourceURL: source, destinationURL: destination, maxDimension: 8)

        guard let cgSource = CGImageSourceCreateWithURL(destination as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(cgSource, 0, nil),
              let cropped = image.cropping(to: CGRect(x: image.width / 2, y: image.height / 2, width: 1, height: 1)) else {
            return XCTFail("no se pudo leer el JPEG de salida")
        }

        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8,
                                       bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return XCTFail("no se pudo armar el contexto de lectura de pixel")
        }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        XCTAssertGreaterThan(pixel[0], 200, "R debe quedar cercano a blanco (aplanado), no negro")
        XCTAssertGreaterThan(pixel[1], 200, "G debe quedar cercano a blanco (aplanado), no negro")
        XCTAssertGreaterThan(pixel[2], 200, "B debe quedar cercano a blanco (aplanado), no negro")
    }

    func testOpaqueSourceIsUnaffectedByFlattening() throws {
        let source = tempDir.appendingPathComponent("opaque.png")
        try writeSolidPNG(to: source, size: 8, red: 0, green: 0, blue: 1, alpha: 1) // azul solido
        let destination = tempDir.appendingPathComponent("out.jpg")

        try ImageResizer.resizeToLCDOptimal(sourceURL: source, destinationURL: destination, maxDimension: 8, quality: 1.0)

        guard let cgSource = CGImageSourceCreateWithURL(destination as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(cgSource, 0, nil),
              let cropped = image.cropping(to: CGRect(x: image.width / 2, y: image.height / 2, width: 1, height: 1)) else {
            return XCTFail("no se pudo leer el JPEG de salida")
        }
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8,
                                       bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return XCTFail("no se pudo armar el contexto de lectura de pixel")
        }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        XCTAssertLessThan(pixel[0], 60, "el rojo de una fuente azul solida sigue bajo tras aplanar")
        XCTAssertGreaterThan(pixel[2], 180, "el azul de una fuente azul solida se conserva tras aplanar")
    }
}
