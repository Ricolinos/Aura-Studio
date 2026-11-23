import XCTest
@testable import AuraStudio

/// Ronda rendimiento-3, camino B: la caché en disco de candidatas de
/// carátula. Ver `AlbumCoverSearchCache`.
final class AlbumCoverSearchCacheTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cover-search-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeCandidate(_ byte: UInt8, score: Int, source: AlbumCoverSearch.Source = .coverArtArchive,
                               detail: String? = nil, discoveryOrder: Int = 0) -> AlbumCoverSearch.Candidate {
        AlbumCoverSearch.Candidate(data: Data(repeating: byte, count: 64),
                                   source: source, detail: detail, score: score,
                                   discoveryOrder: discoveryOrder)
    }

    private let key = AlbumCoverSearchCache.Key(album: "Signos", artist: "Soda Stereo", year: "1986", trackCount: 9)

    func testRoundTripPreservesContentSourceScoreAndOrder() {
        let cache = AlbumCoverSearchCache(directory: tempDir)
        let candidates = [
            makeCandidate(1, score: 100, detail: "Signos · 1986", discoveryOrder: 0),
            makeCandidate(2, score: 40, discoveryOrder: 1),
        ]

        cache.store(candidates, for: key)
        let loaded = cache.load(key)

        XCTAssertEqual(loaded?.count, 2)
        XCTAssertEqual(loaded?.first?.data, candidates[0].data)
        XCTAssertEqual(loaded?.first?.source, .coverArtArchive)
        XCTAssertEqual(loaded?.first?.detail, "Signos · 1986")
        XCTAssertEqual(loaded?.first?.score, 100)
        XCTAssertEqual(loaded?.last?.discoveryOrder, 1)
    }

    func testExpiredEntryIsNotServed() {
        let t0 = Date()
        AlbumCoverSearchCache(directory: tempDir, now: { t0 })
            .store([makeCandidate(1, score: 100)], for: key)

        // Ocho días después, la entrada venció (la vigencia es 7). Se
        // relee con OTRA instancia cuyo reloj ya avanzo: capturar un
        // `var` mutable en el closure del reloj es una captura no
        // Sendable y el target del .xcodeproj compila con concurrencia
        // estricta (SwiftPM no lo detectaba).
        let later = t0.addingTimeInterval(8 * 24 * 60 * 60)
        let cache = AlbumCoverSearchCache(directory: tempDir, now: { later })
        XCTAssertNil(cache.load(key))
    }

    func testEntryWithinTTLIsServed() {
        let t0 = Date()
        AlbumCoverSearchCache(directory: tempDir, now: { t0 })
            .store([makeCandidate(1, score: 100)], for: key)

        let later = t0.addingTimeInterval(6 * 24 * 60 * 60)
        let cache = AlbumCoverSearchCache(directory: tempDir, now: { later })
        XCTAssertEqual(cache.load(key)?.count, 1)
    }

    func testAMissingImageInvalidatesOnlyItsOwnCandidate() throws {
        let cache = AlbumCoverSearchCache(directory: tempDir)
        cache.store([makeCandidate(1, score: 100), makeCandidate(2, score: 40)], for: key)

        // Borrar a mano la imagen de la primera candidata: la segunda
        // sobrevive -- una entrada a medias no tira la búsqueda entera.
        let folder = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil).first)
        try FileManager.default.removeItem(at: folder.appendingPathComponent("0.jpg"))

        let loaded = cache.load(key)
        XCTAssertEqual(loaded?.count, 1)
        XCTAssertEqual(loaded?.first?.score, 40)
    }

    func testCorrectedMetadataProducesADifferentKey() {
        let cache = AlbumCoverSearchCache(directory: tempDir)
        cache.store([makeCandidate(1, score: 100)], for: key)

        // El usuario corrigió el número de pistas: otra búsqueda, no la
        // candidata puntuada contra datos viejos.
        let corrected = AlbumCoverSearchCache.Key(album: "Signos", artist: "Soda Stereo", year: "1986", trackCount: 10)
        XCTAssertNil(cache.load(corrected))
    }

    func testStoringNothingWritesNothing() {
        let cache = AlbumCoverSearchCache(directory: tempDir)
        cache.store([], for: key)
        XCTAssertNil(cache.load(key))
    }
}
