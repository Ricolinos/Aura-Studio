import Foundation

/// Un iPod montado, ya inspeccionado: no solo "hay un disco Apple ahi"
/// (eso lo resuelve DiskModeInfo) sino QUE tiene instalado y cuanto hay
/// sincronizado. Es lo que le permite a Studio abrir directo la vista del
/// dispositivo en vez de pedirle al usuario que confirme nada.
///
/// ST-016: la deteccion separa DOS hechos que antes iban fusionados:
///
///  - `firmware`: que ARCHIVOS hay en el disco (`.rockbox/`, `aura/`,
///    `rockbox.ipod`, `iPod_Control/`) y si el firmware correspondiente
///    dejo rastro de haber ARRANCADO alguna vez (`hasBooted`).
///  - `runningFirmware`: que firmware esta atendiendo el USB AHORA,
///    leido de los descriptores USB (`USBDeviceIdentity`) -- la unica
///    lectura real que existe desde una Mac.
///
/// Con esa separacion, una carpeta `.rockbox` copiada a mano sobre un
/// iPod con firmware de Apple (caso real del dueño) ya no se reporta como
/// "Aura instalado en dual boot": son archivos sin evidencia de arranque,
/// con el firmware de Apple corriendo -- y `isAura`, que es lo que
/// habilita biblioteca, sync, temas y nombre, exige evidencia.
struct AuraDevice: Equatable {
    /// Que firmware se detecto EN EL DISCO (archivos), con la evidencia
    /// de arranque que cada uno deja.
    enum Firmware: Equatable {
        /// Ni firmware de Apple (`iPod_Control/`) ni rastro de Rockbox:
        /// un disco recien formateado, sin nada que arrancar.
        case empty
        /// `iPod_Control/` presente y sin rastro de Rockbox: el iPod
        /// sigue con el firmware original de Apple.
        case stock
        /// Hay un `.rockbox/` pero sin rastro de Aura -- una instalacion
        /// de Rockbox comun. Se distingue del caso Aura a proposito: el
        /// instalador tiene que poder avisar que va a escribir encima.
        /// `hasBooted` es true cuando Rockbox dejo `.rockbox/.resume.cfg`
        /// o `.rockbox/config.cfg` -- archivos que solo escribe un
        /// Rockbox corriendo (no vienen en ningun paquete).
        case rockbox(hasBooted: Bool)
        /// Archivos de Aura en el disco. `hasBooted` es true cuando existe
        /// su `aura.cfg`, que el firmware escribe en el primer arranque
        /// (ver aura_settings.c) -- permite distinguir "recien copiado,
        /// nunca encendido" de "en uso".
        case aura(hasBooted: Bool)

        var hasBooted: Bool {
            switch self {
            case .rockbox(let booted), .aura(let booted): return booted
            case .stock, .empty: return false
            }
        }
    }

    let volumeName: String
    let mountPath: String
    let isFAT32: Bool
    let firmware: Firmware
    /// `iPod_Control/` existe en el volumen -- el contenido del firmware
    /// original de Apple sigue ahi, aunque el firmware activo sea otro.
    let originalFirmwarePresent: Bool
    /// ST-016: que firmware esta atendiendo el USB ahora mismo, leido de
    /// los descriptores USB del aparato. `.unknown` si no se pudo leer.
    let runningFirmware: RunningFirmware
    /// Serial USB reportado por el firmware que corre (ver
    /// `USBDeviceIdentity.serialNumber` -- cambia entre modos).
    let usbSerial: String?
    /// UUID del volumen (estable entre modos, vive en el disco).
    let volumeUUID: String?
    /// Capacidad y espacio libre reales del volumen, en bytes.
    let capacityBytes: Int64
    let freeBytes: Int64
    /// Resumen del ultimo sync (`sync_summary.cfg`). nil si Studio nunca
    /// sincronizo este dispositivo.
    let librarySummary: CatalogSummary?
    /// Nombre editable del iPod (`.rockbox/aura/device.cfg`,
    /// PLAN-general-sync.md §1.5/§9) -- `nil` hasta que Studio le asigne
    /// uno (la primera vez que ve este dispositivo con Aura instalada).
    let deviceIdentity: DeviceIdentity?

    /// Lo que se muestra en pantalla: el nombre asignado si ya existe,
    /// si no la etiqueta del volumen (como antes de esta funcionalidad).
    var displayName: String {
        deviceIdentity?.deviceName ?? volumeName
    }

    /// Hay archivos de Aura en el disco -- sin afirmar que arranquen.
    var hasAuraFiles: Bool {
        if case .aura = firmware { return true }
        return false
    }

    /// Aura instalada DE VERDAD: archivos de Aura en el disco y ademas
    /// evidencia de que ese firmware corre en este aparato -- o bien esta
    /// atendiendo el USB ahora mismo (lectura real), o bien ya arranco
    /// alguna vez y dejo su `aura.cfg`. Es lo que habilita biblioteca,
    /// sync, temas y nombre del iPod. Archivos copiados a mano sin
    /// ninguna de las dos cosas NO cuentan (ST-016).
    var isAura: Bool {
        guard case .aura(let hasBooted) = firmware else { return false }
        return hasBooted || runningFirmware == .rockboxFamily
    }

    /// Hay un arbol de la familia Rockbox (Aura o Rockbox comun) en el
    /// disco. Solo habla de archivos.
    var isRockboxFamily: Bool {
        switch firmware {
        case .aura, .rockbox: return true
        case .stock, .empty: return false
        }
    }

    /// Evidencia de que un firmware de la familia Rockbox CORRE en este
    /// aparato (y por lo tanto de que hay un bootloader de esa familia
    /// grabado en la NOR): esta atendiendo el USB ahora, o dejo rastro de
    /// haber arrancado. La NOR en si no se puede leer desde una Mac.
    var rockboxFamilyVerified: Bool {
        runningFirmware == .rockboxFamily || firmware.hasBooted
    }

    /// Ambos firmwares conviven Y el de la familia Rockbox tiene evidencia
    /// de arrancar. Sin esa evidencia no se afirma "dual boot": una
    /// carpeta copiada junto a `iPod_Control/` no lo es (ST-016).
    var isDualBoot: Bool {
        rockboxFamilyVerified && originalFirmwarePresent
    }

    /// Clave para el registro local "a este disco ya le verificamos el
    /// bootloader" (`AppPreferences.bootloaderVerifiedDisks`).
    var diskRecordKey: String? { volumeUUID ?? usbSerial }

    /// Decision del instalador (ST-016): ¿hay evidencia suficiente de que
    /// el bootloader de la familia Rockbox esta en la NOR como para
    /// saltarse el flasheo por DFU?
    ///
    ///  - Si el USB lo esta atendiendo Aura/Rockbox ahora mismo: si, sin
    ///    mas -- solo un bootloader grabado pudo arrancar eso.
    ///  - Si el disco tiene rastro de arranque (`aura.cfg`, `.resume.cfg`)
    ///    Y ADEMAS Studio tiene registro local de haber verificado el
    ///    bootloader en este mismo disco (lo flasheo, o lo vio corriendo
    ///    Rockbox/Aura antes): si.
    ///  - Cualquier otra cosa -- incluidos archivos con rastro de arranque
    ///    pero sin registro local (pudieron copiarse de otro iPod): no, se
    ///    flashea. Reflashear los mismos bytes es inofensivo; una
    ///    instalacion sin bootloader no arranca nunca (D-186, D-273).
    func canSkipBootloaderFlash(diskRecordedAsVerified: Bool) -> Bool {
        if runningFirmware == .rockboxFamily { return true }
        return firmware.hasBooted && diskRecordedAsVerified
    }

    var usedBytes: Int64 {
        max(capacityBytes - freeBytes, 0)
    }
}
