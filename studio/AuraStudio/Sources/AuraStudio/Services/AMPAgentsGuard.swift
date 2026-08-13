import Foundation

/// Punto unico de verdad sobre si los agentes AMP (D-041/D-044) siguen
/// pausados en este momento, sin importar que instancia de
/// `InstallerViewModel` los pauso -- el asistente se puede recrear
/// (salir al selector de Instalar/Restaurar y volver a entrar) pero la
/// Mac del usuario sigue siendo la misma hasta que la app cierra de
/// verdad. `AppDelegate` consulta este estado para bloquear el cierre
/// de la app (`applicationShouldTerminate`) hasta reactivarlos --
/// dejarlos pausados y confiar solo en el watchdog de
/// `PrivilegedExecutor` (que tarda hasta 10 minutos) es la clase de
/// "se arregla solo eventualmente" que este proyecto evita cuando se
/// puede resolver de una al cerrar.
@MainActor
final class AMPAgentsGuard {
    static let shared = AMPAgentsGuard()

    private(set) var isPaused = false
    private let executor = PrivilegedExecutor()

    private init() {}

    func markPaused() {
        isPaused = true
    }

    /// Idempotente: llamarlo sin que haya nada pausado no hace nada.
    /// Los errores se ignoran a proposito -- reactivar los agentes es
    /// best-effort (el watchdog sigue siendo la red de seguridad real
    /// si esto falla), nunca algo que deba bloquear que la app cierre.
    func resumeIfNeeded() async {
        guard isPaused else { return }
        isPaused = false
        try? await executor.resumeAMPAgents()
    }
}
