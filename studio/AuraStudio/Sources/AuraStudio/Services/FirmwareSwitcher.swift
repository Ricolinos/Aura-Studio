import Foundation

/// ST-056 / CONTRATO-firmware-studio.md v10 (ST-065: hasta tres): varios firmwares instalados a la
/// vez y conmutacion entre ellos POR RENOMBRE, sin borrar ni descargar.
///
/// El arbol activo es siempre `/.rockbox/` (lo unico que el bootloader
/// compartido sabe arrancar); el de la otra familia duerme como
/// `/.firmware-aura/` o `/.firmware-metro/`, completo y con sus propios
/// ajustes. Cambiar de firmware son dos renombres en FAT (instantaneos),
/// en un orden que importa -- el saliente primero -- mas el respaldo del
/// bootloader en la raiz y el marcador de sync para que el entrante
/// reconstruya su base de datos. Todo son operaciones de FileManager
/// sobre el volumen montado: se prueba con carpetas temporales.
///
/// Esta misma secuencia la ejecuta el firmware desde Ajustes (M-090 /
/// D-327); aqui esta la version de Studio.
///
/// INVARIANTE (ST-069 / contrato v15): todo lo de aqui opera SOLO sobre
/// `/.rockbox/`, `/.firmware-*/` y `/rockbox.ipod`. `/.aura/tagcache/`
/// (base de datos compartida por los tres firmwares) y `/.aura/thumbs/`
/// (miniaturas compartidas) son propiedad del firmware aunque vivan bajo
/// `/.aura/`: ningun renombre, estacionamiento, reparacion, siembra ni
/// espejo los toca. Ver `LibrarySync.sharedTagcacheDirRelativePath`.
enum FirmwareSwitcher {
    static let activeTreeName = ".rockbox"
    static let rootFirmwareBinaryName = "rockbox.ipod"
    /// ST-059 / contrato v12: sello de biblioteca compartido (cambia solo
    /// cuando un sync toca musica) y su anotacion POR ARBOL (contra que
    /// sello construyo su base ese firmware). Igualdad exacta de sellos =
    /// la base del arbol entrante sigue valida = no se escribe marcador.
    static let libraryStampRelativePath = ".aura/library-stamp"
    /// Hasta v14 la anotacion vivia por arbol; desde v15 (ST-069) el
    /// firmware la lee/escribe en `/.aura/tagcache/db_stamp.txt`. Studio
    /// conserva la ruta por arbol solo para compararla al cambiar de
    /// familia con arboles anteriores a v15 y para borrarla al forzar una
    /// reconstruccion.
    static let dbStampRelativePathInTree = "aura/db_stamp.txt"

    enum SwitchError: Error, Equatable {
        /// No hay `/.firmware-<familia>/` que despertar.
        case dormantTreeMissing(FirmwareFamily)
        /// La familia pedida ya es la activa.
        case alreadyActive(FirmwareFamily)
        /// La familia activa no se pudo determinar y por lo tanto no hay
        /// nombre bajo el cual estacionarla.
        case activeFamilyUnknown
        /// Una familia que no se puede estacionar ni despertar.
        case familyNotSwitchable(FirmwareFamily)
    }

    /// Que familias tienen un arbol dormido en el volumen.
    static func dormantFamilies(volumeRoot: URL, fileManager: FileManager = .default) -> [FirmwareFamily] {
        FirmwareFamily.installable.filter { family in
            guard let name = family.dormantTreeName else { return false }
            var isDir: ObjCBool = false
            return fileManager.fileExists(atPath: volumeRoot.appendingPathComponent(name).path,
                                          isDirectory: &isDir) && isDir.boolValue
        }
    }

    static func hasActiveTree(volumeRoot: URL, fileManager: FileManager = .default) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: volumeRoot.appendingPathComponent(activeTreeName).path,
                                      isDirectory: &isDir) && isDir.boolValue
    }

    /// Un cambio que quedo a medias (bateria, cable): sin `/.rockbox/` pero
    /// con exactamente un arbol dormido. Se repara despertandolo. Con dos
    /// dormidos y ningun activo no se adivina: se deja como esta y se
    /// reporta `nil`.
    @discardableResult
    static func repairIfNeeded(volumeRoot: URL, fileManager: FileManager = .default) throws -> FirmwareFamily? {
        guard !hasActiveTree(volumeRoot: volumeRoot, fileManager: fileManager) else { return nil }
        let dormant = dormantFamilies(volumeRoot: volumeRoot, fileManager: fileManager)
        guard dormant.count == 1, let family = dormant.first, let name = family.dormantTreeName else { return nil }
        try fileManager.moveItem(at: volumeRoot.appendingPathComponent(name),
                                 to: volumeRoot.appendingPathComponent(activeTreeName))
        try refreshRootBinary(volumeRoot: volumeRoot, fileManager: fileManager)
        return family
    }

    /// Estaciona el arbol activo como dormido de `family` (reemplazando un
    /// dormido anterior de esa misma familia, si lo hubiera -- nunca dos
    /// de la misma). Lo usa el instalador antes de instalar la OTRA
    /// familia en `/.rockbox/`, en vez de borrarla.
    static func parkActiveTree(as family: FirmwareFamily, volumeRoot: URL,
                               fileManager: FileManager = .default) throws {
        guard let name = family.dormantTreeName else { throw SwitchError.familyNotSwitchable(family) }
        let active = volumeRoot.appendingPathComponent(activeTreeName)
        let dormant = volumeRoot.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: active.path) else { return }
        if fileManager.fileExists(atPath: dormant.path) {
            try fileManager.removeItem(at: dormant)
        }
        try fileManager.moveItem(at: active, to: dormant)
    }

    /// Borra el arbol dormido de `family` si existe (tras instalar esa
    /// familia fresca en `/.rockbox/`: nunca un dormido de la familia
    /// activa).
    static func removeDormantTree(of family: FirmwareFamily, volumeRoot: URL,
                                  fileManager: FileManager = .default) throws {
        guard let name = family.dormantTreeName else { return }
        let dormant = volumeRoot.appendingPathComponent(name)
        if fileManager.fileExists(atPath: dormant.path) {
            try fileManager.removeItem(at: dormant)
        }
    }

    /// EL cambio (contrato v10, pasos 2-5; el 1 -- que el firmware guarde
    /// lo suyo -- no aplica desde Studio porque el firmware no esta
    /// corriendo en modo disco, y el 6 -- reiniciar -- lo hace el usuario
    /// al expulsar):
    ///   `/.rockbox/` -> `/.firmware-<activa>/`
    ///   `/.firmware-<destino>/` -> `/.rockbox/`
    ///   `/rockbox.ipod` := `/.rockbox/rockbox.ipod` del entrante
    ///   `/.aura/sync-pending.json` con music: true
    static func switchActiveFirmware(to target: FirmwareFamily, currentlyActive: FirmwareFamily,
                                     volumeRoot: URL, fileManager: FileManager = .default) throws {
        guard target != currentlyActive else { throw SwitchError.alreadyActive(target) }
        guard let targetName = target.dormantTreeName else { throw SwitchError.familyNotSwitchable(target) }
        guard let activeName = currentlyActive.dormantTreeName else { throw SwitchError.activeFamilyUnknown }

        let active = volumeRoot.appendingPathComponent(activeTreeName)
        let targetDormant = volumeRoot.appendingPathComponent(targetName)
        let parkedActive = volumeRoot.appendingPathComponent(activeName)

        guard fileManager.fileExists(atPath: targetDormant.path) else {
            throw SwitchError.dormantTreeMissing(target)
        }

        // (2) saliente primero: el peor caso (corte aqui) deja un arbol
        // dormido entero y ningun activo -- repairIfNeeded() lo levanta.
        if fileManager.fileExists(atPath: active.path) {
            if fileManager.fileExists(atPath: parkedActive.path) {
                try fileManager.removeItem(at: parkedActive)
            }
            try fileManager.moveItem(at: active, to: parkedActive)
        }
        // (3) entrante
        try fileManager.moveItem(at: targetDormant, to: active)
        // (4) respaldo del bootloader
        try refreshRootBinary(volumeRoot: volumeRoot, fileManager: fileManager)
        // (5) v12/ST-059: el marcador solo si la biblioteca cambio desde
        // que el ENTRANTE construyo su base -- sin sync de por medio, el
        // cambio es instantaneo y sin reconstruccion (reporte del dueño:
        // cada ida y vuelta costaba ~5 min de "optimizando").
        if !incomingDatabaseIsCurrent(volumeRoot: volumeRoot, outgoing: currentlyActive,
                                      fileManager: fileManager) {
            try SyncPendingMarker(changes: .init(music: true, video: false, images: false))
                .write(to: volumeRoot, fileManager: fileManager)
        }
    }

    /// ST-059: compara el sello del arbol ya renombrado a `/.rockbox/`
    /// (el entrante) contra `/.aura/library-stamp`. Si el sello
    /// compartido falta (primer cambio tras v12), lo crea y lo anota como
    /// del SALIENTE -- su base si esta al dia, acaba de estar corriendo --
    /// para que el proximo cambio de vuelta ya no reconstruya.
    private static func incomingDatabaseIsCurrent(volumeRoot: URL, outgoing: FirmwareFamily,
                                                  fileManager: FileManager) -> Bool {
        let stampURL = volumeRoot.appendingPathComponent(libraryStampRelativePath)
        var stamp = (try? String(contentsOf: stampURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if stamp == nil || stamp?.isEmpty == true {
            let fresh = Self.makeLibraryStamp()
            try? fileManager.createDirectory(at: stampURL.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
            try? (fresh + "\n").write(to: stampURL, atomically: true, encoding: .utf8)
            if let name = outgoing.dormantTreeName {
                let outgoingStamp = volumeRoot.appendingPathComponent(name)
                    .appendingPathComponent(dbStampRelativePathInTree)
                try? (fresh + "\n").write(to: outgoingStamp, atomically: true, encoding: .utf8)
            }
            stamp = fresh
        }
        let incoming = volumeRoot.appendingPathComponent(activeTreeName)
            .appendingPathComponent(dbStampRelativePathInTree)
        guard let recorded = try? String(contentsOf: incoming, encoding: .utf8) else { return false }
        return recorded.trimmingCharacters(in: .whitespacesAndNewlines) == stamp
    }

    static func makeLibraryStamp(date: Date = Date()) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date) + "-" + UUID().uuidString.prefix(8)
    }

    /// ST-059: Studio renueva el sello en cada sync que toca musica -- es
    /// LA definicion de "la biblioteca cambio" para el cambio de firmware.
    static func bumpLibraryStamp(volumeRoot: URL, fileManager: FileManager = .default) {
        let url = volumeRoot.appendingPathComponent(libraryStampRelativePath)
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
        try? (makeLibraryStamp() + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// `/rockbox.ipod` (raiz) = el binario del arbol activo. Es lo que el
    /// bootloader arranca si `/.rockbox/rockbox.ipod` falta; tiene que ser
    /// SIEMPRE el del firmware activo, nunca el de un arbol dormido.
    static func refreshRootBinary(volumeRoot: URL, fileManager: FileManager = .default) throws {
        let source = volumeRoot.appendingPathComponent(activeTreeName).appendingPathComponent(rootFirmwareBinaryName)
        let root = volumeRoot.appendingPathComponent(rootFirmwareBinaryName)
        guard fileManager.fileExists(atPath: source.path) else { return }
        if fileManager.fileExists(atPath: root.path) {
            try fileManager.removeItem(at: root)
        }
        try fileManager.copyItem(at: source, to: root)
    }

    /// Archivos del contrato que Studio escribe en `.rockbox/aura/` y que
    /// el firmware dormido tambien necesita al despertar (v10). Se copian
    /// tal cual desde el activo a cada dormido presente, al final de cada
    /// sync. `aura.cfg` NO (es de cada firmware); `themes/` tampoco (es de
    /// Aura, activo o dormido, y viaja con su arbol).
    /// NOTA (v12/ST-059): `aura/db_stamp.txt` tampoco se espeja -- es la
    /// anotacion de CADA arbol sobre su propia base de datos.
    /// NOTA (v11/ST-058): `aura/install_manifest.cfg` NO esta aqui a
    /// proposito -- es POR ARBOL (describe lo instalado en ESE arbol) y
    /// espejarlo haria que la actualizacion selectiva del dormido diera
    /// por escritos archivos que nunca se le escribieron.
    static let mirroredContractEntries = [
        "aura/sync_summary.cfg",
        "aura/sync_manifest.json",
        "aura/artist_images.cfg",
        "aura/artists",
        "aura/video_categories.cfg",
        "aura/photo_categories.cfg",
        "aura/ratings.cfg",
        "aura/device.cfg",
    ]

    /// ST-061: el problema inverso al espejo -- un arbol ACTIVO recien
    /// instalado (extraccion fresca) no tiene los archivos del contrato
    /// que Studio escribio en su vida anterior: sin `sync_summary.cfg`
    /// el firmware dice "sin sincronizar todavia", sin
    /// `artist_images.cfg`/`artists/` no hay fotos de artista, sin
    /// `*_categories.cfg` los videos/fotos salen sin clasificar (reporte
    /// del dueño con Metro). Si el arbol dormido SI los tiene (los
    /// conservo al estacionarse, o el espejo de cada sync lo mantuvo al
    /// dia), se copian de ahi. Solo cuando el activo NO tiene
    /// `sync_summary.cfg` -- si lo tiene, lo suyo es igual o mas nuevo.
    @discardableResult
    static func seedContractFilesToActiveTree(volumeRoot: URL, fileManager: FileManager = .default) -> Bool {
        let active = volumeRoot.appendingPathComponent(activeTreeName)
        guard !fileManager.fileExists(atPath: active.appendingPathComponent("aura/sync_summary.cfg").path) else {
            return false
        }
        guard let donorFamily = dormantFamilies(volumeRoot: volumeRoot, fileManager: fileManager).first(where: { family in
            guard let name = family.dormantTreeName else { return false }
            return fileManager.fileExists(atPath: volumeRoot.appendingPathComponent(name)
                .appendingPathComponent("aura/sync_summary.cfg").path)
        }), let donorName = donorFamily.dormantTreeName else { return false }

        let donor = volumeRoot.appendingPathComponent(donorName)
        try? fileManager.createDirectory(at: active.appendingPathComponent("aura"),
                                         withIntermediateDirectories: true)
        for entry in mirroredContractEntries {
            let src = donor.appendingPathComponent(entry)
            let dst = active.appendingPathComponent(entry)
            guard fileManager.fileExists(atPath: src.path) else { continue }
            if fileManager.fileExists(atPath: dst.path) {
                try? fileManager.removeItem(at: dst)
            }
            try? fileManager.copyItem(at: src, to: dst)
        }
        return true
    }

    static func mirrorContractFilesToDormantTrees(volumeRoot: URL, fileManager: FileManager = .default) throws {
        let active = volumeRoot.appendingPathComponent(activeTreeName)
        for family in dormantFamilies(volumeRoot: volumeRoot, fileManager: fileManager) {
            guard let name = family.dormantTreeName else { continue }
            let dormant = volumeRoot.appendingPathComponent(name)
            try fileManager.createDirectory(at: dormant.appendingPathComponent("aura"),
                                            withIntermediateDirectories: true)
            for entry in mirroredContractEntries {
                let src = active.appendingPathComponent(entry)
                let dst = dormant.appendingPathComponent(entry)
                if fileManager.fileExists(atPath: dst.path) {
                    try fileManager.removeItem(at: dst)
                }
                if fileManager.fileExists(atPath: src.path) {
                    try fileManager.copyItem(at: src, to: dst)
                }
            }
        }
    }
}
