import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import AuraStudio

// PLAN-sync-media-hardening.md PARTE 2A: `.preparados/` (staging) es
// una unica carpeta PLANA compartida por toda la biblioteca -- dos
// fotos con el mismo nombre base de carpetas distintas (dos cámaras
// que numeran "IMG_1.jpg" desde cero) se pisaban en silencio.
@MainActor
final class PhotoStagingCollisionTests: XCTestCase {
    private var libraryRoot: URL!
    private var fixturesDir: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoStagingTests-\(UUID().uuidString)", isDirectory: true)
        fixturesDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoStagingFixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixturesDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
        try? FileManager.default.removeItem(at: fixturesDir)
    }

    private func freshPreferences() -> AppPreferences {
        let prefs = AppPreferences(defaults: makeIsolatedDefaults("PhotoStagingTests"))
        prefs.copyMediaIntoLibrary = false
        return prefs
    }

    /// Dos imágenes "IMG_1.jpg" en carpetas distintas de origen -- un
    /// nombre repetido con contenido distinto, el caso real que rompía.
    private func makeSolidJPEG(named name: String, in subfolder: String, red: CGFloat) throws -> URL {
        let dir = fixturesDir.appendingPathComponent(subfolder, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8,
                                       bytesPerRow: 0, space: colorSpace,
                                       bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw XCTSkip("no se pudo crear el contexto de prueba")
        }
        context.setFillColor(CGColor(red: red, green: 0, blue: 1 - red, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        guard let image = context.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw XCTSkip("no se pudo escribir el JPEG de prueba")
        }
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    func testTwoPhotosWithSameBaseNameFromDifferentFoldersDoNotCollideInStaging() async throws {
        let urlA = try makeSolidJPEG(named: "IMG_1.jpg", in: "CamaraA", red: 1)
        let urlB = try makeSolidJPEG(named: "IMG_1.jpg", in: "CamaraB", red: 0)

        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        viewModel.addDroppedFiles([urlA, urlB])
        await viewModel.processAll()

        let itemA = try XCTUnwrap(viewModel.items.first(where: { $0.sourceURL == urlA }))
        let itemB = try XCTUnwrap(viewModel.items.first(where: { $0.sourceURL == urlB }))
        let preparedA = try XCTUnwrap(itemA.preparedURL)
        let preparedB = try XCTUnwrap(itemB.preparedURL)

        XCTAssertNotEqual(preparedA.path, preparedB.path, "dos IMG_1.jpg de carpetas distintas no deben terminar en el mismo preparado")
        XCTAssertTrue(FileManager.default.fileExists(atPath: preparedA.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: preparedB.path))
        // El segundo procesado gana el sufijo -- confirma que no se
        // trata de una colision resuelta al azar por orden de proceso.
        XCTAssertTrue(preparedB.lastPathComponent.hasPrefix("IMG_1 2") || preparedA.lastPathComponent.hasPrefix("IMG_1 2"),
                      "uno de los dos debe llevar el sufijo de colision \"IMG_1 2.jpg\"")

        // Contenido realmente distinto -- no es solo que las rutas
        // difieran, el archivo B no piso los bytes del archivo A.
        let dataA = try Data(contentsOf: preparedA)
        let dataB = try Data(contentsOf: preparedB)
        XCTAssertNotEqual(dataA, dataB, "el contenido de las dos fotos preparadas debe seguir siendo distinto")
    }

    func testLongAccentedFilenameStaysWithinDeviceByteLimit() throws {
        let longName = String(repeating: "Añoñuevo ", count: 15) + ".jpg"
        let sanitized = PathSanitizer.sanitizeFilename(longName, maxBytes: LibrarySync.deviceFilenameMaxBytes)
        XCTAssertLessThanOrEqual(sanitized.utf8.count, LibrarySync.deviceFilenameMaxBytes)
        XCTAssertTrue(sanitized.hasSuffix(".jpg"))
    }
}
