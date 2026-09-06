import XCTest
@testable import AuraStudio

/// Cubre `LibraryViewModel.rereadLocalTags` y el banner de biblioteca
/// existente (PLAN-studio-ux.md §2/P1-P2): que solo reemplaza los
/// campos que el archivo trae, que respeta ediciones manuales previas
/// cuando corresponde (`respectUserEdits`), y que el banner se ofrece
/// una sola vez por instalacion (persistido en `AppPreferences`, no en
/// el `LibraryViewModel` -- se simula "la proxima vez que se abre la
/// app" creando una segunda instancia sobre el mismo `libraryRoot`/
/// `preferences`, igual que hace la propia app al reiniciar).
@MainActor
final class LibraryViewModelLocalTagRereadTests: XCTestCase {
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalTagRereadTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    private func freshPreferences() -> AppPreferences {
        AppPreferences(defaults: makeIsolatedDefaults("LocalTagRereadTests"))
    }

    /// Genera un mp3 real con tags ID3v2.4 (title/artist/album) en una
    /// carpeta aparte de `libraryRoot` -- `copyMediaIntoLibrary` esta
    /// apagado en estos tests para que `sourceURL` siga apuntando
    /// directo al fixture (mas simple de inspeccionar que perseguir la
    /// copia dentro de la biblioteca).
    private func makeTaggedFixture(title: String, artist: String, album: String) throws -> URL {
        guard let ffmpeg = FFmpegLocator.locate() else {
            throw XCTSkip("ffmpeg no esta instalado")
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LocalTagRereadFixtures-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("\(UUID().uuidString).mp3")
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = [
            "-y", "-loglevel", "error",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
            "-metadata", "title=\(title)", "-metadata", "artist=\(artist)", "-metadata", "album=\(album)",
            url.path,
        ]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw XCTSkip("ffmpeg no pudo generar el fixture")
        }
        return url
    }

    // MARK: - rereadLocalTags: merge

    func testRereadFillsFromFileWithoutErasingFieldsTheFileDoesNotHave() async throws {
        let url = try makeTaggedFixture(title: "Del archivo", artist: "Artista archivo", album: "Album archivo")
        let prefs = freshPreferences()
        prefs.copyMediaIntoLibrary = false
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: prefs)
        viewModel.addDroppedFiles([url])
        let id = try XCTUnwrap(viewModel.items.first?.id)

        // Genero/compositor NO estan en el archivo -- si ya venian de
        // otra via (aca, simulados a mano), no deben borrarse.
        var preExisting = TrackMetadata()
        preExisting.genre = "Genero previo"
        preExisting.rating = 4
        preExisting.syncedLyrics = "la la la"
        await viewModel.applyReview(id: id, metadata: preExisting)

        await viewModel.rereadLocalTags(ids: [id])

        let metadata = try XCTUnwrap(viewModel.items.first(where: { $0.id == id })?.metadata)
        XCTAssertEqual(metadata.title, "Del archivo")
        XCTAssertEqual(metadata.artist, "Artista archivo")
        XCTAssertEqual(metadata.album, "Album archivo")
        XCTAssertEqual(metadata.genre, "Genero previo", "el archivo no trae genero -- no debe pisar lo que ya habia")
        XCTAssertEqual(metadata.rating, 4, "la calificacion nunca es una tag del archivo")
        XCTAssertEqual(metadata.syncedLyrics, "la la la", "la letra sincronizada nunca es una tag del archivo")
    }

    func testRespectUserEditsSkipsManuallyEditedItems() async throws {
        let url = try makeTaggedFixture(title: "Del archivo", artist: "Artista archivo", album: "Album archivo")
        let prefs = freshPreferences()
        prefs.copyMediaIntoLibrary = false
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: prefs)
        viewModel.addDroppedFiles([url])
        let id = try XCTUnwrap(viewModel.items.first?.id)

        var manual = TrackMetadata()
        manual.title = "Corregido a mano"
        manual.artist = "Artista a mano"
        manual.album = "Album a mano"
        await viewModel.applyReview(id: id, metadata: manual) // marca metadataEditedByUser = true

        await viewModel.rereadLocalTags(ids: [id], respectUserEdits: true)
        var metadata = try XCTUnwrap(viewModel.items.first(where: { $0.id == id })?.metadata)
        XCTAssertEqual(metadata.title, "Corregido a mano", "respectUserEdits: true no debe pisar una correccion manual")

        // La accion explicita del menu (respectUserEdits: false, el
        // default) SI pisa, sea cual sea metadataEditedByUser.
        await viewModel.rereadLocalTags(ids: [id])
        metadata = try XCTUnwrap(viewModel.items.first(where: { $0.id == id })?.metadata)
        XCTAssertEqual(metadata.title, "Del archivo", "la accion explicita del menu contextual siempre relee, aunque haya edicion manual")
    }

    // MARK: - Banner de biblioteca existente (P1)

    func testOfferAppearsOnceForExistingLibraryWithMusic() async throws {
        let url = try makeTaggedFixture(title: "T", artist: "A", album: "Al")
        let prefs = freshPreferences()
        prefs.copyMediaIntoLibrary = false

        let firstSession = LibraryViewModel(libraryRoot: libraryRoot, preferences: prefs)
        firstSession.addDroppedFiles([url])
        XCTAssertNil(firstSession.legacyMetadataRereadOfferCount, "no se ofrece en la MISMA sesion que agrega el archivo -- es para bibliotecas YA existentes")

        // Simula reabrir la app: nueva instancia sobre el mismo catalogo.
        let secondSession = LibraryViewModel(libraryRoot: libraryRoot, preferences: prefs)
        XCTAssertEqual(secondSession.legacyMetadataRereadOfferCount, 1)

        secondSession.dismissLegacyMetadataRereadOffer()
        XCTAssertNil(secondSession.legacyMetadataRereadOfferCount)
        XCTAssertTrue(prefs.legacyMetadataBannerShown)

        // Una tercera sesion nunca vuelve a preguntar.
        let thirdSession = LibraryViewModel(libraryRoot: libraryRoot, preferences: prefs)
        XCTAssertNil(thirdSession.legacyMetadataRereadOfferCount)
    }

    func testEmptyLibraryNeverOffersReread() throws {
        let prefs = freshPreferences()
        let viewModel = LibraryViewModel(libraryRoot: libraryRoot, preferences: prefs)
        XCTAssertNil(viewModel.legacyMetadataRereadOfferCount)
    }

    func testAcceptingOfferRereadsAllMusicRespectingManualEditsAndDismisses() async throws {
        let urlA = try makeTaggedFixture(title: "Del archivo A", artist: "Artista A", album: "Album A")
        let urlB = try makeTaggedFixture(title: "Del archivo B", artist: "Artista B", album: "Album B")
        let prefs = freshPreferences()
        prefs.copyMediaIntoLibrary = false

        let firstSession = LibraryViewModel(libraryRoot: libraryRoot, preferences: prefs)
        firstSession.addDroppedFiles([urlA, urlB])
        let idA = try XCTUnwrap(firstSession.items.first(where: { $0.sourceURL == urlA })?.id)
        var manual = TrackMetadata()
        manual.title = "Corregido a mano"
        await firstSession.applyReview(id: idA, metadata: manual)

        let secondSession = LibraryViewModel(libraryRoot: libraryRoot, preferences: prefs)
        XCTAssertEqual(secondSession.legacyMetadataRereadOfferCount, 2)

        await secondSession.acceptLegacyMetadataRereadOffer()

        XCTAssertNil(secondSession.legacyMetadataRereadOfferCount)
        XCTAssertTrue(prefs.legacyMetadataBannerShown)
        let titleA = secondSession.items.first(where: { $0.sourceURL == urlA })?.metadata?.title
        let titleB = secondSession.items.first(where: { $0.sourceURL == urlB })?.metadata?.title
        XCTAssertEqual(titleA, "Corregido a mano", "el banner respeta ediciones manuales")
        XCTAssertEqual(titleB, "Del archivo B", "el resto de la biblioteca si se actualiza")
    }
}
