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

    /// Los 4 criterios que pide la Fase de seguridad de discos: vendor
    /// Apple, removible, externo (no interno), y tamaño dentro de lo
    /// esperado para un iPod Classic 6G de 120GB. Deliberadamente NO
    /// exige que `model`/`vendor` contenga literalmente "iPod": en
    /// pruebas reales contra hardware fisico, `diskutil info` devolvio
    /// como nombre de media el modelo del disco duro interno del iPod
    /// (p.ej. "HS12YHA"), no un string de marca Apple -- exigir eso
    /// hubiera rechazado el dispositivo real. El vendor si se exige
    /// (viene de DiskArbitration, que en las pruebas de esta sesion
    /// consistentemente reportaba "Apple" para este dispositivo), y el
    /// combo removible+externo+tamaño da la señal de seguridad real.
    var matchesIPodCriteria: Bool {
        guard vendor.localizedCaseInsensitiveContains("Apple") else { return false }
        guard isRemovable, !isInternal else { return false }
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
