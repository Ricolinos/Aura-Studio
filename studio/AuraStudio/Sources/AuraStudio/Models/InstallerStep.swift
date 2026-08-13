import Foundation

/// Pasos del asistente de instalacion/restauracion. El flujo normal es
/// lineal, pero varios pasos avanzan solos cuando `IPodMonitor` (o el
/// resultado de una operacion privilegiada) confirma el estado
/// esperado -- ver `InstallerViewModel`.
///
/// Orden real verificado a mano por el usuario en hardware real: primero
/// se prepara el disco de datos (formatear a FAT32 si hace falta, copiar
/// los archivos del firmware) mientras el iPod todavia esta corriendo su
/// firmware original y montado en modo disco normal -- eso NO requiere
/// DFU, porque en el iPod 6G el bootloader vive en NOR flash interna,
/// completamente separada del disco. Recien al final se entra a DFU para
/// flashear el bootloader. El diseño anterior lo hacia al reves
/// (DFU/bootloader primero, disco despues via un reconecte especial a
/// "modo Bootloader USB") -- funcionaba en teoria pero dependia de un
/// paso extra fragil (detectar el reconecte en ese modo especifico) que
/// nunca hizo falta.
enum InstallerStep: Int, CaseIterable, Comparable {
    case welcome
    /// Solo en modo instalar -- elegir dual boot (default) o reemplazar
    /// por completo el firmware de Apple. Restaurar la salta siempre.
    case chooseBootMode
    case permissions
    case detectDevice
    case preparingDisk
    case copyingFiles
    case enterDFU
    case installing
    /// Solo en modo restaurar (D-184): tras quitar el bootloader por
    /// DFU, esperar a que el iPod reaparezca como disco y prepararlo
    /// para Finder con el doble formateo (puente FAT/MBR y despues
    /// Mac OS Plus con registro / mapa GUID).
    case restoreFormatting
    /// Solo en modo restaurar: el disco quedo listo -- la restauracion
    /// del firmware de Apple la termina Finder, con Aura Studio CERRADO
    /// para no interferir con la deteccion USB.
    case restoreHandoff
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
        case restoreFormatDisk(diskIdentifier: String)
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
            cancelConsequence: "Si cancelas, Aura Studio va a seguir intentando detectar el iPod igual -- en la mayoría de las Mac esto no hace falta, pero si la detección falla repetidamente, puede ser la causa."
        )
    }

    static func restoreFormatDisk(diskIdentifier: String) -> PendingAuthorization {
        PendingAuthorization(
            kind: .restoreFormatDisk(diskIdentifier: diskIdentifier),
            explanationTitle: "Preparar el disco para Finder",
            explanationBody: "Para que Finder pueda restaurar el firmware original de Apple, el disco del iPod (\(diskIdentifier)) se va a formatear dos veces: primero un formato puente (FAT con esquema MBR) y despues Mac OS Plus con registro con mapa de particiones GUID -- el estado que Finder espera. Esto borra todo el contenido del iPod.",
            cancelConsequence: "Si cancelas, el iPod queda sin el bootloader de Aura pero con el disco sin preparar -- Finder podria no reconocerlo para restaurar. Puedes reintentar cuando quieras."
        )
    }

    static func formatDisk(volumeName: String, diskIdentifier: String) -> PendingAuthorization {
        PendingAuthorization(
            kind: .formatDisk(volumeName: volumeName, diskIdentifier: diskIdentifier),
            explanationTitle: "Preparar el disco del iPod",
            explanationBody: "Vamos a formatear la partición de datos de tu iPod (identificada como \"\(volumeName)\", disco \(diskIdentifier)) para que pueda arrancar Aura. Esto borra TODO el contenido actual del iPod -- solo del iPod, Aura Studio ya verificó su identidad por tamaño, fabricante y tipo de disco antes de llegar a este paso.",
            cancelConsequence: "Si cancelas, la instalación se detiene acá. El iPod queda como estaba, sin ningún cambio -- puedes reintentar cuando quieras."
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
    /// TCC bloqueo la escritura directa al disco (newfs_msdos crudo).
    /// `FailedView` muestra para este caso el boton que abre el panel
    /// de Acceso total al disco, con la explicacion de que hacer.
    case fullDiskAccessDenied
    /// Dual boot elegido pero el disco necesitaria formatearse desde
    /// cero -- lo que destruiria justamente el firmware de Apple que
    /// dual boot promete conservar (D-185).
    case dualBootRequiresWinpod
    /// El volumen del iPod dejo de responder a mitad de la copia del
    /// firmware -- reproducido a mano (D-189): copiar el arbol
    /// completo (miles de archivos chicos) por USB puede tardar varios
    /// minutos, y el aparato se desconecto antes de terminar. No es un
    /// error de la app ni del disco: nada que la app haya escrito se
    /// pierde (la extraccion hace merge, retomar desde cero es seguro).
    case deviceDisconnectedDuringCopy

    var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "No se detecto ningun iPod conectado."
        case .wrongDiskFormat:
            return "El iPod no esta formateado en FAT32. Conviértelo antes de continuar."
        case .dfuTimeout:
            return "No se detecto el iPod en modo DFU a tiempo. Vuelve a intentar la combinacion de botones."
        case .checksumMismatch(let file):
            return "El archivo \(file) no supero la verificacion de integridad."
        case .processFailed(let exitCode, let output):
            // Sin nombrar herramienta: este error lo producen tanto
            // mks5lboot como la extraccion de archivos (ditto) -- el
            // texto viejo culpaba a mks5lboot de fallas que no eran
            // suyas (visto en vivo, D-185).
            return "La operación terminó con código \(exitCode): \(output)"
        case .missingBundledArtifact(let name):
            return "Falta el artefacto \(name) dentro de la app. Reinstala Aura Studio."
        case .diskAmbiguous(let count):
            return "Se encontraron \(count) discos que podrian ser tu iPod. Por seguridad, Aura Studio no elige uno solo -- desconecta los demas discos externos y vuelve a intentar."
        case .authorizationCancelled:
            return "Cancelaste la autorización de administrador. Este paso no puede continuar sin ese permiso."
        case .privilegedOperationFailed(let message):
            return message
        case .fullDiskAccessDenied:
            return "macOS bloqueó el acceso directo al disco del iPod. Concede \"Acceso total al disco\" a Aura Studio en Ajustes del Sistema (Privacidad y seguridad), cierra la app por completo, vuelve a abrirla y reintenta. Si Aura Studio ya aparece en la lista, quítala con el botón \"−\" y agrégala de nuevo -- el permiso puede quedar atado a una versión anterior de la app."
        case .dualBootRequiresWinpod:
            return "Para dual boot, el iPod debe conservar el firmware original de Apple en formato \"winpod\": tabla de particiones MBR con la partición de firmware de Apple intacta más una partición FAT32 -- el formato que crea iTunes al restaurar en una PC con WINDOWS. Este iPod está en formato de Mac (particiones Apple/HFS, que Rockbox no puede leer) o su disco no es legible, y prepararlo desde aquí borraría el disco completo, incluido el firmware original -- exactamente lo que dual boot promete conservar. Por eso no se te pidió la contraseña de administrador como en una instalación normal: no hay nada seguro que formatear todavía. Opciones: restaura el iPod con iTunes en Windows y vuelve a intentar dual boot, o instala solo Aura si no necesitas conservar el firmware de Apple."
        case .deviceDisconnectedDuringCopy:
            return "Tu iPod se desconectó durante la copia de archivos. Copiar el firmware completo son miles de archivos chicos y puede tardar varios minutos por USB -- revisa el cable (evita hubs USB si usas uno) y vuelve a intentar: lo que ya se copió no se pierde, la copia sigue desde donde quedó."
        }
    }
}
