import XCTest
@testable import AuraStudio

/// Los mismos casos, con los mismos números, que
/// `AuraStudio.Core.Tests/SquareCropPlanTests.cs` en el port de Windows.
/// Si una de las dos plataformas cambia de criterio, esta pareja de
/// archivos es donde se nota.
final class SquareCropPlanTests: XCTestCase {
    func testASquareSourceIsNotCroppedAtAll() {
        let plan = SquareCropPlan(width: 500, height: 500, maxSide: 320)
        XCTAssertEqual(plan.cropX, 0)
        XCTAssertEqual(plan.cropY, 0)
        XCTAssertEqual(plan.cropSide, 500)
        XCTAssertEqual(plan.outputSide, 320)
        XCTAssertFalse(plan.needsCrop)   // no hay nada que tirar
        XCTAssertTrue(plan.needsResize)  // pero sí que reducir
    }

    func testAFourThreeCoverLosesTheSidesInEqualHalves() {
        let plan = SquareCropPlan(width: 1600, height: 1200, maxSide: 320)
        XCTAssertEqual(plan.cropX, 200)   // (1600-1200)/2
        XCTAssertEqual(plan.cropY, 0)
        XCTAssertEqual(plan.cropSide, 1200)
        XCTAssertEqual(plan.outputSide, 320)
        XCTAssertTrue(plan.needsCrop)
    }

    func testASixteenNineCoverLosesMuchMoreOfTheSides() {
        let plan = SquareCropPlan(width: 1920, height: 1080, maxSide: 320)
        XCTAssertEqual(plan.cropX, 420)   // (1920-1080)/2
        XCTAssertEqual(plan.cropY, 0)
        XCTAssertEqual(plan.cropSide, 1080)
        XCTAssertEqual(plan.outputSide, 320)
    }

    func testAVeryTallSourceIsCroppedTopAndBottom() {
        // 1:4 -- el recorte va por arriba y por abajo, no por los lados.
        let plan = SquareCropPlan(width: 200, height: 800, maxSide: 128)
        XCTAssertEqual(plan.cropX, 0)
        XCTAssertEqual(plan.cropY, 300)   // (800-200)/2
        XCTAssertEqual(plan.cropSide, 200)
        XCTAssertEqual(plan.outputSide, 128)
    }

    func testTheLeftoverPixelIsAlwaysDiscardedFromTheRight() {
        // 401 de ancho: sobran 101 columnas, 50 a la izquierda y 51 a la
        // derecha. Determinista a propósito -- las dos plataformas tienen
        // que recortar exactamente el mismo píxel.
        let plan = SquareCropPlan(width: 401, height: 300, maxSide: 1000)
        XCTAssertEqual(plan.cropX, 50)
        XCTAssertEqual(plan.cropSide, 300)
        XCTAssertEqual(plan.sourceWidth - (plan.cropX + plan.cropSide), 51)
    }

    func testTheLeftoverPixelIsAlwaysDiscardedFromTheBottom() {
        let plan = SquareCropPlan(width: 300, height: 401, maxSide: 1000)
        XCTAssertEqual(plan.cropY, 50)
        XCTAssertEqual(plan.cropSide, 300)
        XCTAssertEqual(plan.sourceHeight - (plan.cropY + plan.cropSide), 51)
    }

    func testASourceSmallerThanAskedIsNeverBlownUp() {
        // Agrandarla solo agrega peso y se ve peor -- el mismo criterio que
        // ImageResizer.resizeToLCDOptimal.
        let plan = SquareCropPlan(width: 200, height: 200, maxSide: 320)
        XCTAssertEqual(plan.outputSide, 200)
        XCTAssertFalse(plan.needsResize)
        XCTAssertFalse(plan.needsCrop)
    }

    func testTheSmallestPossibleImageStillGivesAValidPlan() {
        let plan = SquareCropPlan(width: 1, height: 1, maxSide: 320)
        XCTAssertEqual(plan.cropSide, 1)
        XCTAssertEqual(plan.outputSide, 1)
        XCTAssertFalse(plan.isEmpty)
        XCTAssertFalse(plan.needsCrop)
        XCTAssertFalse(plan.needsResize)
    }

    func testTheCanonicalSidesOfTheContract() {
        // v18: cover.jpg 320x320 y artists/*.jpg 128x128 desde una copia
        // local cuadrada de 1000 -- sobre una fuente ya cuadrada el plan es
        // solo un reescalado.
        let cover = SquareCropPlan(width: 1000, height: 1000, maxSide: 320)
        XCTAssertEqual(cover.outputSide, 320)
        XCTAssertFalse(cover.needsCrop)
        XCTAssertTrue(cover.needsResize)

        let artist = SquareCropPlan(width: 1000, height: 1000, maxSide: 128)
        XCTAssertEqual(artist.outputSide, 128)
    }

    func testADegenerateSizeGivesNothingInsteadOfGarbage() {
        for (width, height, maxSide) in [(0, 100, 320), (100, 0, 320), (-5, 100, 320), (100, 100, 0)] {
            let plan = SquareCropPlan(width: width, height: height, maxSide: maxSide)
            XCTAssertTrue(plan.isEmpty, "\(width)x\(height) max \(maxSide) debería dar un plan vacío")
            XCTAssertEqual(plan, .empty)
            XCTAssertFalse(plan.needsCrop)
            XCTAssertFalse(plan.needsResize)
        }
    }
}
