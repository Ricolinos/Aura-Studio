import Foundation

/// Pasos del asistente de instalacion/restauracion. El flujo normal es
/// lineal (welcome -> permissions -> detect -> enterDFU -> installing ->
/// done), pero `detect`/`enterDFU` pueden avanzar solos cuando
/// `IPodMonitor` confirma el estado esperado (ver InstallerViewModel).
enum InstallerStep: Int, CaseIterable, Comparable {
    case welcome
    case permissions
    case detectDevice
    case enterDFU
    case installing
    case done
    case failed

    static func < (lhs: InstallerStep, rhs: InstallerStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum InstallerMode: Equatable {
    case install
    case restore
}

enum InstallerError: Error, LocalizedError, Equatable {
    case deviceNotFound
    case wrongDiskFormat
    case dfuTimeout
    case checksumMismatch(file: String)
    case processFailed(exitCode: Int32, output: String)
    case missingBundledArtifact(String)

    var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "No se detecto ningun iPod conectado."
        case .wrongDiskFormat:
            return "El iPod no esta formateado en FAT32. Convertilo antes de continuar."
        case .dfuTimeout:
            return "No se detecto el iPod en modo DFU a tiempo. Volve a intentar la combinacion de botones."
        case .checksumMismatch(let file):
            return "El archivo \(file) no supero la verificacion de integridad."
        case .processFailed(let exitCode, let output):
            return "mks5lboot termino con codigo \(exitCode): \(output)"
        case .missingBundledArtifact(let name):
            return "Falta el artefacto \(name) dentro de la app. Reinstala Aura Studio."
        }
    }
}
