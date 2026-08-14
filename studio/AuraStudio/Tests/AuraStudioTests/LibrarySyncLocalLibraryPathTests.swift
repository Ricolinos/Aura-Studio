import XCTest
@testable import AuraStudio

/// D-228: `LibrarySync.localLibraryRelativePath` -- la ruta dentro de la
/// carpeta LOCAL de la biblioteca (Finder), probada como funcion pura
/// (sin tocar disco), igual que su hermana `musicDestinationRelativePath`
/// en `LibrarySyncMusicPathTests`.
final class LibrarySyncLocalLibraryPathTests: XCTestCase {
    private func musicItem(title: String? = nil, artist: String? = nil, album: String? = nil,
                            albumArtist: String? = nil) -> AuraStudio.LibraryItem {
        var item = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/original.mp3"))
        item.metadata = TrackMetadata(title: title, artist: artist, album: album, albumArtist: albumArtist)
        return item
    }

    private func categorizedItem(kind: LibraryItemKind, category: String?, sourceName: String = "file.jpg") -> AuraStudio.LibraryItem {
        var item = AuraStudio.LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/\(sourceName)"))
        item.category = category
        return item
    }

    // MARK: - Musica

    func testMusicGoesUnderArtistAlbumWithOriginalFileName() {
        let item = musicItem(title: "Bohemian Rhapsody", artist: "Queen", album: "A Night at the Opera")
        XCTAssertEqual(
            LibrarySync.localLibraryRelativePath(for: item, kind: .music, fileName: "original file name.flac"),
            "Música/Queen/A Night at the Opera/original file name.flac")
    }

    func testMusicMissingMetadataFallsBackToDesconocido() {
        let item = musicItem()
        XCTAssertEqual(
            LibrarySync.localLibraryRelativePath(for: item, kind: .music, fileName: "track07.mp3"),
            "Música/Desconocido/Desconocido/track07.mp3")
    }

    func testMusicIllegalCharactersInMetadataAreSanitized() {
        let item = musicItem(artist: "AC/DC", album: "Live: 1996")
        XCTAssertEqual(
            LibrarySync.localLibraryRelativePath(for: item, kind: .music, fileName: "song.mp3"),
            "Música/AC_DC/Live_ 1996/song.mp3")
    }

    func testMusicAlbumArtistTakesPrecedenceOverTrackArtist() {
        let item = musicItem(artist: "Featured Guest", album: "Compilation", albumArtist: "Various Artists")
        XCTAssertEqual(
            LibrarySync.localLibraryRelativePath(for: item, kind: .music, fileName: "track.mp3"),
            "Música/Various Artists/Compilation/track.mp3")
    }

    // MARK: - Fotos

    func testPhotoWithCategoryAndOrganizationOnGoesUnderCollectionFolder() {
        let item = categorizedItem(kind: .photo, category: "Fotos")
        XCTAssertEqual(
            LibrarySync.localLibraryRelativePath(for: item, kind: .photo, fileName: "IMG_001.heic", organizePhotosByCategory: true),
            "Imágenes/Fotos/IMG_001.heic")
    }

    func testPhotoWithOrganizationOffStaysFlat() {
        let item = categorizedItem(kind: .photo, category: "Fotos")
        XCTAssertEqual(
            LibrarySync.localLibraryRelativePath(for: item, kind: .photo, fileName: "IMG_001.heic", organizePhotosByCategory: false),
            "Imágenes/IMG_001.heic")
    }

    func testPhotoWithoutCategoryStaysFlatEvenWithOrganizationOn() {
        let item = categorizedItem(kind: .photo, category: nil)
        XCTAssertEqual(
            LibrarySync.localLibraryRelativePath(for: item, kind: .photo, fileName: "IMG_002.heic", organizePhotosByCategory: true),
            "Imágenes/IMG_002.heic")
    }

    // MARK: - Video

    func testVideoWithCategoryAndOrganizationOnGoesUnderCategoryFolder() {
        let item = categorizedItem(kind: .video, category: "Series")
        XCTAssertEqual(
            LibrarySync.localLibraryRelativePath(for: item, kind: .video, fileName: "clip.mov", organizeVideosByCategory: true),
            "Videos/Series/clip.mov")
    }

    func testVideoWithOrganizationOffStaysFlat() {
        let item = categorizedItem(kind: .video, category: "Series")
        XCTAssertEqual(
            LibrarySync.localLibraryRelativePath(for: item, kind: .video, fileName: "clip.mov", organizeVideosByCategory: false),
            "Videos/clip.mov")
    }
}
