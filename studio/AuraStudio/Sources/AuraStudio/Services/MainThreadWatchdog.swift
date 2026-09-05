import Foundation
import os
#if canImport(Darwin)
import Darwin
#endif

/// PLAN-studio-rendimiento.md Fase 0: vigilante de hilo principal, solo
/// para diagnóstico en desarrollo (`DEBUG` + variable de entorno
/// `AURA_WATCHDOG=1`). Late un "corazón" en el hilo principal cada
/// `pollInterval`; un hilo aparte lo revisa, y si pasan más de
/// `thresholdSeconds` sin uno nuevo, asume que el hilo principal está
/// bloqueado.
///
/// La pila se captura en dos tiempos a propósito: el manejador de la
/// señal solo llama `backtrace()` sobre un buffer ya reservado (sin
/// `malloc`, razonablemente seguro dentro de un manejador de señal);
/// symbolizar (`backtrace_symbols`, que sí reserva memoria) pasa a
/// después, ya en el hilo vigilante -- symbolizar DENTRO del manejador
/// podría colgar algo de verdad si el hilo principal tenía el lock de
/// `malloc` tomado justo cuando lo interrumpió la señal, que es
/// precisamente el escenario que este vigilante existe para detectar.
///
/// Nunca corre fuera de `DEBUG` ni sin la variable de entorno: no es
/// parte de lo que ve el usuario, y jamás se activa en una build de
/// Release.
enum MainThreadWatchdog {
    #if DEBUG
    private static let signpostLog = OSLog(subsystem: "com.ricolinos.aurastudio", category: "Rendimiento")
    private static let thresholdSeconds: TimeInterval = 0.25
    private static let pollInterval: TimeInterval = 0.05
    private static let maxFrames = 64

    private static let heartbeatLock = NSLock()
    private static var lastHeartbeat = Date()
    private static var mainThreadPort: pthread_t?
    private static let frameBuffer = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: maxFrames)
    private static var frameCount: Int32 = -1
    private static var started = false
    #endif

    /// Se llama una vez al arrancar la app, desde el hilo principal
    /// (`AuraStudioApp`). No hace nada fuera de `DEBUG` o sin la
    /// variable de entorno.
    static func startIfRequested() {
        #if DEBUG
        guard !started, ProcessInfo.processInfo.environment["AURA_WATCHDOG"] == "1" else { return }
        started = true
        mainThreadPort = pthread_self()
        installSignalHandler()
        beatHeartbeat()
        let thread = Thread { watch() }
        thread.name = "AuraStudio.MainThreadWatchdog"
        thread.start()
        log("[MainThreadWatchdog] activo -- avisa de bloqueos del hilo principal > \(Int(thresholdSeconds * 1000)) ms")
        #endif
    }

    #if DEBUG
    private static func beatHeartbeat() {
        heartbeatLock.lock()
        lastHeartbeat = Date()
        heartbeatLock.unlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) { beatHeartbeat() }
    }

    private static func installSignalHandler() {
        var action = sigaction()
        action.__sigaction_u.__sa_handler = { _ in
            MainThreadWatchdog.frameCount = backtrace(MainThreadWatchdog.frameBuffer, Int32(MainThreadWatchdog.maxFrames))
        }
        sigemptyset(&action.sa_mask)
        action.sa_flags = 0
        sigaction(SIGUSR2, &action, nil)
    }

    private static func watch() {
        var hangStartedAt: Date?
        while true {
            Thread.sleep(forTimeInterval: pollInterval)
            heartbeatLock.lock()
            let sinceLastBeat = Date().timeIntervalSince(lastHeartbeat)
            heartbeatLock.unlock()

            if sinceLastBeat > thresholdSeconds {
                if hangStartedAt == nil {
                    hangStartedAt = Date().addingTimeInterval(-sinceLastBeat)
                    os_signpost(.begin, log: signpostLog, name: "MainThreadHang")
                    frameCount = -1
                    if let port = mainThreadPort { pthread_kill(port, SIGUSR2) }
                }
            } else if let startedAt = hangStartedAt {
                os_signpost(.end, log: signpostLog, name: "MainThreadHang")
                let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                report(durationMs: durationMs)
                hangStartedAt = nil
            }
        }
    }

    private static func report(durationMs: Int) {
        log("[MainThreadWatchdog] bloqueo de ~\(durationMs) ms en el hilo principal")
        guard frameCount > 0 else {
            log("    (no se alcanzó a capturar la pila -- el bloqueo terminó antes de que la señal llegara)")
            return
        }
        if let symbols = backtrace_symbols(frameBuffer, frameCount) {
            for i in 0..<Int(frameCount) {
                if let cString = symbols[i] { log("    " + String(cString: cString)) }
            }
            free(symbols)
        }
    }

    /// `print` normal queda con buffer completo cuando la salida no es una
    /// terminal (p. ej. corriendo bajo `swift test` con la salida
    /// redirigida) -- un bloqueo real puede terminar el proceso de
    /// pruebas antes de que ese buffer se vacíe, y el aviso nunca llega a
    /// verse. `fflush` fuerza a que cada línea salga de inmediato.
    private static func log(_ message: String) {
        print(message)
        fflush(stdout)
    }
    #endif
}
