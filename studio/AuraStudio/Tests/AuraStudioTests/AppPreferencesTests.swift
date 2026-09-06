import XCTest
@testable import AuraStudio

/// D-192: defaults nuevos de AppPreferences y que persistan/recarguen
/// bien desde UserDefaults. `UserDefaults(suiteName:)` aislado por test
/// (mismo patron que el resto de la suite para no tocar el
/// UserDefaults.standard real de quien corre los tests).
@MainActor
final class AppPreferencesTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        // ST-194: la suite se borra al terminar la prueba.
        makeIsolatedDefaults("AppPreferencesTests")
    }

    func testDefaultLibraryFolderPathIsUnderDocuments() {
        XCTAssertTrue(AppPreferences.defaultLibraryFolderPath.contains("/Documents/Aura Library"))
    }

    func testDefaultsMatchOwnerSpec() {
        let prefs = AppPreferences(defaults: freshDefaults())
        XCTAssertTrue(prefs.copyMediaIntoLibrary)
        XCTAssertEqual(prefs.musicOrganization, .artistAlbum)
        XCTAssertEqual(prefs.musicFilenameFormat, .titleOnly)
        XCTAssertEqual(prefs.audioQuality, .originalLossless)
        XCTAssertEqual(prefs.photoQuality, .optimized)
        XCTAssertTrue(prefs.organizePhotosByCategory)
        XCTAssertTrue(prefs.organizeVideosByCategory)
        XCTAssertEqual(prefs.coverArtProviderOrder, [.coverArtArchive, .fanartTV, .deezer])
        XCTAssertTrue(prefs.deezerEnabled)
    }

    func testPhotoQualityMaxDimensions() {
        XCTAssertEqual(AppPreferences.PhotoQuality.optimized.maxDimension, 320)
        XCTAssertEqual(AppPreferences.PhotoQuality.hd.maxDimension, 640)
    }

    func testLinkedLibraryFoldersDefaultsToEmpty() {
        let prefs = AppPreferences(defaults: freshDefaults())
        XCTAssertTrue(prefs.linkedLibraryFolders.isEmpty)
    }

    func testAddLinkedLibraryFolderDedupsByPath() {
        let prefs = AppPreferences(defaults: freshDefaults())
        let url = URL(fileURLWithPath: "/Users/test/Music External")

        prefs.addLinkedLibraryFolder(url)
        prefs.addLinkedLibraryFolder(url)

        XCTAssertEqual(prefs.linkedLibraryFolders, [url.standardizedFileURL.path])
    }

    func testAddLinkedLibraryFolderKeepsInsertionOrderForDistinctPaths() {
        let prefs = AppPreferences(defaults: freshDefaults())
        let first = URL(fileURLWithPath: "/Volumes/External/A")
        let second = URL(fileURLWithPath: "/Volumes/External/B")

        prefs.addLinkedLibraryFolder(first)
        prefs.addLinkedLibraryFolder(second)

        XCTAssertEqual(prefs.linkedLibraryFolders, [first.standardizedFileURL.path, second.standardizedFileURL.path])
    }

    func testRemoveLinkedLibraryFolderRemovesOnlyThatPath() {
        let prefs = AppPreferences(defaults: freshDefaults())
        let first = URL(fileURLWithPath: "/Volumes/External/A")
        let second = URL(fileURLWithPath: "/Volumes/External/B")
        prefs.addLinkedLibraryFolder(first)
        prefs.addLinkedLibraryFolder(second)

        prefs.removeLinkedLibraryFolder(first.standardizedFileURL.path)

        XCTAssertEqual(prefs.linkedLibraryFolders, [second.standardizedFileURL.path])
    }

    func testLinkedLibraryFoldersPersistAcrossInstancesWithSameDefaults() {
        let defaults = freshDefaults()
        let first = AppPreferences(defaults: defaults)
        first.addLinkedLibraryFolder(URL(fileURLWithPath: "/Volumes/External/Musica"))

        let second = AppPreferences(defaults: defaults)
        XCTAssertEqual(second.linkedLibraryFolders, [URL(fileURLWithPath: "/Volumes/External/Musica").standardizedFileURL.path])
    }

    /// A diferencia de `photoCollections` (nombres cortos, sin coma
    /// real nunca), una ruta de carpeta SÍ puede traer una coma en el
    /// nombre -- persistir esta lista como arreglo nativo de
    /// `UserDefaults` (no una lista separada por comas) evita que ese
    /// caso real corrompa la lista al releerla.
    func testLinkedLibraryFolderWithCommaInPathSurvivesRoundTrip() {
        let defaults = freshDefaults()
        let path = "/Volumes/External/Música, respaldo 2024"
        let first = AppPreferences(defaults: defaults)
        first.addLinkedLibraryFolder(URL(fileURLWithPath: path))

        let second = AppPreferences(defaults: defaults)
        XCTAssertEqual(second.linkedLibraryFolders, [URL(fileURLWithPath: path).standardizedFileURL.path])
    }

    func testChangedValuesPersistAcrossInstancesWithSameDefaults() {
        let defaults = freshDefaults()
        let first = AppPreferences(defaults: defaults)
        first.copyMediaIntoLibrary = false
        first.musicOrganization = .album
        first.musicFilenameFormat = .titleArtist
        first.audioQuality = .compressed
        first.photoQuality = .hd
        first.organizePhotosByCategory = false
        first.organizeVideosByCategory = false
        first.coverArtProviderOrder = [.deezer, .coverArtArchive, .fanartTV]
        first.deezerEnabled = false

        let second = AppPreferences(defaults: defaults)
        XCTAssertFalse(second.copyMediaIntoLibrary)
        XCTAssertEqual(second.musicOrganization, .album)
        XCTAssertEqual(second.musicFilenameFormat, .titleArtist)
        XCTAssertEqual(second.audioQuality, .compressed)
        XCTAssertEqual(second.photoQuality, .hd)
        XCTAssertFalse(second.organizePhotosByCategory)
        XCTAssertFalse(second.organizeVideosByCategory)
        XCTAssertEqual(second.coverArtProviderOrder, [.deezer, .coverArtArchive, .fanartTV])
        XCTAssertFalse(second.deezerEnabled)
    }
}
