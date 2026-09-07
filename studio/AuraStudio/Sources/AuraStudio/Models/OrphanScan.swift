import Foundation

/// Un archivo huérfano: ningún elemento del catálogo lo referencia.
struct OrphanFile: Equatable {
    var url: URL
    var byteSize: Int
}

/// Lo que encontró la búsqueda, listo para mostrárselo al usuario y para
/// borrar.
struct OrphanScanResult: Equatable {
    var files: [OrphanFile] = []

    var count: Int { files.count }
    var totalBytes: Int { files.reduce(0) { $0 + $1.byteSize } }
    var isEmpty: Bool { files.isEmpty }
}

/// ST-225: detector de huérfanos en `.preparados/` y `.portadas/`
/// (hermano de `OrphanFinder.cs` de Windows, ST-245).
///
/// **De dónde salen.** De "Eliminar" antes de esta ronda, que no tocaba
/// ninguna de las dos carpetas; de un reprocesamiento que dejó atrás el
/// derivado o la carátula vieja; y ahora también de "Convertir
/// referenciados en copias" (ST-224), que deja el derivado por id
/// deliberadamente para que lo limpie esta acción y no a espaldas del
/// usuario.
///
/// **Nunca toca disco por su cuenta.** `scan` solo mira y devuelve lo
/// que encontró; borrar es un segundo paso explícito, para que Ajustes
/// pueda mostrar cuántos son y cuánto ocupan **antes** de pedir
/// confirmación. Y nunca mira `Música/`, `Imágenes/` ni `Videos/`: ahí
/// viven archivos del usuario, y esta acción no tiene nada que hacer
/// entre ellos.
enum OrphanScan {
    /// Las dos carpetas que esta acción puede mirar. Que sea una lista
    /// corta y explícita es parte del diseño: no hay forma de que un
    /// cambio futuro la haga caminar por las carpetas del usuario sin
    /// que se vea acá.
    static let scannedDirectories = [PersistedLibrary.preparedDirName, PersistedLibrary.coversDirName]

    static func scan(items: [LibraryItem],
                     libraryRoot: URL,
                     fileManager: FileManager = .default) -> OrphanScanResult {
        var referenced: Set<String> = []
        for item in items {
            // La música copiada no vive en `.preparados/`
            // (`preparedURL == sourceURL`, ST-223): meter su ruta acá no
            // protegería nada real, y por coincidencia de nombres podría
            // "proteger" un huérfano de verdad.
            if let prepared = item.preparedURL,
               prepared.standardizedFileURL != item.sourceURL.standardizedFileURL {
                referenced.insert(key(prepared))
                // El `.lrc` y el póster hermanos pertenecen al derivado:
                // mientras él esté en uso, ellos también.
                referenced.insert(key(prepared.deletingPathExtension().appendingPathExtension("lrc")))
                referenced.insert(key(prepared.deletingPathExtension().appendingPathExtension("jpg")))
            }
            if let cover = item.metadata?.coverURL {
                referenced.insert(key(cover))
            }
            // La carátula canónica por id, esté anotada o no: es la que
            // esta app escribe siempre.
            referenced.insert(key(libraryRoot
                .appendingPathComponent(PersistedLibrary.coversDirName)
                .appendingPathComponent("\(item.id.uuidString).jpg")))
        }

        var result = OrphanScanResult()
        for directory in scannedDirectories {
            let url = libraryRoot.appendingPathComponent(directory, isDirectory: true)
            guard let entries = try? fileManager.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { continue }
            for entry in entries {
                guard (try? entry.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                // Un temporal a medio escribir de otra operación en curso
                // no es un huérfano: es trabajo de alguien más.
                guard entry.pathExtension != "aura-tmp" else { continue }
                guard !referenced.contains(key(entry)) else { continue }
                let size = (try? entry.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                result.files.append(OrphanFile(url: entry, byteSize: size ?? 0))
            }
        }
        result.files.sort { $0.url.path < $1.url.path }
        return result
    }

    /// La comparación va en NFC, como todo lo que compara rutas en este
    /// repo (ST-221). Comparar crudo haría que un derivado con acento que
    /// SÍ está en uso apareciera como huérfano -- y de ahí se borraría
    /// algo que un elemento del catálogo todavía necesita.
    private static func key(_ url: URL) -> String {
        SharedCatalogPath.catalogNormalized(url.standardizedFileURL.path)
    }
}
