import Foundation

/// PLAN-studio-rendimiento.md Fase 1: reemplaza `LibraryViewModel.
/// selectionForSync`. Diagnóstico §0.1 -- ese campo era un `@Published`
/// del ViewModel gigante que `ContentView` observa entero, así que
/// publicar la selección ahí disparaba `objectWillChange` para TODA la
/// ventana en cada clic, no solo para quien de verdad necesita saber qué
/// hay seleccionado. Un `SelectionStore` chico y aparte, observado solo
/// por quien consume la selección (`DeviceGeneralView`, `AlbumsView`,
/// `MoviesView`), saca al resto de la app de ese camino.
///
/// Mismo comportamiento de siempre (ver `MediaSectionView.onAppear`/
/// `.onChange`/`.onDisappear`, que sigue exactamente igual salvo por a
/// dónde publica): la tabla de canciones/video/fotos que esté visible en
/// un momento dado -- la de nivel superior, o una embebida dentro de un
/// álbum/película expandido -- publica su selección acá, y se limpia al
/// desaparecer para que otra sección no herede una selección que ya no
/// es la que el usuario ve. Un solo `SelectionStore` compartido (no uno
/// por tipo de medio) a propósito: así es como ya funciona hoy
/// `selectionForSync` -- `AlbumsView`/`MoviesView` leen la selección que
/// publica su propia tabla de canciones embebida, y separarlo por tipo
/// de medio habría sido un cambio de comportamiento, no solo de
/// rendimiento.
///
/// PLAN-studio-rendimiento-2.md Fase 1 (ST-181): ahora las CUADRÍCULAS
/// (`GridSelection` de Álbumes/Artistas/Películas/Series/Fotos) también
/// publican acá -- seleccionar tres álbumes y pedir "sincronizar solo la
/// selección" tiene que sincronizar esas canciones, no nada. Como el
/// mismo `SelectionStore` lo escriben ahora dos vistas que se relevan
/// (la cuadrícula y la tabla embebida del álbum abierto) y SwiftUI no
/// garantiza el orden entre el `onAppear` de la que entra y el
/// `onDisappear` de la que sale, cada publicador se identifica con un
/// `owner`: **solo el dueño actual puede limpiar**. Sin eso, salir de la
/// cuadrícula hacia el detalle borraba la selección que el detalle acaba
/// de publicar.
@MainActor
final class SelectionStore: ObservableObject {
    @Published private(set) var selected: Set<UUID> = []

    /// Quién publicó lo que hay ahora. `nil` = nadie (recién limpiado).
    private var owner: UUID?

    /// `owner` identifica a la vista que publica (un `UUID` estable por
    /// instancia de vista). Omitirlo publica sin reclamar la propiedad
    /// -- solo para pruebas y llamadas puntuales.
    func replace(with ids: Set<UUID>, from owner: UUID? = nil) {
        if let owner { self.owner = owner }
        // Publicar un valor idéntico invalidaría a todos los
        // observadores sin que nada haya cambiado: cada clic en una
        // cuadrícula sin selección publicaba un conjunto vacío sobre
        // otro vacío.
        if selected != ids { selected = ids }
    }

    /// Limpieza de quien se va: no hace nada si mientras tanto otra
    /// vista ya tomó la propiedad.
    func clear(from owner: UUID) {
        guard self.owner == owner else { return }
        clear()
    }

    func clear() {
        owner = nil
        if !selected.isEmpty { selected = [] }
    }
}
