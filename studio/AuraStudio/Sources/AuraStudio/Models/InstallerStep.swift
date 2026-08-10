import Foundation

/// Pasos del asistente de instalacion/restauracion. El flujo normal es
/// lineal, pero varios pasos avanzan solos cuando `IPodMonitor` (o el
/// resultado de una operacion privilegiada) confirma el estado
/// esperado -- ver `InstallerViewModel`.
///
/// `bootloaderUSBMode`/`preparingDisk`/`copyingFiles` se agregaron
/// despues de flashear un iPod real por primera vez en esta sesion: el
/// flujo original terminaba en `installing`, pero en la practica hace
/// falta reconectar en modo Bootloader USB, (a veces) reformatear la
/// particion de datos, y recien despues copiar los archivos del
/// firmware -- ninguno de esos pasos existia en el diseño original.
enum InstallerStep: Int, CaseIterable, Comparable {
    case welcome
    case permissions
    case detectDevice
    case enterDFU
    case installing
    case bootloaderUSBMode
    case preparingDisk
    case copyingFiles
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

/// Una accion privilegiada pendiente de autorizacion del usuario. La UI
/// muestra `explanationTitle`/`explanationBody`/`cancelConsequence`
/// ANTES de disparar el dialogo nativo de contraseña de macOS -- nunca
/// se pide autorizacion sin explicar antes, en español simple, que se
/// va a hacer y por que.
struct PendingAuthorization: Identifiable {
    enum Kind: Equatable {
        case pauseAMPAgents
        case formatDisk(volumeName: String, diskIdentifier: String)
    }

    let id = UUID()
    let kind: Kind
    let explanationTitle: String
    let explanationBody: String
    let cancelConsequence: String

    static func pauseAMPAgents() -> PendingAuthorization {
        PendingAuthorization(
            kind: .pauseAMPAgents,
            explanationTitle: "Pausar servicios de macOS",
            explanationBody: "Aura Studio necesita pausar temporalmente dos servicios de macOS que a veces interfieren con la conexión del iPod (AMPDevicesAgent y AMPDeviceDiscoveryAgent). Se reactivan automáticamente al terminar, o solos después de unos minutos si algo falla.",
            cancelConsequence: "Si cancelás, Aura Studio va a seguir intentando detectar el iPod igual -- en la mayoría de las Mac esto no hace falta, pero si la detección falla repetidamente, puede ser la causa."
        )
    }

    static func formatDisk(volumeName: String, diskIdentifier: String) -> PendingAuthorization {
        PendingAuthorization(
            kind: .formatDisk(volumeName: volumeName, diskIdentifier: diskIdentifier),
            explanationTitle: "Preparar el disco del iPod",
            explanationBody: "Vamos a formatear la partición de datos de tu iPod (identificada como \"\(volumeName)\", disco \(diskIdentifier)) para que pueda arrancar Aura. Esto borra TODO el contenido actual del iPod -- solo del iPod, Aura Studio ya verificó su identidad por tamaño, fabricante y tipo de disco antes de llegar a este paso.",
            cancelConsequence: "Si cancelás, la instalación se detiene acá. El iPod queda como estaba, sin ningún cambio -- podés reintentar cuando quieras."
        )
    }
}

enum InstallerError: Error, LocalizedError, Equatable {
    case deviceNotFound
    case wrongDiskFormat
    case dfuTimeout
    case checksumMismatch(file: String)
    case processFailed(exitCode: Int32, output: String)
    case missingBundledArtifact(String)
    case diskAmbiguous(count: Int)
    case authorizationCancelled
    case privilegedOperationFailed(String)

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
        case .diskAmbiguous(let count):
            return "Se encontraron \(count) discos que podrian ser tu iPod. Por seguridad, Aura Studio no elige uno solo -- desconecta los demas discos externos y volve a intentar."
        case .authorizationCancelled:
            return "Cancelaste la autorización de administrador. Este paso no puede continuar sin ese permiso."
        case .privilegedOperationFailed(let message):
            return message
        }
    }
}
