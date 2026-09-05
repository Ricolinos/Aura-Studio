import XCTest
@testable import AuraStudio

/// PLAN-studio-rendimiento.md Fase 4 punto 1.
@MainActor
final class BackgroundTaskCenterTests: XCTestCase {
    func testBeginAddsATaskAndFinishRemovesIt() {
        let center = BackgroundTaskCenter()
        XCTAssertTrue(center.isEmpty)
        let handle = center.begin(title: "Importando")
        XCTAssertEqual(center.count, 1)
        XCTAssertTrue(center.tasks.contains { $0.id == handle.id })
        center.finish(handle)
        XCTAssertTrue(center.isEmpty)
    }

    func testUpdateChangesProgressOnTheHandleItself() {
        let center = BackgroundTaskCenter()
        let handle = center.begin(title: "Enriqueciendo", progress: .determinate(completed: 0, total: 10))
        handle.update(.determinate(completed: 3, total: 10), statusText: "3 de 10")
        XCTAssertEqual(handle.progress, .determinate(completed: 3, total: 10))
        XCTAssertEqual(handle.statusText, "3 de 10")
    }

    func testAggregateFractionAveragesOnlyDeterminateTasks() {
        let center = BackgroundTaskCenter()
        let a = center.begin(title: "A", progress: .determinate(completed: 1, total: 2)) // 0.5
        _ = center.begin(title: "B", progress: .indeterminate)
        let c = center.begin(title: "C", progress: .determinate(completed: 3, total: 4)) // 0.75
        XCTAssertEqual(center.aggregateFraction ?? -1, 0.625, accuracy: 0.001)
        _ = a
        _ = c
    }

    func testAggregateFractionIsNilWithOnlyIndeterminateTasks() {
        let center = BackgroundTaskCenter()
        _ = center.begin(title: "A", progress: .indeterminate)
        XCTAssertNil(center.aggregateFraction)
    }

    func testAggregateFractionIsNilWithNoTasks() {
        let center = BackgroundTaskCenter()
        XCTAssertNil(center.aggregateFraction)
    }

    func testRequestCancelCallsTheClosureOnceEvenIfCalledTwice() {
        let center = BackgroundTaskCenter()
        var cancelCount = 0
        let handle = center.begin(title: "Copiando") { cancelCount += 1 }
        XCTAssertTrue(handle.isCancellable)
        handle.requestCancel()
        handle.requestCancel()
        XCTAssertEqual(cancelCount, 1)
        XCTAssertTrue(handle.isCancelled)
    }

    func testATaskWithoutACancelClosureIsNotCancellable() {
        let center = BackgroundTaskCenter()
        let handle = center.begin(title: "Guardando catálogo")
        XCTAssertFalse(handle.isCancellable)
        handle.requestCancel() // no debe crashear ni hacer nada
        XCTAssertTrue(handle.isCancelled) // se marca igual, aunque no haya nada que interrumpir
    }

    func testFailSetsAnErrorMessageWithoutRemovingTheTask() {
        let center = BackgroundTaskCenter()
        let handle = center.begin(title: "Sincronizando")
        handle.fail("Se perdió la conexión con el iPod")
        XCTAssertEqual(handle.errorText, "Se perdió la conexión con el iPod")
        XCTAssertEqual(center.count, 1, "un error no debe hacer que la tarea desaparezca sola")
    }

    func testMultipleTasksTrackIndependently() {
        let center = BackgroundTaskCenter()
        let a = center.begin(title: "A")
        let b = center.begin(title: "B")
        center.finish(a)
        XCTAssertEqual(center.count, 1)
        XCTAssertEqual(center.tasks.first?.id, b.id)
    }
}
