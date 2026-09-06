import Foundation

/// PLAN-studio-rendimiento.md Fase 3 punto 1 (addendum a ST-155):
/// coalesce guardados rápidos seguidos del catálogo (una estrella, un
/// cambio de categoría) en uno solo, con la escritura pesada -- JSON de
/// hasta 12 000 ítems + carátulas -- fuera del hilo principal.
///
/// Diagnóstico §0.4: antes, cada edición individual llamaba
/// `LibraryViewModel.persistCatalog()` de inmediato y en el actor
/// principal -- ese guardado (~1 s con una biblioteca grande) ES el
/// congelamiento que se siente al poner una estrella o cambiar una
/// categoría, no solo el de la selección múltiple (que ST-155 ya
/// arregló con `clearCoverArt(ids:)` y compañía).
///
/// `schedule(_:apply:)` programa un guardado ≤ 500 ms después de la
/// última llamada -- varias ediciones rápidas seguidas terminan en UNA
/// escritura real, no una por edición. `flush(apply:)` guarda de
/// inmediato (salir de la app, pasar a segundo plano, antes de
/// sincronizar) y también es lo que corre cuando el debounce expira. La
/// escritura en sí (`write(_:)`) es `nonisolated` y corre en un
/// `Task.detached(priority: .utility)`, sobre un `Snapshot` `Sendable`
/// capturado en el actor principal -- copiar `items`/`playlists` es
/// barato (son structs de valor), la parte cara (mapear cada ítem,
/// escribir carátulas, codificar JSON) pasa a otro hilo.
@MainActor
final class CatalogPersister {
    struct Snapshot: Sendable {
        var items: [LibraryItem]
        var playlists: [Playlist]
        var coversNormalizedVersion: Int?
        var libraryRoot: URL
        var lastWrittenCoverHash: [UUID: Int]
    }

    struct WriteResult: Sendable {
        var lastWrittenCoverHash: [UUID: Int]
        /// PLAN-studio-rendimiento-2.md Fase 5 (ST-185): las carátulas
        /// que este guardado dejó escritas en `.portadas/`, con su hash.
        /// `LibraryViewModel` las aplica a `items` -- y al hacerlo suelta
        /// los bytes de `pendingCoverData`, que es lo que saca los JPEG
        /// de la memoria.
        var storedCovers: [UUID: StoredCover] = [:]
        var errorDescription: String?
    }

    struct StoredCover: Sendable {
        var url: URL
        var hash: String
    }

    /// Para pruebas: si `true`, `schedule(_:apply:)` escribe de
    /// inmediato en vez de esperar el debounce -- el comportamiento
    /// síncrono que ya asumían las pruebas escritas antes de que
    /// existiera este coalescer (construir un `LibraryViewModel`, mutar,
    /// construir OTRO sobre el mismo `libraryRoot` y verificar sin
    /// esperar nada de por medio).
    var isSynchronousForTesting = false

    private var pendingSnapshot: Snapshot?
    private var debounceTask: Task<Void, Never>?
    private static let coalesceNanoseconds: UInt64 = 500_000_000

    deinit {
        debounceTask?.cancel()
    }

    /// Programa un guardado. Una llamada nueva antes de que expire el
    /// debounce de la anterior la reemplaza (mismo `Snapshot`, más
    /// nuevo) y reinicia el reloj -- no se acumulan guardados, el
    /// último gana.
    func schedule(_ snapshot: Snapshot, apply: @escaping @MainActor (WriteResult) -> Void) {
        pendingSnapshot = snapshot
        if isSynchronousForTesting {
            flushSynchronously(apply: apply)
            return
        }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.coalesceNanoseconds)
            guard !Task.isCancelled else { return }
            self?.flush(apply: apply)
        }
    }

    /// Guardado inmediato de lo último programado, sin esperar el
    /// debounce -- pero la escritura en sí sigue fuera del hilo
    /// principal (`Task.detached`). Sin nada pendiente, no hace nada.
    func flush(apply: @escaping @MainActor (WriteResult) -> Void) {
        debounceTask?.cancel()
        debounceTask = nil
        guard let snapshot = pendingSnapshot else { return }
        pendingSnapshot = nil
        Task.detached(priority: .utility) {
            let result = Self.write(snapshot)
            await apply(result)
        }
    }

    /// Guardado inmediato Y SÍNCRONO, bloqueando el actor que llama
    /// hasta terminar -- para salir de la app y pasar a segundo plano
    /// (hay que garantizar que el archivo quedó escrito antes de que el
    /// proceso pueda morir, un `Task.detached` que sigue corriendo por
    /// detrás no sirve ahí) y para `isSynchronousForTesting` (el patrón
    /// "mutar con un ViewModel, cargar con otro sobre el mismo
    /// `libraryRoot`, verificar sin esperar nada" que ya usaban varias
    /// pruebas escritas antes de que existiera este coalescer).
    func flushSynchronously(apply: (WriteResult) -> Void) {
        debounceTask?.cancel()
        debounceTask = nil
        guard let snapshot = pendingSnapshot else { return }
        pendingSnapshot = nil
        apply(Self.write(snapshot))
    }

    /// `true` si hay un guardado esperando el debounce o ya despachado
    /// -- para que quien vaya a leer el catálogo de otra fuente (p. ej.
    /// una prueba) sepa que todavía no es seguro asumir que el disco
    /// está al día.
    var hasPendingWork: Bool { pendingSnapshot != nil }

    /// Escribe YA, en el actor que llama (síncrono) -- cancela
    /// cualquier guardado programado pendiente (ya no hace falta, esto
    /// es más nuevo que lo que hubiera esperando). Es lo que usa
    /// `LibraryViewModel.persistCatalog()`, el guardado inmediato de
    /// siempre para todo lo que no pasó por `schedule(_:apply:)`.
    func writeNow(_ snapshot: Snapshot) -> WriteResult {
        debounceTask?.cancel()
        debounceTask = nil
        pendingSnapshot = nil
        return Self.write(snapshot)
    }

    nonisolated private static func write(_ snapshot: Snapshot) -> WriteResult {
        let coversDirectory = snapshot.libraryRoot.appendingPathComponent(PersistedLibrary.coversDirName, isDirectory: true)
        let catalogURL = snapshot.libraryRoot.appendingPathComponent(PersistedLibrary.catalogFileName)

        var persisted = PersistedLibrary()
        persisted.coversNormalized = snapshot.coversNormalizedVersion

        var newHash = snapshot.lastWrittenCoverHash
        var coverIDsOnDisk: Set<UUID> = []
        var storedCovers: [UUID: StoredCover] = [:]
        try? FileManager.default.createDirectory(at: coversDirectory, withIntermediateDirectories: true)
        for item in snapshot.items {
            var coverRelative: String?
            var coverHash: String?
            // PLAN-studio-rendimiento-2.md Fase 5 (ST-185): hay dos
            // casos, y el primero es el interesante.
            if let pending = item.metadata?.pendingCoverData {
                // Carátula recién entrada (leída del archivo, bajada, o
                // elegida por el usuario) que todavía vive en RAM. Se
                // escribe acá -- fuera del hilo principal, que es donde
                // ya corría este guardado -- y se avisa de vuelta para
                // que el ViewModel suelte los bytes.
                if let stored = try? CoverStore.write(pending, forItem: item.id, in: snapshot.libraryRoot) {
                    coverRelative = CoverStore.relativePath(forItem: item.id)
                    coverHash = stored.hash
                    storedCovers[item.id] = StoredCover(url: stored.url, hash: stored.hash)
                    newHash[item.id] = pending.hashValue
                    coverIDsOnDisk.insert(item.id)
                }
            } else if item.metadata?.coverURL != nil {
                // Ya estaba en disco: no se reescribe nada. Antes, cada
                // guardado del catálogo reescribía las 1 000 carátulas
                // aunque no hubiera cambiado ninguna.
                coverRelative = CoverStore.relativePath(forItem: item.id)
                coverHash = item.metadata?.coverHash
                coverIDsOnDisk.insert(item.id)
            }
            persisted.items.append(PersistedLibraryItem(
                id: item.id,
                sourceRelativePath: relativePath(of: item.sourceURL, in: snapshot.libraryRoot),
                kind: LibraryPersistenceMapper.persistedKind(item.kind),
                status: LibraryPersistenceMapper.persistedStatus(item.status),
                metadata: LibraryPersistenceMapper.persistedMetadata(item.metadata),
                preparedRelativePath: item.preparedURL.map { relativePath(of: $0, in: snapshot.libraryRoot) },
                coverRelativePath: coverRelative,
                coverHash: coverHash,
                category: item.category,
                seriesName: item.seriesName,
                season: item.season,
                episode: item.episode,
                photoAlbum: item.photoAlbum,
                metadataEditedByUser: item.metadataEditedByUser,
                addedAt: item.addedAt
            ))
        }
        newHash = newHash.filter { coverIDsOnDisk.contains($0.key) }
        persisted.playlists = snapshot.playlists.map {
            PersistedPlaylist(id: $0.id, name: $0.name, trackItemIDs: $0.trackItemIDs,
                               imageRelativePath: $0.imageRelativePath)
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(persisted).write(to: catalogURL, options: .atomic)
            return WriteResult(lastWrittenCoverHash: newHash, storedCovers: storedCovers, errorDescription: nil)
        } catch {
            return WriteResult(lastWrittenCoverHash: newHash, storedCovers: storedCovers,
                               errorDescription: "No se pudo guardar el catalogo de la biblioteca: \(error.localizedDescription)")
        }
    }

    /// Copia exacta de `LibraryViewModel.relativePath(of:)` -- tiene que
    /// ser `nonisolated`/estática para poder correr en el `Task.detached`,
    /// así que no puede seguir siendo un método de instancia del VM.
    nonisolated private static func relativePath(of url: URL, in libraryRoot: URL) -> String {
        let rootPath = libraryRoot.standardizedFileURL.path
        let fullPath = url.standardizedFileURL.path
        if fullPath.hasPrefix(rootPath + "/") {
            return String(fullPath.dropFirst(rootPath.count + 1))
        }
        return fullPath
    }
}
