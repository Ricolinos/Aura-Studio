import XCTest
@testable import AuraStudio

/// Fase 23 (PLAN-UX.md): antes la barra de progreso de transcodificacion
/// quedaba congelada en 0 durante todo el proceso -- estos tests fijan
/// el parseo real de la salida de ffmpeg que la resuelve, sin necesitar
/// invocar ffmpeg de verdad (los tests de integracion con ffmpeg real ya
/// viven en LibraryPipelineIntegrationTests).
final class FFmpegTranscoderTests: XCTestCase {
    func testParseDurationFromStandardFFmpegHeader() throws {
        let output = """
        Input #0, mov,mp4,m4a,3gp,3g2,mj2, from 'input.mp4':
          Duration: 00:02:03.45, start: 0.000000, bitrate: 1234 kb/s
            Stream #0:0: Video: h264
        """
        let duration = try XCTUnwrap(FFmpegTranscoder.parseDuration(from: output))
        XCTAssertEqual(duration, 123.45, accuracy: 0.01)
    }

    func testParseDurationReturnsNilWhenNotYetPresent() {
        let partial = "Input #0, mov,mp4,m4a,3gp,3g2,mj2, from 'input.mp4':\n"
        XCTAssertNil(FFmpegTranscoder.parseDuration(from: partial))
    }

    func testParseDurationHandlesZeroHours() throws {
        let output = "  Duration: 00:00:05.00, start: 0.000000, bitrate: 128 kb/s\n"
        let duration = try XCTUnwrap(FFmpegTranscoder.parseDuration(from: output))
        XCTAssertEqual(duration, 5.0, accuracy: 0.01)
    }

    func testParseOutTimeMsReadsLastCompleteValue() {
        let progress = """
        frame=1
        out_time_ms=1000000
        progress=continue
        frame=2
        out_time_ms=2500000
        progress=continue
        """
        XCTAssertEqual(FFmpegTranscoder.parseOutTimeMs(from: progress), 2_500_000)
    }

    func testParseOutTimeMsReturnsNilWithoutAnyValue() {
        let progress = "frame=1\nprogress=continue\n"
        XCTAssertNil(FFmpegTranscoder.parseOutTimeMs(from: progress))
    }

    func testProgressFractionComputation() {
        // 2.5s de 5s totales = 50% -- la misma cuenta que hace
        // transcode() con out_time_ms (microsegundos) y la duracion en
        // segundos parseada del header.
        let outTimeMs = 2_500_000.0
        let duration = 5.0
        let fraction = min(max((outTimeMs / 1_000_000) / duration, 0), 1)
        XCTAssertEqual(fraction, 0.5, accuracy: 0.001)
    }
}
