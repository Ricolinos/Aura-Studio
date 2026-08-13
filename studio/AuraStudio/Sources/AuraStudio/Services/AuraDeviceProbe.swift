import Foundation

/// Inspecciona un volumen ya montado para saber que firmware tiene y
/// cuanto hay sincronizado.
///
/// La deteccion es por archivos, no por USB: cuando el iPod esta en modo
/// almacenamiento el firmware NO se esta ejecutando -- es un disco y
/// nada mas. Asi que "tiene Aura instalada" solo se puede responder
/// mirando lo que quedo escrito en el disco:
///
///   - `rockbox.ipod` en la raiz -> lo copia el instalador de Studio.
///   - `.rockbox/aura/` -> lo crea el propio firmware Aura al guardar sus
///     ajustes o al recibir un sync.
///   - `.rockbox/` sin `aura/` -> una instalacion de Rockbox comun.
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

        let firmware: AuraDevice.Firmware
        if exists(auraDirRelativePath) || exists(auraIconsRelativePath) {
            firmware = .aura(hasBooted: exists(auraConfigRelativePath))
        } else if exists(firmwareBinaryName) {
            // Binario copiado pero el firmware nunca escribio nada suyo:
            // instalacion recien hecha, todavia sin arrancar.
            firmware = .aura(hasBooted: false)
        } else if exists(rockboxDirName) {
            firmware = .rockbox
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
            capacityBytes: capacity,
            freeBytes: free,
            librarySummary: readSummary(root: root, fileManager: fileManager)
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
