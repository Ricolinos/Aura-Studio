import Foundation

/// Un iPod montado, ya inspeccionado: no solo "hay un disco Apple ahi"
/// (eso lo resuelve DiskModeInfo) sino QUE tiene instalado y cuanto hay
/// sincronizado. Es lo que le permite a Studio abrir directo la vista del
/// dispositivo en vez de pedirle al usuario que confirme nada.
struct AuraDevice: Equatable {
    /// Que firmware se detecto en el volumen.
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
        case rockbox
        /// Aura instalada. `hasBooted` es true cuando existe su
        /// `aura.cfg`, que el firmware escribe en el primer arranque
        /// (ver aura_settings.c) -- permite distinguir "recien flasheado,
        /// nunca encendido" de "en uso".
        case aura(hasBooted: Bool)
    }

    let volumeName: String
    let mountPath: String
    let isFAT32: Bool
    let firmware: Firmware
    /// `iPod_Control/` existe en el volumen -- el contenido del firmware
    /// original de Apple sigue ahi, aunque el firmware activo sea otro.
    /// Es la mitad "en disco" de la deteccion de dual boot: que
    /// bootloader hay grabado en la NOR no se puede leer desde aca, asi
    /// que "dual boot" se reporta como "ambos firmwares conviven en el
    /// disco", que es lo observable y lo que el usuario necesita saber.
    let originalFirmwarePresent: Bool
    /// Capacidad y espacio libre reales del volumen, en bytes.
    let capacityBytes: Int64
    let freeBytes: Int64
    /// Resumen del ultimo sync (`sync_summary.cfg`). nil si Studio nunca
    /// sincronizo este dispositivo.
    let librarySummary: CatalogSummary?

    var isAura: Bool {
        if case .aura = firmware { return true }
        return false
    }

    /// Aura o Rockbox comun: cualquiera de los dos implica que hay (casi
    /// con certeza) un bootloader de la familia Rockbox ya grabado en la
    /// NOR -- y ese bootloader arranca `/.rockbox/rockbox.ipod` sin
    /// importar cual de los dos arboles este en el disco. Es la señal
    /// que le permite al instalador reemplazar solo la carpeta, sin
    /// pedir DFU de nuevo.
    var isRockboxFamily: Bool {
        switch firmware {
        case .aura, .rockbox: return true
        case .stock, .empty: return false
        }
    }

    var isDualBoot: Bool {
        isRockboxFamily && originalFirmwarePresent
    }

    var usedBytes: Int64 {
        max(capacityBytes - freeBytes, 0)
    }
}
