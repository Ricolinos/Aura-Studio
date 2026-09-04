import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import AuraStudio

/// Fase 24: LibrarySync.sync() contra una carpeta temporal en vez de un
/// iPod de verdad (mismo patron que LibraryPipelineIntegrationTests,
/// pero sin ffmpeg de por medio -- solo musica, asi que corre rapido y
/// sin fixtures externos).
final class LibrarySyncTests: XCTestCase {
    private var fakeIPod: URL!
    private var stagingFile: URL!

    override func setUpWithError() throws {
        fakeIPod = FileManager.default.temporaryDirectory.appendingPathComponent("FakeIPod-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeIPod, withIntermediateDirectories: true)
        stagingFile = FileManager.default.temporaryDirectory.appendingPathComponent("staged-\(UUID().uuidString).mp3")
        try Data("fake mp3 bytes".utf8).write(to: stagingFile)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fakeIPod)
        try? FileManager.default.removeItem(at: stagingFile)
    }

    /// Un JPEG liso de verdad (ST-142: el sync decodifica la carátula
    /// para recortarla, así que ya no sirve cualquier secuencia de bytes).
    private func solidJPEG(width: Int, height: Int) throws -> Data {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = 180; pixels[i + 1] = 70; pixels[i + 2] = 120; pixels[i + 3] = 255
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
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func musicItem() -> AuraStudio.LibraryItem {
        var item = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/source-\(UUID().uuidString).mp3"))
        item.metadata = TrackMetadata(title: "Bohemian Rhapsody", artist: "Queen", album: "A Night at the Opera", trackNumber: 11)
        item.preparedURL = stagingFile
        item.status = .ready
        return item
    }

    func testSyncWritesMusicAtHierarchicalPath() throws {
        let item = musicItem()
        let sync = LibrarySync(volumeRoot: fakeIPod)

        let result = try sync.sync(items: [item])

        XCTAssertEqual(result.filesCopied, 1)
        let expected = fakeIPod.appendingPathComponent("Music/Queen/A Night at the Opera/Bohemian Rhapsody.mp3")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expected.path))
    }

    /// Regresión (encontrado 2026-08-14 comparando simulador vs.
    /// hardware real): `writeAlbumCovers()` envolvía la ruta relativa
    /// del destino ("Music/Artista/Álbum/Canción.mp3") sola en
    /// `URL(fileURLWithPath:)` -- eso la resuelve contra el directorio
    /// de trabajo del PROCESO, no contra `volumeRoot`, así que la
    /// portada terminaba en una carpeta anidada sin sentido en vez de
    /// la carpeta real del álbum. Sin ninguna prueba que tocara esto
    /// antes, pasó desapercibido en cada sync, incluidos los reales.
    func testSyncWritesAlbumCoverInsideAlbumFolder() throws {
        var item = musicItem()
        // ST-142: la carátula ya no viaja cruda -- se recorta a 320x320
        // antes de escribirla, así que tiene que ser una imagen de
        // verdad (unos bytes cualesquiera ya no son una carátula).
        item.metadata?.coverArtData = try solidJPEG(width: 800, height: 600)
        let sync = LibrarySync(volumeRoot: fakeIPod)

        _ = try sync.sync(items: [item], coverArtPolicy: .albumOnly)

        let expectedCover = fakeIPod.appendingPathComponent("Music/Queen/A Night at the Opera/cover.jpg")
        XCTAssertEqual(ImageResizer.orientedPixelSize(ofFileAt: expectedCover)?.width, LibrarySync.deviceCoverSide,
                       "la portada debe quedar junto a la pista, dentro de la carpeta real del álbum")

        // La regresión real: la portada no puede quedar en NINGUNA otra
        // ruta -- el bug viejo la mandaba a una carpeta anidada armada
        // con el directorio de trabajo del proceso.
        //
        // Se comprueba enumerando el volumen entero en vez de construir
        // "la ruta mala" a partir del cwd: esa versión de la prueba
        // dependía de cuál era el cwd al correrla. Con `swift test` es
        // la carpeta del paquete y pasaba; con `xcodebuild` es `/`, y
        // entonces "la ruta mala" se reducía a `<volumeRoot>/Music`,
        // que el propio sync crea siempre -- la prueba fallaba pasara
        // lo que pasara. Enumerar no depende de nada de eso.
        let coversFound = FileManager.default
            .enumerator(at: fakeIPod, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.lastPathComponent == "cover.jpg" }
            .map { $0.standardizedFileURL.path } ?? []
        XCTAssertEqual(coversFound, [expectedCover.standardizedFileURL.path],
                       "la portada debe existir en la carpeta del álbum y en ninguna otra ruta del volumen")
    }

    func testMigrationDeletesStaleFlatFile() throws {
        let item = musicItem()
        let sync = LibrarySync(volumeRoot: fakeIPod)

        // Simula un dispositivo sincronizado antes de esta fase: el
        // manifiesto apunta a la ruta plana vieja y el archivo ya esta
        // ahi.
        let staleRelative = "Music/\(item.sourceURL.lastPathComponent)"
        let staleURL = fakeIPod.appendingPathComponent(staleRelative)
        try FileManager.default.createDirectory(at: staleURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old flat copy".utf8).write(to: staleURL)

        let attrs = try FileManager.default.attributesOfItem(atPath: stagingFile.path)
        let manifest = SyncManifest(records: [
            item.sourceURL.path: SyncRecord(
                sourcePath: item.sourceURL.path,
                sourceSize: (attrs[.size] as? Int64) ?? 0,
                sourceModifiedAt: (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0,
                destinationRelativePath: staleRelative
            ),
        ])
        try sync.saveManifest(manifest)

        let result = try sync.sync(items: [item])

        XCTAssertEqual(result.filesCopied, 1, "el destino cambio, debe recopiarse aunque tamano/fecha sean iguales")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleURL.path), "el archivo en la ruta plana vieja debe borrarse")
        let newURL = fakeIPod.appendingPathComponent("Music/Queen/A Night at the Opera/Bohemian Rhapsody.mp3")
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
    }

    func testPlaylistIsWrittenAsM3U8WithResolvedPaths() throws {
        let item = musicItem()
        let playlist = Playlist(name: "Roadtrip", trackItemIDs: [item.id])
        let sync = LibrarySync(volumeRoot: fakeIPod)

        let result = try sync.sync(items: [item], playlists: [playlist])

        XCTAssertEqual(result.playlistsWritten, 1)
        let playlistURL = fakeIPod.appendingPathComponent("Playlists/Roadtrip.m3u8")
        let contents = try String(contentsOf: playlistURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("#EXTM3U"))
        XCTAssertTrue(contents.contains("/Music/Queen/A Night at the Opera/Bohemian Rhapsody.mp3"))
    }

    func testPlaylistWithNoResolvableTracksIsNotWritten() throws {
        let playlist = Playlist(name: "Vacio", trackItemIDs: [UUID()])
        let sync = LibrarySync(volumeRoot: fakeIPod)

        let result = try sync.sync(items: [], playlists: [playlist])

        XCTAssertEqual(result.playlistsWritten, 0)
        let playlistURL = fakeIPod.appendingPathComponent("Playlists/Vacio.m3u8")
        XCTAssertFalse(FileManager.default.fileExists(atPath: playlistURL.path))
    }

    // MARK: - Portada de playlist (encargo del dueno, 2026-08-14)

    /// Sin caratula de album conocida en ninguna pista, LibrarySync igual
    /// deja un sidecar valido (tile placeholder de PlaylistArtGenerator)
    /// -- el firmware siempre encuentra ALGO junto al .m3u8.
    func testPlaylistWithoutCoverArtOrCustomImageStillGetsASidecar() throws {
        let item = musicItem() // sin coverArtData
        let playlist = Playlist(name: "Roadtrip", trackItemIDs: [item.id])
        let sync = LibrarySync(volumeRoot: fakeIPod)

        _ = try sync.sync(items: [item], playlists: [playlist])

        let imageURL = fakeIPod.appendingPathComponent("Playlists/Roadtrip.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))
        XCTAssertNotNil(NSImage(contentsOf: imageURL), "el sidecar generado debe ser un JPEG valido")
    }

    /// Con una imagen elegida a mano (`Playlist.imageRelativePath`,
    /// resuelta contra `libraryRoot`), esa es la que se copia -- no el
    /// colage/placeholder generado.
    func testPlaylistWithCustomImageCopiesItInsteadOfGeneratingADefault() throws {
        let libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("FakeLibrary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: libraryRoot.appendingPathComponent(".portadas"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: libraryRoot) }

        let playlistID = UUID()
        let customImageRelative = ".portadas/playlist-\(playlistID.uuidString).jpg"
        let customImageData = Data("caratula custom".utf8)
        try customImageData.write(to: libraryRoot.appendingPathComponent(customImageRelative))

        let item = musicItem()
        let playlist = Playlist(id: playlistID, name: "Roadtrip", trackItemIDs: [item.id],
                                 imageRelativePath: customImageRelative)
        let sync = LibrarySync(volumeRoot: fakeIPod)

        _ = try sync.sync(items: [item], playlists: [playlist], libraryRoot: libraryRoot)

        let imageURL = fakeIPod.appendingPathComponent("Playlists/Roadtrip.jpg")
        let written = try Data(contentsOf: imageURL)
        XCTAssertEqual(written, customImageData, "debe copiar la imagen custom tal cual, no generar un default")
    }

    // MARK: - Progreso (D-217)

    func testOnProgressReportsEachCopiedFileAgainstFilesActuallyCopied() throws {
        let item = musicItem()
        let sync = LibrarySync(volumeRoot: fakeIPod)
        var calls: [(copied: Int, total: Int)] = []

        _ = try sync.sync(items: [item], onProgress: { copied, total in
            calls.append((copied, total))
        })

        XCTAssertEqual(calls.count, 1, "un solo archivo por copiar -- un solo tick de progreso")
        XCTAssertEqual(calls.first?.copied, 1)
        XCTAssertEqual(calls.first?.total, 1)
    }

    func testOnProgressNotCalledWhenNothingNeedsCopying() throws {
        let item = musicItem()
        let sync = LibrarySync(volumeRoot: fakeIPod)
        _ = try sync.sync(items: [item])

        var calls = 0
        _ = try sync.sync(items: [item], onProgress: { _, _ in calls += 1 })

        XCTAssertEqual(calls, 0, "el segundo sync no copia nada (mismo tamaño/fecha) -- sin tick de progreso")
    }

    // MARK: - Calificaciones (D-200)

    func testRatedItemWritesNativeScaleRatingToSidecar() throws {
        var item = musicItem()
        item.metadata?.rating = 4
        let sync = LibrarySync(volumeRoot: fakeIPod)

        _ = try sync.sync(items: [item])

        let url = fakeIPod.appendingPathComponent(LibrarySync.ratingsRelativePath)
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("/Music/Queen/A Night at the Opera/Bohemian Rhapsody.mp3: 8"),
                      "4 estrellas de Aura Studio deben llegar como 8 en la escala nativa 0-10 de Rockbox")
    }

    func testUnratedItemsProduceNoSidecar() throws {
        let item = musicItem()
        let sync = LibrarySync(volumeRoot: fakeIPod)

        _ = try sync.sync(items: [item])

        let url = fakeIPod.appendingPathComponent(LibrarySync.ratingsRelativePath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testClearingRatingRemovesAnExistingSidecar() throws {
        var item = musicItem()
        item.metadata?.rating = 5
        let sync = LibrarySync(volumeRoot: fakeIPod)
        _ = try sync.sync(items: [item])
        let url = fakeIPod.appendingPathComponent(LibrarySync.ratingsRelativePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        item.metadata?.rating = nil
        _ = try sync.sync(items: [item])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testSummaryFileReflectsSyncedCounts() throws {
        let item = musicItem()
        let sync = LibrarySync(volumeRoot: fakeIPod)

        _ = try sync.sync(items: [item])

        let summaryURL = fakeIPod.appendingPathComponent(LibrarySync.summaryRelativePath)
        let contents = try String(contentsOf: summaryURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("music_count: 1"))
        XCTAssertTrue(contents.contains("video_count: 0"))
        XCTAssertTrue(contents.contains("playlist_count: 0"))
    }
}
