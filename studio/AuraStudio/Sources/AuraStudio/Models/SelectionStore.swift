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
@MainActor
final class SelectionStore: ObservableObject {
    @Published private(set) var selected: Set<UUID> = []

    func replace(with ids: Set<UUID>) {
        selected = ids
    }

    func clear() {
        selected = []
    }
}
