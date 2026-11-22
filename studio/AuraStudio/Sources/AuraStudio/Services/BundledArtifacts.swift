import Foundation
import CryptoKit

/// Ubica y verifica los artefactos del firmware Aura que la app trae
/// embebidos (copiados desde Vendor/firmware-dist/ en tiempo de build,
/// ver project.yml -- poblado por scripts/fetch-firmware.sh desde un
/// Release del repositorio Aura-Firmware, nunca desde un checkout de
/// sus fuentes. Ver CONTRATO-firmware-studio.md).
struct BundledArtifacts {
    let bundle: Bundle
    /// ST-047: de que familia son estos artefactos. Decide el
    /// subdirectorio de Resources (`FirmwareFamily.bundleSubdirectory`).
    let family: FirmwareFamily
    /// ST-077: si esta puesto, los artefactos NO salen del bundle sino de
    /// este directorio (los que `FirmwareReleaseDownloader` bajo y
    /// verifico del Release mas nuevo). Todo lo demas -- `verifyAll()`,
    /// `releaseTag`, la verificacion del contenido de `rockbox.zip` --
    /// funciona igual, que es justamente el punto: el instalador no
    /// tiene que saber de donde vinieron los archivos.
    let directory: URL?

    init(bundle: Bundle, family: FirmwareFamily = .aura) {
        self.bundle = bundle
        self.family = family
        self.directory = nil
    }

    /// Artefactos ya bajados y verificados en disco (ST-077).
    init(directory: URL, family: FirmwareFamily) {
        self.bundle = .main
        self.family = family
        self.directory = directory
    }

    /// Los de Aura, como siempre.
    static let shared = BundledArtifacts(bundle: .main)

    /// ST-047: los de la familia pedida. Para una familia no instalable
    /// devuelve igualmente un objeto, cuyo `url(for:)` sera nil para
    /// todo -- el llamador ya deberia haber filtrado por
    /// `FirmwareFamily.isInstallable`.
    static func forFamily(_ family: FirmwareFamily) -> BundledArtifacts {
        family == .aura ? shared : BundledArtifacts(bundle: .main, family: family)
    }

    enum Name: String, CaseIterable {
        case firmware = "rockbox.ipod"
        /// Arbol `.rockbox/` completo para el disco del iPod (ARM real,
        /// generado con `make zip` en build-ipod6g + fuentes e iconos
        /// del design system encima) -- fuentes a26-*, iconos/mascaras,
        /// codecs, plugins (solitaire incluido), codepages. Sin esto el
        /// firmware arranca pero sin tipografias SF ni iconos (D-045,
        /// cerrado en D-178).
        case rockboxTree = "rockbox.zip"
        case bootloader = "bootloader-ipod6g.ipod"
        case mks5lboot = "mks5lboot"
        case checksums = "checksums.txt"
    }

    func url(for name: Name) -> URL? {
        if let directory {
            let candidate = directory.appendingPathComponent(name.rawValue)
            return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
        }
        let base = name.rawValue as NSString
        return bundle.url(
            forResource: base.deletingPathExtension,
            withExtension: base.pathExtension.isEmpty ? nil : base.pathExtension,
            subdirectory: family.bundleSubdirectory
        )
    }

    /// ST-047: tag del Release del que salieron estos artefactos
    /// (`firmware-version.txt`, lo escribe scripts/fetch-firmware.sh).
    /// `nil` si la build se hizo sin el script (desarrollo viejo) -- la
    /// pantalla de Licencias lo dice en vez de inventar un tag.
    var releaseTag: String? {
        let versionURL: URL?
        if let directory {
            versionURL = directory.appendingPathComponent("firmware-version.txt")
        } else {
            versionURL = bundle.url(forResource: "firmware-version", withExtension: "txt",
                                    subdirectory: family.bundleSubdirectory)
        }
        guard let url = versionURL,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Parsea `checksums.txt` (formato de `shasum -a 256`: hash, dos
    /// espacios, nombre de archivo) en un diccionario nombre->hash.
    static func parseChecksums(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            let hash = String(parts[0])
            let filename = parts[1].trimmingCharacters(in: .whitespaces)
            result[filename] = hash
        }
        return result
    }

    static func sha256Hex(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// D-297/D-298 (Aura-Firmware), ST-018: `package_dist.sh` armaba
    /// `rockbox.zip` copiando assets a mano en vez de correr `make zip`
    /// -- el zip resultante tenia checksum interno consistente (coincidia
    /// con lo que el propio Release publicaba) pero **no traia codecs ni
    /// plugins/rocks**, asi que un iPod instalado con ese Release se
    /// quedaba sin video (mpegplayer.rock ausente) y, en instalaciones
    /// desde cero, sin audio tambien. Un checksum correcto por si solo
    /// nunca hubiera detectado esto -- el bug estaba en lo que el Release
    /// publico, no en la transferencia. Dos entradas representativas
    /// alcanzan (un plugin real y un codec real): si estas dos estan, el
    /// resto de `make zip` tambien corrio.
    static let requiredRockboxTreeEntries = [
        ".rockbox/rocks/viewers/mpegplayer.rock",
        ".rockbox/codecs/mpa.codec",
    ]

    /// Lista el contenido de `rockbox.zip` con `/usr/bin/unzip -l`
    /// (siempre presente en macOS, sin dependencias nuevas) y confirma
    /// que `requiredRockboxTreeEntries` esta en la salida.
    static func verifyRockboxTreeContents(at fileURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-l", fileURL.path]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        try process.run()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw InstallerError.incompleteRockboxTree(missing: requiredRockboxTreeEntries)
        }
        let listing = String(data: data, encoding: .utf8) ?? ""
        let missing = requiredRockboxTreeEntries.filter { !listing.contains($0) }
        guard missing.isEmpty else {
            throw InstallerError.incompleteRockboxTree(missing: missing)
        }
    }

    /// Verifica que cada artefacto embebido coincida con su hash en
    /// checksums.txt (lanza InstallerError.checksumMismatch en el primer
    /// archivo que no coincida) y, para `rockbox.zip`, que su contenido
    /// real tenga codecs y plugins (ver verifyRockboxTreeContents).
    func verifyAll() throws {
        guard let checksumsURL = url(for: .checksums) else {
            throw InstallerError.missingBundledArtifact(Name.checksums.rawValue)
        }
        let text = try String(contentsOf: checksumsURL, encoding: .utf8)
        let expected = Self.parseChecksums(text)

        for name in [Name.firmware, .rockboxTree, .bootloader, .mks5lboot] {
            guard let fileURL = url(for: name) else {
                throw InstallerError.missingBundledArtifact(name.rawValue)
            }
            guard let expectedHash = expected[name.rawValue] else {
                throw InstallerError.missingBundledArtifact(name.rawValue)
            }
            let actualHash = try Self.sha256Hex(of: fileURL)
            guard actualHash == expectedHash else {
                throw InstallerError.checksumMismatch(file: name.rawValue)
            }
            if name == .rockboxTree {
                try Self.verifyRockboxTreeContents(at: fileURL)
            }
        }
    }
}
