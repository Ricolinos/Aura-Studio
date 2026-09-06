import XCTest
@testable import AuraStudio

/// ST-189: "decide el volumen, no la carpeta". Cubre los casos que
/// "experto en código opus" señaló como valiosos de aislar -- en
/// particular, que una ruta de biblioteca en el volumen de arranque
/// (Documentos, la Casa del usuario) SIEMPRE reporte "montado", aunque
/// la lista de volúmenes montados solo traiga `/`.
final class LibraryRootAvailabilityTests: XCTestCase {
    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    func testHomeDirectoryPath_withOnlyRootMounted_reportsMounted() {
        let root = url("/Users/dueño/Documentos/Aura")
        XCTAssertTrue(LibraryRoot.volumeIsMounted(root, mountedVolumes: [url("/")]))
        XCTAssertEqual(LibraryRoot.availability(of: root, mountedVolumes: [url("/")]), .available)
    }

    func testExternalVolumePath_whenVolumeIsMounted_reportsMounted() {
        let root = url("/Volumes/Mac Externo/Aura")
        let mounted = [url("/"), url("/Volumes/Mac Externo")]
        XCTAssertTrue(LibraryRoot.volumeIsMounted(root, mountedVolumes: mounted))
        XCTAssertEqual(LibraryRoot.availability(of: root, mountedVolumes: mounted), .available)
    }

    func testExternalVolumePath_whenOnlyRootIsMounted_reportsNotMounted() {
        let root = url("/Volumes/Mac Externo/Aura")
        XCTAssertFalse(LibraryRoot.volumeIsMounted(root, mountedVolumes: [url("/")]))
        XCTAssertEqual(LibraryRoot.availability(of: root, mountedVolumes: [url("/")]), .volumeMissing)
    }

    func testExternalVolumePath_exactlyAtMountPoint_reportsMounted() {
        let root = url("/Volumes/Mac Externo")
        let mounted = [url("/"), url("/Volumes/Mac Externo")]
        XCTAssertTrue(LibraryRoot.volumeIsMounted(root, mountedVolumes: mounted))
    }

    func testExternalVolumePath_withADifferentVolumeMounted_reportsNotMounted() {
        // Otro disco externo sí está montado, pero no el que contiene
        // la biblioteca -- sigue siendo "no está", no "sí, algo está".
        let root = url("/Volumes/Mac Externo/Aura")
        let mounted = [url("/"), url("/Volumes/Otro Disco")]
        XCTAssertFalse(LibraryRoot.volumeIsMounted(root, mountedVolumes: mounted))
    }

    func testExpectedVolumeName_forExternalPath_extractsTheVolumeName() {
        XCTAssertEqual(LibraryRoot.expectedVolumeName(of: url("/Volumes/Mac Externo/Aura/Música")), "Mac Externo")
    }

    func testExpectedVolumeName_forHomeDirectoryPath_isNil() {
        XCTAssertNil(LibraryRoot.expectedVolumeName(of: url("/Users/dueño/Documentos/Aura")))
    }

    func testExpectedVolumeName_forVolumesRootItself_isNil() {
        XCTAssertNil(LibraryRoot.expectedVolumeName(of: url("/Volumes")))
    }
}
