import XCTest
@testable import AuraStudio

/// D-193: parseo puro de M3U/M3U8 importado desde otro programa --
/// sin tocar disco (resolver contra el catalogo real es responsabilidad
/// de `LibraryViewModel.importPlaylist`, no de este parser).
final class PlaylistImporterTests: XCTestCase {
    private let playlistDir = URL(fileURLWithPath: "/Users/test/Music")

    func testIgnoresCommentsAndBlankLines() {
        let contents = """
        #EXTM3U
        #EXTINF:355,Queen - Bohemian Rhapsody
        /Users/test/Music/Queen/Bohemian Rhapsody.mp3

        #EXTINF:180,Other - Song
        /Users/test/Music/Other/Song.mp3
        """
        let paths = PlaylistImporter.parseTrackPaths(contents: contents, playlistDirectory: playlistDir)
        XCTAssertEqual(paths, [
            "/Users/test/Music/Queen/Bohemian Rhapsody.mp3",
            "/Users/test/Music/Other/Song.mp3",
        ])
    }

    func testAbsolutePathsPassThroughUnchanged() {
        let contents = "/Volumes/External/song.flac"
        XCTAssertEqual(PlaylistImporter.parseTrackPaths(contents: contents, playlistDirectory: playlistDir),
                        ["/Volumes/External/song.flac"])
    }

    func testRelativePathsResolveAgainstPlaylistDirectory() {
        let contents = "Queen/Bohemian Rhapsody.mp3"
        XCTAssertEqual(PlaylistImporter.parseTrackPaths(contents: contents, playlistDirectory: playlistDir),
                        ["/Users/test/Music/Queen/Bohemian Rhapsody.mp3"])
    }

    func testFileURLLinesResolveToPlainPaths() {
        let contents = "file:///Users/test/Music/song.mp3"
        XCTAssertEqual(PlaylistImporter.parseTrackPaths(contents: contents, playlistDirectory: playlistDir),
                        ["/Users/test/Music/song.mp3"])
    }

    func testSuggestedNameStripsExtension() {
        let url = URL(fileURLWithPath: "/Users/test/Downloads/Road Trip.m3u8")
        XCTAssertEqual(PlaylistImporter.suggestedName(for: url), "Road Trip")
    }

    func testEmptyContentsProducesNoTracks() {
        XCTAssertTrue(PlaylistImporter.parseTrackPaths(contents: "", playlistDirectory: playlistDir).isEmpty)
        XCTAssertTrue(PlaylistImporter.parseTrackPaths(contents: "#EXTM3U\n", playlistDirectory: playlistDir).isEmpty)
    }
}
