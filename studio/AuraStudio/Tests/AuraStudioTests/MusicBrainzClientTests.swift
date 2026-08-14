import XCTest
@testable import AuraStudio

/// D-203: `buildQuery` es la pieza que causaba busquedas rotas en
/// silencio con titulos reales (comillas, barras invertidas) -- ver
/// DECISIONS.md. Sin red, verifica solo el armado de la query Lucene.
final class MusicBrainzClientTests: XCTestCase {
    func testPlainTitleAndArtistAreQuoted() {
        let query = MusicBrainzClient.buildQuery(title: "Bohemian Rhapsody", artist: "Queen")
        XCTAssertEqual(query, "recording:\"Bohemian Rhapsody\" AND artist:\"Queen\"")
    }

    func testDoubleQuoteInTitleIsEscapedNotLeftBroken() {
        let query = MusicBrainzClient.buildQuery(title: "Rock \"N\" Roll", artist: nil)
        XCTAssertEqual(query, "recording:\"Rock \\\"N\\\" Roll\"")
    }

    func testBackslashInArtistIsEscaped() {
        let query = MusicBrainzClient.buildQuery(title: nil, artist: "Y\\N")
        XCTAssertEqual(query, "artist:\"Y\\\\N\"")
    }

    func testOnlyTitleOmitsArtistClause() {
        let query = MusicBrainzClient.buildQuery(title: "Yesterday", artist: nil)
        XCTAssertEqual(query, "recording:\"Yesterday\"")
    }
}
