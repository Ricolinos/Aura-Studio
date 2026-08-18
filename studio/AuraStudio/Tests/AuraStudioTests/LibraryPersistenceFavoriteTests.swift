import XCTest
@testable import AuraStudio

/// ST-019: `isFavorite`, `discNumber` y `addedAt` viajan al catalogo y
/// vuelven; un catalogo anterior a esos campos sigue decodificando.
final class LibraryPersistenceFavoriteTests: XCTestCase {
    func testFavoriteAndDiscNumberRoundTripThroughMapper() {
        let live = TrackMetadata(title: "T", trackNumber: 3, isFavorite: true, discNumber: 2)
        let persisted = LibraryPersistenceMapper.persistedMetadata(live)
        XCTAssertEqual(persisted?.isFavorite, true)
        XCTAssertEqual(persisted?.discNumber, 2)
        let back = LibraryPersistenceMapper.liveMetadata(persisted, coverArtData: nil)
        XCTAssertEqual(back?.isFavorite, true)
        XCTAssertEqual(back?.discNumber, 2)
    }

    func testNotFavoriteIsOmittedFromCatalog() {
        let persisted = LibraryPersistenceMapper.persistedMetadata(TrackMetadata(title: "T"))
        XCTAssertNil(persisted?.isFavorite, "false no se escribe: catalogo mas chico y mismo significado que ausente")
        XCTAssertEqual(LibraryPersistenceMapper.liveMetadata(persisted, coverArtData: nil)?.isFavorite, false)
    }

    func testCatalogWithoutNewKeysStillDecodes() throws {
        let json = """
        {"items":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","sourceRelativePath":"Música/a.mp3","kind":"music","status":"ready","metadata":{"title":"Vieja"}}],"playlists":[]}
        """
        let library = try JSONDecoder().decode(PersistedLibrary.self, from: Data(json.utf8))
        XCTAssertEqual(library.items.count, 1)
        XCTAssertNil(library.items[0].addedAt)
        XCTAssertNil(library.items[0].metadata?.isFavorite)
        XCTAssertEqual(LibraryPersistenceMapper.liveMetadata(library.items[0].metadata, coverArtData: nil)?.isFavorite, false)
    }

    func testNewItemsRecordWhenTheyWereAdded() {
        let item = LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/x.mp3"))
        XCTAssertNotNil(item.addedAt)
    }
}
