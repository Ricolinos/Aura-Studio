import Foundation

/// Cuándo ofrecer "Actualizar el arranque" (ST-143, plan maestro §B.5).
///
/// El bootloader vive en la NOR del iPod y **no se puede leer desde la
/// Mac** — la única forma de saber cuál está grabado es acordarse de
/// haberlo grabado (`AppPreferences.bootloaderVerifiedDisks`). Cuando el
/// pin de `FIRMWARE_VERSION` trae un `bootloader-ipod6g.ipod` distinto
/// al registrado, esta es la regla que decide si vale la pena decírselo
/// al usuario.
///
/// Es aritmética de tres datos, sin disco ni red de por medio, para que
/// se pueda probar entera — la misma decisión y los mismos casos que
/// `AuraStudio.Core/Installer/BootloaderUpdate.cs` en el port.
enum BootloaderUpdate {
    /// Un disco verificado por una versión anterior, que anotaba fecha y
    /// no hash. No es "sin verificar": el bootloader está, solo que no se
    /// sabe de qué versión -- por eso se ofrece actualizarlo, sin exigirlo.
    static let unknownBootloader = "unknown"

    /// `true` si hay algo que ofrecer.
    ///
    /// - `recordedHash`: lo que esta instalación anotó para ese disco.
    ///   `nil` = nunca le verificó el arranque; `unknown` = lo verificó
    ///   una versión anterior a ST-143, que no guardaba el hash.
    /// - `embeddedHash`: el del `bootloader-ipod6g.ipod` que trae esta
    ///   build **para la familia instalada en el iPod** — no para la
    ///   familia por omisión: un iPod con Metro se compara contra el
    ///   bootloader de Metro.
    /// - `hasOurFirmware`: hay rastro de un firmware nuestro en el disco.
    ///   Sin eso no se ofrece nada: en un iPod de fábrica lo que
    ///   corresponde es instalar, no "actualizar el arranque".
    static func isAvailable(recordedHash: String?, embeddedHash: String?, hasOurFirmware: Bool) -> Bool {
        guard hasOurFirmware, let embeddedHash, !embeddedHash.isEmpty else { return false }
        return recordedHash != embeddedHash
    }

    /// Por qué se ofrece, para poder decirlo en pantalla sin que la vista
    /// tenga que deducirlo.
    enum Reason: Equatable {
        /// Se sabe que el arranque grabado es de otra versión.
        case differentBootloader
        /// El iPod se instaló con una versión de Studio que no anotaba
        /// cuál — o lo instaló otra Mac. Puede que ya esté al día.
        case unknownBootloader
    }

    /// Segundos que se espera en la pantalla de DFU antes de ofrecer la
    /// ayuda de último recurso (pausar los agentes AMP). Doce son los
    /// que tarda la combinación de botones; veinte dan margen para
    /// intentarla una vez y ver que no pasó nada.
    static let assistDelaySeconds: TimeInterval = 20

    /// ST-143 (addendum): si la pantalla de DFU debe ofrecer **"¿No
    /// aparece? Pausar los servicios de macOS"**.
    ///
    /// El flujo de actualizar el arranque arranca con **cero diálogos de
    /// contraseña** a propósito, así que esta ayuda no puede estar desde
    /// el principio: aparece solo cuando ya se esperó de más y el iPod
    /// sigue sin detectarse. En el instalador completo no se ofrece acá
    /// porque ese flujo ya lo propone antes de llegar al DFU.
    static func shouldOfferServicePause(mode: InstallerMode,
                                        secondsWaiting: TimeInterval,
                                        isDFUDetected: Bool,
                                        alreadyPaused: Bool) -> Bool {
        guard mode == .updateBootloader else { return false }
        guard !isDFUDetected, !alreadyPaused else { return false }
        return secondsWaiting >= assistDelaySeconds
    }

    static func reason(recordedHash: String?, embeddedHash: String?, hasOurFirmware: Bool) -> Reason? {
        guard isAvailable(recordedHash: recordedHash, embeddedHash: embeddedHash,
                          hasOurFirmware: hasOurFirmware) else { return nil }
        guard let recordedHash, recordedHash != unknownBootloader else {
            return .unknownBootloader
        }
        return .differentBootloader
    }
}
