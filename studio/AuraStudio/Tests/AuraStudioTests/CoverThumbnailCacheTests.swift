import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import AuraStudio

/// Bug real (encargo del dueño, 2026-08-19: "las imágenes se ven
/// distorsionadas"): el `NSImage.size` reportado por el thumbnail
/// forzaba un cuadrado exacto sin importar el aspecto real de la
/// imagen -- SwiftUI calcula `.aspectRatio(contentMode: .fill)` contra
/// ESE tamaño reportado, así que una foto 16:9 se estiraba para
/// "llenar" un cuadrado que su contenido real nunca tuvo.
final class CoverThumbnailCacheTests: XCTestCase {
    /// JPEG sintético NO cuadrado (D-303): nunca datos reales.
    private func makeFakeJPEGData(width: Int, height: Int) -> Data? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                       space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 0.4, green: 0.6, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { return nil }
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }

    func testThumbnailReportsTheSourceAspectRatioNotAForcedSquare() throws {
        // 16:9 real, bien lejos de 1:1 -- si el bug reaparece, esta
        // proporción es imposible de confundir con "redondeo".
        let data = try XCTUnwrap(makeFakeJPEGData(width: 1600, height: 900))
        let cache = CoverThumbnailCache()

        let thumbnail = try XCTUnwrap(cache.thumbnail(for: data, side: 200))

        let reportedAspect = thumbnail.size.width / thumbnail.size.height
        XCTAssertEqual(reportedAspect, 16.0 / 9.0, accuracy: 0.05,
                       "el tamaño reportado del NSImage debe reflejar el aspecto REAL del contenido, no un cuadrado forzado")
    }

    func testSquareSourceStillReportsASquareThumbnail() throws {
        let data = try XCTUnwrap(makeFakeJPEGData(width: 400, height: 400))
        let cache = CoverThumbnailCache()

        let thumbnail = try XCTUnwrap(cache.thumbnail(for: data, side: 200))

        XCTAssertEqual(thumbnail.size.width, thumbnail.size.height, accuracy: 0.5)
    }

    func testPortraitSourceReportsATallerThanWideThumbnail() throws {
        let data = try XCTUnwrap(makeFakeJPEGData(width: 900, height: 1600))
        let cache = CoverThumbnailCache()

        let thumbnail = try XCTUnwrap(cache.thumbnail(for: data, side: 200))

        XCTAssertLessThan(thumbnail.size.width, thumbnail.size.height)
    }

    func testNilOrEmptyDataReturnsNil() {
        let cache = CoverThumbnailCache()
        XCTAssertNil(cache.thumbnail(for: nil, side: 200))
        XCTAssertNil(cache.thumbnail(for: Data(), side: 200))
    }
}
