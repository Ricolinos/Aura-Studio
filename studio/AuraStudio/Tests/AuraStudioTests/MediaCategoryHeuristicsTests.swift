import XCTest
@testable import AuraStudio

/// D-192/D-228: heuristicas puras de categorizacion de fotos/video --
/// sin tocar disco, la lectura real de EXIF/duracion vive en
/// `MediaCategoryClassifier` (no testeado aca, necesita archivos reales).
final class MediaCategoryHeuristicsTests: XCTestCase {
    // MARK: - Fotos

    func testPhotoWithKnownAISoftwareTagIsAIGenerated() {
        XCTAssertEqual(MediaCategoryHeuristics.classifyPhoto(softwareTag: "Midjourney v6", hasCameraExif: false), "IA")
        XCTAssertEqual(MediaCategoryHeuristics.classifyPhoto(softwareTag: "Adobe Firefly", hasCameraExif: true), "IA")
    }

    func testPhotoWithCameraExifAndNoAITagIsPhoto() {
        XCTAssertEqual(MediaCategoryHeuristics.classifyPhoto(softwareTag: nil, hasCameraExif: true), "Fotos")
    }

    func testPhotoWithNoCameraExifAndNoAITagIsImage() {
        XCTAssertEqual(MediaCategoryHeuristics.classifyPhoto(softwareTag: nil, hasCameraExif: false), "Imágenes")
    }

    func testPhotoSoftwareTagMatchIsCaseInsensitive() {
        XCTAssertEqual(MediaCategoryHeuristics.classifyPhoto(softwareTag: "STABLE DIFFUSION XL", hasCameraExif: false), "IA")
    }

    func testUnrelatedSoftwareTagDoesNotTriggerAIGenerated() {
        XCTAssertEqual(MediaCategoryHeuristics.classifyPhoto(softwareTag: "Adobe Photoshop 25.0", hasCameraExif: true), "Fotos")
    }

    // MARK: - Videos

    // D-228: se elimino el corte de "casero" (<= 3 min) -- ya no hay
    // heuristica automatica para "Series", el usuario la asigna a mano.
    // Un video corto ahora cae en el default (.videos), igual que
    // cualquier duracion que no sea claramente una pelicula.
    func testShortVideoIsVideos() {
        XCTAssertEqual(MediaCategoryHeuristics.classifyVideo(durationSeconds: 45), .videos)
        XCTAssertEqual(MediaCategoryHeuristics.classifyVideo(durationSeconds: 180), .videos)
    }

    func testMediumVideoIsVideos() {
        XCTAssertEqual(MediaCategoryHeuristics.classifyVideo(durationSeconds: 600), .videos)
    }

    func testLongVideoIsMovie() {
        XCTAssertEqual(MediaCategoryHeuristics.classifyVideo(durationSeconds: 5400), .movies)
    }

    func testUnknownDurationFallsBackToVideos() {
        XCTAssertEqual(MediaCategoryHeuristics.classifyVideo(durationSeconds: nil), .videos)
        XCTAssertEqual(MediaCategoryHeuristics.classifyVideo(durationSeconds: 0), .videos)
    }
}
