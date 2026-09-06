import Foundation

/// PLAN-studio-rendimiento.md Fase 1: reemplaza el `rows` computed var de
/// `MediaSectionView` (diagnóstico §0.2 -- se recalculaba en el `body`,
/// `filter` ×4 + `map` + `sorted(using:)` en cada pasada, incluso las
/// que solo cambiaban la selección). Memoiza el resultado y solo lo
/// recalcula cuando de verdad cambian sus entradas -- `items` filtrados,
/// el índice de sincronización o el orden -- nunca por selección, porque
/// nada de eso entra en el cálculo.
///
/// Con más de 2000 filas el orden corre en un `Task.detached`: no vale
/// la pena para una biblioteca chica (el salto de hilo cuesta más que el
/// propio `sorted`), pero a 12 000 sí (línea base ST-152: hasta 1.18 s
/// para el caso más caro, orden por tamaño).
@MainActor
final class RowsModel: ObservableObject {
    @Published private(set) var rows: [MediaTableRow] = []

    /// Umbral de la línea base (ST-152): por debajo, el salto a un hilo
    /// aparte no compensa su propio costo.
    private static let asyncThreshold = 2_000

    private var recomputeTask: Task<Void, Never>?
    /// Evita publicar un resultado viejo si una recomputación más nueva
    /// ya arrancó mientras la anterior corría en el hilo aparte.
    private var generation = 0

    deinit {
        recomputeTask?.cancel()
    }

    func recompute(items: [LibraryItem], deviceSyncIndex: DeviceSyncIndex?,
                   sortOrder: [KeyPathComparator<MediaTableRow>]) {
        recomputeTask?.cancel()

        guard items.count > Self.asyncThreshold else {
            rows = Self.buildRows(items: items, deviceSyncIndex: deviceSyncIndex, sortOrder: sortOrder)
            return
        }

        generation += 1
        let thisGeneration = generation
        recomputeTask = Task.detached(priority: .userInitiated) { [weak self] in
            let computed = Self.buildRows(items: items, deviceSyncIndex: deviceSyncIndex, sortOrder: sortOrder)
            guard !Task.isCancelled else { return }
            await self?.apply(rows: computed, generation: thisGeneration)
        }
    }

    /// Publica el resultado, salvo que mientras corría haya arrancado
    /// una recomputación más nueva. Método aparte y no un `MainActor.run`
    /// con `guard let self` adentro: esa forma captura `self` como var
    /// en código concurrente, que el modo Swift 6 rechaza (era la única
    /// advertencia viva del paquete).
    private func apply(rows computed: [MediaTableRow], generation: Int) {
        guard self.generation == generation else { return }
        rows = computed
    }

    private nonisolated static func buildRows(items: [LibraryItem], deviceSyncIndex: DeviceSyncIndex?,
                                               sortOrder: [KeyPathComparator<MediaTableRow>]) -> [MediaTableRow] {
        items
            .map { MediaTableRow(item: $0, syncState: deviceSyncIndex?.state(forSourcePath: $0.sourceURL.path)) }
            .sorted(using: sortOrder)
    }
}
