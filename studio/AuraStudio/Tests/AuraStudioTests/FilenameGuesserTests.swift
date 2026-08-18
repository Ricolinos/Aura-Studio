import XCTest
@testable import AuraStudio

final class FilenameGuesserTests: XCTestCase {
    func testArtistDashTitlePattern() {
        let url = URL(fileURLWithPath: "/tmp/Aura QA - Aura Test Tone.mp3")
        let guess = FilenameGuesser.guess(from: url)
        XCTAssertEqual(guess.artist, "Aura QA")
        XCTAssertEqual(guess.title, "Aura Test Tone")
    }

    func testTitleOnlyWhenNoDash() {
        let url = URL(fileURLWithPath: "/tmp/aura-test.flac")
        let guess = FilenameGuesser.guess(from: url)
        XCTAssertNil(guess.artist)
        XCTAssertEqual(guess.title, "aura-test")
    }

    func testMultipleDashesKeepsRemainderAsTitle() {
        let url = URL(fileURLWithPath: "/tmp/Artist - Song - Remix.mp3")
        let guess = FilenameGuesser.guess(from: url)
        XCTAssertEqual(guess.artist, "Artist")
        XCTAssertEqual(guess.title, "Song - Remix")
    }

    // PLAN-sync-media-hardening.md PARTE 1A: visto en produccion,
    // decenas de canciones de Gorillaz sin tags de artista terminaron
    // en carpetas del iPod literalmente llamadas "1".."20" (una por
    // numero de pista, mezclando artistas distintos que compartian
    // numero) en vez de "Desconocido" -- el guesser tomaba el prefijo
    // numerico del nombre de archivo como si fuera el artista.
    func testNumericPrefixIsNotMistakenForArtist() {
        let url = URL(fileURLWithPath: "/tmp/1 - Lil Dub Chefin' (radio edit).m4a")
        let guess = FilenameGuesser.guess(from: url)
        XCTAssertNil(guess.artist, "\"1\" no es un nombre de artista plausible")
        XCTAssertEqual(guess.title, "1 - Lil Dub Chefin' (radio edit)")
    }

    func testTrackNumberGluedToTitleIsNotMistakenForArtist() {
        let url = URL(fileURLWithPath: "/tmp/01 Lil Dub Chefin - Album Version - Originally -M1 A1-.m4a")
        let guess = FilenameGuesser.guess(from: url)
        XCTAssertNil(guess.artist)
        XCTAssertEqual(guess.title, "01 Lil Dub Chefin - Album Version - Originally -M1 A1-")
    }

    func testArtistStartingWithDigitsButNotFollowedBySpaceIsStillArtist() {
        // "2Pac" no es un prefijo de numero de pista (no hay espacio
        // despues del digito) -- no se descarta como artista.
        let url = URL(fileURLWithPath: "/tmp/2Pac - Changes.mp3")
        let guess = FilenameGuesser.guess(from: url)
        XCTAssertEqual(guess.artist, "2Pac")
        XCTAssertEqual(guess.title, "Changes")
    }
}
