import Foundation
import IOKit
import IOKit.usb
import DiskArbitration

/// Lo que el firmware que esta CORRIENDO en el iPod anuncia en sus
/// descriptores USB (ST-016). Es la unica lectura real que hay desde una
/// Mac: en modo disco el firmware que atiende el USB es el que responde
/// -- el modo disco de Apple se presenta como "Apple Inc." / "iPod";
/// Rockbox (y Aura, que no cambia estas cadenas -- `usb_core.c:141-145`
/// del firmware) se presenta como "Rockbox.org" / "Rockbox media
/// player", tambien cuando es el propio bootloader en su modo USB
/// (`HAVE_BOOTLOADER_USB_MODE`, mismos descriptores). VID/PID son los
/// MISMOS en los dos casos (`0x05AC`/`0x1261`, `ipod6g.h:256-257`), asi
/// que no distinguen firmware, pero si identifican el aparato: ningun
/// otro dispositivo Apple usa ese PID.
///
/// Lo que NO se puede leer desde aca: si el bootloader de Aura esta
/// grabado en la NOR. `mks5lboot --bl-inst` escribe solo la NOR por DFU,
/// no deja rastro en el disco, y no existe un modo de consulta -- verificado
/// contra `utils/mks5lboot/dualboot/dualboot.c` y `main.c` del firmware.
struct USBDeviceIdentity: Equatable, Sendable {
    let vendorName: String
    let productName: String
    /// Serial USB. Ojo: NO es estable entre firmwares -- el modo disco de
    /// Apple reporta 16 hex; Rockbox deriva 40 hex del serial ATA del
    /// disco (`usb_core.c:377-400`). Sirve para reconocer un aparato
    /// dentro del mismo modo, no para cruzar entre modos.
    let serialNumber: String?
    let vendorID: Int
    let productID: Int

    static let appleVendorID = 0x05AC
    /// iPod Classic (6G/7G) en modo disco de Apple -- y Rockbox reutiliza
    /// exactamente el mismo par al correr en el ipod6g.
    static let iPodClassicProductID = 0x1261

    /// El par VID/PID que solo tiene un iPod Classic. Un iPhone/iPad
    /// tambien es 0x05AC pero con otro PID; un disco USB cualquiera no
    /// es 0x05AC.
    var isIPodClassicUSB: Bool {
        vendorID == Self.appleVendorID && productID == Self.iPodClassicProductID
    }

    var runningFirmware: RunningFirmware {
        RunningFirmware.classify(vendorName: vendorName, productName: productName)
    }
}

/// Que firmware esta atendiendo el USB ahora mismo (ST-016). Es un hecho
/// distinto de "que archivos hay en el disco" (`AuraDevice.Firmware`) y
/// se guarda aparte a proposito.
enum RunningFirmware: Equatable, Sendable {
    /// Modo disco del firmware original de Apple.
    case apple
    /// Rockbox o Aura (indistinguibles por USB), o su bootloader en modo
    /// USB. Prueba de que hay un bootloader de la familia Rockbox
    /// grabado en la NOR: nada mas pudo poner ese firmware a atender el
    /// USB.
    case rockboxFamily
    /// No se pudo leer (sin arbol IOKit, tests con datos sinteticos, o
    /// cadenas que no son ninguna de las dos).
    case unknown

    static func classify(vendorName: String, productName: String) -> RunningFirmware {
        let vendor = vendorName.lowercased()
        let product = productName.lowercased()
        if vendor.contains("rockbox") || product.contains("rockbox") { return .rockboxFamily }
        // El modo disco de Apple anuncia producto "iPod" (Rockbox nunca:
        // su producto es "Rockbox media player"). El vendor puede faltar
        // si solo se pudo leer el nodo de interfaz (ver el lector).
        if product.contains("ipod") && (vendor.isEmpty || vendor.contains("apple")) { return .apple }
        return .unknown
    }
}

/// Lector real: sube por el arbol de IOKit desde el `IOMedia` del disco
/// hasta el dispositivo USB que lo aloja y toma sus descriptores. No
/// decide nada -- solo junta datos; la clasificacion es
/// `RunningFirmware.classify`, pura y testeable.
enum USBDeviceIdentityReader {
    private static let maxDepth = 24

    static func identity(forDisk disk: DADisk) -> USBDeviceIdentity? {
        let media = DADiskCopyIOMedia(disk)
        guard media != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(media) }
        return identity(forIOMedia: media)
    }

    /// Al subir desde el IOMedia, el primer nodo con `idVendor`/`idProduct`
    /// suele ser la INTERFAZ USB (`IOUSBHostInterface`), que trae VID/PID
    /// y a veces el nombre de producto pero NO el vendor ni el serial
    /// (medido en hardware real, ST-016: "iPod", 0x05AC/0x1261, vendor
    /// vacio). El nodo de DISPOSITIVO (`IOUSBHostDevice`), un nivel mas
    /// arriba, trae las tres cadenas. Se sigue subiendo hasta encontrar
    /// uno con vendor o serial; si no aparece, se devuelve el mejor
    /// nodo visto (VID/PID siguen valiendo para identificar el aparato).
    static func identity(forIOMedia media: io_object_t) -> USBDeviceIdentity? {
        var current: io_object_t = media
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }

        var best: USBDeviceIdentity?
        for _ in 0..<maxDepth {
            if let identity = readIdentity(from: current) {
                if !identity.vendorName.isEmpty || identity.serialNumber != nil {
                    return identity
                }
                best = merge(best, identity)
            }
            var parent: io_object_t = IO_OBJECT_NULL
            let kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            guard kr == KERN_SUCCESS, parent != IO_OBJECT_NULL else { return best }
            IOObjectRelease(current)
            current = parent
        }
        return best
    }

    /// Conserva las cadenas no vacias de lo ya visto (p. ej. el nombre de
    /// producto de la interfaz) al pasar a un nodo superior.
    private static func merge(_ previous: USBDeviceIdentity?, _ next: USBDeviceIdentity) -> USBDeviceIdentity {
        guard let previous else { return next }
        return USBDeviceIdentity(
            vendorName: next.vendorName.isEmpty ? previous.vendorName : next.vendorName,
            productName: next.productName.isEmpty ? previous.productName : next.productName,
            serialNumber: next.serialNumber ?? previous.serialNumber,
            vendorID: next.vendorID,
            productID: next.productID
        )
    }

    private static func readIdentity(from entry: io_object_t) -> USBDeviceIdentity? {
        guard let vendorID = intProperty("idVendor", of: entry),
              let productID = intProperty("idProduct", of: entry) else { return nil }
        return USBDeviceIdentity(
            vendorName: stringProperty("USB Vendor Name", of: entry) ?? "",
            productName: stringProperty("USB Product Name", of: entry) ?? "",
            serialNumber: stringProperty("USB Serial Number", of: entry),
            vendorID: vendorID,
            productID: productID
        )
    }

    private static func intProperty(_ key: String, of entry: io_object_t) -> Int? {
        guard let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() else { return nil }
        return (value as? NSNumber)?.intValue
    }

    private static func stringProperty(_ key: String, of entry: io_object_t) -> String? {
        guard let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() else { return nil }
        return value as? String
    }
}
