import SwiftUI

@main
struct AuraStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        MainThreadWatchdog.startIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 720, minHeight: 520)
        }
        .windowResizability(.contentSize)
        // ST-063: la barra de menús completa en español. Los menús
        // estándar (Aura Studio, Archivo, Edición, Ventana, Ayuda y sus
        // ítems: Salir, Ocultar, Copiar...) los traduce AppKit/SwiftUI
        // porque el bundle declara español como única localización
        // (Resources/es.lproj, CFBundleLocalizations). Lo propio va acá.
        .commands {
            // ST-193: donde cualquier app de macOS lo pone -- en el menú
            // de la app, debajo de "Acerca de Aura Studio".
            CommandGroup(after: .appInfo) {
                Divider()
                AppUpdateMenuCommand()
            }
            CommandGroup(after: .newItem) {
                AddToLibraryMenuCommand()
                Divider()
                // PLAN-general-sync.md §1.1: acceso rapido a sincronizar
                // sin tener que ir a General -- ver SyncMenuCommand.
                SyncMenuCommand()
            }
            // "Visualización": barra de estado e "Ir a" cada sección,
            // antes del "Ocultar/Mostrar barra lateral" que SwiftUI ya
            // pone solo en ese menú.
            // ST-184: "Seleccionar todo" (⌘A) y "Deseleccionar todo"
            // (⇧⌘A) en el menú Edición, enrutados a la sección con foco.
            // Antes, ⌘A era un `.onKeyPress` dentro de cada cuadrícula:
            // no aparecía en ningún menú y no se podía deshabilitar.
            CommandGroup(after: .pasteboard) {
                Divider()
                EditMenuCommands()
            }
            CommandGroup(before: .sidebar) {
                ViewMenuCommands()
                Divider()
            }
            CommandMenu("Biblioteca") {
                LibraryMenuCommands()
            }
        }
    }
}
