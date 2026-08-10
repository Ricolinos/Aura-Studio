import Foundation
import Combine

/// Fuente de verdad unica del estado del iPod, combinando dos vias de
/// deteccion muy distintas: DiskArbitration (evento-driven, para modo
/// disco/normal) y sondeo periodico de `mks5lboot --dfuscan` (para modo
/// DFU, que no aparece como volumen montado -- es un dispositivo USB
/// crudo). Esto es lo que permite que las pantallas de la guia de
/// instalacion avancen solas apenas detectan el estado que esperan, en
/// vez de depender de que el usuario confirme a mano "ya lo hice".
@MainActor
final class IPodMonitor: ObservableObject {
    @Published private(set) var state: DeviceState = .detecting

    private let diskMonitor = DiskArbitrationMonitor()
    private var dfuPollTask: Task<Void, Never>?
    private var runner: MKS5LBootRunner?
    private var lastDiskInfo: DiskModeInfo?

    init() {
        runner = try? MKS5LBootRunner()
    }

    func start() {
        diskMonitor.start { [weak self] info in
            Task { @MainActor in
                self?.handleDiskChange(info)
            }
        }
        startDFUPolling()
    }

    func stop() {
        diskMonitor.stop()
        dfuPollTask?.cancel()
        dfuPollTask = nil
    }

    func unmountCurrentDisk() async -> Bool {
        await withCheckedContinuation { continuation in
            diskMonitor.unmount { ok in
                continuation.resume(returning: ok)
            }
        }
    }

    private func handleDiskChange(_ info: DiskModeInfo?) {
        lastDiskInfo = info
        if let info {
            state = .diskMode(info)
        } else if case .diskMode = state {
            state = .notConnected
        }
    }

    /// El escaneo DFU es costoso relativo (lanza un proceso y hace I/O
    /// USB), asi que se salta mientras ya sabemos que el disco esta
    /// montado -- no puede estar en las dos formas a la vez.
    private func startDFUPolling() {
        dfuPollTask?.cancel()
        dfuPollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if case .diskMode = self.state {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    continue
                }
                if let runner = self.runner, let dfu = try? runner.scanDFU() {
                    self.state = .dfuMode(dfu)
                } else if case .dfuMode = self.state {
                    self.state = .notConnected
                } else if self.state == .detecting {
                    self.state = .notConnected
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
}
