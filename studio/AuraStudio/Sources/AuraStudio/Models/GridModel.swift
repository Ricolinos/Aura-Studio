import Foundation

/// PLAN-studio-rendimiento-2.md Fase 1 (ST-181): el equivalente de
/// `RowsModel` para las CUADRÍCULAS (Álbumes, Artistas, Películas,
/// Series, álbumes de Fotos). Diagnóstico §0.2: `visibleAlbums` --
/// `filter` de búsqueda + `sort` con `localizedStandardCompare` sobre
/// 1 000 álbumes -- se evaluaba **cinco veces por pasada** del `body`
/// (la barra de estado ×2, el estado vacío, el `ForEach` y el
/// `onChange(of:)` que reconstruía el `GridOrder`), y cada clic dispara
/// al menos una pasada. Acá se calcula UNA vez y solo cuando cambia
/// alguna de sus entradas reales: los grupos, el texto de búsqueda o el
/// criterio de orden. Nunca por selección ni por hover, que no entran
/// en el cálculo.
///
/// `order` sale del mismo cómputo: el `GridOrder` (índice id→posición
/// para el Shift+clic de `GridSelection`, ST-154) ya no necesita su
/// propio `onChange(of: visible.map(\.id))` -- que era, él solo, una de
/// las cinco evaluaciones.
@MainActor
final class GridModel<Element: Identifiable>: ObservableObject {
    @Published private(set) var visible: [Element] = []
    @Published private(set) var order = GridOrder<Element.ID>.empty

    /// La vista llama esto desde `onAppear`/`onChange`, nunca desde el
    /// `body` -- igual que `RowsModel.recompute`.
    func recompute(_ build: () -> [Element]) {
        let result = build()
        visible = result
        let ids = result.map(\.id)
        if order.ids != ids { order = GridOrder(ids) }
    }
}

/// PLAN-studio-rendimiento-2.md Fase 1 (ST-181): `StatusSummaryModel`
/// para las cuadrículas. `StatusSummaryModel` memoiza el resumen de una
/// TABLA (`MediaSectionView`, ST-153); las cinco cuadrículas seguían
/// llamando `LibraryStats.albums/artists/movies/series/photoAlbums`
/// crudo dentro del `body` -- `flatMap` de los 12 000 ítems más una
/// normalización de cadenas por ítem, en cada clic (diagnóstico §0.1).
///
/// Se parte en dos, como en las tablas:
/// - **el total** (conteos de todo lo visible) depende solo de la
///   cuadrícula, así que se recalcula con ella;
/// - **la selección** se recalcula al cambiar la selección, pero fuera
///   del hilo principal cuando es cara: seleccionar todo en Álbumes son
///   1 000 grupos y 12 000 canciones que normalizar. Cada recálculo
///   cancela el anterior, así que arrastrar una selección o mantener
///   apretada una flecha no encola trabajo viejo (el efecto de un
///   "debounce" sin la latencia fija de uno).
@MainActor
final class GridStatusModel: ObservableObject {
    @Published private(set) var summary: LibraryStatusSummary?

    /// Mismo umbral que `RowsModel`: por debajo, saltar de hilo cuesta
    /// más que el propio cálculo.
    private static let asyncThreshold = 2_000

    private var total: LibraryStatusSummary?
    private var selectionText: String?
    private var selectionTask: Task<Void, Never>?
    private var generation = 0

    deinit {
        selectionTask?.cancel()
    }

    /// El total de la sección: se recalcula cuando cambia lo visible.
    func recomputeTotal(_ build: () -> LibraryStatusSummary?) {
        total = build()
        publish()
    }

    /// La parte de la selección. `cost` es el tamaño real del trabajo
    /// (ítems alcanzados por la selección, no grupos) -- por encima del
    /// umbral se calcula fuera del hilo principal.
    func recomputeSelection(cost: Int, _ build: @escaping @Sendable () -> String?) {
        selectionTask?.cancel()
        selectionTask = nil
        generation += 1

        guard cost > Self.asyncThreshold else {
            selectionText = build()
            publish()
            return
        }

        let thisGeneration = generation
        selectionTask = Task.detached(priority: .userInitiated) { [weak self] in
            let text = build()
            guard !Task.isCancelled else { return }
            await self?.apply(selectionText: text, generation: thisGeneration)
        }
    }

    /// Publica el resultado del cálculo de arriba, salvo que mientras
    /// corría haya arrancado uno más nuevo.
    private func apply(selectionText text: String?, generation: Int) {
        guard self.generation == generation else { return }
        selectionText = text
        publish()
    }

    private func publish() {
        guard var next = total else {
            if summary != nil { summary = nil }
            return
        }
        next.selection = selectionText
        if summary != next { summary = next }
    }
}

/// PLAN-studio-rendimiento-2.md Fase 1 (ST-181): la selección de una
/// cuadrícula, en un objeto chico e INYECTABLE.
///
/// El motivo es de medición, no de arquitectura: el criterio de cierre
/// de F1 es "un clic reevalúa solo la tarjeta tocada y la barra de
/// estado", y para medirlo hay que poder cambiar la selección desde
/// afuera de la vista. Mientras vivía en un `@State private`, nada podía
/// -- ni siquiera una prueba con `@testable import` -- así que el
/// conteo de evaluaciones de `body` (`BodyEvaluationCounter`) solo podía
/// verificarse a ojo, corriendo la app. Con esto, la prueba hospeda la
/// vista con su propio modelo de selección, lo muta y cuenta.
///
/// El comportamiento en producción es idéntico al `@State` de antes: la
/// vista crea el suyo si nadie le pasa uno, y un cambio de selección la
/// invalida igual. Por ahora solo lo usa `AlbumsView` (la cuadrícula del
/// criterio de cierre); las otras cuatro siguen con `@State` hasta F4,
/// que rehace la selección de todas (marquee, Shift+flechas, ancla).
/// Sin `@MainActor` a propósito, a diferencia de `GridModel` y
/// `GridStatusModel`: tiene que poder construirse como valor por omisión
/// del inicializador de una vista, que no está aislado al actor. Solo lo
/// lee y lo escribe código de vista (hilo principal) y no toca nada
/// compartido.
final class GridSelectionModel<ID: Hashable>: ObservableObject {
    @Published var selection: GridSelection<ID>

    init(_ selection: GridSelection<ID> = GridSelection<ID>()) {
        self.selection = selection
    }
}
