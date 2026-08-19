import XCTest
@testable import AuraStudio

/// PLAN-biblioteca-medios-v2.md §3.3/§3.4: `seriesName`/`season`/
/// `episode` (Series) y `photoAlbum` (álbumes de fotos, solo local) --
/// opcionales por la misma razón que el resto de `PersistedLibraryItem`
/// (ver `LibraryPersistenceFavoriteTests`): un catálogo guardado antes
/// de estos campos no los tiene, y no debe dejar de decodificar.
final class LibraryPersistenceSeriesAlbumFieldsTests: XCTestCase {
    func testCatalogWithoutNewFieldsStillDecodes() throws {
        let json = """
        {"items":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","sourceRelativePath":"Videos/a.mpg","kind":"video","status":"ready"}],"playlists":[]}
        """
        let library = try JSONDecoder().decode(PersistedLibrary.self, from: Data(json.utf8))
        XCTAssertEqual(library.items.count, 1)
        XCTAssertNil(library.items[0].seriesName)
        XCTAssertNil(library.items[0].season)
        XCTAssertNil(library.items[0].episode)
        XCTAssertNil(library.items[0].photoAlbum)
    }

    func testNewFieldsRoundTripThroughEncoding() throws {
        let persisted = PersistedLibraryItem(
            id: UUID(), sourceRelativePath: "Videos/a.mpg", kind: "video", status: "ready",
            seriesName: "Mi Serie", season: 1, episode: 2, photoAlbum: nil)

        let data = try JSONEncoder().encode(PersistedLibrary(items: [persisted], playlists: []))
        let decoded = try JSONDecoder().decode(PersistedLibrary.self, from: data)

        XCTAssertEqual(decoded.items[0].seriesName, "Mi Serie")
        XCTAssertEqual(decoded.items[0].season, 1)
        XCTAssertEqual(decoded.items[0].episode, 2)
    }

    func testPhotoAlbumRoundTripsThroughEncoding() throws {
        let persisted = PersistedLibraryItem(
            id: UUID(), sourceRelativePath: "Imágenes/a.jpg", kind: "photo", status: "ready",
            photoAlbum: "Vacaciones 2026")

        let data = try JSONEncoder().encode(PersistedLibrary(items: [persisted], playlists: []))
        let decoded = try JSONDecoder().decode(PersistedLibrary.self, from: data)

        XCTAssertEqual(decoded.items[0].photoAlbum, "Vacaciones 2026")
        XCTAssertNil(decoded.items[0].seriesName)
    }

    func testLibraryItemDefaultsNewFieldsToNil() {
        let item = LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/x.mkv"))
        XCTAssertNil(item.seriesName)
        XCTAssertNil(item.season)
        XCTAssertNil(item.episode)
        XCTAssertNil(item.photoAlbum)
    }
}
