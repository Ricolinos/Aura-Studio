import XCTest
@testable import AuraStudio

/// ST-262: los filtros de "pendientes" de albumes y canciones -- logica
/// pura, sin vistas.
final class LibraryPendingFilterTests: XCTestCase {

    // MARK: - Utilidades

    private func song(artist: String? = "Artista", album: String? = "Album",
                      year: String? = "2001", lyrics: String? = "la la",
                      withCover: Bool = true) -> AuraStudio.LibraryItem {
        var item = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/cancion.mp3"))
        item.metadata = TrackMetadata(
            title: "Cancion", artist: artist, album: album, year: year,
            coverURL: withCover ? URL(fileURLWithPath: "/tmp/caratula.jpg") : nil,
            syncedLyrics: lyrics)
        return item
    }

    private func group(title: String = "Album", year: String? = "2001",
                       genre: String? = "Rock", withCover: Bool = true,
                       isUnknown: Bool = false) -> AlbumGroup {
        AlbumGroup(id: "clave-\(title)", title: title, artist: "Artista",
                   items: [song()],
                   coverURL: withCover ? URL(fileURLWithPath: "/tmp/caratula.jpg") : nil,
                   coverHash: withCover ? "HASH" : nil,
                   coverPendingData: nil,
                   year: year, genre: genre, isUnknown: isUnknown)
    }

    // MARK: - AlbumPendingFilter

    func testAllMatchesEverythingIncludingUnknown() {
        XCTAssertTrue(AlbumPendingFilter.all.matches(group()))
        XCTAssertTrue(AlbumPendingFilter.all.matches(group(isUnknown: true)))
    }

    func testMissingCoverUsesTheGroupCover() {
        XCTAssertTrue(AlbumPendingFilter.missingCover.matches(group(withCover: false)))
        XCTAssertFalse(AlbumPendingFilter.missingCover.matches(group(withCover: true)))
    }

    func testMissingCoverIgnoresTheUnknownGroup() {
        // "Sin album" nunca tiene caratula de grupo y ninguna
        // herramienta de albumes puede arreglarlo: no es un pendiente.
        XCTAssertFalse(AlbumPendingFilter.missingCover.matches(group(withCover: false, isUnknown: true)))
    }

    func testMissingYearTreatsBlankAsMissing() {
        XCTAssertTrue(AlbumPendingFilter.missingYear.matches(group(year: nil)))
        XCTAssertTrue(AlbumPendingFilter.missingYear.matches(group(year: "  ")))
        XCTAssertFalse(AlbumPendingFilter.missingYear.matches(group(year: "2001")))
        XCTAssertFalse(AlbumPendingFilter.missingYear.matches(group(year: nil, isUnknown: true)))
    }

    func testMissingGenreTreatsBlankAsMissing() {
        XCTAssertTrue(AlbumPendingFilter.missingGenre.matches(group(genre: nil)))
        XCTAssertTrue(AlbumPendingFilter.missingGenre.matches(group(genre: " ")))
        XCTAssertFalse(AlbumPendingFilter.missingGenre.matches(group(genre: "Rock")))
    }

    // MARK: - SongPendingFilter

    func testSongAllMatchesEverything() {
        XCTAssertTrue(SongPendingFilter.all.matches(song()))
        XCTAssertTrue(SongPendingFilter.all.matches(AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/x.mp3"))))
    }

    func testSongMissingCover() {
        XCTAssertTrue(SongPendingFilter.missingCover.matches(song(withCover: false)))
        XCTAssertFalse(SongPendingFilter.missingCover.matches(song(withCover: true)))
        // Sin metadata alguna tambien cuenta como pendiente.
        XCTAssertTrue(SongPendingFilter.missingCover.matches(AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/x.mp3"))))
    }

    func testSongMissingArtistAndAlbumAndYear() {
        XCTAssertTrue(SongPendingFilter.missingArtist.matches(song(artist: nil)))
        XCTAssertTrue(SongPendingFilter.missingArtist.matches(song(artist: " ")))
        XCTAssertFalse(SongPendingFilter.missingArtist.matches(song()))

        XCTAssertTrue(SongPendingFilter.missingAlbum.matches(song(album: nil)))
        XCTAssertFalse(SongPendingFilter.missingAlbum.matches(song()))

        XCTAssertTrue(SongPendingFilter.missingYear.matches(song(year: nil)))
        XCTAssertFalse(SongPendingFilter.missingYear.matches(song()))
    }

    func testSongMissingLyrics() {
        XCTAssertTrue(SongPendingFilter.missingLyrics.matches(song(lyrics: nil)))
        XCTAssertTrue(SongPendingFilter.missingLyrics.matches(song(lyrics: "")))
        XCTAssertFalse(SongPendingFilter.missingLyrics.matches(song()))
    }

    func testPendingFiltersArePersistableByRawValue() {
        // Las vistas guardan el rawValue en @AppStorage: todos los
        // casos tienen que hacer el viaje ida y vuelta.
        for f in AlbumPendingFilter.allCases {
            XCTAssertEqual(AlbumPendingFilter(rawValue: f.rawValue), f)
        }
        for f in SongPendingFilter.allCases {
            XCTAssertEqual(SongPendingFilter(rawValue: f.rawValue), f)
        }
    }
}
