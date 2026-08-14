import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import AuraStudio

/// Encargo del dueno, 2026-08-14: colage/placeholder generado cuando una playlist no tiene
/// imagen propia -- se prueba contra un archivo real en disco (no hay
/// forma pura de verificar pixeles sin ImageIO de por medio), pero sin
/// tocar LibrarySync ni un iPod simulado.
final class PlaylistArtGeneratorTests: XCTestCase {
    private var destination: URL!

    override func setUpWithError() throws {
        destination = FileManager.default.temporaryDirectory.appendingPathComponent("playlist-art-\(UUID().uuidString).jpg")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: destination)
    }

    func testEmptyCandidatesProduceAValidPlaceholderJPEG() throws {
        try PlaylistArtGenerator.generateDefault(coverArtCandidates: [], destinationURL: destination)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        let image = NSImage(contentsOf: destination)
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.representations.first?.pixelsWide, Int(PlaylistArtGenerator.dimension))
    }

    func testCoverArtCandidatesProduceAValidCollageJPEG() throws {
        // Un JPEG minimo real (1x1) alcanza -- solo importa que
        // CGImageSource lo pueda decodificar para armar el colage.
        let onePixelJPEG = try XCTUnwrap(makeSolidColorJPEG())

        try PlaylistArtGenerator.generateDefault(coverArtCandidates: [onePixelJPEG, onePixelJPEG], destinationURL: destination)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertNotNil(NSImage(contentsOf: destination))
    }

    func testCorruptCandidatesAreSkippedNotThrown() throws {
        let garbage = Data("no soy un jpeg".utf8)

        XCTAssertNoThrow(try PlaylistArtGenerator.generateDefault(coverArtCandidates: [garbage], destinationURL: destination))
        XCTAssertNotNil(NSImage(contentsOf: destination), "sin candidatos decodificables, debe caer al placeholder")
    }

    private func makeSolidColorJPEG() -> Data? {
        let size = 8
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                       space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 0.4, green: 0.2, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        guard let image = context.makeImage() else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
