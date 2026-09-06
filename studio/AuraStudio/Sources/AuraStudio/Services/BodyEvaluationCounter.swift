import Foundation

/// PLAN-studio-rendimiento-2.md Fase 0 (arnés de medición, pedido de la
/// sesión "mecanico sonnet"): cuántas veces evaluó su `body` cada vista.
/// Es la medida directa del síntoma de la ronda 2 -- un clic en una
/// tarjeta no debe reevaluar `ContentView` ni las 1 000 tarjetas, solo
/// la tocada y la barra de estado.
///
/// Solo existe en DEBUG. En Release las tres funciones son cuerpos
/// vacíos que el optimizador borra, así que llamarlas desde un `body` no
/// cuesta nada en la app que usa el dueño. Mismo patrón de gancho para
/// pruebas que `MainThreadWatchdog.onHangDetectedForTesting`.
///
/// El conteo es deliberadamente simple (un diccionario sin candado): las
/// evaluaciones de `body` de SwiftUI ocurren en el hilo principal, que
/// es donde corren también las pruebas que lo leen.
enum BodyEvaluationCounter {
    #if DEBUG
    nonisolated(unsafe) private static var counts: [String: Int] = [:]

    static func record(_ view: String) {
        counts[view, default: 0] += 1
    }

    static func count(for view: String) -> Int {
        counts[view] ?? 0
    }

    static func resetForTesting() {
        counts = [:]
    }
    #else
    static func record(_ view: String) {}
    static func count(for view: String) -> Int { 0 }
    static func resetForTesting() {}
    #endif
}
