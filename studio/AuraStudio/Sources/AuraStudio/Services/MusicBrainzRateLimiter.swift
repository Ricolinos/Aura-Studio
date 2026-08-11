import Foundation

/// Serializa los pedidos a MusicBrainz respetando su limite documentado
/// de 1 request por segundo por IP, que esta *estrictamente* aplicado:
/// pasarse no da un error distinto, te mete en una cola compartida y te
/// degrada a todos los usuarios del mismo User-Agent.
///
/// Es un actor y no un simple `sleep` en el cliente porque el limite es
/// por IP, no por llamada: si el pipeline enriquece varias canciones a la
/// vez, todas tienen que pasar por el mismo cuello de botella.
actor MusicBrainzRateLimiter {
    static let shared = MusicBrainzRateLimiter()

    private let minimumInterval: TimeInterval
    private var lastRequestAt: Date?

    init(minimumInterval: TimeInterval = 1.0) {
        self.minimumInterval = minimumInterval
    }

    /// Espera lo necesario para que hayan pasado al menos
    /// `minimumInterval` desde el pedido anterior, y reserva el turno.
    func waitForTurn(now: Date = Date()) async {
        if let last = lastRequestAt {
            let elapsed = now.timeIntervalSince(last)
            if elapsed < minimumInterval {
                let remaining = minimumInterval - elapsed
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
        }
        lastRequestAt = Date()
    }

    /// Solo para tests: cuanto habria que esperar, sin dormir ni reservar.
    func pendingDelay(now: Date) -> TimeInterval {
        guard let last = lastRequestAt else { return 0 }
        return max(0, minimumInterval - now.timeIntervalSince(last))
    }

    func reserve(at date: Date) {
        lastRequestAt = date
    }
}
