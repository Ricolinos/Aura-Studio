import XCTest
@testable import AuraStudio

/// ST-019: columnas personalizables de la tabla de Canciones, criterio de
/// orden persistible y su ida y vuelta con los comparadores de `Table`.
@MainActor
final class MusicTableColumnTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "MusicTableColumnTests-\(UUID().uuidString)")!
    }

    // MARK: - Modelo

    func testEveryColumnBelongsToAGroupAndGroupsCoverAll() {
        let grouped = MusicTableColumn.Group.allCases.flatMap(\.columns)
        XCTAssertEqual(Set(grouped), Set(MusicTableColumn.allCases))
        XCTAssertEqual(grouped.count, MusicTableColumn.allCases.count, "ninguna columna en dos grupos")
    }

    func testDefaultVisibleColumnsMatchTheOldFixedTablePlusFavorite() {
        XCTAssertEqual(MusicTableColumn.defaultVisible, [.artist, .album, .genre, .duration, .favorite, .status])
    }

    func testLegacyExtraColumnsMigrateIntoVisibleColumns() {
        let migrated = MusicTableColumn.migratingLegacyExtraColumns("rating,year")
        XCTAssertEqual(migrated, MusicTableColumn.defaultVisible + [.rating, .year])
        XCTAssertEqual(MusicTableColumn.migratingLegacyExtraColumns(nil), MusicTableColumn.defaultVisible)
        XCTAssertEqual(MusicTableColumn.migratingLegacyExtraColumns("basura,fileSize"), MusicTableColumn.defaultVisible)
    }

    func testSortMenuFieldsAreAlphabeticalAndIncludeTitle() {
        let titles = MusicSortField.menuFields.map(\.title)
        XCTAssertEqual(titles, titles.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        XCTAssertTrue(MusicSortField.menuFields.contains(.title))
        XCTAssertTrue(MusicSortField.menuFields.contains(.column(.favorite)))
    }

    func testSortFieldRawValueRoundTrip() {
        for field in MusicSortField.menuFields {
            XCTAssertEqual(MusicSortField(rawValue: field.rawValue), field)
        }
        XCTAssertNil(MusicSortField(rawValue: "reproducciones"))
    }

    // MARK: - Comparadores <-> criterio

    func testEveryColumnComparatorMapsBackToItself() {
        for column in MusicTableColumn.allCases {
            let comparator = column.comparator(order: .reverse)
            XCTAssertEqual(comparator.order, .reverse)
            XCTAssertEqual(MusicSortField(keyPath: comparator.keyPath), .column(column), "\(column)")
        }
        let title = MusicSortField.title.comparator(order: .forward)
        XCTAssertEqual(MusicSortField(keyPath: title.keyPath), .title)
    }

    func testFavoriteComparatorPutsFavoritesFirstWhenAscending() {
        var plain = LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/a.mp3"))
        plain.metadata = TrackMetadata(title: "A")
        var loved = LibraryItem(sourceURL: URL(fileURLWithPath: "/tmp/b.mp3"))
        loved.metadata = TrackMetadata(title: "B", isFavorite: true)
        let rows = [MediaTableRow(item: plain), MediaTableRow(item: loved)]
        let sorted = rows.sorted(using: [MusicTableColumn.favorite.comparator(order: .forward)])
        XCTAssertEqual(sorted.map(\.title), ["B", "A"])
    }

    // MARK: - Preferencias

    func testPreferencesDefaults() {
        let prefs = AppPreferences(defaults: freshDefaults())
        XCTAssertEqual(prefs.musicVisibleColumns, MusicTableColumn.defaultVisible)
        XCTAssertEqual(prefs.musicSortField, .title)
        XCTAssertTrue(prefs.musicSortAscending)
        XCTAssertFalse(prefs.musicShowOnlyFavorites)
    }

    func testPreferencesPersistColumnsOrderSortAndFilter() {
        let defaults = freshDefaults()
        let prefs = AppPreferences(defaults: defaults)
        prefs.musicVisibleColumns = [.status, .albumArtist, .dateAdded]
        prefs.musicSortField = .column(.duration)
        prefs.musicSortAscending = false
        prefs.musicShowOnlyFavorites = true

        let reloaded = AppPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.musicVisibleColumns, [.status, .albumArtist, .dateAdded])
        XCTAssertEqual(reloaded.musicSortField, .column(.duration))
        XCTAssertFalse(reloaded.musicSortAscending)
        XCTAssertTrue(reloaded.musicShowOnlyFavorites)
    }

    func testEmptyColumnListIsRespectedNotResetToDefaults() {
        let defaults = freshDefaults()
        let prefs = AppPreferences(defaults: defaults)
        prefs.musicVisibleColumns = []
        XCTAssertEqual(AppPreferences(defaults: defaults).musicVisibleColumns, [])
    }

    func testToggleColumnAppendsAtEndAndRemovesInPlace() {
        let prefs = AppPreferences(defaults: freshDefaults())
        prefs.toggleMusicColumn(.composer)
        XCTAssertEqual(prefs.musicVisibleColumns.last, .composer)
        prefs.toggleMusicColumn(.album)
        XCTAssertFalse(prefs.musicVisibleColumns.contains(.album))
        XCTAssertEqual(prefs.musicVisibleColumns.first, .artist, "quitar no reordena el resto")
    }

    func testLegacyPlusMenuKeyIsMigratedOnFirstLoad() {
        let defaults = freshDefaults()
        defaults.set("trackNumber,rating", forKey: "aura.visibleColumns.music")
        let prefs = AppPreferences(defaults: defaults)
        XCTAssertEqual(prefs.musicVisibleColumns, MusicTableColumn.defaultVisible + [.trackNumber, .rating])
    }
}
