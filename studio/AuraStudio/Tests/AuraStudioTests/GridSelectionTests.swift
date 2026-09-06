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

    // MARK: - F4 (ST-184): el núcleo puro de la selección tipo Finder

    private let manyOrder = GridOrder((1...20).map { "t\($0)" })

    /// El caso que "experto en código opus" señaló como el más valioso de
    /// F4 -- Shift+clic ya no acumula (`formUnion`), reemplaza el rango
    /// anterior CONSERVANDO lo marcado aparte con ⌘: ⌘+clic en tres
    /// sueltos, clic simple en 10, Shift+clic en 20, Shift+clic en 15 →
    /// deben quedar los tres sueltos más 10-15, no 10-20.
    func testShiftClickReplacesThePreviousRangeButKeepsCommandClickedItems() {
        var selection = GridSelection<String>()
        selection.handleTap("t1", order: manyOrder, modifiers: [.command])
        selection.handleTap("t2", order: manyOrder, modifiers: [.command])
        selection.handleTap("t3", order: manyOrder, modifiers: [.command])
        // ⌘+clic también en el 10 -- fija el ancla del rango SIN
        // reemplazar la selección (un clic simple sí la reemplazaría,
        // perdiendo t1/t2/t3; no es el gesto que describe este escenario).
        selection.handleTap("t10", order: manyOrder, modifiers: [.command])
        selection.handleTap("t20", order: manyOrder, modifiers: [.shift])
        XCTAssertEqual(selection.selected, Set(["t1", "t2", "t3"] + (10...20).map { "t\($0)" }))

        selection.handleTap("t15", order: manyOrder, modifiers: [.shift])
        XCTAssertEqual(selection.selected, Set(["t1", "t2", "t3"] + (10...15).map { "t\($0)" }),
                       "el segundo Shift+clic debe ACHICAR el rango, no sumarse al anterior")
    }

    /// Un clic simple (o ⌘+clic, o la casilla) reubica el ancla -- el
    /// siguiente Shift+clic arma un rango nuevo desde ahí, no desde donde
    /// empezó el rango viejo.
    func testPlainTapAfterARangeMovesTheAnchor() {
        var selection = GridSelection<String>()
        selection.handleTap("t5", order: manyOrder, modifiers: [])
        selection.handleTap("t10", order: manyOrder, modifiers: [.shift])
        XCTAssertEqual(selection.selected, Set((5...10).map { "t\($0)" }))

        selection.handleTap("t15", order: manyOrder, modifiers: [])
        XCTAssertEqual(selection.selected, ["t15"])
        selection.handleTap("t18", order: manyOrder, modifiers: [.shift])
        XCTAssertEqual(selection.selected, Set((15...18).map { "t\($0)" }))
    }

    func testLastTappedIsPubliclyReadable() {
        var selection = GridSelection<String>()
        XCTAssertNil(selection.lastTapped)
        selection.handleTap("t3", order: manyOrder, modifiers: [])
        XCTAssertEqual(selection.lastTapped, "t3")
    }

    // MARK: - F4: flechas (`move`)

    func testArrowWithNoFocusSelectsFirstOrLastDependingOnDirection() {
        var selection = GridSelection<String>()
        let id = selection.move(.right, order: manyOrder, columnsPerRow: 5, extending: false)
        XCTAssertEqual(id, "t1")
        XCTAssertEqual(selection.selected, ["t1"])

        var backwards = GridSelection<String>()
        let last = backwards.move(.left, order: manyOrder, columnsPerRow: 5, extending: false)
        XCTAssertEqual(last, "t20")
    }

    func testArrowRightMovesFocusByOne() {
        var selection = GridSelection<String>()
        selection.handleTap("t3", order: manyOrder, modifiers: [])
        let id = selection.move(.right, order: manyOrder, columnsPerRow: 5, extending: false)
        XCTAssertEqual(id, "t4")
        XCTAssertEqual(selection.selected, ["t4"], "sin Shift, la flecha REEMPLAZA la selección")
    }

    func testArrowDownJumpsAFullRow() {
        var selection = GridSelection<String>()
        selection.handleTap("t3", order: manyOrder, modifiers: [])
        let id = selection.move(.down, order: manyOrder, columnsPerRow: 5, extending: false)
        XCTAssertEqual(id, "t8", "con 5 columnas por fila, abajo salta 5 posiciones")
    }

    func testArrowClampsAtTheEdgesOfTheOrder() {
        var selection = GridSelection<String>()
        selection.handleTap("t1", order: manyOrder, modifiers: [])
        let id = selection.move(.left, order: manyOrder, columnsPerRow: 5, extending: false)
        XCTAssertEqual(id, "t1", "no hay adónde ir más allá del primero")
    }

    func testShiftArrowExtendsFromTheAnchorAndIsReversible() {
        var selection = GridSelection<String>()
        selection.handleTap("t5", order: manyOrder, modifiers: [])
        selection.move(.right, order: manyOrder, columnsPerRow: 5, extending: true)
        selection.move(.right, order: manyOrder, columnsPerRow: 5, extending: true)
        XCTAssertEqual(selection.selected, Set((5...7).map { "t\($0)" }))

        // Retroceder con Shift+flecha debe ACHICAR el rango, no sumarse.
        selection.move(.left, order: manyOrder, columnsPerRow: 5, extending: true)
        XCTAssertEqual(selection.selected, Set((5...6).map { "t\($0)" }))
    }

    func testMoveOnEmptyOrderReturnsNil() {
        var selection = GridSelection<String>()
        XCTAssertNil(selection.move(.right, order: GridOrder<String>.empty, columnsPerRow: 5, extending: false))
    }

    // MARK: - F4: arrastre (`applyMarquee`)

    func testApplyMarqueeWithNoModifiersReplacesSelection() {
        var selection = GridSelection<String>()
        selection.handleTap("t1", order: manyOrder, modifiers: [])
        selection.applyMarquee(rect: CGRect(x: 0, y: 0, width: 10, height: 10),
                               frames: [.init(id: "t5", rect: CGRect(x: 1, y: 1, width: 2, height: 2))],
                               base: selection.selected, modifiers: [])
        XCTAssertEqual(selection.selected, ["t5"])
    }

    func testApplyMarqueeWithShiftAddsToBase() {
        var selection = GridSelection<String>()
        let base: Set<String> = ["t1"]
        selection.applyMarquee(rect: CGRect(x: 0, y: 0, width: 10, height: 10),
                               frames: [.init(id: "t5", rect: CGRect(x: 1, y: 1, width: 2, height: 2))],
                               base: base, modifiers: [.shift])
        XCTAssertEqual(selection.selected, ["t1", "t5"])
    }

    // MARK: - F4: `GridMarquee` (núcleo puro del arrastre)

    func testMarqueeRectNormalizesAnyDragDirection() {
        let downRight = GridMarquee.rect(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 10, y: 20))
        let upLeft = GridMarquee.rect(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 0, y: 0))
        XCTAssertEqual(downRight, CGRect(x: 0, y: 0, width: 10, height: 20))
        XCTAssertEqual(upLeft, downRight, "el rectángulo es el mismo sin importar la dirección del arrastre")
    }

    func testMarqueeHitsOnlyTouchedFrames() {
        let frames = [
            GridMarquee.Frame(id: "a", rect: CGRect(x: 0, y: 0, width: 10, height: 10)),
            GridMarquee.Frame(id: "b", rect: CGRect(x: 100, y: 100, width: 10, height: 10)),
        ]
        let hits = GridMarquee.hits(in: CGRect(x: 0, y: 0, width: 20, height: 20), frames: frames)
        XCTAssertEqual(hits, ["a"])
    }

    func testMarqueeTouchingIsEnoughNoNeedToFullyContain() {
        // Roza la esquina de "a" (que va de 0,0 a 10,10) sin contenerla.
        let frames = [GridMarquee.Frame(id: "a", rect: CGRect(x: 0, y: 0, width: 10, height: 10))]
        let hits = GridMarquee.hits(in: CGRect(x: 5, y: 5, width: 20, height: 20), frames: frames)
        XCTAssertEqual(hits, ["a"], "Finder selecciona con solo rozar, no hace falta rodear la tarjeta entera")
    }

    func testMarqueeSelectionNoModifiersReplaces() {
        XCTAssertEqual(GridMarquee.selection(base: ["a"], hits: ["b"], modifiers: []), ["b"])
    }

    func testMarqueeSelectionShiftUnionsWithBase() {
        XCTAssertEqual(GridMarquee.selection(base: ["a"], hits: ["b"], modifiers: [.shift]), ["a", "b"])
    }

    func testMarqueeSelectionCommandTogglesAgainstBase() {
        // "b" no estaba en la base -> se agrega; "a" sí estaba y el
        // rectángulo también la toca -> se quita.
        XCTAssertEqual(GridMarquee.selection(base: ["a"], hits: ["a", "b"], modifiers: [.command]), ["b"])
    }

    /// Agrandar y achicar el rectángulo tiene que ser reversible -- cada
    /// posición se resuelve contra la MISMA `base` (la selección al
    /// empezar el arrastre), nunca contra la selección actual.
    func testGrowingThenShrinkingTheMarqueeIsReversible() {
        let base: Set<String> = ["a"]
        let frames = [
            GridMarquee.Frame(id: "b", rect: CGRect(x: 0, y: 0, width: 10, height: 10)),
            GridMarquee.Frame(id: "c", rect: CGRect(x: 20, y: 0, width: 10, height: 10)),
        ]
        let grown = GridMarquee.selection(rect: CGRect(x: 0, y: 0, width: 35, height: 10),
                                          frames: frames, base: base, modifiers: [])
        XCTAssertEqual(grown, ["b", "c"])
        let shrunk = GridMarquee.selection(rect: CGRect(x: 0, y: 0, width: 10, height: 10),
                                           frames: frames, base: base, modifiers: [])
        XCTAssertEqual(shrunk, ["b"], "achicar el rectángulo debe soltar lo que ya no toca, sin acumular")
    }

    // MARK: - F4: `GridDirection`

    func testDirectionStepColumns() {
        XCTAssertEqual(GridDirection.left.step(columnsPerRow: 5), -1)
        XCTAssertEqual(GridDirection.right.step(columnsPerRow: 5), 1)
        XCTAssertEqual(GridDirection.up.step(columnsPerRow: 5), -5)
        XCTAssertEqual(GridDirection.down.step(columnsPerRow: 5), 5)
    }

    func testDirectionStepDegradesToOneColumnWhenUnknown() {
        // Sin marcos (lista de una columna, o cuadrícula sin realizar
        // todavía), arriba/abajo deben comportarse como izquierda/derecha.
        XCTAssertEqual(GridDirection.down.step(columnsPerRow: 0), 1)
        XCTAssertEqual(GridDirection.up.step(columnsPerRow: 0), -1)
    }

    func testDirectionIsBackwards() {
        XCTAssertTrue(GridDirection.left.isBackwards)
        XCTAssertTrue(GridDirection.up.isBackwards)
        XCTAssertFalse(GridDirection.right.isBackwards)
        XCTAssertFalse(GridDirection.down.isBackwards)
    }

    // MARK: - F4: `GridSelectionModel` (arrastre + `columnsPerRow` deducido)

    func testColumnsPerRowIsOneWithoutAnyReportedFrame() {
        let model = GridSelectionModel<String>()
        XCTAssertEqual(model.columnsPerRow, 1)
    }

    func testColumnsPerRowCountsFramesOnTheTopRow() {
        let model = GridSelectionModel<String>()
        model.setFramesForTesting([
            "a": CGRect(x: 0, y: 0, width: 10, height: 10),
            "b": CGRect(x: 20, y: 0, width: 10, height: 10),
            "c": CGRect(x: 40, y: 0, width: 10, height: 10),
            "d": CGRect(x: 0, y: 20, width: 10, height: 10),
        ])
        XCTAssertEqual(model.columnsPerRow, 3)
    }

    func testMarqueeLifecycleAppliesAgainstTheFrozenBase() {
        let model = GridSelectionModel<String>()
        model.selection.handleTap("preexisting", order: GridOrder(["preexisting", "a"]), modifiers: [])
        model.setFramesForTesting(["a": CGRect(x: 0, y: 0, width: 10, height: 10)])

        model.beginMarquee()
        model.updateMarquee(rect: CGRect(x: 0, y: 0, width: 5, height: 5), modifiers: [.shift])
        XCTAssertEqual(model.selection.selected, ["preexisting", "a"])
        XCTAssertNotNil(model.marqueeRect)

        model.endMarquee()
        XCTAssertNil(model.marqueeRect)
    }
}
