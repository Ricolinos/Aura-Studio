import SwiftUI

@main
struct AuraStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 720, minHeight: 520)
        }
        .windowResizability(.contentSize)
        .commands {
            // PLAN-general-sync.md §1.1: acceso rapido a sincronizar
            // sin tener que ir a General -- ver SyncMenuCommand.
            CommandGroup(after: .newItem) {
                Divider()
                SyncMenuCommand()
            }
        }
    }
}
