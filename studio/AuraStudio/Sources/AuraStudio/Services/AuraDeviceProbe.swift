import Foundation

/// Inspecciona un volumen ya montado para saber que firmware tiene y
/// cuanto hay sincronizado.
///
/// Dos fuentes, guardadas por separado en `AuraDevice` (ST-016):
///
///   1. Archivos en el disco (`AuraDevice.firmware`):
///      - `rockbox.ipod` en la raiz -> lo copia el instalador de Studio.
///      - `.rockbox/aura/` o `.rockbox/icons/aura/` -> arbol de Aura.
///      - `.rockbox/` sin `aura/` -> una instalacion de Rockbox comun.
///      - `.rockbox/aura/aura.cfg` -> Aura ARRANCO aqui (lo escribe el
///        firmware en el primer arranque). `.rockbox/.resume.cfg` /
///        `.rockbox/config.cfg` -> un Rockbox arranco aqui (solo los
///        escribe un Rockbox corriendo; ningun paquete los trae).
///   2. Descriptores USB (`AuraDevice.runningFirmware`, via
///      `DiskModeInfo.usb`): que firmware esta atendiendo el USB ahora.
///      Es la unica lectura real -- los archivos se pueden copiar a mano,
///      los descriptores los emite el firmware que corre.
///   3. ST-046: la clave `firmware_family` de `aura.cfg`
///      (`AuraDevice.declaredFamily`): que dice ser el firmware instalado.
///      Ninguna de las dos fuentes de arriba puede contestar eso --
///      Metro-Aura escribe el mismo arbol `.rockbox/aura/` que Aura
///      (comparten el contrato §D a proposito) y por USB los dos se
///      anuncian como Rockbox.
///
/// El bootloader en la NOR no se puede leer desde una Mac; ver
/// `AuraDevice.canSkipBootloaderFlash`.
enum AuraDeviceProbe {
    static let firmwareBinaryName = "rockbox.ipod"
    static let rockboxDirName = ".rockbox"
    static let auraDirRelativePath = ".rockbox/aura"
    static let auraConfigRelativePath = ".rockbox/aura/aura.cfg"
    /// Marcador de instalacion de Aura que Studio SIEMPRE deja (los
    /// iconos del design system viajan en el arbol .rockbox desde
    /// D-178) -- a diferencia de `.rockbox/aura/`, que lo crea el
    /// firmware al arrancar por primera vez, este existe desde el
    /// momento de la instalacion.
    static let auraIconsRelativePath = ".rockbox/icons/aura"
    /// Rastro de un Rockbox (Aura incluida) que ya corrio: `.resume.cfg`
    /// lo escribe `flush_global_status_callback` en cada rato de disco
    /// inactivo (con el contador de tiempo de uso), `config.cfg` cada vez
    /// que cambia un ajuste y al apagar. Ninguno viene en `rockbox.zip`.
    static let rockboxResumeRelativePath = ".rockbox/.resume.cfg"
    static let rockboxConfigRelativePath = ".rockbox/config.cfg"
    /// Carpeta del firmware original de Apple (ahi viven su base de
    /// datos y su musica). Su presencia es lo que distingue "firmware
    /// original" de "disco recien formateado", y la mitad en disco de
    /// la deteccion de dual boot.
    static let iPodControlDirName = "iPod_Control"

    /// Devuelve nil si `mountPath` no es una ruta utilizable. No es
    /// paranoia: `URL(fileURLWithPath: "")` NO falla, se resuelve contra
    /// el directorio de trabajo del proceso -- o sea "/" -- asi que una
    /// ruta vacia hacia que todo lo de abajo (capacidad, lectura del
    /// resumen y despues la escritura del sync) apuntara al disco de
    /// arranque del Mac en vez de al iPod. Ya paso (D-070); esta guarda
    /// existe para que, si el origen vuelve a fallar, falle a la vista y
    /// no contra el disco equivocado.
    static func probe(diskInfo: DiskModeInfo,
                       fileManager: FileManager = .default) -> AuraDevice? {
        guard !diskInfo.mountPath.isEmpty, diskInfo.mountPath.hasPrefix("/") else { return nil }
        let root = URL(fileURLWithPath: diskInfo.mountPath)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }

        let exists: (String) -> Bool = { relative in
            fileManager.fileExists(atPath: root.appendingPathComponent(relative).path)
        }

        let originalPresent = exists(iPodControlDirName)
        let rockboxBooted = exists(rockboxResumeRelativePath) || exists(rockboxConfigRelativePath)

        let firmware: AuraDevice.Firmware
        if exists(auraDirRelativePath) || exists(auraIconsRelativePath) {
            firmware = .aura(hasBooted: exists(auraConfigRelativePath))
        } else if exists(firmwareBinaryName) {
            // Binario copiado pero el firmware nunca escribio nada suyo:
            // instalacion recien hecha, todavia sin arrancar.
            firmware = .aura(hasBooted: false)
        } else if exists(rockboxDirName) {
            firmware = .rockbox(hasBooted: rockboxBooted)
        } else if originalPresent {
            firmware = .stock
        } else {
            firmware = .empty
        }

        let (capacity, free) = capacityAndFree(at: root)

        return AuraDevice(
            volumeName: diskInfo.volumeName,
            mountPath: diskInfo.mountPath,
            isFAT32: diskInfo.isFAT32,
            firmware: firmware,
            originalFirmwarePresent: originalPresent,
            runningFirmware: diskInfo.usb?.runningFirmware ?? .unknown,
            declaredFamily: FirmwareCapabilities.declaredFamily(volumeRoot: root,
                                                                fileManager: fileManager),
            dormantFamilies: FirmwareSwitcher.dormantFamilies(volumeRoot: root, fileManager: fileManager),
            usbSerial: diskInfo.usb?.serialNumber,
            volumeUUID: diskInfo.volumeUUID,
            capacityBytes: capacity,
            freeBytes: free,
            librarySummary: readSummary(root: root, fileManager: fileManager),
            deviceIdentity: DeviceNameStore.load(volumeRoot: root, fileManager: fileManager)
        )
    }

    private static func readSummary(root: URL, fileManager: FileManager) -> CatalogSummary? {
        let url = root.appendingPathComponent(LibrarySync.summaryRelativePath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return CatalogSummaryReader.parse(text)
    }

    private static func capacityAndFree(at root: URL) -> (Int64, Int64) {
        guard let values = try? root.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
        ]) else {
            return (0, 0)
        }
        return (Int64(values.volumeTotalCapacity ?? 0),
                Int64(values.volumeAvailableCapacity ?? 0))
    }
}
