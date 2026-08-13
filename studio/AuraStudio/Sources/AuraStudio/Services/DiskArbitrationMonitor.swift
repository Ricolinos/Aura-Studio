import Foundation
import DiskArbitration
import IOKit
import IOKit.usb

/// Detecta el iPod cuando esta montado como disco (modo normal o modo
/// disco de Apple) usando DiskArbitration, y resuelve el problema de que
/// macOS moderno lo monta automaticamente en Finder: `unmount(then:)`
/// lo desmonta/expulsa programaticamente en el momento exacto en que
/// Aura Studio necesita escribir en el volumen o llevar al usuario a
/// modo DFU.
final class DiskArbitrationMonitor {
    typealias DiskChangeHandler = (DiskModeInfo?) -> Void

    private var session: DASession?
    private let queue = DispatchQueue(label: "com.ricolinos.aurastudio.diskarbitration")
    private var onChange: DiskChangeHandler?
    private var currentDisk: DADisk?

    func start(onChange: @escaping DiskChangeHandler) {
        self.onChange = onChange
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return }
        self.session = session
        DASessionSetDispatchQueue(session, queue)

        let context = Unmanaged.passUnretained(self).toOpaque()

        DARegisterDiskAppearedCallback(session, nil, { disk, ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<DiskArbitrationMonitor>.fromOpaque(ctx).takeUnretainedValue()
            monitor.handleDiskEvent(disk)
        }, context)

        DARegisterDiskDisappearedCallback(session, nil, { disk, ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<DiskArbitrationMonitor>.fromOpaque(ctx).takeUnretainedValue()
            monitor.handleDiskDisappeared(disk)
        }, context)

        // CRITICO (D-182): "aparecer" y "montarse" son eventos DISTINTOS
        // en DiskArbitration. DiskAppeared dispara cuando existe el
        // dispositivo BSD -- normalmente ANTES de que el volumen tenga
        // punto de montaje, asi que diskModeInfo() lo rechaza (regla
        // dura de D-070: sin montaje no hay nada donde trabajar). El
        // montaje real llega como cambio de descripcion. Sin este
        // callback, un volumen recien formateado por el instalador
        // montaba y nadie se enteraba: la pantalla "Copiando
        // archivos..." esperaba para siempre un evento que no existia
        // (visto en hardware real, 2026-08-13).
        DARegisterDiskDescriptionChangedCallback(
            session, nil,
            [kDADiskDescriptionVolumePathKey] as CFArray,
            { disk, _, ctx in
                guard let ctx else { return }
                let monitor = Unmanaged<DiskArbitrationMonitor>.fromOpaque(ctx).takeUnretainedValue()
                monitor.handleDiskDescriptionChanged(disk)
            }, context)
    }

    func stop() {
        if let session {
            DASessionSetDispatchQueue(session, nil)
        }
        session = nil
        currentDisk = nil
    }

    private func handleDiskEvent(_ disk: DADisk) {
        guard let info = Self.diskModeInfo(for: disk) else { return }
        currentDisk = disk
        onChange?(info)
    }

    private func handleDiskDisappeared(_ disk: DADisk) {
        guard let bsd = DADiskGetBSDName(disk), let current = currentDisk,
              let currentBSD = DADiskGetBSDName(current),
              String(cString: bsd) == String(cString: currentBSD) else { return }
        currentDisk = nil
        onChange?(nil)
    }

    /// Cambio el punto de montaje de un volumen: si ahora tiene uno y
    /// pasa los criterios, es el mismo camino que una aparicion; si el
    /// volumen que estabamos siguiendo se DESMONTO (sin desaparecer el
    /// dispositivo -- p.ej. el instalador lo desmonto para formatear),
    /// se notifica como perdido, porque un disco sin montaje no sirve
    /// para leer ni escribir.
    private func handleDiskDescriptionChanged(_ disk: DADisk) {
        if let info = Self.diskModeInfo(for: disk) {
            currentDisk = disk
            onChange?(info)
            return
        }
        if let bsd = DADiskGetBSDName(disk), let current = currentDisk,
           let currentBSD = DADiskGetBSDName(current),
           String(cString: bsd) == String(cString: currentBSD) {
            currentDisk = nil
            onChange?(nil)
        }
    }

    /// Traduce la descripcion de DiskArbitration a un `DiskModeInfo`, o
    /// nil si ese disco no es un volumen de iPod donde se pueda trabajar.
    ///
    /// Las dos condiciones son igual de importantes, y las dos fallaron
    /// en la version anterior (D-070):
    ///
    /// 1. TIENE que estar montado. DiskArbitration avisa por cada disco
    ///    Y cada particion: para un iPod llegan tres eventos (el disco
    ///    entero, la particion de firmware y el volumen de datos), y solo
    ///    el ultimo tiene punto de montaje. Aceptar los otros dejaba
    ///    `mountPath` vacio, y `URL(fileURLWithPath: "")` no falla: se
    ///    resuelve contra el directorio de trabajo, o sea "/". La app
    ///    terminaba leyendo la capacidad del disco de arranque del Mac e
    ///    intentando escribirle encima.
    ///
    /// 2. Tiene que pasar los MISMOS criterios estrictos que usa el
    ///    instalador (`DiskCandidateInfo.matchesIPodCriteria`). Antes
    ///    aca habia un criterio propio y mucho mas laxo -- un OR entre
    ///    vendor y modelo, sin exigir removible ni externo -- que
    ///    duplicaba mal una decision de seguridad que ya estaba resuelta
    ///    y testeada en otro archivo.
    /// La IDENTIDAD ("¿es un iPod?") se evalua sobre el DISCO COMPLETO
    /// y la operatividad (montaje, nombre, formato) sobre el volumen
    /// (D-186, medido en hardware real): la particion montada de un
    /// iPod en modo disco de Apple llega SIN MediaName y SIN
    /// DeviceVendor en su propia descripcion -- juzgarla por sus campos
    /// propios la rechazaba, y la app caia al falso "modo bootloader"
    /// con el volumen perfectamente montado en /Volumes. El disco
    /// completo padre si trae la identidad ("iPod", "Apple iPod
    /// Media"). Las protecciones de D-070 no cambian: el disco de
    /// arranque del Mac sigue siendo interno/no-removible tambien a
    /// nivel de disco completo.
    static func diskModeInfo(for disk: DADisk) -> DiskModeInfo? {
        guard let descCF = DADiskCopyDescription(disk) else { return nil }
        let desc = descCF as NSDictionary

        guard let mountURL = desc[kDADiskDescriptionVolumePathKey as String] as? URL,
              !mountURL.path.isEmpty else { return nil }

        let wholeDesc: NSDictionary
        if let wholeDisk = DADiskCopyWholeDisk(disk),
           let wholeCF = DADiskCopyDescription(wholeDisk) {
            wholeDesc = wholeCF as NSDictionary
        } else {
            wholeDesc = desc
        }

        let bsdName = DADiskGetBSDName(disk).map { String(cString: $0) } ?? ""
        let candidate = DiskCandidateInfo(
            bsdName: bsdName,
            vendor: (wholeDesc[kDADiskDescriptionDeviceVendorKey as String] as? String) ?? "",
            model: (wholeDesc[kDADiskDescriptionDeviceModelKey as String] as? String)
                ?? (wholeDesc[kDADiskDescriptionMediaNameKey as String] as? String) ?? "",
            isRemovable: (wholeDesc[kDADiskDescriptionMediaRemovableKey as String] as? Bool) ?? false,
            isInternal: (wholeDesc[kDADiskDescriptionDeviceInternalKey as String] as? Bool) ?? true,
            sizeBytes: (wholeDesc[kDADiskDescriptionMediaSizeKey as String] as? Int64) ?? 0,
            volumeName: desc[kDADiskDescriptionVolumeNameKey as String] as? String
        )
        guard candidate.matchesIPodCriteria else { return nil }

        let volumeKind = (desc[kDADiskDescriptionVolumeKindKey as String] as? String) ?? ""

        return DiskModeInfo(
            volumeName: candidate.volumeName ?? mountURL.lastPathComponent,
            mountPath: mountURL.path,
            bsdName: bsdName,
            isFAT32: volumeKind.lowercased() == "msdos"
        )
    }

    /// Desmonta (y expulsa) el disco detectado. Necesario antes de
    /// instalar el bootloader o de guiar al usuario a modo DFU/disco,
    /// porque Finder/macOS lo tiene montado y bloqueado apenas se
    /// conecta -- sin este paso el usuario tendria que hacerlo a mano
    /// desde Finder, y el flujo guiado se rompe.
    func unmount(completion: @escaping (Bool) -> Void) {
        guard let disk = currentDisk else {
            completion(false)
            return
        }
        DADiskUnmount(disk, DADiskUnmountOptions(kDADiskUnmountOptionWhole), { _, dissenter, ctx in
            let ok = dissenter == nil
            guard let ctx else { return }
            let box = Unmanaged<CompletionBox>.fromOpaque(ctx).takeRetainedValue()
            box.completion(ok)
        }, Unmanaged.passRetained(CompletionBox(completion: completion)).toOpaque())
    }

    private final class CompletionBox {
        let completion: (Bool) -> Void
        init(completion: @escaping (Bool) -> Void) { self.completion = completion }
    }
}
