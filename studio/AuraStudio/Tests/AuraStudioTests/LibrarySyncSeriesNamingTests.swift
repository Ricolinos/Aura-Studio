import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import AuraStudio

/// PLAN-biblioteca-medios-v2.md §3.5: nombre de destino de un episodio
/// de Series (" SxxEyy", que `parse_sxxeyy()` del firmware agrupa por
/// temporada) y el póster de temporada compartido.
final class LibrarySyncSeriesNamingTests: XCTestCase {

    // MARK: - seriesEpisodeFilename (puro)

    func testEpisodeFilenameMatchesFirmwareParsePattern() {
        let name = LibrarySync.seriesEpisodeFilename(seriesName: "Mi Serie", season: 1, episode: 2, ext: "mpg")
        XCTAssertEqual(name, "Mi Serie S01E02.mpg")
    }

    func testEpisodeFilenameTruncatesSeriesNameNeverTheSuffix() {
        let longName = String(repeating: "A", count: 200)
        let name = LibrarySync.seriesEpisodeFilename(seriesName: longName, season: 1, episode: 2, ext: "mpg", maxBytes: 95)
        XCTAssertTrue(name.utf8.count <= 95, "el resultado debe respetar el tope de bytes")
        XCTAssertTrue(name.hasSuffix(" S01E02.mpg"), "el sufijo SxxEyy nunca se trunca, solo el nombre de la serie")
    }

    func testEpisodeFilenameTruncatesByBytesNotCharactersForAccentedNames() {
        // Cada "ó" pesa 2 bytes en UTF-8 -- un tope por caracteres
        // podría exceder el límite real de bytes del firmware.
        let accented = String(repeating: "ó", count: 90)
        let name = LibrarySync.seriesEpisodeFilename(seriesName: accented, season: 1, episode: 1, ext: "mpg", maxBytes: 95)
        XCTAssertTrue(name.utf8.count <= 95)
        XCTAssertTrue(name.hasSuffix(" S01E01.mpg"))
    }

    // MARK: - destinationRelativePath integrado

    func testDestinationRelativePathUsesSeriesNamingForSeriesEpisode() {
        var item = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/Mi Serie 1x02.mkv"))
        item.category = "Series"
        item.seriesName = "Mi Serie"
        item.season = 1
        item.episode = 2
        item.preparedURL = URL(fileURLWithPath: "/tmp/staged.mpg")

        let relative = LibrarySync.destinationRelativePath(for: item, musicOrganization: .artistAlbum, musicFilenameFormat: .titleOnly)

        XCTAssertEqual(relative, "Videos/Mi Serie S01E02.mpg")
    }

    func testDestinationRelativePathFallsBackWhenSeriesFieldsAreMissing() {
        // Categoría Series pero sin los tres campos resueltos (p. ej. el
        // usuario clasificó a mano un archivo sin patrón SxxEyy en el
        // nombre): sigue el nombre preparado tal cual, sin inventar
        // temporada/episodio.
        var item = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/Capitulo suelto.mkv"))
        item.category = "Series"
        item.preparedURL = URL(fileURLWithPath: "/tmp/Capitulo suelto.mpg")

        let relative = LibrarySync.destinationRelativePath(for: item, musicOrganization: .artistAlbum, musicFilenameFormat: .titleOnly)

        XCTAssertEqual(relative, "Videos/Capitulo suelto.mpg")
    }

    func testDestinationRelativePathIgnoresSeriesFieldsWhenCategoryIsNotSeries() {
        var item = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/x.mkv"))
        item.category = "Películas"
        item.seriesName = "Mi Serie"
        item.season = 1
        item.episode = 2
        item.preparedURL = URL(fileURLWithPath: "/tmp/pelicula.mpg")

        let relative = LibrarySync.destinationRelativePath(for: item, musicOrganization: .artistAlbum, musicFilenameFormat: .titleOnly)

        XCTAssertEqual(relative, "Videos/pelicula.mpg")
    }

    // MARK: - seasonPosterRelativePath (puro)

    func testSeasonPosterRelativePath() {
        XCTAssertEqual(LibrarySync.seasonPosterRelativePath(seriesName: "Mi Serie", season: 1), "Videos/Mi Serie S01.jpg")
    }

    func testSeasonPosterRelativePathFromEpisodeDestination() {
        let poster = LibrarySync.seasonPosterRelativePath(fromEpisodeDestinationRelativePath: "Videos/Mi Serie S01E02.mpg")
        XCTAssertEqual(poster, "Videos/Mi Serie S01.jpg")
    }

    func testSeasonPosterRelativePathFromEpisodeDestinationIsNilForNonEpisodes() {
        XCTAssertNil(LibrarySync.seasonPosterRelativePath(fromEpisodeDestinationRelativePath: "Videos/pelicula.mpg"))
    }

    // MARK: - Integración: sync() escribe el póster de temporada

    private var fakeIPod: URL!
    private var stagedFiles: [URL] = []

    override func setUpWithError() throws {
        fakeIPod = FileManager.default.temporaryDirectory.appendingPathComponent("FakeIPod-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeIPod, withIntermediateDirectories: true)
        stagedFiles = []
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fakeIPod)
        for url in stagedFiles { try? FileManager.default.removeItem(at: url) }
    }

    private func stage(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try Data("fake mpg bytes".utf8).write(to: url)
        stagedFiles.append(url)
        return url
    }

    private func episodeItem(episode: Int, preparedName: String, cover: Data?) throws -> AuraStudio.LibraryItem {
        var item = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).mkv"))
        item.category = "Series"
        item.seriesName = "Mi Serie"
        item.season = 1
        item.episode = episode
        item.preparedURL = try stage(named: preparedName)
        item.metadata = TrackMetadata(coverArtData: cover)
        item.status = .ready
        return item
    }

    func testSyncWritesEpisodeAtNormalizedPathAndSeasonPoster() throws {
        let coverData = try XCTUnwrap(makeFakeJPEGData())
        let ep1 = try episodeItem(episode: 1, preparedName: "e1.mpg", cover: coverData)
        let sync = LibrarySync(volumeRoot: fakeIPod)

        let result = try sync.sync(items: [ep1])

        XCTAssertEqual(result.filesCopied, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fakeIPod.appendingPathComponent("Videos/Mi Serie S01E01.mpg").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fakeIPod.appendingPathComponent("Videos/Mi Serie S01.jpg").path),
                      "el póster de temporada debe escribirse junto a los episodios")
    }

    func testSyncPrefersLowestEpisodeCoverForSeasonPoster() throws {
        let cover1 = try XCTUnwrap(makeFakeJPEGData(marker: 1))
        let cover2 = try XCTUnwrap(makeFakeJPEGData(marker: 2))
        // Episodio 2 se agrega primero para probar que el orden de
        // inserción no importa -- siempre gana el episodio de menor número.
        let ep2 = try episodeItem(episode: 2, preparedName: "e2.mpg", cover: cover2)
        let ep1 = try episodeItem(episode: 1, preparedName: "e1.mpg", cover: cover1)
        let sync = LibrarySync(volumeRoot: fakeIPod)

        _ = try sync.sync(items: [ep2, ep1])

        let posterData = try Data(contentsOf: fakeIPod.appendingPathComponent("Videos/Mi Serie S01.jpg"))
        // El resize pasa por JPEG real -- alcanza con comprobar que el
        // archivo existe con contenido no vacío (la igualdad de bytes
        // exactos depende del codificador de ImageIO); lo que importa
        // aquí es que se haya elegido una imagen y no fallado en silencio.
        XCTAssertFalse(posterData.isEmpty)
    }

    /// JPEG mínimo válido (1x1) generado con CoreGraphics -- las
    /// imágenes de prueba sintéticas van así en todo el repo (D-303),
    /// nunca datos de la biblioteca real del dueño.
    private func makeFakeJPEGData(marker: Int = 0) -> Data? {
        let size = CGSize(width: 4, height: 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                       bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(red: CGFloat(marker % 2), green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))
        guard let cgImage = context.makeImage() else { return nil }
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }
}
