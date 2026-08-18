import Foundation

/// ST-017: decide, sin tocar nada, cual es la PRIMERA accion del
/// instalador al confirmar el dispositivo -- es la parte de
/// `InstallerViewModel.acknowledgeDeviceReady()` que se puede probar con
/// datos sinteticos. Dos ordenes segun el modo de arranque (ver
/// `InstallerStep`):
///
///  - Dual boot: copiar primero (el modo disco de Apple sirve el USB),
///    DFU al final.
///  - Solo Aura (`--single`): formatear, flashear por DFU, y copiar
///    DESPUES via el "Bootloader USB mode" del bootloader recien grabado.
enum InstallPlanner {
    enum Action: Equatable {
        /// Copiar los archivos ahora (dual boot; o el bootloader ya esta,
        /// por evidencia o porque se grabo en esta corrida).
        case copyFiles
        /// Formatear el disco y despues ir a DFU (Solo Aura).
        case formatThenFlash
        /// Formatear el disco y despues copiar (el bootloader ya se grabo
        /// en esta corrida y el disco no esta en FAT32).
        case formatThenCopy
        /// Ir a DFU ahora (Solo Aura con el disco ya listo).
        case enterDFU
        /// Dual boot sobre un disco que habria que formatear: se detiene
        /// antes de borrar nada (D-185).
        case refuseDualBootRequiresWinpod
    }

    struct Plan: Equatable {
        let action: Action
        /// `true` cuando el flasheo va antes que la copia (Solo Aura).
        let flashFirst: Bool
    }

    /// - Parameters:
    ///   - volumeIsFAT32: `true`/`false` para un volumen montado, `nil`
    ///     cuando el disco no tiene ningun sistema de archivos legible.
    ///   - singleBoot: el usuario eligio Solo Aura (`--single`).
    ///   - canSkipFlash: `AuraDevice.canSkipBootloaderFlash` (evidencia
    ///     de bootloader grabado, ST-016).
    ///   - deviceIsAura: Aura verificada en el disco -- en Solo Aura se
    ///     conserva la biblioteca en vez de formatear.
    ///   - bootloaderFlashedThisFlow: el flasheo ya se hizo en esta
    ///     corrida (reintento tras un problema posterior).
    ///   - diskPreparedThisFlow: el disco ya se formateo en esta corrida.
    static func plan(volumeIsFAT32: Bool?,
                     singleBoot: Bool,
                     canSkipFlash: Bool,
                     deviceIsAura: Bool,
                     bootloaderFlashedThisFlow: Bool,
                     diskPreparedThisFlow: Bool) -> Plan {
        guard volumeIsFAT32 == true else {
            // Hay que formatear.
            if !singleBoot { return Plan(action: .refuseDualBootRequiresWinpod, flashFirst: false) }
            if bootloaderFlashedThisFlow { return Plan(action: .formatThenCopy, flashFirst: false) }
            return Plan(action: .formatThenFlash, flashFirst: true)
        }
        if canSkipFlash || bootloaderFlashedThisFlow {
            return Plan(action: .copyFiles, flashFirst: false)
        }
        if singleBoot {
            // Sin Aura verificada se formatea limpio: en Solo Aura no hay
            // particion de firmware de Apple que conservar, y un disco
            // con el firmware original (o archivos sueltos) no aporta
            // nada. Con Aura verificada, o ya formateado en esta corrida,
            // directo a DFU.
            if diskPreparedThisFlow || deviceIsAura {
                return Plan(action: .enterDFU, flashFirst: true)
            }
            return Plan(action: .formatThenFlash, flashFirst: true)
        }
        return Plan(action: .copyFiles, flashFirst: false)
    }
}
