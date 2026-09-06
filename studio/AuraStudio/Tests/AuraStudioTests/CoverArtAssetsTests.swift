import XCTest
@testable import AuraStudio

/// ST-012 / `docs/contracts/library-layout-v1.md` SS2: las caratulas son
/// assets de Musica/Video, nunca entradas de Imagenes -- el detector puro,
/// el filtro de importacion por modulo, la asociacion como portada, y la
/// migracion (con confirmacion) de bibliotecas ya contaminadas.
@MainActor
final class CoverArtAssetsTests: XCTestCase {
    private var root: URL!
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("CoverAssets-\(UUID().uuidString)", isDirectory: true)
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("CoverAssetsLib-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    private func write(_ relative: String) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
        return url
    }

    private func freshPreferences() -> AppPreferences {
        AppPreferences(defaults: UserDefaults(suiteName: "CoverArtAssetsTests-\(UUID().uuidString)")!)
    }


    /// Siembra `biblioteca.json` como lo dejaba el importador viejo (por
    /// extension): rutas absolutas, sin metadata, sin categoria salvo la
    /// que se indique. El ViewModel lo carga en su init.
    private func seedCatalog(_ entries: [(url: URL, kind: String, category: String?)]) throws {
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        let persisted = PersistedLibrary(items: entries.map { entry in
            PersistedLibraryItem(id: UUID(), sourceRelativePath: entry.url.path, kind: entry.kind,
                                 status: "queued", metadata: nil, preparedRelativePath: nil,
                                 coverRelativePath: nil, category: entry.category)
        })
        try JSONEncoder().encode(persisted).write(to: libraryRoot.appendingPathComponent("biblioteca.json"))
    }

    // MARK: - Detector puro

    func testCoverLikeNames() {
        for name in ["cover.jpg", "Folder.PNG", "front.jpeg", "album.jpg", "AlbumArt_{ABC}_Large.jpg",
                     "cover 2.jpg", "front-1.jpg", "artwork.png", "back.jpg"] {
            XCTAssertTrue(CoverArtAssets.hasCoverLikeName(URL(fileURLWithPath: "/x/\(name)")), name)
        }
        for name in ["IMG_0001.jpg", "vacaciones 2024.jpg", "cover.mp3", "portada de mi hijo.jpg", "discovery.jpg"] {
            XCTAssertFalse(CoverArtAssets.hasCoverLikeName(URL(fileURLWithPath: "/x/\(name)")), name)
        }
    }

    func testImageInFolderWithMediaInSameDropIsCover() throws {
        let track = try write("Album/01.mp3")
        let cover = try write("Album/IMG_9999.jpg") // nombre de foto, pero viaja con el album
        let context = CoverArtAssets.DropContext(urls: [track, cover])
        XCTAssertTrue(CoverArtAssets.isCoverAsset(cover, context: context, droppedIntoPhotos: false))
        XCTAssertTrue(CoverArtAssets.isCoverAsset(cover, context: context, droppedIntoPhotos: true),
                      "aunque se suelte en Fotos, una imagen que viaja con el audio del mismo directorio es caratula")
    }

    func testCoverNameAloneIsCoverUnlessDroppedIntoPhotos() throws {
        let cover = try write("Fotos sueltas/cover.jpg") // sin audio al lado
        XCTAssertTrue(CoverArtAssets.isCoverAsset(cover, context: .init(urls: []), droppedIntoPhotos: false))
        XCTAssertFalse(CoverArtAssets.isCoverAsset(cover, context: .init(urls: []), droppedIntoPhotos: true),
                       "soltada a proposito en Fotos, sin audio al lado: el usuario dijo que es una foto")
    }

    func testCoverNameDroppedIntoPhotosButLivingWithAudioOnDiskIsCover() throws {
        _ = try write("Album/01.mp3")
        let cover = try write("Album/cover.jpg")
        // Solo se arrastro la imagen (el drop no trae el audio), pero en
        // disco convive con el: sigue siendo caratula.
        XCTAssertTrue(CoverArtAssets.isCoverAsset(cover, context: .init(urls: []), droppedIntoPhotos: true))
    }

    func testPhotoFolderWithHomeVideosKeepsItsPhotos() throws {
        // Carpeta de un viaje: fotos + clips .mov. Las fotos son fotos; el
        // unico "poster" es la imagen con el mismo nombre base que un video.
        let urls = [try write("Viaje/IMG_1.jpg"), try write("Viaje/clip.mov"), try write("Viaje/clip.jpg")]
        let imported = LibraryViewModel.importableURLs(from: urls, into: .photo).map(\.lastPathComponent)
        XCTAssertEqual(Set(imported), ["IMG_1.jpg"], "clip.jpg es el poster de clip.mov")
    }

    func testFolderCoverPrefersCoverThenFolder() throws {
        let track = try write("Album/01.mp3")
        _ = try write("Album/folder.jpg")
        _ = try write("Album/back.jpg")
        XCTAssertEqual(CoverArtAssets.folderCover(near: track)?.lastPathComponent, "folder.jpg")
        _ = try write("Album/cover.png")
        XCTAssertEqual(CoverArtAssets.folderCover(near: track)?.lastPathComponent, "cover.png")
        let lonely = try write("Otro/02.mp3")
        XCTAssertNil(CoverArtAssets.folderCover(near: lonely))
    }

    // MARK: - Filtro de importacion por modulo

    func testDroppingAlbumIntoMusicImportsOnlyMusic() throws {
        let urls = [try write("Album/01.mp3"), try write("Album/02.flac"), try write("Album/cover.jpg"),
                    try write("Album/clip.mp4"), try write("Album/notas.txt")]
        let imported = LibraryViewModel.importableURLs(from: urls, into: .music).map(\.lastPathComponent)
        XCTAssertEqual(Set(imported), ["01.mp3", "02.flac"])
    }

    func testDroppingIntoPhotosImportsOnlyRealPhotos() throws {
        let urls = [try write("Viaje/IMG_1.jpg"), try write("Viaje/IMG_2.heic"), try write("Viaje/video.mov"),
                    try write("Album/01.mp3"), try write("Album/cover.jpg")]
        let imported = LibraryViewModel.importableURLs(from: urls, into: .photo).map(\.lastPathComponent)
        XCTAssertEqual(Set(imported), ["IMG_1.jpg", "IMG_2.heic"],
                       "el video no entra a Fotos y el cover.jpg del album es caratula")
    }

    func testUntargetedImportKeepsEverythingButCovers() throws {
        // Reimportacion desde el iPod (ForeignContentSheet): sin modulo
        // destino, pero un Photos/cover.jpg reimportado NO vuelve a Imagenes.
        let urls = [try write("Photos/cover.jpg"), try write("Photos/IMG_5.jpg"), try write("Music/A/B/song.mp3")]
        let imported = LibraryViewModel.importableURLs(from: urls, into: nil).map(\.lastPathComponent)
        XCTAssertEqual(Set(imported), ["IMG_5.jpg", "song.mp3"])
    }

    func testViewModelFolderDropIntoMusicLeavesNoPhotoEntries() throws {
        _ = try write("Album/01.mp3"); _ = try write("Album/cover.jpg")
        let vm = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        vm.addDroppedFiles([root.appendingPathComponent("Album")], into: .music)
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertTrue(vm.items.allSatisfy { $0.kind == .music })
    }

    // MARK: - Asociacion: la caratula de carpeta es la portada de la cancion

    func testLocalTagReaderUsesFolderCoverWhenNoEmbeddedArt() async throws {
        // Un mp3 "vacio" no tiene arte embebido; el cover.jpg de la carpeta
        // pasa a ser su portada.
        let track = try write("Album/01.mp3")
        let coverBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02, 0x03])
        try coverBytes.write(to: root.appendingPathComponent("Album/cover.jpg"))
        let metadata = await LocalTagReader.readTag(from: track)
        XCTAssertEqual(metadata.pendingCoverData, coverBytes)
    }

    // MARK: - Migracion con biblioteca mixta

    func testMigrationCandidatesNeverIncludeRealPhotos() throws {
        // Biblioteca mixta: dos fotos personales, una caratula fuerte
        // (convive con musica), una caratula solo por nombre, y una
        // "cover.jpg" que es una fotografia real (EXIF de camara ->
        // categoria "Fotografias").
        let song = try write("Album/01.mp3")
        let strongCover = try write("Album/cover.jpg")
        let nameOnly = try write("Descargas/folder.jpg")
        let photo1 = try write("Viaje/IMG_1.jpg")
        let photo2 = try write("Viaje/playa.jpg")
        let realPhotoNamedCover = try write("Camara/cover.jpg")
        try seedCatalog([(song, "music", nil), (strongCover, "photo", nil), (nameOnly, "photo", nil),
                         (photo1, "photo", nil), (photo2, "photo", nil), (realPhotoNamedCover, "photo", "Fotografías")])
        let vm = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        XCTAssertEqual(vm.items.count, 6)

        let candidates = vm.coverContaminationCandidates()
        let names = candidates.map { $0.item.sourceURL.lastPathComponent }
        XCTAssertEqual(candidates.count, 2, "solo las dos caratulas: \(names)")
        XCTAssertEqual(candidates[0].item.sourceURL.path, strongCover.path, "la de evidencia fuerte primero")
        XCTAssertTrue(candidates[0].strong)
        XCTAssertEqual(candidates[1].item.sourceURL.path, nameOnly.path)
        XCTAssertFalse(candidates[1].strong)
        XCTAssertFalse(candidates.contains { $0.item.sourceURL.path == photo1.path })
        XCTAssertFalse(candidates.contains { $0.item.sourceURL.path == photo2.path })
        XCTAssertFalse(candidates.contains { $0.item.sourceURL.path == realPhotoNamedCover.path },
                       "una fotografia real (EXIF de camara) nunca es candidata aunque se llame cover.jpg")
        XCTAssertEqual(vm.coverContaminationOfferCount, 2, "la oferta se anuncia al cargar")
    }

    func testRemoveFromImagesRemovesOnlyChosenEntriesAndKeepsOriginals() throws {
        _ = try write("Album/01.mp3")
        let cover = try write("Album/cover.jpg")
        let photo = try write("Viaje/IMG_1.jpg")
        try seedCatalog([(cover, "photo", nil), (photo, "photo", nil)])
        let vm = LibraryViewModel(libraryRoot: libraryRoot, preferences: freshPreferences())
        let coverID = try XCTUnwrap(vm.items.first { $0.sourceURL.path == cover.path }).id

        vm.removeFromImages(ids: [coverID])

        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items.first?.sourceURL.path, photo.path, "la foto real no se toca")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cover.path),
                      "quitar de Imagenes = quitar la entrada, no borrar el archivo original")
        XCTAssertNil(vm.coverContaminationOfferCount, "la oferta no se vuelve a mostrar")
    }

    func testOfferIsOneShot() throws {
        let prefs = freshPreferences()
        _ = try write("Album/01.mp3"); let cover = try write("Album/cover.jpg")
        try seedCatalog([(cover, "photo", nil)])
        let vm = LibraryViewModel(libraryRoot: libraryRoot, preferences: prefs)
        XCTAssertEqual(vm.coverContaminationOfferCount, 1)
        XCTAssertFalse(prefs.coverContaminationReviewShown)
        vm.dismissCoverContaminationOffer()
        XCTAssertTrue(prefs.coverContaminationReviewShown)
        XCTAssertNil(vm.coverContaminationOfferCount)

        // Otra instancia con las mismas preferencias: ya no se ofrece.
        let again = LibraryViewModel(libraryRoot: libraryRoot, preferences: prefs)
        XCTAssertNil(again.coverContaminationOfferCount)
    }
}
