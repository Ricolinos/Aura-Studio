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

    // MARK: - parseFrameRate / arguments(sourceFrameRate:) -- PARTE 3A

    func testParseFrameRateFromStandardVideoStreamLine() throws {
        let output = """
        Input #0, mov,mp4,m4a,3gp,3g2,mj2, from 'input.mov':
          Duration: 00:00:10.00, start: 0.000000, bitrate: 5000 kb/s
            Stream #0:0(und): Video: h264 (High), yuv420p, 1920x1080, 60 fps, 60 tbr, 600 tbn
        """
        let fps = try XCTUnwrap(FFmpegTranscoder.parseFrameRate(from: output))
        XCTAssertEqual(fps, 60, accuracy: 0.01)
    }

    func testParseFrameRateHandlesDecimalValue() throws {
        let line = "    Stream #0:0: Video: mpeg4, yuv420p, 640x480, 29.97 fps, 29.97 tbr"
        let fps = try XCTUnwrap(FFmpegTranscoder.parseFrameRate(from: line))
        XCTAssertEqual(fps, 29.97, accuracy: 0.01)
    }

    func testParseFrameRateNilWithoutVideoStream() {
        let audioOnly = "    Stream #0:0: Audio: aac, 44100 Hz, stereo"
        XCTAssertNil(FFmpegTranscoder.parseFrameRate(from: audioOnly))
    }

    func testArgumentsOmitsFrameRateCapWhenSourceIsAtOrBelow24() {
        let args = FFmpegTranscoder.arguments(input: URL(fileURLWithPath: "/in.mov"),
                                               output: URL(fileURLWithPath: "/out.mpg"),
                                               sourceFrameRate: 24)
        XCTAssertFalse(args.contains("-r"), "24 fps ya esta dentro del limite -- no hace falta forzar nada")
    }

    func testArgumentsCapsFrameRateWhenSourceExceeds24() {
        let args = FFmpegTranscoder.arguments(input: URL(fileURLWithPath: "/in.mov"),
                                               output: URL(fileURLWithPath: "/out.mpg"),
                                               sourceFrameRate: 60)
        guard let rIndex = args.firstIndex(of: "-r") else {
            return XCTFail("60 fps deberia forzar -r 24")
        }
        XCTAssertEqual(args[rIndex + 1], "24")
        guard let gIndex = args.firstIndex(of: "-g") else {
            return XCTFail("el limite de fps deberia venir acompañado de -g 15")
        }
        XCTAssertEqual(args[gIndex + 1], "15")
    }

    func testArgumentsOmitsFrameRateCapWhenSourceFrameRateUnknown() {
        let args = FFmpegTranscoder.arguments(input: URL(fileURLWithPath: "/in.mov"),
                                               output: URL(fileURLWithPath: "/out.mpg"),
                                               sourceFrameRate: nil)
        XCTAssertFalse(args.contains("-r"))
    }

    func testArgumentsAlwaysForcesAudioSampleRateFor44100() {
        // libmad (decoder de audio de mpegplayer) solo entiende MPEG
        // audio en frecuencias estandar -- sin esto, el audio quedaba
        // al sample rate de origen (48kHz es comun en video de telefono).
        let args = FFmpegTranscoder.arguments(input: URL(fileURLWithPath: "/in.mov"),
                                               output: URL(fileURLWithPath: "/out.mpg"))
        guard let arIndex = args.firstIndex(of: "-ar") else {
            return XCTFail("deberia forzar -ar 44100 siempre")
        }
        XCTAssertEqual(args[arIndex + 1], "44100")
    }

    // MARK: - cropFilter / detectCropFilter -- PARTE 3 (franjas horneadas)

    func testArgumentsOmitsCropWhenNotProvided() {
        let args = FFmpegTranscoder.arguments(input: URL(fileURLWithPath: "/in.mov"),
                                               output: URL(fileURLWithPath: "/out.mpg"))
        guard let vfIndex = args.firstIndex(of: "-vf") else {
            return XCTFail("deberia tener -vf")
        }
        XCTAssertFalse(args[vfIndex + 1].contains("crop="))
    }

    func testArgumentsPrependsCropFilterBeforeScale() {
        let args = FFmpegTranscoder.arguments(input: URL(fileURLWithPath: "/in.mov"),
                                               output: URL(fileURLWithPath: "/out.mpg"),
                                               cropFilter: "crop=320:132:0:54")
        guard let vfIndex = args.firstIndex(of: "-vf") else {
            return XCTFail("deberia tener -vf")
        }
        let vf = args[vfIndex + 1]
        XCTAssertTrue(vf.hasPrefix("crop=320:132:0:54,scale="),
                      "el crop tiene que ir ANTES del scale: \(vf)")
    }

    func testParseCropFilterReadsLastLine() {
        let output = """
        [Parsed_cropdetect_0 @ 0x1] crop=320:180:0:30
        [Parsed_cropdetect_0 @ 0x1] crop=320:132:0:54
        """
        XCTAssertEqual(FFmpegTranscoder.parseCropFilter(from: output), "crop=320:132:0:54")
    }

    func testParseCropFilterNilWithoutAnyCropLine() {
        XCTAssertNil(FFmpegTranscoder.parseCropFilter(from: "frame=1\nprogress=continue\n"))
    }

    func testParseCropFilterNilForZeroDimensions() {
        // No deberia pasar en la practica, pero si cropdetect reporta
        // basura (fuente extrana) mejor no recortar nada a arriesgar un
        // filtro invalido que tire el transcode entero.
        XCTAssertNil(FFmpegTranscoder.parseCropFilter(from: "crop=0:0:0:0"))
    }

    func testParseResolutionFromStandardVideoStreamLine() throws {
        let output = """
        Input #0, mov,mp4,m4a,3gp,3g2,mj2, from 'in.mp4':
          Duration: 00:00:02.50, start: 0.000000, bitrate: 15668 kb/s
            Stream #0:0(eng): Video: h264 (Main), yuv420p(tv, bt709, progressive), 1920x1080, 15631 kb/s, 30 fps, 30 tbr, 30k tbn (default)
        """
        let res = try XCTUnwrap(FFmpegTranscoder.parseResolution(from: output))
        XCTAssertEqual(res.width, 1920)
        XCTAssertEqual(res.height, 1080)
    }

    func testParseResolutionNilWithoutVideoStream() {
        XCTAssertNil(FFmpegTranscoder.parseResolution(from: "Stream #0:0: Audio: aac, 44100 Hz, stereo"))
    }
}
