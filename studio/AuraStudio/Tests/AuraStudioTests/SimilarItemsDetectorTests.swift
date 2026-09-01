import XCTest
@testable import AuraStudio

/// ST-063: detector de elementos "sospechosamente similares" y
/// resúmenes de la barra de estado.
final class SimilarItemsDetectorTests: XCTestCase {
    private func song(_ title: String, artist: String? = nil, album: String? = nil,
                      duration: Double? = nil, ext: String = "mp3", track: Int? = nil,
                      cover: Bool = false, path: String? = nil) -> AuraStudio.LibraryItem {
        var item = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: path ?? "/tmp/aura-tests/\(UUID().uuidString).\(ext)"))
        item.metadata = TrackMetadata(title: title, artist: artist, album: album, trackNumber: track,
                                      coverArtData: cover ? Data([1, 2, 3]) : nil, durationSeconds: duration)
        item.status = .ready
        return item
    }

    private func photo(_ name: String) -> AuraStudio.LibraryItem {
        var item = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/aura-tests/\(name)"))
        item.category = "Fotos"
        return item
    }

    private func sizes(_ map: [UUID: Int64], items: [AuraStudio.LibraryItem]) -> (URL) -> Int64 {
        let byPath = Dictionary(uniqueKeysWithValues: items.map { ($0.sourceURL.path, map[$0.id] ?? 0) })
        return { byPath[$0.path] ?? 0 }
    }

    // MARK: - Normalización

    func testStripsLeadingTrackNumbers() {
        XCTAssertEqual(SimilarItemsDetector.stripLeadingTrackNumber("01 Amor"), "Amor")
        XCTAssertEqual(SimilarItemsDetector.stripLeadingTrackNumber("1. Amor"), "Amor")
        XCTAssertEqual(SimilarItemsDetector.stripLeadingTrackNumber("01 - Amor"), "Amor")
        XCTAssertEqual(SimilarItemsDetector.stripLeadingTrackNumber("1-01 Amor"), "Amor")
        XCTAssertEqual(SimilarItemsDetector.stripLeadingTrackNumber("Amor"), "Amor")
        XCTAssertEqual(SimilarItemsDetector.stripLeadingTrackNumber("2000 Light Years"), "2000 Light Years")
        // Un título que ES un número no se vacía.
        XCTAssertEqual(SimilarItemsDetector.stripLeadingTrackNumber("7"), "7")
    }

    func testNormalizedTitleExtractsVersionQualifiers() {
        let live = SimilarItemsDetector.normalizedTitle("Amor (En Vivo)")
        XCTAssertEqual(live.core, "amor")
        XCTAssertTrue(live.qualifiers.contains("vivo") || live.qualifiers.contains("envivo"))
        let plain = SimilarItemsDetector.normalizedTitle("01 Amór")
        XCTAssertEqual(plain.core, "amor")
        XCTAssertTrue(plain.qualifiers.isEmpty)
    }

    func testAlnumFoldsCaseDiacriticsAndPunctuation() {
        XCTAssertEqual(SimilarItemsDetector.alnum("Soda-Stereo"), "sodastereo")
        XCTAssertEqual(SimilarItemsDetector.alnum("SodaStereo"), "sodastereo")
        XCTAssertEqual(SimilarItemsDetector.alnum("Café Tacvba"), "cafetacvba")
    }

    func testNormalizedStemDropsCopySuffixes() {
        XCTAssertEqual(SimilarItemsDetector.normalizedStem(URL(fileURLWithPath: "/x/IMG_0001 copia.jpg")), "img0001")
        XCTAssertEqual(SimilarItemsDetector.normalizedStem(URL(fileURLWithPath: "/x/IMG_0001 (1).jpg")), "img0001")
        XCTAssertEqual(SimilarItemsDetector.normalizedStem(URL(fileURLWithPath: "/x/IMG_0001.jpg")), "img0001")
    }

    // MARK: - Detección

    func testOwnerExampleSodaStereoIsGrouped() throws {
        let a = song("01 Amor", artist: "SodaStereo", album: "Signos", duration: 200)
        let b = song("Amor", artist: "Soda-Stereo", album: "Signos", duration: 201)
        let c = song("De Música Ligera", artist: "Soda Stereo", album: "Canción Animal", duration: 213)
        let groups = SimilarItemsDetector.detect(in: [a, b, c], fileSize: { _ in 0 })
        XCTAssertEqual(groups.count, 1)
        let group = try XCTUnwrap(groups.first)
        XCTAssertEqual(Set(group.items.map(\.id)), [a.id, b.id])
        XCTAssertEqual(group.confidence, .duplicate, "misma duración ±2 s con título y artista equivalentes")
        XCTAssertTrue(group.reasons.contains { $0.contains("Artista escrito distinto") })
        XCTAssertTrue(group.reasons.contains { $0.contains("número de pista") })
        // Sugiere el título limpio para "01 Amor" y unificar el artista.
        XCTAssertTrue(group.proposedEdits.contains { $0.itemID == a.id && $0.field == .title && $0.proposedValue == "Amor" })
        XCTAssertTrue(group.proposedEdits.contains { $0.field == .artist })
        XCTAssertFalse(group.suggestion.isEmpty)
    }

    func testCanonicalArtistIsTheMostFrequentSpelling() {
        let items = [
            song("A", artist: "Soda Stereo"), song("B", artist: "Soda Stereo"), song("C", artist: "Soda Stereo"),
            song("D", artist: "SodaStereo"), song("E", artist: "Soda-Stereo"),
        ]
        XCTAssertEqual(SimilarItemsDetector.canonicalSpelling(of: "SodaStereo", in: items, field: .artist), "Soda Stereo")
    }

    func testLiveVersionIsOnlyPossible() {
        let studio = song("Amor", artist: "Soda Stereo", duration: 200)
        // Duración cercana (una versión en vivo muy distinta de largo se
        // descarta a propósito: ya no es "sospechosa").
        let live = song("Amor (En Vivo)", artist: "Soda Stereo", duration: 204)
        let groups = SimilarItemsDetector.detect(in: [studio, live], fileSize: { _ in 0 })
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.confidence, .possible)
        XCTAssertTrue(groups.first?.reasons.contains { $0.contains("otra versión") } ?? false)
    }

    func testDifferentDurationsAreNotGrouped() {
        let a = song("Amor", artist: "Soda Stereo", duration: 200)
        let b = song("Amor", artist: "Soda Stereo", duration: 320)
        XCTAssertTrue(SimilarItemsDetector.detect(in: [a, b], fileSize: { _ in 0 }).isEmpty)
    }

    func testUnrelatedSongsAreNotGrouped() {
        let a = song("Amor", artist: "Soda Stereo", duration: 200)
        let b = song("Amanecer", artist: "Soda Stereo", duration: 200)
        let c = song("Amor", artist: "Los Fabulosos Cadillacs", album: "Vasos Vacíos", duration: 200)
        XCTAssertTrue(SimilarItemsDetector.detect(in: [a, b, c], fileSize: { _ in 0 }).isEmpty)
    }

    func testSuggestsKeepingLosslessWithCover() {
        let mp3 = song("Amor", artist: "Soda Stereo", duration: 200, ext: "mp3")
        let flac = song("Amor", artist: "Soda Stereo", duration: 200, ext: "flac", cover: true)
        let groups = SimilarItemsDetector.detect(in: [mp3, flac], fileSize: { _ in 0 })
        XCTAssertEqual(groups.first?.suggestedKeepID, flac.id)
        XCTAssertEqual(groups.first?.items.first?.id, flac.id, "el sugerido va primero")
        XCTAssertTrue(groups.first?.suggestion.contains("FLAC") ?? false)
    }

    func testIgnoredGroupsAreHidden() {
        let a = song("Amor", artist: "Soda Stereo", duration: 200)
        let b = song("Amor", artist: "Soda Stereo", duration: 200)
        let first = SimilarItemsDetector.detect(in: [a, b], fileSize: { _ in 0 })
        XCTAssertEqual(first.count, 1)
        let hidden = SimilarItemsDetector.detect(in: [a, b], ignoredGroupIDs: [first[0].id], fileSize: { _ in 0 })
        XCTAssertTrue(hidden.isEmpty)
        XCTAssertEqual(first[0].id, SimilarItemsGroup.key(for: [b.id, a.id]), "id estable sin importar el orden")
    }

    func testPhotoCopiesWithSameSizeAreDuplicates() {
        let original = photo("IMG_0001.jpg")
        let copy = photo("IMG_0001 copia.jpg")
        let other = photo("IMG_0002.jpg")
        let sizeOf = sizes([original.id: 1000, copy.id: 1000, other.id: 999], items: [original, copy, other])
        let groups = SimilarItemsDetector.detect(in: [original, copy, other], fileSize: sizeOf)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].items.map(\.id)), [original.id, copy.id])
        XCTAssertEqual(groups[0].confidence, .duplicate)
    }

    func testSameEpisodeTwiceIsDuplicate() {
        var a = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/aura-tests/show-s01e01.mp4"))
        a.category = MediaCategory.series.displayName
        a.seriesName = "Show"; a.season = 1; a.episode = 1
        a.metadata = TrackMetadata(title: "Piloto", durationSeconds: 2500)
        var b = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/aura-tests/Show 1x01.mkv"))
        b.category = MediaCategory.series.displayName
        b.seriesName = "show"; b.season = 1; b.episode = 1
        b.metadata = TrackMetadata(title: "Pilot", durationSeconds: 2501)
        let groups = SimilarItemsDetector.detect(in: [a, b], fileSize: { _ in 0 })
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].confidence, .duplicate)
        XCTAssertTrue(groups[0].reasons.contains { $0.contains("Mismo episodio") })
    }

    func testLargeLibraryScansQuickly() {
        // Títulos variados (como una biblioteca real), no 3 000 que
        // empiecen igual -- eso derrota cualquier bloqueo por prefijo.
        let words = ["Amor", "Luna", "Sol", "Noche", "Cielo", "Mar", "Fuego", "Viento", "Sombra", "Luz",
                     "Camino", "Ciudad", "Tiempo", "Silencio", "Corazón", "Reina", "Rey", "Sueño", "Verano", "Lluvia"]
        var items: [AuraStudio.LibraryItem] = []
        for i in 0..<3000 {
            let title = "\(words[i % 20]) \(words[(i / 20) % 20]) \(i / 400)"
            items.append(song(title, artist: "Artista \(i % 50)", album: "Álbum \(i % 200)", duration: Double(100 + i % 300)))
        }
        items.append(song("01 Amor Amor 0", artist: "Artista 0", album: "Álbum 0", duration: 100))
        let start = Date()
        let groups = SimilarItemsDetector.detect(in: items, fileSize: { _ in 0 })
        let elapsed = Date().timeIntervalSince(start)
        // Compilación debug sin optimizar; en release es varias veces más rápido.
        XCTAssertLessThan(elapsed, 20, "3 000 canciones deben analizarse en segundos, tardó \(elapsed)")
        XCTAssertTrue(groups.contains { $0.items.contains { $0.metadata?.title == "01 Amor Amor 0" } })
    }

    // MARK: - Barra de estado

    func testMusicSummaryCountsArtistsAndAlbums() {
        let items = [
            song("A", artist: "Soda Stereo", album: "Signos", duration: 60),
            song("B", artist: "Soda Stereo", album: "Signos", duration: 60),
            song("C", artist: "Café Tacvba", album: "Re", duration: 60),
            song("D", artist: nil, album: nil, duration: 0),
        ]
        let summary = LibraryStats.music(items: items, selected: Array(items.prefix(2)))
        XCTAssertEqual(summary.total, "4 canciones · 2 artistas · 2 álbumes")
        XCTAssertEqual(summary.selection, "2 de 4 seleccionadas · 1 artista · 1 álbum · 2 min")
        XCTAssertEqual(summary.trailing, "3 min")
        XCTAssertNil(LibraryStats.music(items: items, selected: []).selection)
    }

    func testDurationTextFormats() {
        XCTAssertNil(LibraryStats.durationText(seconds: 0))
        XCTAssertEqual(LibraryStats.durationText(seconds: 45), "45 s")
        XCTAssertEqual(LibraryStats.durationText(seconds: 754), "12 min")
        XCTAssertEqual(LibraryStats.durationText(seconds: 3600 * 8 + 60 * 12), "8 h 12 min")
    }

    func testPluralization() {
        XCTAssertEqual(LibraryStats.count(1, "canción", "canciones"), "1 canción")
        XCTAssertEqual(LibraryStats.count(1500, "canción", "canciones"), "1,500 canciones")
    }
}
