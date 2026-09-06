import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import AuraStudio

/// ST-141: toda carátula que entra a la biblioteca queda cuadrada, y la
/// pasada única deja así a las que ya estaban. Las mismas reglas que
/// `AuraStudio.Core.Tests/CoverArtNormalizationTests.cs` en el port.
final class CoverArtNormalizerTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Un JPEG liso del tamaño pedido (JPEG, no PNG: es lo que de verdad
    /// vive en `.portadas/`).
    private func jpeg(width: Int, height: Int) throws -> Data {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = 40; pixels[i + 1] = 160; pixels[i + 2] = 90; pixels[i + 3] = 255
        }
        guard let context = pixels.withUnsafeMutableBytes({ buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }), let image = context.makeImage() else {
            throw XCTSkip("no se pudo generar la imagen de prueba")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw XCTSkip("no se pudo codificar el JPEG de prueba")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func size(of data: Data) throws -> (width: Int, height: Int) {
        guard let size = ImageResizer.orientedPixelSize(of: data) else {
            throw XCTSkip("no se pudo leer el tamaño de la imagen")
        }
        return size
    }

    // MARK: - La política

    func testTheRuleIsSquareAndNoBiggerThanAThousand() {
        XCTAssertFalse(CoverArtNormalizer.needsNormalizing(width: 1000, height: 1000))
        XCTAssertFalse(CoverArtNormalizer.needsNormalizing(width: 500, height: 500))
        XCTAssertTrue(CoverArtNormalizer.needsNormalizing(width: 1600, height: 1200))   // 4:3
        XCTAssertTrue(CoverArtNormalizer.needsNormalizing(width: 1001, height: 1001))   // cuadrada pero enorme
        XCTAssertTrue(CoverArtNormalizer.needsNormalizing(width: 300, height: 301))     // por un píxel
    }

    func testADegenerateSizeIsNotWorthNormalizing() {
        // No hay nada que recortar y el codificador fallaría: se deja pasar.
        XCTAssertFalse(CoverArtNormalizer.needsNormalizing(width: 0, height: 500))
        XCTAssertFalse(CoverArtNormalizer.needsNormalizing(width: -1, height: -1))
    }

    // MARK: - Los bytes

    func testAFourThreeCoverComesBackSquare() throws {
        let normalized = CoverArtNormalizer.normalized(try jpeg(width: 1600, height: 1200))
        let size = try size(of: normalized)
        XCTAssertEqual(size.width, 1000)   // min(lado corto 1200, tope 1000)
        XCTAssertEqual(size.height, 1000)
    }

    func testASmallCoverIsNeverBlownUp() throws {
        let normalized = CoverArtNormalizer.normalized(try jpeg(width: 400, height: 300))
        let size = try size(of: normalized)
        XCTAssertEqual(size.width, 300)
        XCTAssertEqual(size.height, 300)
    }

    func testAnAlreadySquareCoverIsReturnedUntouched() throws {
        // Byte por byte: recomprimir de gratis solo perdería calidad.
        let original = try jpeg(width: 800, height: 800)
        XCTAssertEqual(CoverArtNormalizer.normalized(original), original)
    }

    func testASquareCoverBiggerThanTheCapIsShrunk() throws {
        let normalized = CoverArtNormalizer.normalized(try jpeg(width: 1400, height: 1400))
        let size = try size(of: normalized)
        XCTAssertEqual(size.width, 1000)
        XCTAssertEqual(size.height, 1000)
    }

    func testSomethingUnreadableIsReturnedAsIsInsteadOfLost() {
        // Perder la carátula por no poder normalizarla sería peor que
        // dejarla como está: el sync la recorta igual antes del iPod.
        let garbage = Data([1, 2, 3, 4])
        XCTAssertEqual(CoverArtNormalizer.normalized(garbage), garbage)
        XCTAssertEqual(CoverArtNormalizer.normalized(Data()), Data())
    }

    // MARK: - Archivos

    func testNormalizingAFileRewritesOnlyWhatItHasTo() throws {
        let rectangular = tempDir.appendingPathComponent("4-3.jpg")
        let square = tempDir.appendingPathComponent("cuadrada.jpg")
        try jpeg(width: 1200, height: 900).write(to: rectangular)
        let squareBytes = try jpeg(width: 600, height: 600)
        try squareBytes.write(to: square)

        XCTAssertTrue(CoverArtNormalizer.normalizeFile(at: rectangular))
        XCTAssertFalse(CoverArtNormalizer.normalizeFile(at: square))

        let normalized = try size(of: try Data(contentsOf: rectangular))
        XCTAssertEqual(normalized.width, 900)
        XCTAssertEqual(normalized.height, 900)
        // La que ya cumplía quedó intacta, no reescrita.
        XCTAssertEqual(try Data(contentsOf: square), squareBytes)
    }

    func testAFileThatIsNotAnImageIsLeftAlone() throws {
        let bogus = tempDir.appendingPathComponent("roto.jpg")
        try Data([0, 1, 2, 3]).write(to: bogus)
        XCTAssertFalse(CoverArtNormalizer.normalizeFile(at: bogus))
        XCTAssertEqual(try Data(contentsOf: bogus), Data([0, 1, 2, 3]))
    }

    // MARK: - La pasada única

    func testTheMigrationSkipsWhatIsAlreadySquare() throws {
        var files: [URL] = []
        for index in 0..<3 {
            let url = tempDir.appendingPathComponent("rect-\(index).jpg")
            try jpeg(width: 800, height: 600).write(to: url)
            files.append(url)
        }
        let alreadyFine = tempDir.appendingPathComponent("ok.jpg")
        try jpeg(width: 500, height: 500).write(to: alreadyFine)
        files.append(alreadyFine)

        let lastReported = ProgressBox()
        let result = CoverNormalizationMigration.run(files: files,
                                                     onProgress: { done, total in lastReported.set(done, total) })

        XCTAssertEqual(result.normalized, 3)
        XCTAssertEqual(result.visited, 4)
        XCTAssertFalse(result.cancelled)
        XCTAssertEqual(lastReported.completed, 4)
        XCTAssertEqual(lastReported.total, 4)
    }

    func testTheMigrationStopsWhenCancelledAndPicksUpWhereItLeftOff() throws {
        var files: [URL] = []
        for index in 0..<4 {
            let url = tempDir.appendingPathComponent("rect-\(index).jpg")
            try jpeg(width: 800, height: 600).write(to: url)
            files.append(url)
        }

        // Se cancela después del segundo archivo.
        let done = ProgressBox()
        let first = CoverNormalizationMigration.run(files: files,
                                                    isCancelled: { done.completed >= 2 },
                                                    onProgress: { completed, _ in done.set(completed, 0) })
        XCTAssertTrue(first.cancelled)
        XCTAssertEqual(first.normalized, 2)

        // Retomar: los dos ya hechos se saltan sin reescribirse, los dos
        // que faltaban se normalizan. Sin archivo de progreso: saltarse
        // lo que ya está cuadrado ES el mecanismo de retomar.
        let second = CoverNormalizationMigration.run(files: files)
        XCTAssertFalse(second.cancelled)
        XCTAssertEqual(second.normalized, 2)
        XCTAssertEqual(second.visited, 4)

        for url in files {
            let size = try size(of: try Data(contentsOf: url))
            XCTAssertEqual(size.width, 600)
            XCTAssertEqual(size.height, 600)
        }

        // Y una tercera pasada ya no reescribe nada.
        XCTAssertEqual(CoverNormalizationMigration.run(files: files).normalized, 0)
    }

    func testTheMarkTravelsInTheCatalog() throws {
        var library = PersistedLibrary()
        library.coversNormalized = CoverArtNormalizer.normalizedVersion
        let data = try JSONEncoder().encode(library)
        let decoded = try JSONDecoder().decode(PersistedLibrary.self, from: data)
        XCTAssertEqual(decoded.coversNormalized, 2)

        // Un catálogo anterior a ST-141 no la trae, y eso NO puede
        // tirar la decodificación entera: significa "hay que migrar".
        let legacy = #"{"items":[],"playlists":[]}"#.data(using: .utf8)!
        XCTAssertNil(try JSONDecoder().decode(PersistedLibrary.self, from: legacy).coversNormalized)
    }
}

/// ST-192: `CoverNormalizationMigration.run` recibe sus closures como
/// `@Sendable`, y el modo Swift 6 —el que usa el proyecto de Xcode—
/// rechaza capturar un `var` local en uno de ellos. Con `swift test`
/// (modo permisivo) era solo una advertencia, así que pasó inadvertido:
/// el efecto era que **el target de pruebas unitarias no compilaba con
/// `xcodebuild`**, y por lo tanto `xcodebuild test` no servía para las
/// unitarias.
///
/// Una caja con candado dice lo mismo que el `var` y además es honesta:
/// quien la escribe es el hilo que corre la migración, no el de la
/// prueba.
private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = (completed: 0, total: 0)

    func set(_ completed: Int, _ total: Int) {
        lock.lock()
        value = (completed, total)
        lock.unlock()
    }

    var completed: Int {
        lock.lock()
        defer { lock.unlock() }
        return value.completed
    }

    var total: Int {
        lock.lock()
        defer { lock.unlock() }
        return value.total
    }
}
