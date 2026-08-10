import Foundation

/// Localiza un ffmpeg instalado en el sistema (D-038 en DECISIONS.md
/// explica por que no viene embebido) y lo invoca para transcodificar
/// video al formato interno de Aura: MPEG-1/2 320x240, el unico que el
/// dispositivo reproduce (delegado al plugin mpegplayer de Rockbox, ver
/// D-029 en el firmware).
struct FFmpegLocator {
    static let commonPaths = [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/usr/bin/ffmpeg",
    ]

    static func locate(environmentPath: String? = ProcessInfo.processInfo.environment["PATH"]) -> URL? {
        let fm = FileManager.default
        for path in commonPaths where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        guard let environmentPath else { return nil }
        for dir in environmentPath.split(separator: ":") {
            let candidate = "\(dir)/ffmpeg"
            if fm.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }
}

struct FFmpegTranscoder {
    enum TranscodeError: Error, LocalizedError {
        case ffmpegNotFound
        case processFailed(String)

        var errorDescription: String? {
            switch self {
            case .ffmpegNotFound:
                return "No se encontro ffmpeg instalado. Instalalo con \"brew install ffmpeg\" y volve a intentar."
            case .processFailed(let output):
                return "ffmpeg fallo: \(output)"
            }
        }
    }

    let ffmpegURL: URL

    init(ffmpegURL: URL? = nil) throws {
        guard let url = ffmpegURL ?? FFmpegLocator.locate() else {
            throw TranscodeError.ffmpegNotFound
        }
        self.ffmpegURL = url
    }

    /// Arma los argumentos de ffmpeg para producir el .mpg que
    /// mpegplayer necesita: 320x240 (escalado preservando aspecto y
    /// rellenando con barras negras si el video no es 4:3, para no
    /// deformar la imagen), MPEG-2 video + MP2 audio dentro de un
    /// contenedor MPEG-PS, bitrate moderado para no saturar la lectura
    /// de disco del iPod.
    static func arguments(input: URL, output: URL, videoBitrateKbps: Int = 768) -> [String] {
        [
            "-y", "-loglevel", "error",
            "-i", input.path,
            "-vf", "scale=320:240:force_original_aspect_ratio=decrease,pad=320:240:(ow-iw)/2:(oh-ih)/2",
            "-c:v", "mpeg2video", "-b:v", "\(videoBitrateKbps)k",
            "-c:a", "mp2", "-b:a", "128k",
            "-f", "mpeg",
            output.path,
        ]
    }

    func transcode(input: URL, output: URL, videoBitrateKbps: Int = 768) throws {
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = Self.arguments(input: input, output: output, videoBitrateKbps: videoBitrateKbps)

        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            throw TranscodeError.processFailed(String(data: errData, encoding: .utf8) ?? "codigo \(process.terminationStatus)")
        }
    }
}
