import XCTest
@testable import AuraStudio

/// R2-4 (ST-116): homologación de artistas. La especificación vinculante
/// es `docs/normalizacion-artistas.md` y la app de Windows implementa lo
/// mismo -- estas pruebas son la forma ejecutable de ese documento.
final class ArtistNameNormalizerTests: XCTestCase {
    private func principal(_ raw: String,
                           on: Bool = true,
                           exceptions: [String] = []) -> String {
        ArtistNameNormalizer.principalArtist(
            raw, options: ArtistGroupingOptions(homologateCollaborations: on, exceptions: exceptions))
    }

    // MARK: - Los separadores de la lista cerrada

    func testEverySeparatorInTheClosedListCuts() {
        XCTAssertEqual(principal("Gorillaz feat. De La Soul"), "Gorillaz")
        XCTAssertEqual(principal("Gorillaz feat De La Soul"), "Gorillaz")
        XCTAssertEqual(principal("Gorillaz ft. De La Soul"), "Gorillaz")
        XCTAssertEqual(principal("Gorillaz ft De La Soul"), "Gorillaz")
        XCTAssertEqual(principal("Gorillaz featuring De La Soul"), "Gorillaz")
        XCTAssertEqual(principal("Gorillaz + De La Soul"), "Gorillaz")
        XCTAssertEqual(principal("Gorillaz with De La Soul"), "Gorillaz")
        XCTAssertEqual(principal("Julieta Venegas con Bandalos Chinos"), "Julieta Venegas")
    }

    func testTheSeparatorIsMatchedWithoutCaseOrAccents() {
        XCTAssertEqual(principal("Gorillaz FEAT. De La Soul"), "Gorillaz")
        XCTAssertEqual(principal("Gorillaz Featuring De La Soul"), "Gorillaz")
        XCTAssertEqual(principal("Julieta Venegas CON Juanes"), "Julieta Venegas")
    }

    func testTheArtistKeepsEverythingBeforeTheFirstSeparator() {
        XCTAssertEqual(principal("Calle 13 feat. Rubén Blades ft. Café Tacvba"), "Calle 13")
        XCTAssertEqual(principal("Los Ángeles Azules con Ximena Sariñana"), "Los Ángeles Azules")
    }

    // MARK: - Lo que NO se toca

    func testVersusIsNeverHomologated() {
        // Decisión explícita del dueño: una colaboración con identidad
        // propia es OTRO artista, no el principal con invitados.
        XCTAssertEqual(principal("Spacemonkeyz vs. Gorillaz"), "Spacemonkeyz vs. Gorillaz")
        XCTAssertEqual(principal("Spacemonkeyz vs Gorillaz"), "Spacemonkeyz vs Gorillaz")
        XCTAssertEqual(principal("Spacemonkeyz versus Gorillaz"), "Spacemonkeyz versus Gorillaz")
    }

    func testASeparatorInsideAWordDoesNotCut() {
        // "ft" vive dentro de "Daft"; "con" dentro de "Confeti". Se
        // comparan tokens completos justamente por esto.
        XCTAssertEqual(principal("Daft Punk"), "Daft Punk")
        XCTAssertEqual(principal("Confeti de Odio"), "Confeti de Odio")
        XCTAssertEqual(principal("Blink+182"), "Blink+182")
    }

    func testACreditThatStartsWithTheSeparatorIsLeftAlone() {
        // Recortarlo daría cadena vacía, y esa pista terminaría bajo
        // "Artista desconocido" -- peor que no hacer nada.
        XCTAssertEqual(principal("feat. Alguien"), "feat. Alguien")
        XCTAssertEqual(principal("+ Alguien"), "+ Alguien")
    }

    func testAnArtistWithoutSeparatorsIsUnchanged() {
        XCTAssertEqual(principal("Soda Stereo"), "Soda Stereo")
        XCTAssertEqual(principal("  Café Tacvba  "), "Café Tacvba")
        XCTAssertEqual(principal(""), "")
    }

    // MARK: - Ajuste y excepciones

    func testTurningItOffRestoresTheExactPreviousGrouping() {
        XCTAssertEqual(principal("Gorillaz feat. De La Soul", on: false), "Gorillaz feat. De La Soul")
    }

    func testAnExceptionIsNeverCut() {
        // La lista de separadores es ciega: "Simon + Garfunkel" y "Café
        // con Leche" son nombres de grupo, no colaboraciones.
        XCTAssertEqual(principal("Simon + Garfunkel", exceptions: ["Simon + Garfunkel"]),
                       "Simon + Garfunkel")
        XCTAssertEqual(principal("Café con Leche", exceptions: ["cafe con leche"]),
                       "Café con Leche")
    }

    func testExceptionsIgnoreCaseAndAccentsButNotOtherArtists() {
        XCTAssertEqual(principal("Gorillaz feat. De La Soul", exceptions: ["Simon + Garfunkel"]),
                       "Gorillaz")
    }

    func testHasCollaboratorsSaysWhenSomethingWasTrimmed() {
        XCTAssertTrue(ArtistNameNormalizer.hasCollaborators("Gorillaz feat. De La Soul"))
        XCTAssertFalse(ArtistNameNormalizer.hasCollaborators("Gorillaz"))
        XCTAssertFalse(ArtistNameNormalizer.hasCollaborators("Spacemonkeyz vs. Gorillaz"))
    }

    // MARK: - Efecto sobre la agrupación (que es todo el punto)

    private func song(_ title: String, artist: String, album: String) -> AuraStudio.LibraryItem {
        var item = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).mp3"))
        item.metadata = TrackMetadata(title: title, artist: artist, album: album)
        return item
    }

    func testCollaborationsCollapseIntoOneArtist() {
        let items = [song("Feel Good Inc.", artist: "Gorillaz feat. De La Soul", album: "Demon Days"),
                     song("Dare", artist: "Gorillaz", album: "Demon Days")]

        let artists = LibraryGrouping.artists(from: items, options: ArtistGroupingOptions())

        XCTAssertEqual(artists.count, 1)
        XCTAssertEqual(artists.first?.name, "Gorillaz")
        XCTAssertEqual(artists.first?.trackCount, 2)
    }

    func testTheTrackArtistIsNeverRewritten() {
        // Lo que se ve en la tabla y lo que viaja en el archivo son los
        // créditos COMPLETOS. La homologación solo agrupa.
        let credited = song("Feel Good Inc.", artist: "Gorillaz feat. De La Soul", album: "Demon Days")
        let artists = LibraryGrouping.artists(from: [credited], options: ArtistGroupingOptions())

        XCTAssertEqual(artists.first?.name, "Gorillaz")
        XCTAssertEqual(artists.first?.items.first?.metadata?.artist,
                       "Gorillaz feat. De La Soul",
                       "la metadata de la pista tiene que quedar intacta")
    }

    func testWithTheSettingOffTheyStaySeparate() {
        let items = [song("Feel Good Inc.", artist: "Gorillaz feat. De La Soul", album: "Demon Days"),
                     song("Dare", artist: "Gorillaz", album: "Demon Days")]

        let artists = LibraryGrouping.artists(
            from: items, options: ArtistGroupingOptions(homologateCollaborations: false))

        XCTAssertEqual(artists.count, 2)
    }

    func testVersusStaysItsOwnArtistInTheGrouping() {
        let items = [song("Lil Dub Chefin'", artist: "Spacemonkeyz vs. Gorillaz", album: "Laika Come Home"),
                     song("Dare", artist: "Gorillaz", album: "Demon Days")]

        let artists = LibraryGrouping.artists(from: items, options: ArtistGroupingOptions())

        XCTAssertEqual(artists.count, 2)
    }
}
