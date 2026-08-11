import XCTest
@testable import AuraStudio

/// Fase 24: la ruta jerarquica Music/<Artista>/<Album>/NN Titulo.ext,
/// probada como funcion pura (sin tocar disco ni un iPod).
final class LibrarySyncMusicPathTests: XCTestCase {
    private func item(title: String? = nil, artist: String? = nil, album: String? = nil,
                       albumArtist: String? = nil, trackNumber: Int? = nil,
                       sourceName: String = "song.mp3") -> AuraStudio.LibraryItem {
        var libraryItem = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/\(sourceName)"))
        libraryItem.metadata = TrackMetadata(title: title, artist: artist, album: album,
                                              albumArtist: albumArtist, trackNumber: trackNumber)
        libraryItem.preparedURL = URL(fileURLWithPath: "/staging/\(sourceName)")
        return libraryItem
    }

    func testFullMetadataProducesHierarchicalPathWithTrackNumber() {
        let libraryItem = item(title: "Bohemian Rhapsody", artist: "Queen", album: "A Night at the Opera", trackNumber: 11)
        XCTAssertEqual(LibrarySync.musicDestinationRelativePath(for: libraryItem),
                        "Music/Queen/A Night at the Opera/11 Bohemian Rhapsody.mp3")
    }

    func testAlbumArtistTakesPrecedenceOverTrackArtist() {
        let libraryItem = item(title: "Track", artist: "Featured Guest", album: "Compilation", albumArtist: "Various Artists")
        XCTAssertEqual(LibrarySync.musicDestinationRelativePath(for: libraryItem),
                        "Music/Various Artists/Compilation/Track.mp3")
    }

    func testMissingTrackNumberOmitsPrefix() {
        let libraryItem = item(title: "Intro", artist: "Artist", album: "Album")
        XCTAssertEqual(LibrarySync.musicDestinationRelativePath(for: libraryItem),
                        "Music/Artist/Album/Intro.mp3")
    }

    func testMissingMetadataFallsBackToFilenameAndDesconocido() {
        let libraryItem = item(sourceName: "track07.mp3")
        XCTAssertEqual(LibrarySync.musicDestinationRelativePath(for: libraryItem),
                        "Music/Desconocido/Desconocido/track07.mp3")
    }

    func testIllegalCharactersInMetadataAreSanitized() {
        let libraryItem = item(title: "Live at O2", artist: "AC/DC", album: "Live: 1996")
        XCTAssertEqual(LibrarySync.musicDestinationRelativePath(for: libraryItem),
                        "Music/AC_DC/Live_ 1996/Live at O2.mp3")
    }
}
