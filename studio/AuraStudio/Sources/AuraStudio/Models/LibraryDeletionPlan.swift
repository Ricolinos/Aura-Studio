import Foundation

/// ST-225 (PLAN-studio-ajustes-3.md §0.4/§2): qué se hace con cada
/// archivo al eliminar elementos de la biblioteca.
///
/// **Por qué es una función pura y aparte.** Lo que había borraba con
/// `removeItem` —**definitivo, sin confirmación y sin vuelta atrás**— el
/// archivo copiado dentro de la biblioteca. Un clic mal dado en una
/// tabla de doce mil canciones y el archivo no estaba en ningún lado.
/// Decidir qué se borra es lo que hay que poder revisar y probar sin
/// tocar disco; borrarlo es el paso de después, y con confirmación.
///
/// **La distinción que gobierna todo**: hay archivos del **usuario** y
/// archivos **nuestros**.
///
/// - El archivo del usuario (la copia en `Música/`, `Imágenes/`,
///   `Videos/`) va a la **Papelera**, nunca se borra. En modo referencia
///   ni eso: el original está donde el usuario lo dejó y no se toca.
/// - Los derivados que produjo la app —el preparado de `.preparados/`,
///   su póster hermano, la carátula de `.portadas/`— se borran. Son
///   nuestros, se regeneran solos y no tienen por qué llenarle la
///   Papelera a nadie.
enum LibraryDeletionPlan {
    struct Plan: Equatable {
        /// Archivos del usuario: van a la Papelera.
        var toTrash: [URL] = []
        /// Derivados nuestros: se borran.
        var toDelete: [URL] = []

        var isEmpty: Bool { toTrash.isEmpty && toDelete.isEmpty }
    }

    /// - Parameters:
    ///   - doomed: los elementos que se eliminan.
    ///   - survivors: los que se quedan. Hacen falta porque un derivado
    ///     que un sobreviviente todavía usa **no se borra** -- fue el
    ///     defecto de ST-064, y aunque ST-221 lo desarmó nombrando los
    ///     derivados por id, la comprobación se queda: cuesta nada y
    ///     protege de un catálogo viejo donde dos elementos sí comparten
    ///     uno.
    static func plan(deleting doomed: [LibraryItem],
                     survivors: [LibraryItem],
                     libraryRoot: URL,
                     coversDirectory: URL) -> Plan {
        var plan = Plan()
        let survivingPrepared = Set(survivors.compactMap {
            $0.preparedURL.map { SharedCatalogPath.catalogNormalized($0.standardizedFileURL.path) }
        })
        let survivingSources = Set(survivors.map {
            SharedCatalogPath.catalogNormalized($0.sourceURL.standardizedFileURL.path)
        })

        for item in doomed {
            let sourceKey = SharedCatalogPath.catalogNormalized(item.sourceURL.standardizedFileURL.path)

            // El archivo del usuario. Solo si está DENTRO de la
            // biblioteca es nuestro para moverlo: en modo referencia
            // vive donde el usuario lo puso y no se toca ni para la
            // Papelera.
            if item.storage == .copy,
               SharedCatalogPath.isInside(item.sourceURL, root: libraryRoot),
               !survivingSources.contains(sourceKey) {
                plan.toTrash.append(item.sourceURL)
                // La letra es un archivo hermano y viaja con la canción
                // (ST-012): a la Papelera con ella, para que se pueda
                // recuperar el par completo.
                let lrc = item.sourceURL.deletingPathExtension().appendingPathExtension("lrc")
                plan.toTrash.append(lrc)
            }

            // El derivado. En modo copia `preparedURL == sourceURL`, así
            // que ya está contemplado arriba y no se borra dos veces.
            if let prepared = item.preparedURL,
               prepared.standardizedFileURL != item.sourceURL.standardizedFileURL,
               !survivingPrepared.contains(SharedCatalogPath.catalogNormalized(prepared.standardizedFileURL.path)) {
                plan.toDelete.append(prepared)
                plan.toDelete.append(prepared.deletingPathExtension().appendingPathExtension("lrc"))
                // El póster de un video viaja como `<preparado>.jpg`
                // hermano (D-066).
                if item.kind == .video {
                    plan.toDelete.append(prepared.deletingPathExtension().appendingPathExtension("jpg"))
                }
            }

            // La carátula por id es siempre nuestra.
            plan.toDelete.append(coversDirectory.appendingPathComponent("\(item.id.uuidString).jpg"))
        }
        return plan
    }
}
