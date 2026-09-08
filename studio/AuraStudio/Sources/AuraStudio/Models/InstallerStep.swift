import Foundation

/// Pasos del asistente de instalacion/restauracion. El flujo normal es
/// lineal, pero varios pasos avanzan solos cuando `IPodMonitor` (o el
/// resultado de una operacion privilegiada) confirma el estado
/// esperado -- ver `InstallerViewModel`.
///
/// Dos ordenes segun el modo de arranque elegido (ST-017):
///
///  - **Dual boot**: primero se prepara el disco de datos (copiar los
///    archivos del firmware) mientras el iPod todavia corre su firmware
///    original y esta montado en modo disco normal -- no requiere DFU,
///    porque en el iPod 6G el bootloader vive en NOR flash interna,
///    separada del disco. Recien al final se entra a DFU para flashear.
///    Tras el flasheo el bootloader encuentra `rockbox.ipod` y arranca.
///  - **Solo Aura** (`--single`, destruye el arranque de Apple): el
///    flasheo va PRIMERO. Se formatea el disco (todavia con Apple
///    corriendo), se flashea por DFU, el iPod se reinicia solo y -- como
///    aun no tiene `rockbox.ipod` -- su bootloader cae en `fatal_error
///    (ERR_RB)` y entra automaticamente a "Bootloader USB mode"
///    (`bootloader/ipod-s5l87xx.c`): aparece como disco, y RECIEN AHI se
///    copia Aura. Copiar antes de flashear era trabajo perdido si el
///    flasheo fallaba, y en este modo el que atiende el USB despues ya no
///    es Apple: es el bootloader de Rockbox, que Studio reconoce por sus
///    descriptores USB (`Rockbox.org`, ST-016).
enum InstallerStep: Int, CaseIterable, Comparable {
    case welcome
    /// Solo en modo instalar -- elegir dual boot (default) o reemplazar
    /// por completo el firmware de Apple. Restaurar la salta siempre.
    /// ST-050: ya no se visita (la instalacion es siempre Solo firmware);
    /// se conserva el caso para no renumerar ni romper el switch exhaustivo.
    case chooseBootMode
    case permissions
    case detectDevice
    case preparingDisk
    case copyingFiles
    case enterDFU
    case installing
    /// Solo en Solo Aura (ST-017): el bootloader ya quedo grabado y se
    /// espera a que el iPod reaparezca como disco en "Bootloader USB
    /// mode" (o corriendo Aura) para copiar los archivos.
    case awaitingBootloaderUSB
    /// Solo en modo restaurar (D-184): tras quitar el bootloader por
    /// DFU, esperar a que el iPod reaparezca como disco y prepararlo
    /// para Finder con el doble formateo (puente FAT/MBR y despues
    /// Mac OS Plus con registro / mapa GUID).
    case restoreFormatting
    /// Solo en modo restaurar: el disco quedo listo -- la restauracion
    /// del firmware de Apple la termina Finder, con Aura Studio CERRADO
    /// para no interferir con la deteccion USB.
    case restoreHandoff
    case done
    case failed

    static func < (lhs: InstallerStep, rhs: InstallerStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum InstallerMode: Equatable {
    case install
    case restore
    /// ST-143 (plan maestro §B.5): regrabar SOLO el bootloader, sin
    /// formatear, sin copiar archivos y sin tocar la biblioteca. Existe
    /// porque el arranque cambió de versión y la NOR no se puede releer:
    /// la única forma de ponerlo al día es volver a flashearlo por DFU.
    case updateBootloader
}

/// Una accion privilegiada pendiente de autorizacion del usuario. La UI
/// muestra `explanationTitle`/`explanationBody`/`cancelConsequence`
/// ANTES de disparar el dialogo nativo de contraseña de macOS -- nunca
/// se pide autorizacion sin explicar antes, en español simple, que se
/// va a hacer y por que.
struct PendingAuthorization: Identifiable {
    enum Kind: Equatable {
        case pauseAMPAgents
        case formatDisk(volumeName: String, diskIdentifier: String)
        case restoreFormatDisk(diskIdentifier: String)
    }

    let id = UUID()
    let kind: Kind
    let explanationTitle: String
    let explanationBody: String
    let cancelConsequence: String

    static func pauseAMPAgents() -> PendingAuthorization {
        PendingAuthorization(
            kind: .pauseAMPAgents,
            explanationTitle: LS("installer.pause-services.title"),
            // ST-227 (A7c, cierre 5): la lista sale de `ampAgentNames`,
            // que es quien de verdad los pausa. Acá decía "dos servicios
            // ... (AMPDevicesAgent y AMPDeviceDiscoveryAgent)" y se
            // pausan TRES -- falta `deviceinterfaced`. Esta pantalla
            // existe para decirle al usuario exactamente qué se va a
            // hacer con permisos de administrador antes de que macOS le
            // pida la contraseña; nombrar dos de tres es justo lo que no
            // puede pasar acá.
            explanationBody: LSf("installer.pause-services.body",
                                 Sentence.list(PrivilegedExecutor.ampAgentNames)),
            cancelConsequence: LS("installer.pause-services.cancel")
        )
    }

    static func restoreFormatDisk(diskIdentifier: String) -> PendingAuthorization {
        PendingAuthorization(
            kind: .restoreFormatDisk(diskIdentifier: diskIdentifier),
            explanationTitle: LS("installer.restore-format.title"),
            explanationBody: LSf("installer.restore-format.body", diskIdentifier),
            cancelConsequence: LS("installer.restore-format.cancel")
        )
    }

    static func formatDisk(volumeName: String, diskIdentifier: String) -> PendingAuthorization {
        PendingAuthorization(
            kind: .formatDisk(volumeName: volumeName, diskIdentifier: diskIdentifier),
            explanationTitle: LS("installer.format-disk.title"),
            explanationBody: LSf("installer.format-disk.body", volumeName, diskIdentifier),
            cancelConsequence: LS("installer.format-disk.cancel")
        )
    }
}

enum InstallerError: Error, LocalizedError, Equatable {
    case deviceNotFound
    case wrongDiskFormat
    case dfuTimeout
    case checksumMismatch(file: String)
    /// D-297/D-298 (Aura-Firmware), ST-018: rockbox.zip paso su checksum
    /// pero le faltan entradas reales (codecs/plugins) -- un Release mal
    /// empaquetado en el firmware, no un problema de transferencia. Ver
    /// BundledArtifacts.verifyRockboxTreeContents.
    case incompleteRockboxTree(missing: [String])
    case processFailed(exitCode: Int32, output: String)
    case missingBundledArtifact(String)
    case diskAmbiguous(count: Int)
    case authorizationCancelled
    case privilegedOperationFailed(String)
    /// TCC bloqueo la escritura directa al disco (newfs_msdos crudo).
    /// `FailedView` muestra para este caso el boton que abre el panel
    /// de Acceso total al disco, con la explicacion de que hacer.
    case fullDiskAccessDenied
    /// Dual boot elegido pero el disco necesitaria formatearse desde
    /// cero -- lo que destruiria justamente el firmware de Apple que
    /// dual boot promete conservar (D-185).
    case dualBootRequiresWinpod
    /// El volumen del iPod dejo de responder a mitad de la copia del
    /// firmware -- reproducido a mano (D-189): copiar el arbol
    /// completo (miles de archivos chicos) por USB puede tardar varios
    /// minutos, y el aparato se desconecto antes de terminar. No es un
    /// error de la app ni del disco: nada que la app haya escrito se
    /// pierde (la extraccion hace merge, retomar desde cero es seguro).
    case deviceDisconnectedDuringCopy
    /// mks5lboot confirmo el ENVIO por USB (D-191) pero el iPod nunca
    /// salio de modo DFU -- no hay evidencia de que aplico el flasheo.
    /// Visto en hardware real: Aura Studio decia "Aura instalado" con
    /// el iPod en pantalla negra y Finder mostrando "Modo DFU del
    /// iPod". Causa mas probable: el demonio deviceinterfaced de
    /// macOS reclama el USB apenas el aparato entra a DFU y abre
    /// Finder a mitad del envio -- desde D-191 Aura Studio lo pausa
    /// junto con los agentes AMP, pero puede seguir pasando si algo
    /// mas interfiere con el cable.
    case deviceStuckInDFU
    /// ST-017 (Solo Aura): tras el flasheo `--single`, el iPod reaparecio
    /// atendiendo el USB con el firmware original de Apple -- el
    /// bootloader de Aura no quedo grabado (con `--single` el arranque de
    /// Apple ya no deberia existir).
    case bootloaderNotApplied
    /// ST-077: no se pudo bajar el Release mas nuevo (sin red, token sin
    /// acceso, Release incompleto). NUNCA es fatal por si mismo: el
    /// instalador cae a los binarios embebidos y sigue. El caso existe
    /// para poder DECIR por que se instalo la version embebida en vez de
    /// la mas nueva, no para detener nada.
    case releaseDownloadFailed(family: String, reason: String)
    /// ST-077: el Release publicado no trae alguno de los assets que la
    /// tabla §A del contrato exige. Mismo trato: se dice y se cae a lo
    /// embebido.
    case releaseMissingAsset(tag: String, asset: String)

    var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return LS("installer.error.device-not-found")
        case .wrongDiskFormat:
            return LS("installer.error.wrong-disk-format")
        case .dfuTimeout:
            return LS("installer.error.dfu-timeout")
        case .checksumMismatch(let file):
            return LSf("installer.error.checksum-mismatch", file)
        case .releaseDownloadFailed(let family, let reason):
            return LSf("installer.error.release-download-failed", family, reason)
        case .releaseMissingAsset(let tag, let asset):
            return LSf("installer.error.release-missing-asset", tag, asset)
        case .incompleteRockboxTree(let missing):
            return LSf("installer.error.incomplete-rockbox-tree", Sentence.commaList(missing))
        case .processFailed(let exitCode, let output):
            // Sin nombrar herramienta: este error lo producen tanto
            // mks5lboot como la extraccion de archivos (ditto) -- el
            // texto viejo culpaba a mks5lboot de fallas que no eran
            // suyas (visto en vivo, D-185).
            return LSf("installer.error.process-failed", exitCode, output)
        case .missingBundledArtifact(let name):
            return LSf("installer.error.missing-bundled-artifact", name)
        case .diskAmbiguous(let count):
            return LSf("installer.error.disk-ambiguous", count)
        case .authorizationCancelled:
            return LS("installer.error.authorization-cancelled")
        case .privilegedOperationFailed(let message):
            return message
        case .fullDiskAccessDenied:
            return LS("installer.error.full-disk-access-denied")
        case .dualBootRequiresWinpod:
            return LS("installer.error.dual-boot-requires-winpod")
        case .deviceDisconnectedDuringCopy:
            return LS("installer.error.disconnected-during-copy")
        case .bootloaderNotApplied:
            return LS("installer.error.bootloader-not-applied")
        case .deviceStuckInDFU:
            return LS("installer.error.stuck-in-dfu")
        }
    }
}
