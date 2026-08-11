import Foundation

/// Un iPod montado, ya inspeccionado: no solo "hay un disco Apple ahi"
/// (eso lo resuelve DiskModeInfo) sino QUE tiene instalado y cuanto hay
/// sincronizado. Es lo que le permite a Studio abrir directo la vista del
/// dispositivo en vez de pedirle al usuario que confirme nada.
struct AuraDevice: Equatable {
    /// Que firmware se detecto en el volumen.
    enum Firmware: Equatable {
        /// Ni `rockbox.ipod` ni `.rockbox/`: el iPod sigue con el
        /// firmware original de Apple (o esta recien formateado).
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

    var usedBytes: Int64 {
        max(capacityBytes - freeBytes, 0)
    }
}
