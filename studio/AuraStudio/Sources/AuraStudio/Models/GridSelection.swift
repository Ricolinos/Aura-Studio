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
    private var lastTapped: ID?

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
        if flags.contains(.shift), let last = lastTapped,
           let lastIndex = order.index(of: last), let thisIndex = order.index(of: id) {
            let range = lastIndex <= thisIndex ? lastIndex...thisIndex : thisIndex...lastIndex
            selected.formUnion(order.ids[range])
        } else if flags.contains(.command) {
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        } else {
            selected = [id]
        }
        lastTapped = id
    }

    /// Alterna `id` desde su CASILLA de seleccion (ST-103). A
    /// diferencia de `handleTap`, la casilla es un control explicito:
    /// no depende de ninguna tecla y nunca reemplaza la seleccion
    /// entera -- solo agrega o quita ese elemento. Es la unica forma de
    /// armar una seleccion multiple sin saber que existe Cmd+clic.
    mutating func toggle(_ id: ID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        lastTapped = id
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
    }

    /// PLAN-studio-rendimiento.md Fase 2 punto 1: Cmd+A -- selecciona
    /// todo lo VISIBLE (`order` ya viene filtrado por quien llama, igual
    /// que para `handleTap`).
    mutating func selectAll(_ order: GridOrder<ID>) {
        selected = Set(order.ids)
        lastTapped = order.ids.last
    }

    /// Quita del set los ids que ya no existen (p. ej. tras borrar
    /// items o que `viewModel.items` cambie) -- llamar en cada
    /// `rebuild()` de la vista.
    mutating func pruneMissing(from validIDs: Set<ID>) {
        selected.formIntersection(validIDs)
        if let last = lastTapped, !validIDs.contains(last) {
            lastTapped = nil
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

extension UTType {
    static let auraLibrarySelection = UTType(exportedAs: "com.ricolinos.aurastudio.library-selection")
}
