import XCTest
@testable import AuraStudio

/// No existían pruebas de `GridSelection` antes de
/// PLAN-studio-rendimiento.md Fase 2 -- se agregan ahora, junto con el
/// cambio de API (`orderedIDs: [ID]` -> `order: GridOrder<ID>`, punto 2:
/// diccionario id→índice en vez de `firstIndex(of:)` O(N)) y la función
/// nueva `selectAll` (punto 1, Cmd+A).
final class GridSelectionTests: XCTestCase {
    private let order = GridOrder(["a", "b", "c", "d", "e"])

    func testPlainTapReplacesSelection() {
        var selection = GridSelection<String>()
        selection.handleTap("a", order: order, modifierFlags: [])
        selection.handleTap("c", order: order, modifierFlags: [])
        XCTAssertEqual(selection.selected, ["c"])
    }

    func testCommandTapTogglesWithoutReplacing() {
        var selection = GridSelection<String>()
        selection.handleTap("a", order: order, modifierFlags: [])
        selection.handleTap("c", order: order, modifierFlags: [.command])
        XCTAssertEqual(selection.selected, ["a", "c"])
        selection.handleTap("a", order: order, modifierFlags: [.command])
        XCTAssertEqual(selection.selected, ["c"])
    }

    func testShiftTapSelectsRangeFromLastTapped() {
        var selection = GridSelection<String>()
        selection.handleTap("b", order: order, modifierFlags: [])
        selection.handleTap("d", order: order, modifierFlags: [.shift])
        XCTAssertEqual(selection.selected, ["b", "c", "d"])
    }

    func testShiftTapBackwardsAlsoSelectsTheRange() {
        var selection = GridSelection<String>()
        selection.handleTap("d", order: order, modifierFlags: [])
        selection.handleTap("b", order: order, modifierFlags: [.shift])
        XCTAssertEqual(selection.selected, ["b", "c", "d"])
    }

    func testShiftTapWithoutAPreviousTapBehavesAsPlainTap() {
        var selection = GridSelection<String>()
        selection.handleTap("c", order: order, modifierFlags: [.shift])
        XCTAssertEqual(selection.selected, ["c"])
    }

    /// PLAN-studio-rendimiento.md Fase 2 punto 1: Cmd+A.
    func testSelectAllSelectsEveryVisibleID() {
        var selection = GridSelection<String>()
        selection.selectAll(order)
        XCTAssertEqual(selection.selected, Set(order.ids))
    }

    /// `selectAll` deja `lastTapped` en el último id visible -- un clic
    /// simple después de Cmd+A reemplaza toda la selección, igual que
    /// cualquier otro clic simple (no queda un "ancla" en un estado raro).
    func testPlainTapAfterSelectAllReplacesTheWholeSelection() {
        var selection = GridSelection<String>()
        selection.selectAll(order)
        XCTAssertEqual(selection.selected, Set(order.ids))
        selection.handleTap("b", order: order, modifierFlags: [])
        XCTAssertEqual(selection.selected, ["b"])
    }

    func testClearEmptiesSelectionAndForgetsLastTapped() {
        var selection = GridSelection<String>()
        selection.handleTap("a", order: order, modifierFlags: [])
        selection.clear()
        XCTAssertTrue(selection.selected.isEmpty)
        // Sin "último tocado", un Shift+clic se comporta como un clic simple.
        selection.handleTap("c", order: order, modifierFlags: [.shift])
        XCTAssertEqual(selection.selected, ["c"])
    }

    // MARK: - GridOrder

    func testGridOrderIndexLookupMatchesPosition() {
        XCTAssertEqual(order.index(of: "a"), 0)
        XCTAssertEqual(order.index(of: "e"), 4)
        XCTAssertNil(order.index(of: "z"))
    }

    func testGridOrderEqualityIsByIDSequence() {
        XCTAssertEqual(GridOrder(["a", "b"]), GridOrder(["a", "b"]))
        XCTAssertNotEqual(GridOrder(["a", "b"]), GridOrder(["b", "a"]))
    }

    func testEmptyGridOrderHasNoIndices() {
        let empty = GridOrder<String>.empty
        XCTAssertNil(empty.index(of: "a"))
        XCTAssertTrue(empty.ids.isEmpty)
    }
}
