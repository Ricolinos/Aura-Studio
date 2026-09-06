import SwiftUI
import AppKit

/// Lo que la ventana activa expone a la barra de menús (ST-063). Vive
/// como `FocusedValue` por la misma razón que `SyncCommandContext`: el
/// estado real (`library`, `selection` de la barra lateral) está en
/// `ContentView`, no en `AuraStudioApp`. Sin ventana enfocada los
/// comandos quedan deshabilitados, como en cualquier app de macOS.
struct LibraryCommandContext {
    /// Sección visible ahora mismo (para "Agregar a la biblioteca" y
    /// para arrancar "Elementos similares" filtrado al tipo correcto).
    let currentSection: SidebarSection
    let navigate: (SidebarSection) -> Void
    let addFiles: () -> Void
    let showSimilarItems: () -> Void
    let revealLibraryFolder: () -> Void
}

private struct LibraryCommandKey: FocusedValueKey {
    typealias Value = LibraryCommandContext
}

extension FocusedValues {
    var auraLibraryCommand: LibraryCommandContext? {
        get { self[LibraryCommandKey.self] }
        set { self[LibraryCommandKey.self] = newValue }
    }
}

/// PLAN-studio-rendimiento-2.md Fase 4 (ST-184): lo que la sección con
/// foco expone al menú **Edición**.
///
/// "Seleccionar todo" existía solo como un `.onKeyPress(keys: ["a"])`
/// dentro de cada cuadrícula: funcionaba, pero no aparecía en ningún
/// menú, así que no era descubrible y no se podía deshabilitar cuando no
/// tenía sentido. Y "deseleccionar todo" no existía: la única forma era
/// Escape, que nadie encuentra sin que se lo digan.
///
/// Va por `FocusedValue` por lo mismo que `LibraryCommandContext`: el
/// estado real (la selección) vive en la sección visible, no en
/// `AuraStudioApp`. Sin sección con selección, los dos comandos quedan
/// grises, como en cualquier app de macOS.
struct SelectionCommandContext {
    let selectAll: () -> Void
    let deselectAll: () -> Void
    /// Para deshabilitar "Deseleccionar todo" cuando no hay nada que
    /// deseleccionar.
    let hasSelection: Bool
}

private struct SelectionCommandKey: FocusedValueKey {
    typealias Value = SelectionCommandContext
}

extension FocusedValues {
    var auraSelectionCommand: SelectionCommandContext? {
        get { self[SelectionCommandKey.self] }
        set { self[SelectionCommandKey.self] = newValue }
    }
}

/// Menú Edición: ⌘A / ⇧⌘A enrutados a la sección con foco.
struct EditMenuCommands: View {
    @FocusedValue(\.auraSelectionCommand) private var context

    var body: some View {
        Button("Seleccionar todo") {
            context?.selectAll()
        }
        .keyboardShortcut("a", modifiers: .command)
        .disabled(context == nil)

        Button("Deseleccionar todo") {
            context?.deselectAll()
        }
        .keyboardShortcut("a", modifiers: [.command, .shift])
        .disabled(context?.hasSelection != true)
    }
}

/// Menú Archivo: "Agregar a la biblioteca..." (⌘O) -- mismo camino que
/// soltar archivos sobre la sección visible.
struct AddToLibraryMenuCommand: View {
    @FocusedValue(\.auraLibraryCommand) private var context

    var body: some View {
        Button("Agregar a la biblioteca...") {
            context?.addFiles()
        }
        .keyboardShortcut("o", modifiers: .command)
        .disabled(context == nil)
    }
}

/// Menú Visualización: barra de estado (⌘/, como Finder) y "Ir a" cada
/// sección con ⌘1…⌘9 / ⌘0.
struct ViewMenuCommands: View {
    @ObservedObject private var preferences = AppPreferences.shared
    @FocusedValue(\.auraLibraryCommand) private var context

    var body: some View {
        Toggle(isOn: $preferences.showStatusBar) {
            Text("Mostrar barra de estado")
        }
        .keyboardShortcut("/", modifiers: .command)

        Divider()

        ForEach(Self.navigationTargets, id: \.section) { target in
            Button(target.title) {
                context?.navigate(target.section)
            }
            .keyboardShortcut(target.key, modifiers: .command)
            .disabled(context == nil)
        }
    }

    static let navigationTargets: [(section: SidebarSection, title: String, key: KeyEquivalent)] = [
        (.general, "General", "0"),
        (.music, "Canciones", "1"),
        (.musicAlbums, "Álbumes", "2"),
        (.musicArtists, "Artistas", "3"),
        (.musicPlaylists, "Listas", "4"),
        (.video, "Todos los videos", "5"),
        (.videoMovies, "Películas", "6"),
        (.videoSeries, "Series", "7"),
        (.photos, "Todas las fotos", "8"),
        (.extras, "Extras", "9"),
    ]
}

/// Menú Biblioteca: herramientas de organización que no dependen de
/// una selección puntual.
struct LibraryMenuCommands: View {
    @FocusedValue(\.auraLibraryCommand) private var context

    var body: some View {
        Button("Buscar elementos similares...") {
            context?.showSimilarItems()
        }
        .keyboardShortcut("d", modifiers: [.command, .option])
        .disabled(context == nil)

        Divider()

        Button("Mostrar carpeta de la biblioteca en Finder") {
            context?.revealLibraryFolder()
        }
        .disabled(context == nil)
    }
}
