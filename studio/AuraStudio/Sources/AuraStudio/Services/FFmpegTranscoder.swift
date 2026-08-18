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
                return "No se encontro ffmpeg instalado. Instálalo con \"brew install ffmpeg\" y vuelve a intentar."
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
    ///
    /// `sourceFrameRate` (PLAN-sync-media-hardening.md PARTE 3A):
    /// mpegplayer en el S5L8702 del iPod Classic decodifica bien video
    /// de hasta ~24-25 fps -- 60 fps de un iPhone lo ahoga (el síntoma
    /// real reportado: "tampoco se han podido visualizar"). Solo se
    /// fuerza `-r 24` cuando la fuente EXCEDE 24 fps -- forzarlo
    /// siempre duplicaría frames sin necesidad en una fuente ya lenta
    /// (un timelapse a 10 fps, por ejemplo), agrandando el archivo sin
    /// ganar nada. `-g 15` (un keyframe cada ~0.6s a 24fps) acorta el
    /// salto a nitidez tras el primer frame -- sin GPU para decodificar
    /// P/B-frames rápido, un GOP largo se siente "sucio" al arrancar.
    /// `-ar 44100`: libmad (el decoder de audio de mpegplayer) solo
    /// entiende MPEG audio Layer I/II/III en las frecuencias estándar
    /// -- sin esto, el audio queda al sample rate de origen (48kHz es
    /// común en video de teléfono), que antes no se forzaba a nada.
    static func arguments(input: URL, output: URL, videoBitrateKbps: Int = 768,
                           sourceFrameRate: Double? = nil) -> [String] {
        var args = [
            "-y", "-loglevel", "error",
            "-i", input.path,
            "-vf", "scale=320:240:force_original_aspect_ratio=decrease,pad=320:240:(ow-iw)/2:(oh-ih)/2",
            "-c:v", "mpeg2video", "-b:v", "\(videoBitrateKbps)k",
        ]
        if let sourceFrameRate, sourceFrameRate > 24 {
            args += ["-r", "24", "-g", "15"]
        }
        args += [
            "-c:a", "mp2", "-b:a", "128k", "-ar", "44100",
            "-f", "mpeg",
            output.path,
        ]
        return args
    }

    func transcode(input: URL, output: URL, videoBitrateKbps: Int = 768, sourceFrameRate: Double? = nil) throws {
        try transcode(input: input, output: output, videoBitrateKbps: videoBitrateKbps,
                      sourceFrameRate: sourceFrameRate, onProgress: nil)
    }

    /// Fase 23 (PLAN-UX.md): `onProgress` recibe una fraccion real en
    /// [0, 1], no un valor fijo en 0 -- antes la UI mostraba una barra
    /// congelada durante toda la transcodificacion (LibraryViewModel
    /// nunca actualizaba `.transcoding(progress:)` despues del valor
    /// inicial). Se agrega "-progress pipe:1" para que ffmpeg reporte
    /// `out_time_ms=...` por stdout a medida que avanza, y se lee la
    /// duracion total del video de la primera linea "Duration: HH:MM:SS.cc"
    /// que ffmpeg ya imprime por stderr antes de arrancar a codificar --
    /// no hace falta invocar ffprobe por separado.
    ///
    /// `readabilityHandler` corre en un hilo interno de Foundation, no en
    /// el que llamo a `transcode`: bajo Swift 6 strict concurrency (que
    /// solo `xcodebuild` chequea de verdad, ver D-034) mutar `var`
    /// capturadas ahi es un error de compilacion, no solo un warning --
    /// son closures `@Sendable` de verdad. `TranscodeProgressTracker`
    /// mueve ese estado mutable a una clase con lock propio en vez de
    /// capturar locals.
    func transcode(input: URL, output: URL, videoBitrateKbps: Int = 768, sourceFrameRate: Double? = nil,
                    onProgress: (@Sendable (Double) -> Void)?) throws {
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = Self.arguments(input: input, output: output, videoBitrateKbps: videoBitrateKbps,
                                            sourceFrameRate: sourceFrameRate)
            + ["-progress", "pipe:1"]

        let errPipe = Pipe()
        let outPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = outPipe

        let tracker = TranscodeProgressTracker()

        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            tracker.appendStderr(chunk)
        }

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            if let fraction = tracker.appendStdout(chunk) {
                onProgress?(fraction)
            }
        }

        try process.run()
        process.waitUntilExit()
        errPipe.fileHandleForReading.readabilityHandler = nil
        outPipe.fileHandleForReading.readabilityHandler = nil

        guard process.terminationStatus == 0 else {
            throw TranscodeError.processFailed(tracker.stderrText.isEmpty
                ? "codigo \(process.terminationStatus)" : tracker.stderrText)
        }
    }

    /// Fase 24 (PLAN-UX.md): un frame al ~10% de la duracion del video
    /// (portada mas representativa que el primer frame, casi siempre
    /// negro/logo de intro) para el panel derecho del navegador de
    /// video del firmware (D-066: la lectura del lado del dispositivo
    /// queda para una fase futura, esto solo genera y sincroniza el
    /// archivo). `-pix_fmt yuvj420p` fuerza el submuestreo de croma
    /// 4:2:0 estandar que el decoder JPEG de Rockbox necesita -- mismo
    /// hallazgo que D-031 para las caratulas de musica.
    func generatePoster(input: URL, output: URL, atFraction fraction: Double = 0.1) throws {
        let probedDuration = (try? Self.probeDurationSeconds(of: input, ffmpegURL: ffmpegURL)) ?? nil
        let seekSeconds = max((probedDuration ?? 10) * fraction, 0)

        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = [
            "-y", "-loglevel", "error",
            "-ss", String(format: "%.2f", seekSeconds),
            "-i", input.path,
            "-frames:v", "1",
            "-pix_fmt", "yuvj420p",
            output.path,
        ]
        let errPipe = Pipe()
        process.standardError = errPipe

        try process.run()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let text = String(data: errData, encoding: .utf8) ?? "codigo \(process.terminationStatus)"
            throw TranscodeError.processFailed(text)
        }
    }

    /// Probe minimo: le pide a ffmpeg que abra el archivo sin ningun
    /// output. ffmpeg termina con error ("At least one output file must
    /// be specified") pero ya imprimio la linea "Duration: ..." por
    /// stderr antes de fallar -- alcanza para reusar `parseDuration` sin
    /// invocar `ffprobe` por separado (mismo criterio que Fase 23).
    static func probeDurationSeconds(of input: URL, ffmpegURL: URL) throws -> Double? {
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = ["-i", input.path]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()

        try process.run()
        let data = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let text = String(data: data, encoding: .utf8) ?? ""
        return parseDuration(from: text)
    }

    /// PLAN-sync-media-hardening.md PARTE 3A: mismo probe que
    /// `probeDurationSeconds`, pero en una sola pasada de ffmpeg
    /// devuelve también el frame rate de origen (hace falta para
    /// decidir si `arguments(sourceFrameRate:)` debe forzar `-r 24`).
    /// Un solo proceso de ffmpeg para video -- ambos valores salen del
    /// mismo volcado de cabecera por stderr, no hace falta invocarlo
    /// dos veces.
    static func probeVideoInfo(of input: URL, ffmpegURL: URL) throws -> (duration: Double?, frameRate: Double?) {
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = ["-i", input.path]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()

        try process.run()
        let data = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let text = String(data: data, encoding: .utf8) ?? ""
        return (parseDuration(from: text), parseFrameRate(from: text))
    }

    /// Acumula stdout/stderr de ffmpeg detras de un `NSLock` para que
    /// `transcode(...)` pueda mutarlo desde los `readabilityHandler`
    /// (hilos concurrentes de Foundation) sin violar Swift 6 strict
    /// concurrency -- ver el comentario en `transcode(...onProgress:)`.
    private final class TranscodeProgressTracker: @unchecked Sendable {
        private let lock = NSLock()
        private var stderrBuffer = Data()
        private var outBuffer = Data()
        private var durationSeconds: Double?

        func appendStderr(_ chunk: Data) {
            lock.lock(); defer { lock.unlock() }
            stderrBuffer.append(chunk)
            if durationSeconds == nil, let text = String(data: stderrBuffer, encoding: .utf8) {
                durationSeconds = FFmpegTranscoder.parseDuration(from: text)
            }
        }

        /// Devuelve la fraccion [0, 1] de avance si ya se puede calcular
        /// (duracion total conocida y al menos un `out_time_ms` leido).
        func appendStdout(_ chunk: Data) -> Double? {
            lock.lock(); defer { lock.unlock() }
            outBuffer.append(chunk)
            guard let duration = durationSeconds, duration > 0,
                  let text = String(data: outBuffer, encoding: .utf8),
                  let outTimeMs = FFmpegTranscoder.parseOutTimeMs(from: text) else { return nil }
            return min(max((outTimeMs / 1_000_000) / duration, 0), 1)
        }

        var stderrText: String {
            lock.lock(); defer { lock.unlock() }
            return String(data: stderrBuffer, encoding: .utf8) ?? ""
        }
    }

    /// Busca "Duration: HH:MM:SS.cc" en la salida de ffmpeg y devuelve
    /// segundos totales. Devuelve nil si todavia no aparecio esa linea
    /// (llega al principio, antes de que arranque la codificacion).
    static func parseDuration(from ffmpegOutput: String) -> Double? {
        guard let range = ffmpegOutput.range(of: "Duration: ") else { return nil }
        let rest = ffmpegOutput[range.upperBound...]
        guard let comma = rest.firstIndex(of: ",") else { return nil }
        let timeString = rest[rest.startIndex..<comma]
        return parseTimecode(String(timeString))
    }

    /// PLAN-sync-media-hardening.md PARTE 3A: busca "NN fps" (o
    /// "NN.NN fps") en la línea "Stream #0:0(...): Video: ..." que
    /// ffmpeg imprime al abrir el archivo -- mismo volcado de cabecera
    /// que ya usa `parseDuration`. `nil` si no hay pista de video (solo
    /// audio) o el formato de origen no trae ese campo (poco común,
    /// pero no todos los contenedores lo declaran).
    static func parseFrameRate(from ffmpegOutput: String) -> Double? {
        for line in ffmpegOutput.split(separator: "\n") where line.contains(" Video: ") {
            guard let fpsRange = line.range(of: " fps") else { continue }
            let before = line[line.startIndex..<fpsRange.lowerBound]
            guard let comma = before.range(of: ",", options: .backwards) else { continue }
            let numberPart = before[before.index(after: comma.lowerBound)...]
                .trimmingCharacters(in: .whitespaces)
            if let value = Double(numberPart) {
                return value
            }
        }
        return nil
    }

    private static func parseTimecode(_ s: String) -> Double? {
        let parts = s.split(separator: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]), let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }

    /// `-progress pipe:1` emite bloques "key=value" separados por
    /// saltos de linea, uno de ellos "out_time_ms=<microsegundos>"
    /// (pese al nombre, ffmpeg reporta microsegundos, no milisegundos --
    /// comportamiento documentado y estable de la propia herramienta).
    /// Se toma el ultimo valor completo del buffer acumulado.
    static func parseOutTimeMs(from progressOutput: String) -> Double? {
        var lastValue: Double?
        for line in progressOutput.split(separator: "\n") {
            if line.hasPrefix("out_time_ms=") {
                let value = line.dropFirst("out_time_ms=".count)
                if let parsed = Double(value) {
                    lastValue = parsed
                }
            }
        }
        return lastValue
    }
}
