import Foundation

/// ST-264: dedupe de `.portadas/` por contenido.
///
/// **El problema.** Cada carátula se guardaba como `.portadas/<uuid del
/// elemento>.jpg`, una copia POR CANCION: un album de 12 pistas con la
/// misma tapa embebida guardaba 12 JPEG identicos. En la biblioteca del
/// dueño: 1 130 archivos, solo 388 distintos -- ~90 MB regalados.
///
/// **El esquema.** Los elementos que tienen la MISMA imagen (mismo
/// `coverHash`, SHA-256 del contenido) apuntan al MISMO archivo. El
/// nombre del archivo no cambia de forma: sigue siendo `<uuid>.jpg`,
/// el del **sobreviviente** del grupo. Nada se renombra a esquemas
/// nuevos (tipo `<hash>.jpg`) a proposito.
///
/// **El invariante que lo hace seguro.** Un archivo de caratula
/// compartido lleva siempre el nombre canonico de un elemento
/// EXISTENTE que lo referencia. Asi, una version VIEJA de la app (la
/// de Windows de antes de esta ronda, por ejemplo) que limpia
/// huerfanos por nombre (`OrphanFinder` protege `<uuid>.jpg` de cada
/// elemento vivo) jamas borra un archivo compartido: su nombre es el
/// de alguien que existe. Por eso, cuando el dueño del nombre se va
/// (eliminado, o le quitaron la caratula) y quedan elementos usando el
/// archivo, hay que **re-alojarlo**: renombrarlo al canonico de un
/// sobreviviente y reapuntar a todos los que lo comparten -- ver
/// `actionForRemovedCover`.
struct CoverDedupePlan: Equatable {
    /// itemID -> nueva coverURL (la del sobreviviente de su grupo).
    var reassignments: [UUID: URL] = [:]
    /// Copias que quedan sin referencia tras reapuntar: se borran.
    var filesToDelete: [URL] = []
    var isEmpty: Bool { reassignments.isEmpty && filesToDelete.isEmpty }
}

/// Que hacer con la caratula de un elemento que se va de la biblioteca
/// (eliminado, o "Quitar caratula").
enum RemovedCoverAction: Equatable {
    /// Nadie mas la usa: el archivo se borra.
    case deleteFile
    /// La usa alguien mas Y el archivo ya lleva el nombre canonico de
    /// uno de esos: el invariante se cumple solo, no hay nada que hacer.
    case keep
    /// La usa alguien mas pero el archivo lleva el nombre del que se
    /// va: renombrar al canonico de `toItem` y reapuntar a `sharerIDs`.
    case rehome(toItem: UUID, sharerIDs: [UUID])
}

enum CoverDedupe {
    /// Comparacion de rutas como en todo el repo (NFC, ST-221).
    static func key(_ url: URL) -> String {
        SharedCatalogPath.catalogNormalized(url.standardizedFileURL.path)
    }

    static func canonicalURL(forItem id: UUID, in libraryRoot: URL) -> URL {
        CoverStore.url(forItem: id, in: libraryRoot)
    }

    /// Deja UN archivo por imagen distinta. Solo agrupa elementos con
    /// `coverHash` presente y archivo existente: un hash ausente ("no
    /// se sabe", catalogo viejo) nunca es prueba de que dos imagenes
    /// sean la misma, y un archivo que no existe no se puede compartir.
    /// Deterministico: el sobreviviente es el de UUID mas chico que ya
    /// tiene su propia canonica (asi el archivo ni se mueve); si ninguno
    /// la tiene, el de UUID mas chico y el archivo que ya tenga.
    static func plan(items: [LibraryItem], libraryRoot: URL,
                     fileManager: FileManager = .default) -> CoverDedupePlan {
        var byHash: [String: [(id: UUID, url: URL)]] = [:]
        for item in items {
            guard let hash = item.metadata?.coverHash,
                  let url = item.metadata?.coverURL,
                  fileManager.fileExists(atPath: url.path) else { continue }
            byHash[hash, default: []].append((item.id, url))
        }

        var plan = CoverDedupePlan()
        for (_, group) in byHash {
            let sorted = group.sorted { $0.id.uuidString < $1.id.uuidString }
            let target = sorted.first { key($0.url) == key(canonicalURL(forItem: $0.id, in: libraryRoot)) }
                ?? sorted[0]
            for entry in group where entry.id != target.id && key(entry.url) != key(target.url) {
                plan.reassignments[entry.id] = target.url
                plan.filesToDelete.append(entry.url)
            }
        }
        return plan
    }

    /// Que hacer con la caratula de `itemID`, que se va. `remaining`
    /// son los elementos que se QUEDAN (ya sin el que se va).
    static func actionForRemovedCover(itemID: UUID, coverURL: URL,
                                      remaining: [LibraryItem],
                                      libraryRoot: URL) -> RemovedCoverAction {
        let removedKey = key(coverURL)
        let sharers = remaining.filter {
            guard let url = $0.metadata?.coverURL else { return false }
            return key(url) == removedKey
        }
        guard !sharers.isEmpty else { return .deleteFile }
        let namedAfterSurvivor = sharers.contains {
            key(canonicalURL(forItem: $0.id, in: libraryRoot)) == removedKey
        }
        if namedAfterSurvivor { return .keep }
        let target = sharers.min { $0.id.uuidString < $1.id.uuidString }!
        return .rehome(toItem: target.id, sharerIDs: sharers.map(\.id))
    }
}
