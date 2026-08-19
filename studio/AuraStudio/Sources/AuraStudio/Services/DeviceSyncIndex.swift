import Foundation

/// Estado de sincronización de UN elemento de la biblioteca, comparado
/// contra el iPod conectado (PLAN-general-sync.md §4.1).
enum SyncItemState: Equatable {
    /// Hay registro propio, la huella del preparado coincide con la
    /// registrada, y el destino en el iPod existe con la huella que se
    /// registró al copiarlo.
    case synced
    /// Nunca se copió a ESTE dispositivo (sin registro), o el item
    /// todavía no está `.ready`.
    case pending
    /// Hay registro, pero la huella del preparado YA NO coincide (se
    /// editó metadata, se reorganizó, se transcodificó de nuevo) -- el
    /// destino en el iPod sigue siendo el de la versión vieja.
    case changedLocally
    /// El destino existe pero su huella real difiere de la que se
    /// registró al copiarlo -- alguien lo tocó fuera de Aura Studio.
    case modifiedOnDevice
    /// Hay registro pero el archivo YA NO existe en el destino -- se
    /// borró a mano en el iPod. Nunca se vuelve a copiar solo (§0.1):
    /// es una decisión del usuario que se respeta.
    case removedFromDevice
}

/// Resultado de comparar la biblioteca contra el iPod conectado.
/// `states` cubre los items que SÍ tienen (o tuvieron) representación
/// en el dispositivo; `orphanedRecords` son registros del manifiesto
/// cuyo origen ya no está en la biblioteca (PLAN-general-sync.md tabla
/// §1.2, fila "elemento quitado de la biblioteca"); `foreignPaths` son
/// archivos bajo `Music/`/`Videos/`/`Photos/`/`Playlists/` que Aura
/// Studio nunca escribió (Finder, otra Mac, u otra app).
struct DeviceSyncIndex: Equatable {
    var states: [String: SyncItemState] // key = sourcePath, mismo criterio que SyncManifest.records
    var orphanedRecords: [SyncRecord]
    var foreignFiles: [ForeignDeviceFile]

    static let empty = DeviceSyncIndex(states: [:], orphanedRecords: [], foreignFiles: [])

    func state(forSourcePath sourcePath: String) -> SyncItemState {
        states[sourcePath] ?? .pending
    }

    var hasConflicts: Bool {
        states.values.contains(.modifiedOnDevice) || !orphanedRecords.isEmpty
    }

    /// Conveniencia para donde solo hace falta la ruta (p. ej. logs o
    /// mensajes de resumen), sin arrastrar el tamaño a todos lados.
    var foreignPaths: [String] { foreignFiles.map(\.relativePath) }
}

/// Un archivo bajo `Music/`/`Videos/`/`Photos/`/`Playlists/` que Aura
/// Studio nunca escribió -- hoja "Solo en el iPod" (PLAN-general-sync.md
/// §1.6): se puede importar a la biblioteca o eliminar del dispositivo,
/// nunca se toca solo.
struct ForeignDeviceFile: Equatable, Identifiable, Hashable {
    var id: String { relativePath }
    let relativePath: String
    let size: Int64
}

/// Construye `DeviceSyncIndex` -- lógica pura (`build`, testeable sin
/// disco) separada del escaneo real (`scan`, hace I/O), mismo criterio
/// que `SyncPlanner`/`LibrarySync`.
enum DeviceSyncIndexBuilder {
    struct CurrentFile {
        let sourcePath: String
        let size: Int64
        let modifiedAt: TimeInterval
    }

    struct DeviceFileStat: Equatable {
        let size: Int64
        let modifiedAt: TimeInterval
    }

    /// `deviceFiles`: TODOS los archivos bajo `Music/`/`Videos/`/
    /// `Photos/`/`Playlists/` del volumen, con su ruta relativa a la
    /// raíz del volumen -- una sola enumeración cubre tanto la
    /// verificación de destino (¿existe? ¿coincide su huella?) como la
    /// detección de "solo en el iPod" (lo que sobra al restar lo que
    /// el manifiesto reclama como propio).
    static func build(
        currentFiles: [CurrentFile],
        manifest: SyncManifest,
        deviceFiles: [String: DeviceFileStat]
    ) -> DeviceSyncIndex {
        var states: [String: SyncItemState] = [:]

        for file in currentFiles {
            guard let record = manifest.records[file.sourcePath] else {
                states[file.sourcePath] = .pending
                continue
            }

            let preparedMatches = record.sourceSize == file.size && record.sourceModifiedAt == file.modifiedAt
            guard preparedMatches else {
                states[file.sourcePath] = .changedLocally
                continue
            }

            guard let destination = deviceFiles[record.destinationRelativePath] else {
                states[file.sourcePath] = .removedFromDevice
                continue
            }

            guard let destSize = record.destinationSize, let destModifiedAt = record.destinationModifiedAt else {
                // Registro v1 (PLAN-general-sync.md §4.2/§9): sin huella
                // de destino no hay con qué comparar -- se trata como
                // "con cambios" UNA vez, el próximo sync la completa.
                states[file.sourcePath] = .changedLocally
                continue
            }

            states[file.sourcePath] = (destSize == destination.size && destModifiedAt == destination.modifiedAt)
                ? .synced
                : .modifiedOnDevice
        }

        let currentSourcePaths = Set(currentFiles.map(\.sourcePath))
        let orphanedRecords = manifest.records.values
            .filter { !currentSourcePaths.contains($0.sourcePath) }
            .sorted { $0.destinationRelativePath < $1.destinationRelativePath }

        let ownedPaths = ownedDevicePaths(manifest: manifest)
        let foreignFiles = deviceFiles
            // `Playlists/` entero es de Aura Studio (D-066: los .m3u8/
            // .jpg de portada se reescriben siempre, sin manifiesto
            // propio -- ver LibrarySync.writePlaylists) -- nunca tiene
            // registro individual que lo cubra via `ownedPaths`.
            .filter { !ownedPaths.contains($0.key) && !$0.key.hasPrefix("Playlists/") }
            .map { ForeignDeviceFile(relativePath: $0.key, size: $0.value.size) }
            .sorted { $0.relativePath < $1.relativePath }

        return DeviceSyncIndex(states: states, orphanedRecords: orphanedRecords, foreignFiles: foreignFiles)
    }

    /// Todo lo que Aura Studio reclama como propio, aunque no tenga
    /// entrada individual en el manifiesto: las rutas registradas MAS
    /// las convenciones de nombre que `LibrarySync` ya usa para lo que
    /// escribe sin registro propio -- `cover.jpg` por álbum, el poster
    /// `<video>.jpg` junto a su `.mpg`, y todo `Playlists/` (D-066: los
    /// `.m3u8`/`.jpg` de portada se reescriben siempre, sin diferencial
    /// propio -- ver `LibrarySync.writePlaylists`).
    private static func ownedDevicePaths(manifest: SyncManifest) -> Set<String> {
        var owned = Set<String>()
        for record in manifest.records.values {
            let relative = record.destinationRelativePath
            owned.insert(relative)
            if relative.hasPrefix("Music/") {
                let albumCover = (relative as NSString).deletingLastPathComponent + "/cover.jpg"
                owned.insert(albumCover)
                // ST-012: el `.lrc` hermano (letras) tambien lo escribe
                // LibrarySync sin registro propio -- sin esto cada letra
                // apareceria como "Solo en el iPod".
                owned.insert(LibrarySync.lyricsSidecarRelativePath(forDeviceRelativePath: relative))
            }
            if relative.hasPrefix("Videos/") {
                let poster = (relative as NSString).deletingPathExtension + ".jpg"
                owned.insert(poster)
                // PLAN-biblioteca-medios-v2.md §3.5: el póster de
                // temporada de un episodio de Series tampoco tiene
                // registro propio -- ver seasonPosterRelativePath(from:).
                if let seasonPoster = LibrarySync.seasonPosterRelativePath(fromEpisodeDestinationRelativePath: relative) {
                    owned.insert(seasonPoster)
                }
            }
        }
        return owned
    }

    /// Escaneo real: una enumeración de `Music/`/`Videos/`/`Photos/`/
    /// `Playlists/` (solo tamaño/fecha, sin leer contenido) -- se llama
    /// fuera del hilo principal (PLAN-general-sync.md §4.2: "corre
    /// fuera del hilo principal, cacheado en memoria").
    static func scan(volumeRoot: URL, currentFiles: [CurrentFile], manifest: SyncManifest,
                      fileManager: FileManager = .default) -> DeviceSyncIndex {
        var deviceFiles: [String: DeviceFileStat] = [:]

        for directoryName in LibrarySync.deviceContentDirectories {
            let root = volumeRoot.appendingPathComponent(directoryName, isDirectory: true)
            guard let enumerator = fileManager.enumerator(
                at: root, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]),
                      values.isDirectory != true else { continue }
                // `.aura-tmp` a medio escribir de un sync interrumpido
                // no es ni "propio verificado" ni "ajeno" -- se ignora
                // aca, `sweepOrphanedTempFiles()` lo limpia en el
                // proximo sync.
                guard url.pathExtension != LibrarySync.temporaryFileExtension else { continue }

                let relative = relativePath(of: url, under: volumeRoot)
                let size = Int64(values.fileSize ?? 0)
                let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
                deviceFiles[relative] = DeviceFileStat(size: size, modifiedAt: modified)
            }
        }

        return build(currentFiles: currentFiles, manifest: manifest, deviceFiles: deviceFiles)
    }

    private static func relativePath(of url: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let fullPath = url.standardizedFileURL.path
        guard fullPath.hasPrefix(rootPath + "/") else { return fullPath }
        return String(fullPath.dropFirst(rootPath.count + 1))
    }
}
