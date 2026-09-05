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
