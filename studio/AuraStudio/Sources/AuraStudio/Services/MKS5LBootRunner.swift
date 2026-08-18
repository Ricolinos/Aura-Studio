import Foundation

/// Envoltorio sobre el binario `mks5lboot` embebido (compilado en la
/// Fase 8 del firmware, ver D-032/D-033 en DECISIONS.md). Aura Studio no
/// reimplementa el protocolo DFU/USB de S5L8702 -- ya existe, probado,
/// en C dentro del propio fork -- solo lo invoca como subproceso y
/// parsea su salida de texto.
struct MKS5LBootRunner {
    struct Result {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    enum RunError: Error, LocalizedError, Equatable {
        case binaryNotFound
        /// El binario esta en el bundle pero sin bit de ejecucion
        /// (ST-018): los assets de un Release de GitHub llegan sin
        /// permisos y Xcode copia el recurso tal cual. Sin esto,
        /// `Process.run()` fallaba con "permission denied", el
        /// sondeo DFU lo tragaba y el instalador se quedaba en
        /// "Esperando modo DFU..." para siempre con el iPod ya en DFU.
        case binaryNotExecutable(path: String)

        var errorDescription: String? {
            switch self {
            case .binaryNotFound:
                return "No se encontró la herramienta mks5lboot dentro de Aura Studio."
            case .binaryNotExecutable(let path):
                return "La herramienta mks5lboot que trae Aura Studio no tiene permiso de ejecución (\(path)). Vuelve a instalar Aura Studio o, si compilas desde el código, corre scripts/fetch-firmware.sh de nuevo."
            }
        }
    }

    let executableURL: URL

    /// Falla si el binario no existe o no se puede ejecutar -- mejor
    /// enterarse al crear el runner que descubrirlo por un `Process`
    /// que nunca arranca.
    init(executableURL: URL? = nil, fileManager: FileManager = .default) throws {
        let url: URL
        if let executableURL {
            url = executableURL
        } else if let bundled = BundledArtifacts.shared.url(for: .mks5lboot) {
            url = bundled
        } else {
            throw RunError.binaryNotFound
        }
        guard fileManager.fileExists(atPath: url.path) else {
            throw RunError.binaryNotFound
        }
        guard fileManager.isExecutableFile(atPath: url.path) else {
            throw RunError.binaryNotExecutable(path: url.path)
        }
        self.executableURL = url
    }

    @discardableResult
    func run(_ arguments: [String]) throws -> Result {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

        return Result(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    /// Corre `--dfuscan` una vez (sin --loop, asi que mks5lboot ya
    /// termina solo con exit(0) si encontro un dispositivo o exit(1) si
    /// no) y devuelve el estado DFU detectado, o nil si no hay ninguno.
    func scanDFU() throws -> DFUModeInfo? {
        let result = try run(["--dfuscan"])
        guard result.exitCode == 0 else { return nil }
        guard let state = Self.parseDFUState(from: result.stdout) else { return nil }
        return DFUModeInfo(productID: state)
    }

    static func parseDFUState(from output: String) -> Int? {
        for line in output.split(separator: "\n") {
            guard let range = line.range(of: "DFU device state: ") else { continue }
            let numberPart = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if let value = Int(numberPart) {
                return value
            }
        }
        return nil
    }

    /// Instala el bootloader embebido. `single: true` destruye el boot
    /// NOR original de Apple (ver README de mks5lboot) -- Aura Studio
    /// solo lo ofrece si el usuario confirma explicitamente que no le
    /// interesa conservar el firmware original.
    func installBootloader(single: Bool) throws -> Result {
        guard let bootloaderURL = BundledArtifacts.shared.url(for: .bootloader) else {
            throw InstallerError.missingBundledArtifact(BundledArtifacts.Name.bootloader.rawValue)
        }
        var args = ["--bl-inst", bootloaderURL.path]
        if single { args.append("--single") }
        return try run(args)
    }

    /// Desinstala el bootloader de Aura, restaurando el arranque
    /// original de Apple.
    func uninstallBootloader() throws -> Result {
        try run(["--bl-uninst", "ipod6g"])
    }
}
