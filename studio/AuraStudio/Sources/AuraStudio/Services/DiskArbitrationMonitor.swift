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

    /// Nombres de volumen/proveedor que identifican un iPod frente a
    /// cualquier otro disco removible conectado (pendrives, etc.). Se
    /// contrasta contra kDADiskDescriptionDeviceVendorKey /
    /// kDADiskDescriptionDeviceModelKey, que expone el string USB real
    /// del dispositivo (p.ej. "Apple" / "iPod").
    private static let vendorMatch = "Apple"
    private static let modelMatch = "iPod"

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

    /// Extrae del diccionario de descripcion de DiskArbitration los
    /// datos que Aura Studio necesita mostrar/decidir: si es
    /// especificamente un iPod (por vendor/model USB), su punto de
    /// montaje, y si el filesystem es FAT32 (msdos) -- Rockbox necesita
    /// FAT32, no HFS+/APFS.
    static func diskModeInfo(for disk: DADisk) -> DiskModeInfo? {
        guard let descCF = DADiskCopyDescription(disk) else { return nil }
        let desc = descCF as NSDictionary

        let vendor = (desc[kDADiskDescriptionDeviceVendorKey as String] as? String) ?? ""
        let model = (desc[kDADiskDescriptionDeviceModelKey as String] as? String) ?? ""
        guard vendor.contains(vendorMatch) || model.contains(modelMatch) else { return nil }

        let volumeName = (desc[kDADiskDescriptionVolumeNameKey as String] as? String) ?? "iPod"
        let volumeKind = (desc[kDADiskDescriptionVolumeKindKey as String] as? String) ?? ""
        let mountURL = desc[kDADiskDescriptionVolumePathKey as String] as? URL
        let bsdNamePtr = DADiskGetBSDName(disk)
        let bsdName = bsdNamePtr.map { String(cString: $0) } ?? ""

        return DiskModeInfo(
            volumeName: volumeName,
            mountPath: mountURL?.path ?? "",
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
