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
    /// mpegplayer necesita: escalado para caber dentro de 320x240
    /// preservando la relacion de aspecto real (sin recortar ni
    /// deformar), MPEG-2 video + MP2 audio dentro de un contenedor
    /// MPEG-PS, bitrate moderado para no saturar la lectura de disco
    /// del iPod.
    ///
    /// PARTE 3 (PLAN-sync-media-hardening.md, D-304 en el firmware): ya
    /// NO se rellena con barras negras horneadas en el video (el `pad`
    /// que existia antes) -- eso dejaba SIEMPRE una imagen de exactamente
    /// 320x240 sin importar el aspecto real del contenido, y el firmware
    /// nunca podia distinguir "video angosto" de "barras", volviendo
    /// inutil su propia logica de centrado/recorte (`vo_setup()`) y
    /// haciendo imposible un modo "cubrir pantalla" real. Ahora el .mpg
    /// conserva su ancho o alto real (el que sea menor que 320/240) en
    /// la cabecera de secuencia MPEG, y es el firmware el que decide en
    /// tiempo de reproduccion si deja franjas (ajustar) o recorta y
    /// escala para llenar la pantalla (cubrir, alternable con SELECT).
    /// `force_divisible_by=2` asegura dimensiones pares, requisito del
    /// submuestreo de crominancia 4:2:0 que espera MPEG-2.
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
    ///
    /// `cropFilter` (PLAN-sync-media-hardening.md PARTE 3, encargo del
    /// dueño tras confirmar en un rip de película que "cubrir" no
    /// recortaba nada): algunas fuentes (rips de DVD/BluRay sobre todo)
    /// declaran un aspecto de contenedor (p. ej. 4:3) que NO es el
    /// aspecto real del contenido -- traen franjas negras HORNEADAS
    /// como píxeles reales dentro de ese contenedor, invisibles para
    /// `scale=...` (que solo mira metadata del stream, nunca el
    /// contenido de los píxeles). Sin detectarlas, Studio escala el
    /// contenedor completo (con sus franjas incluidas) y el firmware no
    /// tiene forma de distinguir "video angosto real" de "franjas
    /// horneadas": la lógica de ajustar/cubrir simplemente no encuentra
    /// nada que recortar. `cropFilter` (si viene) se antepone al
    /// `scale` -- un token `"crop=W:H:X:Y"` ya armado por
    /// `detectCropFilter(of:ffmpegURL:durationSeconds:)`.
    static func arguments(input: URL, output: URL, videoBitrateKbps: Int = 768,
                           sourceFrameRate: Double? = nil, cropFilter: String? = nil) -> [String] {
        let scaleFilter = "scale=320:240:force_original_aspect_ratio=decrease:force_divisible_by=2"
        let vf = cropFilter.map { "\($0),\(scaleFilter)" } ?? scaleFilter
        var args = [
            "-y", "-loglevel", "error",
            "-i", input.path,
            "-vf", vf,
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
        /// Fallo abierto a proposito: si la deteccion de franjas
        /// horneadas falla por cualquier razon (fuente rara, ffmpeg mas
        /// viejo sin cropdetect, timeout), se transcodifica igual sin
        /// recorte -- el comportamiento de antes, nunca bloquear el
        /// pipeline completo por esto.
        let duration = try? Self.probeDurationSeconds(of: input, ffmpegURL: ffmpegURL)
        let cropFilter = try? Self.detectCropFilter(of: input, ffmpegURL: ffmpegURL,
                                                     durationSeconds: duration)

        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = Self.arguments(input: input, output: output, videoBitrateKbps: videoBitrateKbps,
                                            sourceFrameRate: sourceFrameRate, cropFilter: cropFilter)
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

    /// PARTE 3 (PLAN-sync-media-hardening.md, encargo del dueño):
    /// corre el filtro `cropdetect` de ffmpeg sobre una muestra del
    /// video (100 frames, arrancando al 20% de la duración -- salta
    /// intros/logos que suelen ser negros de verdad, no franja) y
    /// devuelve el último `crop=W:H:X:Y` que reportó (cropdetect afina
    /// su estimación cuadro a cuadro, ampliándola lo justo para cubrir
    /// TODO lo visto hasta ahora -- el último valor de la muestra es el
    /// más seguro). `-an` (sin audio) porque no hace falta decodificarlo
    /// para esto. Devuelve `nil` si no se pudo parsear ningún `crop=`
    /// (fuente rara, ffmpeg sin soporte) -- el llamador ya trata esto
    /// como "sin recorte", el mismo comportamiento que había antes de
    /// esta función existir.
    static func detectCropFilter(of input: URL, ffmpegURL: URL,
                                  durationSeconds: Double?) throws -> String? {
        let seek = min(max((durationSeconds ?? 0) * 0.2, 0), max((durationSeconds ?? 0) - 1, 0))

        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = [
            "-ss", String(format: "%.2f", seek),
            "-i", input.path,
            "-an",
            "-vf", "cropdetect=24:2:0",
            "-frames:v", "100",
            "-f", "null", "-",
        ]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()

        try process.run()
        let data = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let text = String(data: data, encoding: .utf8) ?? ""
        guard let crop = parseCropComponents(from: text) else { return nil }

        /// Umbral de "vale la pena recortar": cropdetect encuentra un
        /// recorte MINUSCULO (2-3%) hasta en fuentes sin ninguna franja
        /// real -- ruido de compresion/vineteado en el borde, no franjas
        /// horneadas. Aplicarlo igual "respetaria el AR" al pie de la
        /// letra pero recortaria un poco de TODOS los videos sin
        /// necesidad, contrario al espiritu del pedido. Si el recorte
        /// detectado deja menos del 95% del ancho o alto original,
        /// recien ahi se considera una franja real que vale la pena
        /// quitar. Sin dato de resolucion de origen (parseo fallo),
        /// se confia en cropdetect igual antes que no aplicar nada.
        guard let source = parseResolution(from: text) else {
            return "crop=\(crop.w):\(crop.h):\(crop.x):\(crop.y)"
        }
        let widthRatio = Double(crop.w) / Double(source.width)
        let heightRatio = Double(crop.h) / Double(source.height)
        guard widthRatio < 0.95 || heightRatio < 0.95 else { return nil }

        return "crop=\(crop.w):\(crop.h):\(crop.x):\(crop.y)"
    }

    /// Busca la última ocurrencia de "crop=W:H:X:Y" en la salida de
    /// `cropdetect` (siempre es el último token de cada línea que
    /// reporta, ver `detectCropFilter`) y devuelve el filtro ya armado,
    /// SIN el umbral de "vale la pena" que sí aplica `detectCropFilter`
    /// (ese umbral necesita la resolución de origen, que esta función
    /// no recibe -- pensada para tests unitarios sobre texto suelto).
    /// `nil` si no hay ninguna línea parseable, o si el ancho/alto
    /// detectado es 0 o negativo (fuente extraña, mejor no recortar
    /// nada a arriesgar un filtro inválido).
    static func parseCropFilter(from ffmpegOutput: String) -> String? {
        guard let c = parseCropComponents(from: ffmpegOutput) else { return nil }
        return "crop=\(c.w):\(c.h):\(c.x):\(c.y)"
    }

    private static func parseCropComponents(from ffmpegOutput: String) -> (w: Int, h: Int, x: Int, y: Int)? {
        var last: Substring?
        for line in ffmpegOutput.split(separator: "\n") {
            if let range = line.range(of: "crop=") {
                last = line[range.lowerBound...]
            }
        }
        guard let token = last else { return nil }
        let parts = token.dropFirst("crop=".count).split(separator: ":")
        guard parts.count == 4,
              let w = Int(parts[0]), let h = Int(parts[1]),
              let x = Int(parts[2]), let y = Int(parts[3]),
              w > 0, h > 0 else { return nil }
        return (w, h, x, y)
    }

    /// Busca el primer patron "NNNxNNN" en la linea "Stream #0:0...:
    /// Video: ..." -- la resolucion real del video de origen (mismo
    /// volcado de cabecera que ya usan `parseFrameRate`/`parseDuration`).
    /// Escaneo caracter por caracter en vez de partir por comas: el
    /// nombre del pixel format puede traer comas propias adentro de
    /// parentesis (p. ej. "yuv420p(tv, bt709, progressive)"), que
    /// partirian el resto de la linea en pedazos equivocados.
    static func parseResolution(from ffmpegOutput: String) -> (width: Int, height: Int)? {
        for line in ffmpegOutput.split(separator: "\n") where line.contains(" Video: ") {
            let chars = Array(line)
            var i = 0
            while i < chars.count {
                guard chars[i].isNumber else { i += 1; continue }
                var j = i
                while j < chars.count && chars[j].isNumber { j += 1 }
                if j < chars.count, chars[j] == "x" {
                    var k = j + 1
                    while k < chars.count && chars[k].isNumber { k += 1 }
                    if k > j + 1, let w = Int(String(chars[i..<j])), let h = Int(String(chars[(j + 1)..<k])),
                       w > 0, h > 0 {
                        return (w, h)
                    }
                }
                i = j
            }
        }
        return nil
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
