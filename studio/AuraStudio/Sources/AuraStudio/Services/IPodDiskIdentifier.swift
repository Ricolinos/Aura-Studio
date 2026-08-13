import Foundation
import DiskArbitration
import IOKit
import IOKit.storage

/// Snapshot de un disco candidato, con solo los campos que hacen falta
/// para decidir si es "el iPod" -- deliberadamente un struct de datos
/// planos (no un `DADisk` ni nada atado a IOKit) para que la logica de
/// coincidencia sea una funcion pura, testeable con datos sinteticos
/// sin necesitar hardware real ni permisos de disco en los tests.
struct DiskCandidateInfo: Equatable, Sendable {
    let bsdName: String
    let vendor: String
    let model: String
    let isRemovable: Bool
    let isInternal: Bool
    let sizeBytes: Int64
    let volumeName: String?

    /// Criterios de seguridad para decidir si un disco es "el iPod".
    ///
    /// Obligatorios siempre: removible y externo -- el SSD interno del
    /// propio Mac reporta "APPLE SSD" en su modelo, asi que sin esto se
    /// confundiria con el disco de arranque (paso de verdad, ver D-070).
    ///
    /// Ademas hace falta UNA de estas señales de dispositivo:
    ///
    ///  - que el modelo diga "iPod" -- alcanza por si sola, sin exigir
    ///    vendor "Apple", porque el propio bootloader de mks5lboot en
    ///    "Bootloader USB mode" (D-175: disco con la particion de datos
    ///    invalida, cayendo a modo de recuperacion) NO reporta ningun
    ///    vendor -- confirmado en hardware real, `DeviceVendor` esta
    ///    ausente del todo en la descripcion de DiskArbitration -- pero
    ///    SI reporta "iPod" en el nombre de media (visto en hardware:
    ///    "latform iPod Ada", recortado). Exigir vendor ahi dejaba a
    ///    Aura Studio ciego justo en el escenario que mas necesita
    ///    reconocer el disco: recuperar una instalacion interrumpida.
    ///  - que el vendor sea Apple Y el tamaño caiga en el rango del
    ///    120GB de fabrica, para el caso ya visto en hardware (D-046)
    ///    donde el nombre de media era el del disco duro interno
    ///    ("HS12YHA") y no decia "iPod" -- aca si hace falta el vendor
    ///    como señal extra, porque el tamaño solo es una coincidencia
    ///    mucho mas debil que un modelo que dice "iPod" textualmente.
    ///
    /// El tamaño NO puede ser el unico criterio duro en ningun caso: los
    /// iPod Classic con el disco cambiado por flash (iFlash + SD, lo mas
    /// comun para mantenerlos vivos hoy) van de 32GB a 2TB, y exigir
    /// 120GB±5GB rechazaria justamente a los que mas se usan.
    var matchesIPodCriteria: Bool {
        guard isRemovable, !isInternal else { return false }
        guard IPodDiskIdentifier.plausibleSizeRange.contains(sizeBytes) else { return false }

        if model.localizedCaseInsensitiveContains("iPod") { return true }

        guard vendor.localizedCaseInsensitiveContains("Apple") else { return false }
        let diff = abs(sizeBytes - IPodDiskIdentifier.nominalSizeBytes)
        return diff <= IPodDiskIdentifier.sizeToleranceBytes
    }
}

enum DiskIdentificationResult: Equatable {
    case notFound
    case found(DiskCandidateInfo)
    /// Dos o mas discos cumplen los criterios simultaneamente -- la
    /// regla de seguridad es no elegir "el mas probable" nunca, sino
    /// negarse a continuar y que el usuario desconecte los demas.
    case ambiguous([DiskCandidateInfo])
}

enum IPodDiskIdentifier {
    /// iPod Classic 6G de 120GB: el tamaño reportado real (confirmado
    /// en hardware en esta sesion) es 120,034,123,776 bytes -- se usa
    /// 120GB decimal como nominal con margen generoso, porque el
    /// tamaño exacto reportado puede variar unos MB segun el firmware
    /// del propio disco.
    static let nominalSizeBytes: Int64 = 120_000_000_000
    static let sizeToleranceBytes: Int64 = 5_000_000_000

    /// Rango de tamaños que puede tener un iPod Classic 6G real, de
    /// fabrica o con el disco cambiado por flash: desde una tarjeta
    /// chica hasta el maximo practico de un iFlash con 4 SD. Sirve de
    /// cota de cordura, no de identificacion por si sola.
    static let plausibleSizeRange: ClosedRange<Int64> = 8_000_000_000...2_100_000_000_000

    /// Logica pura: dado el snapshot actual de discos externos, decide
    /// si hay exactamente un candidato valido, ninguno, o mas de uno
    /// (ambiguo). No toca disco, no hace I/O -- 100% testeable.
    static func identify(from candidates: [DiskCandidateInfo]) -> DiskIdentificationResult {
        let matches = candidates.filter { $0.matchesIPodCriteria }
        switch matches.count {
        case 0: return .notFound
        case 1: return .found(matches[0])
        default: return .ambiguous(matches)
        }
    }

    /// Adaptador real: enumera los IOMedia "whole disk" actuales via
    /// IOKit y les pide su descripcion a DiskArbitration. No aplica
    /// ningun filtro de coincidencia aca -- eso es trabajo de
    /// `identify(from:)`, para mantener la parte que decide separada
    /// de la parte que junta datos del sistema.
    static func currentCandidates() -> [DiskCandidateInfo] {
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return [] }

        var candidates: [DiskCandidateInfo] = []
        let matching = IOServiceMatching(kIOMediaClass) as NSMutableDictionary
        matching["Whole"] = true

        var iterator: io_iterator_t = IO_OBJECT_NULL
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching as CFDictionary, &iterator)
        guard kr == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }

            guard let disk = DADiskCreateFromIOMedia(kCFAllocatorDefault, session, service),
                  let descCF = DADiskCopyDescription(disk) else { continue }
            let desc = descCF as NSDictionary

            guard let bsdNamePtr = DADiskGetBSDName(disk) else { continue }
            let bsdName = String(cString: bsdNamePtr)

            let vendor = (desc[kDADiskDescriptionDeviceVendorKey as String] as? String) ?? ""
            let model = (desc[kDADiskDescriptionDeviceModelKey as String] as? String)
                ?? (desc[kDADiskDescriptionMediaNameKey as String] as? String) ?? ""
            let removable = (desc[kDADiskDescriptionMediaRemovableKey as String] as? Bool) ?? false
            let internalDisk = (desc[kDADiskDescriptionDeviceInternalKey as String] as? Bool) ?? true
            let size = (desc[kDADiskDescriptionMediaSizeKey as String] as? Int64) ?? 0
            let volumeName = desc[kDADiskDescriptionVolumeNameKey as String] as? String

            candidates.append(DiskCandidateInfo(
                bsdName: bsdName,
                vendor: vendor,
                model: model,
                isRemovable: removable,
                isInternal: internalDisk,
                sizeBytes: size,
                volumeName: volumeName
            ))
        }

        return candidates
    }
}
