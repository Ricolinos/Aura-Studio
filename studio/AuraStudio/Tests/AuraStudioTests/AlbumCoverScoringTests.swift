import XCTest
@testable import AuraStudio

/// R2-3 (ST-115): puntaje, umbral y desempates de la carátula
/// recomendada. La especificación vinculante es
/// `docs/caratula-recomendada.md`; si un número de acá cambia, cambia
/// allá y en la app de Windows, o las dos apps recomiendan distinto para
/// la misma biblioteca.
final class AlbumCoverScoringTests: XCTestCase {
    private let album = AlbumCoverScoring.AlbumFacts(title: "Signos", year: "1986", trackCount: 8)

    private func release(title: String? = "Signos", year: String? = "1986", trackCount: Int? = 8,
                         status: String? = "Official", country: String? = "MX",
                         front: Bool = true) -> AlbumCoverScoring.ReleaseFacts {
        AlbumCoverScoring.ReleaseFacts(title: title, year: year, trackCount: trackCount,
                                       status: status, country: country, isFrontCover: front)
    }

    // MARK: - Los pesos

    func testAPerfectEditionScoresTheMaximum() {
        XCTAssertEqual(AlbumCoverScoring.score(album: album, release: release()),
                       AlbumCoverScoring.maximum)
        XCTAssertEqual(AlbumCoverScoring.maximum, 110)
    }

    func testEachCriterionIsWorthExactlyWhatTheSpecSays() {
        let perfect = AlbumCoverScoring.maximum
        XCTAssertEqual(perfect - AlbumCoverScoring.score(album: album, release: release(title: "Otro")), 50)
        XCTAssertEqual(perfect - AlbumCoverScoring.score(album: album, release: release(year: "2007")), 25)
        XCTAssertEqual(perfect - AlbumCoverScoring.score(album: album, release: release(trackCount: 12)), 15)
        XCTAssertEqual(perfect - AlbumCoverScoring.score(album: album, release: release(status: "Bootleg")), 6)
        XCTAssertEqual(perfect - AlbumCoverScoring.score(album: album, release: release(front: false)), 10)
        // País: 2 por declararlo, 2 más por ser uno de los preferidos.
        XCTAssertEqual(perfect - AlbumCoverScoring.score(album: album, release: release(country: "JP")), 2)
        XCTAssertEqual(perfect - AlbumCoverScoring.score(album: album, release: release(country: nil)), 4)
    }

    func testTheTitleIsComparedNormalized() {
        XCTAssertEqual(AlbumCoverScoring.score(album: album, release: release(title: "  SIGNOS ")),
                       AlbumCoverScoring.maximum)
    }

    func testAnEmptyTitleOnBothSidesIsNotAMatch() {
        // Dos vacíos no son "el mismo álbum": sin título no hay nada que
        // corroborar y no se pueden regalar 50 puntos.
        let sinTitulo = AlbumCoverScoring.AlbumFacts(title: "", year: nil, trackCount: 0)
        XCTAssertEqual(
            AlbumCoverScoring.score(album: sinTitulo,
                                    release: release(title: "", year: nil, trackCount: nil,
                                                     status: nil, country: nil, front: false)),
            0)
    }

    func testAZeroTrackCountNeverCountsAsAMatch() {
        let sinPistas = AlbumCoverScoring.AlbumFacts(title: "Signos", year: nil, trackCount: 0)
        let score = AlbumCoverScoring.score(
            album: sinPistas,
            release: release(year: nil, trackCount: 0, status: nil, country: nil, front: false))
        XCTAssertEqual(score, AlbumCoverScoring.titleMatch)
    }

    // MARK: - El umbral

    func testTheThresholdNeedsTitlePlusRealCorroboration() {
        XCTAssertEqual(AlbumCoverScoring.automaticThreshold, 85)

        // Título + año + tapa frontal = 85, justo alcanza.
        XCTAssertEqual(
            AlbumCoverScoring.score(album: album,
                                    release: release(trackCount: nil, status: nil, country: nil)),
            85)
        // Título + nº de pistas + oficial + país preferido + frontal = 85.
        XCTAssertEqual(
            AlbumCoverScoring.score(album: album, release: release(year: nil)),
            85)
    }

    func testATitleMatchAloneIsNotEnoughToApplyWithoutAsking() {
        // El caso que el umbral existe para frenar: "Greatest Hits" de
        // cualquiera coincide de título con "Greatest Hits" de otro.
        let soloTitulo = AlbumCoverScoring.score(
            album: album,
            release: release(year: nil, trackCount: nil, status: nil, country: nil, front: false))
        XCTAssertEqual(soloTitulo, 50)
        XCTAssertLessThan(soloTitulo, AlbumCoverScoring.automaticThreshold)
    }

    func testEvenTitlePlusAllTheMinorSignalsStaysBelowTheThreshold() {
        // 50 + 6 + 4 + 10 = 70: sin año ni número de pistas no se aplica
        // sin preguntar, por más "oficial" que sea la edición.
        XCTAssertLessThan(
            AlbumCoverScoring.score(album: album, release: release(year: nil, trackCount: nil)),
            AlbumCoverScoring.automaticThreshold)
    }

    // MARK: - Desempates (tienen que dar el MISMO resultado siempre)

    private func candidate(score: Int, front: Bool = false, official: Bool = false,
                           year: String? = nil, source: AlbumCoverSearch.Source = .coverArtArchive,
                           order: Int = 0) -> AlbumCoverSearch.Candidate {
        AlbumCoverSearch.Candidate(data: Data([UInt8(order &+ 1)]), source: source, detail: nil,
                                   score: score, isFrontCover: front, isOfficial: official,
                                   releaseYear: year, discoveryOrder: order)
    }

    func testHigherScoreWinsFirst() {
        let best = AlbumCoverSearch.recommended(from: [candidate(score: 60), candidate(score: 90, order: 1)])
        XCTAssertEqual(best?.score, 90)
    }

    func testAtEqualScoreTheRealFrontCoverWins() {
        let best = AlbumCoverSearch.recommended(from: [
            candidate(score: 60, front: false),
            candidate(score: 60, front: true, order: 1),
        ])
        XCTAssertTrue(best?.isFrontCover ?? false)
    }

    func testThenTheOfficialEditionWins() {
        let best = AlbumCoverSearch.recommended(from: [
            candidate(score: 60, front: true, official: false),
            candidate(score: 60, front: true, official: true, order: 1),
        ])
        XCTAssertTrue(best?.isOfficial ?? false)
    }

    func testThenTheOldestEditionWins() {
        // La edición original antes que la reedición: es la tapa que la
        // gente reconoce como la del disco.
        let best = AlbumCoverSearch.recommended(from: [
            candidate(score: 60, front: true, official: true, year: "2007"),
            candidate(score: 60, front: true, official: true, year: "1986", order: 1),
        ])
        XCTAssertEqual(best?.releaseYear, "1986")
    }

    func testAnEditionWithoutAYearLosesToOneWithIt() {
        let best = AlbumCoverSearch.recommended(from: [
            candidate(score: 60, front: true, official: true, year: nil),
            candidate(score: 60, front: true, official: true, year: "1999", order: 1),
        ])
        XCTAssertEqual(best?.releaseYear, "1999")
    }

    func testCoverArtArchiveWinsOverDeezerAtEqualEverything() {
        let best = AlbumCoverSearch.recommended(from: [
            candidate(score: 50, source: .deezer),
            candidate(score: 50, source: .coverArtArchive, order: 1),
        ])
        XCTAssertEqual(best?.source, .coverArtArchive)
    }

    func testTheLastTieBreakIsDiscoveryOrderSoItIsAlwaysDeterministic() {
        let best = AlbumCoverSearch.recommended(from: [
            candidate(score: 50, order: 3),
            candidate(score: 50, order: 1),
        ])
        XCTAssertEqual(best?.discoveryOrder, 1)
    }

    func testNoCandidatesHasNoRecommendation() {
        XCTAssertNil(AlbumCoverSearch.recommended(from: []))
    }

    func testReachesAutomaticThresholdMatchesTheConstant() {
        XCTAssertFalse(candidate(score: 84).reachesAutomaticThreshold)
        XCTAssertTrue(candidate(score: 85).reachesAutomaticThreshold)
    }
}
