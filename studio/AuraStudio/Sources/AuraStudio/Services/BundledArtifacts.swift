import Foundation
import CryptoKit

/// Ubica y verifica los artefactos del firmware Aura que la app trae
/// embebidos (copiados desde Vendor/firmware-dist/ en tiempo de build,
/// ver project.yml -- poblado por scripts/fetch-firmware.sh desde un
/// Release del repositorio Aura-Firmware, nunca desde un checkout de
/// sus fuentes. Ver CONTRATO-firmware-studio.md).
struct BundledArtifacts {
    let bundle: Bundle

    static let shared = BundledArtifacts(bundle: .main)

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
        let base = name.rawValue as NSString
        return bundle.url(
            forResource: base.deletingPathExtension,
            withExtension: base.pathExtension.isEmpty ? nil : base.pathExtension
        )
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

    /// Verifica que cada artefacto embebido coincida con su hash en
    /// checksums.txt. Lanza InstallerError.checksumMismatch en el primer
    /// archivo que no coincida.
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
        }
    }
}
