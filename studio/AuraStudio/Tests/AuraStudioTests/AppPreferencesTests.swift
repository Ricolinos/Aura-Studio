import XCTest
@testable import AuraStudio

/// D-192: defaults nuevos de AppPreferences y que persistan/recarguen
/// bien desde UserDefaults. `UserDefaults(suiteName:)` aislado por test
/// (mismo patron que el resto de la suite para no tocar el
/// UserDefaults.standard real de quien corre los tests).
@MainActor
final class AppPreferencesTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let suiteName = "AppPreferencesTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
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
