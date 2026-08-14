import XCTest
@testable import AuraStudio

/// D-192: heuristicas puras de categorizacion de fotos/video -- sin
/// tocar disco, la lectura real de EXIF/duracion vive en
/// `MediaCategoryClassifier` (no testeado aca, necesita archivos reales).
final class MediaCategoryHeuristicsTests: XCTestCase {
    // MARK: - Fotos

    func testPhotoWithKnownAISoftwareTagIsAIGenerated() {
        XCTAssertEqual(MediaCategoryHeuristics.classifyPhoto(softwareTag: "Midjourney v6", hasCameraExif: false), .aiGenerated)
        XCTAssertEqual(MediaCategoryHeuristics.classifyPhoto(softwareTag: "Adobe Firefly", hasCameraExif: true), .aiGenerated)
    }

    func testPhotoWithCameraExifAndNoAITagIsPhoto() {
        XCTAssertEqual(MediaCategoryHeuristics.classifyPhoto(softwareTag: nil, hasCameraExif: true), .photos)
    }

    func testPhotoWithNoCameraExifAndNoAITagIsImage() {
        XCTAssertEqual(MediaCategoryHeuristics.classifyPhoto(softwareTag: nil, hasCameraExif: false), .images)
    }

    func testPhotoSoftwareTagMatchIsCaseInsensitive() {
        XCTAssertEqual(MediaCategoryHeuristics.classifyPhoto(softwareTag: "STABLE DIFFUSION XL", hasCameraExif: false), .aiGenerated)
    }

    func testUnrelatedSoftwareTagDoesNotTriggerAIGenerated() {
        XCTAssertEqual(MediaCategoryHeuristics.classifyPhoto(softwareTag: "Adobe Photoshop 25.0", hasCameraExif: true), .photos)
    }

    // MARK: - Videos

    func testShortVideoIsHomeVideo() {
        XCTAssertEqual(MediaCategoryHeuristics.classifyVideo(durationSeconds: 45), .homeVideos)
        XCTAssertEqual(MediaCategoryHeuristics.classifyVideo(durationSeconds: 180), .homeVideos)
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
