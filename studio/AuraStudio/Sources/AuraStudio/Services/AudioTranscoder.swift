import Foundation

/// Convierte una pista de audio a MP3 256kbps -- el modo "comprimir a
/// buena calidad" de `AppPreferences.audioQuality` (encargo del dueño,
/// 2026-08-13: dejarle elegir entre lossless original o un formato
/// comprimido que "mantiene un poco la calidad"). Reusa `FFmpegLocator`
/// (mismo mecanismo que `FFmpegTranscoder` para encontrar ffmpeg en el
/// sistema, D-038) en vez de duplicar la busqueda.
struct AudioTranscoder {
    enum TranscodeError: Error, LocalizedError {
        case ffmpegNotFound
        case processFailed(String)

        var errorDescription: String? {
            switch self {
            case .ffmpegNotFound:
                return "No se encontro ffmpeg instalado. Instálalo con \"brew install ffmpeg\" y vuelve a intentar."
            case .processFailed(let output):
                return "ffmpeg fallo al comprimir el audio: \(output)"
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

    /// 256kbps CBR: buena calidad perceptual, tamaño predecible (a
    /// diferencia de VBR, mas dificil de explicarle al usuario cuanto
    /// espacio va a ocupar de antemano).
    func transcodeToMP3(input: URL, output: URL) throws {
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = [
            "-y", "-i", input.path,
            "-map", "0:a:0", "-vn",
            "-c:a", "libmp3lame", "-b:a", "256k",
            output.path,
        ]
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            throw TranscodeError.processFailed(String(data: data, encoding: .utf8) ?? "")
        }
    }
}
