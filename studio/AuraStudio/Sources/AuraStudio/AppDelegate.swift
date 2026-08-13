import AppKit

/// Garantiza que la Mac quede exactamente como estaba antes de que
/// Aura Studio hubiera pausado nada, incluso si el usuario cierra la
/// app (Cmd+Q) en medio de la instalacion. Sin esto, `InstallerViewModel.stop()`
/// dispara la reactivacion de los agentes AMP como una `Task` sin
/// esperar su resultado (`fire-and-forget`) desde `.onDisappear` --
/// suficiente cuando la app sigue viva, pero el proceso puede terminar
/// antes de que esa tarea asincrona (que corre un script con
/// privilegios de administrador) alcance a completarse.
/// `applicationShouldTerminate` retrasa el cierre real hasta que
/// `AMPAgentsGuard` confirma que ya no hay nada pendiente por
/// reactivar.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard AMPAgentsGuard.shared.isPaused else { return .terminateNow }

        Task { @MainActor in
            await AMPAgentsGuard.shared.resumeIfNeeded()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
