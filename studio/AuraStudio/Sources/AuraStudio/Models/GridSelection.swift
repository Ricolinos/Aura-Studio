import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Selección múltiple estilo Finder para cuadrículas (encargo del
/// dueño, 2026-08-19: "poder seleccionar múltiples álbumes de música,
/// artistas, o películas, series, episodios... para organizar de una
/// forma más cómoda la biblioteca") -- clic = solo este elemento,
/// Cmd+clic = alternarlo dentro/fuera de la selección, Shift+clic =
/// rango desde el último tocado. SwiftUI no expone el modificador de
/// teclado del propio gesto de tap, así que se lee `NSEvent.
/// modifierFlags` (estado global "qué tecla está apretada ahora
/// mismo") en el momento del clic -- mismo truco que usa el resto del
/// ecosistema SwiftUI en macOS para esto.
///
/// PLAN-studio-rendimiento.md Fase 2 punto 2: el orden visible de una
/// cuadrícula, con su índice id→posición ya construido -- para que
/// `GridSelection.handleTap` resuelva un rango de Shift+clic en O(1) en
/// vez de escanear el arreglo dos veces por clic. Cada vista de
/// cuadrícula construye el suyo cuando cambia lo que se ve (filtro,
/// orden, biblioteca), nunca en el gesto de tap.
struct GridOrder<ID: Hashable>: Equatable where ID: Equatable {
    let ids: [ID]
    private let indexByID: [ID: Int]

    init(_ ids: [ID]) {
        self.ids = ids
        self.indexByID = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
    }

    static var empty: GridOrder<ID> { GridOrder([]) }

    func index(of id: ID) -> Int? { indexByID[id] }

    static func == (lhs: GridOrder<ID>, rhs: GridOrder<ID>) -> Bool { lhs.ids == rhs.ids }
}

/// Genérico sobre `ID` para reusarse en Álbumes/Artistas/Películas/
/// Series/episodios/álbumes de fotos/fotos -- cada cuadrícula guarda
/// la suya (`@State private var selection = GridSelection<String>()`).
struct GridSelection<ID: Hashable>: Equatable {
    var selected: Set<ID> = []

    /// El elemento con el FOCO: el último que se tocó, y desde el que
    /// se mueven las flechas. PLAN-studio-rendimiento-2.md Fase 4
    /// (ST-184) lo expone -- era privado, y sin él no había forma de
    /// probar Shift+flechas ni de saber desde dónde extender.
    private(set) var lastTapped: ID?

    /// Dónde EMPIEZA un rango de Shift. No es lo mismo que
    /// `lastTapped`: el foco se mueve con cada Shift+clic o Shift+flecha,
    /// el ancla se queda donde estaba hasta que un clic simple (o ⌘+clic,
    /// o una casilla) la reubica. Es lo que hace que ampliar y reducir un
    /// rango con Shift sea reversible.
    private var rangeAnchor: ID?

    /// Lo que agregó el ÚLTIMO rango de Shift, para poder deshacerlo al
    /// hacer el siguiente.
    ///
    /// ST-184: antes, cada Shift+clic hacía `formUnion` sobre lo que
    /// hubiera, así que un rango nunca se podía achicar -- Shift+clic en
    /// la pista 20 y después en la 10 dejaba las veinte seleccionadas.
    /// Finder no hace eso: reemplaza el rango anterior **conservando** lo
    /// que se hubiera marcado aparte con ⌘. Eso es exactamente lo que
    /// permite guardar aparte lo que puso el último rango.
    private var lastRangeIDs: Set<ID> = []

    /// Aplica un clic simple sobre `id`, dado el orden visible actual.
    /// PLAN-studio-rendimiento.md Fase 2 punto 2: `order` se construye
    /// UNA VEZ por cambio de la cuadrícula (ver `GridOrder`), no en cada
    /// clic -- antes, cada llamador armaba `[ID]` con un `.map(\.id)`
    /// fresco por clic y esta función hacía dos `firstIndex(of:)`
    /// O(N) sobre esa lista. Ahora el rango de Shift+clic sale de un
    /// diccionario id→índice, O(1).
    mutating func handleTap(_ id: ID, order: GridOrder<ID>) {
        handleTap(id, order: order, modifierFlags: NSEvent.modifierFlags)
    }

    /// PLAN-studio-rendimiento.md Fase 0: separado de `handleTap` para
    /// poder medir/probar el camino de Shift+clic sin depender del
    /// estado global de teclado -- `NSEvent.modifierFlags` no se puede
    /// simular en una prueba. El camino de producción sigue siendo
    /// exactamente el mismo (`handleTap` de arriba se lo delega).
    mutating func handleTap(_ id: ID, order: GridOrder<ID>, modifierFlags flags: NSEvent.ModifierFlags) {
        handleTap(id, order: order, modifiers: GridSelectionModifiers(flags))
    }

    /// ST-184: la forma **pura** del gesto, sin AppKit. Es la que usan
    /// las pruebas y la que llama la de arriba.
    mutating func handleTap(_ id: ID, order: GridOrder<ID>, modifiers: GridSelectionModifiers) {
        if modifiers.contains(.shift), let anchor = rangeAnchor ?? lastTapped,
           let anchorIndex = order.index(of: anchor), let thisIndex = order.index(of: id) {
            if rangeAnchor == nil { rangeAnchor = anchor }
            applyRange(from: anchorIndex, to: thisIndex, order: order)
        } else if modifiers.contains(.command) {
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
            rangeAnchor = id
            lastRangeIDs = []
        } else {
            selected = [id]
            rangeAnchor = id
            lastRangeIDs = []
        }
        lastTapped = id
    }

    /// Reemplaza el rango anterior por el nuevo, conservando lo que se
    /// haya marcado aparte con ⌘ -- ver `lastRangeIDs`.
    private mutating func applyRange(from anchorIndex: Int, to targetIndex: Int, order: GridOrder<ID>) {
        let range = anchorIndex <= targetIndex ? anchorIndex...targetIndex : targetIndex...anchorIndex
        selected.subtract(lastRangeIDs)
        lastRangeIDs = Set(order.ids[range])
        selected.formUnion(lastRangeIDs)
    }

    // MARK: - Teclado y arrastre (ST-184)

    /// Mueve el foco con una flecha y devuelve el elemento que quedó
    /// enfocado (para que la vista lo desplace a la vista).
    ///
    /// - `columnsPerRow` es cuántas tarjetas entran por fila: arriba y
    ///   abajo saltan una fila entera. En una lista de una columna, `1`.
    /// - `extending` es Shift: extiende el rango desde el ancla en vez
    ///   de reemplazar la selección.
    ///
    /// Sin foco previo, la primera flecha selecciona el primer elemento
    /// (o el último, si va hacia atrás) -- como cualquier lista de macOS.
    @discardableResult
    mutating func move(_ direction: GridDirection, order: GridOrder<ID>,
                       columnsPerRow: Int, extending: Bool) -> ID? {
        guard !order.ids.isEmpty else { return nil }
        let count = order.ids.count
        let currentIndex = lastTapped.flatMap { order.index(of: $0) }
        let targetIndex: Int
        if let currentIndex {
            targetIndex = max(0, min(count - 1, currentIndex + direction.step(columnsPerRow: columnsPerRow)))
        } else {
            targetIndex = direction.isBackwards ? count - 1 : 0
        }
        let id = order.ids[targetIndex]

        if extending {
            let anchorIndex = rangeAnchor.flatMap { order.index(of: $0) } ?? currentIndex ?? targetIndex
            rangeAnchor = order.ids[anchorIndex]
            applyRange(from: anchorIndex, to: targetIndex, order: order)
        } else {
            selected = [id]
            rangeAnchor = id
            lastRangeIDs = []
        }
        lastTapped = id
        return id
    }

    /// Aplica un arrastre (marquee). `base` es la selección al EMPEZAR
    /// el arrastre -- ver `GridMarquee.selection(base:hits:modifiers:)`.
    mutating func applyMarquee(rect: CGRect, frames: [GridMarquee.Frame<ID>],
                               base: Set<ID>, modifiers: GridSelectionModifiers) {
        selected = GridMarquee.selection(rect: rect, frames: frames, base: base, modifiers: modifiers)
        // Un arrastre no deja un rango de Shift a medio hacer.
        lastRangeIDs = []
    }

    /// Alterna `id` desde su CASILLA de seleccion (ST-103). A
    /// diferencia de `handleTap`, la casilla es un control explicito:
    /// no depende de ninguna tecla y nunca reemplaza la seleccion
    /// entera -- solo agrega o quita ese elemento. Es la unica forma de
    /// armar una seleccion multiple sin saber que existe Cmd+clic.
    mutating func toggle(_ id: ID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        lastTapped = id
        rangeAnchor = id
        lastRangeIDs = []
    }

    func isSelected(_ id: ID) -> Bool { selected.contains(id) }

    /// IDs a los que aplica una acción disparada DESDE `id` (menú
    /// contextual o arrastre): si `id` ya estaba en la selección, la
    /// selección completa; si no, solo `id` -- mismo criterio que
    /// Finder ("clic derecho sobre algo no seleccionado actúa solo
    /// sobre eso, sin perder tu selección anterior si SÍ lo estaba").
    func effectiveIDs(for id: ID) -> Set<ID> {
        selected.contains(id) ? selected : [id]
    }

    mutating func clear() {
        selected.removeAll()
        lastTapped = nil
        rangeAnchor = nil
        lastRangeIDs = []
    }

    /// PLAN-studio-rendimiento.md Fase 2 punto 1: Cmd+A -- selecciona
    /// todo lo VISIBLE (`order` ya viene filtrado por quien llama, igual
    /// que para `handleTap`).
    mutating func selectAll(_ order: GridOrder<ID>) {
        selected = Set(order.ids)
        lastTapped = order.ids.last
        rangeAnchor = order.ids.first
        lastRangeIDs = []
    }

    /// Quita del set los ids que ya no existen (p. ej. tras borrar
    /// items o que `viewModel.items` cambie) -- llamar en cada
    /// `rebuild()` de la vista.
    mutating func pruneMissing(from validIDs: Set<ID>) {
        selected.formIntersection(validIDs)
        lastRangeIDs.formIntersection(validIDs)
        if let last = lastTapped, !validIDs.contains(last) {
            lastTapped = nil
        }
        if let anchor = rangeAnchor, !validIDs.contains(anchor) {
            rangeAnchor = nil
        }
    }
}

/// Carga transportada al arrastrar una selección de la biblioteca
/// (encargo del dueño: arrastrar varios álbumes/fotos seleccionados de
/// una vez hacia otra categoría/álbum en la barra lateral). Los IDs son
/// de `LibraryItem` -- cada vista arrastrable expande su selección
/// "lógica" (álbumes, temporadas, álbumes de fotos) a los `LibraryItem.
/// id` que contiene antes de envolverlos acá.
struct LibrarySelectionTransfer: Codable, Transferable {
    let itemIDs: [UUID]

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .auraLibrarySelection)
    }
}

extension GridSelectionModifiers {
    /// ST-184: la única traducción entre AppKit y el núcleo puro de la
    /// selección. `NSEvent.ModifierFlags` no aparece en ningún otro
    /// lado de la lógica.
    init(_ flags: NSEvent.ModifierFlags) {
        var result: GridSelectionModifiers = []
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        self = result
    }
}

extension UTType {
    static let auraLibrarySelection = UTType(exportedAs: "com.ricolinos.aurastudio.library-selection")
}
