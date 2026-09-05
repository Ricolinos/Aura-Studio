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
/// Genérico sobre `ID` para reusarse en Álbumes/Artistas/Películas/
/// Series/episodios/álbumes de fotos/fotos -- cada cuadrícula guarda
/// la suya (`@State private var selection = GridSelection<String>()`).
struct GridSelection<ID: Hashable>: Equatable {
    var selected: Set<ID> = []
    private var lastTapped: ID?

    /// Aplica un clic simple sobre `id`, dado el orden visible actual
    /// (`orderedIDs`, para resolver el rango de Shift+clic).
    mutating func handleTap(_ id: ID, orderedIDs: [ID]) {
        handleTap(id, orderedIDs: orderedIDs, modifierFlags: NSEvent.modifierFlags)
    }

    /// PLAN-studio-rendimiento.md Fase 0: separado de `handleTap` para
    /// poder medir (y más adelante probar) el camino de Shift+clic sin
    /// depender del estado global de teclado -- `NSEvent.modifierFlags`
    /// no se puede simular en una prueba. El camino de producción sigue
    /// siendo exactamente el mismo (`handleTap` de arriba se lo delega).
    mutating func handleTap(_ id: ID, orderedIDs: [ID], modifierFlags flags: NSEvent.ModifierFlags) {
        if flags.contains(.shift), let last = lastTapped,
           let lastIndex = orderedIDs.firstIndex(of: last), let thisIndex = orderedIDs.firstIndex(of: id) {
            let range = lastIndex <= thisIndex ? lastIndex...thisIndex : thisIndex...lastIndex
            selected.formUnion(orderedIDs[range])
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
