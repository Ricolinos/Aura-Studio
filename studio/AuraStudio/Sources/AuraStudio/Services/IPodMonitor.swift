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
    /// El volumen ya inspeccionado (que firmware tiene, cuanto espacio,
    /// que hay sincronizado). nil mientras no haya un disco montado.
    @Published private(set) var device: AuraDevice?

    private let diskMonitor = DiskArbitrationMonitor()
    private var dfuPollTask: Task<Void, Never>?
    private var runner: MKS5LBootRunner?
    private var lastDiskInfo: DiskModeInfo?
    /// Discos a los que ya se les intento un `diskutil mountDisk` antes
    /// de declararlos "sin sistema de archivos" (D-182): un disco
    /// DESMONTADO no es lo mismo que un disco sin nada legible -- p.ej.
    /// un formateo interrumpido lo deja desmontado pero con FAT32
    /// valido, y formatearlo de nuevo seria destruir datos sanos. Solo
    /// si el intento de montaje no produce un volumen se pasa a
    /// `diskModeNoFilesystem`. Se limpia al desconectar, para que un
    /// replug reintente.
    private var mountAttempted: Set<String> = []

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
            device = AuraDeviceProbe.probe(diskInfo: info)
        } else if case .diskMode = state {
            state = .notConnected
            device = nil
            mountAttempted.removeAll()
        }
    }

    /// Vuelve a inspeccionar el volumen montado. Hace falta despues de
    /// un sync: el resumen de la biblioteca en el disco cambio, pero el
    /// disco sigue montado, asi que DiskArbitration no notifica nada.
    func refreshDevice() {
        guard let info = lastDiskInfo else { return }
        device = AuraDeviceProbe.probe(diskInfo: info)
    }

    /// El escaneo DFU es costoso relativo (lanza un proceso y hace I/O
    /// USB), asi que se salta mientras ya sabemos que el disco esta
    /// montado -- no puede estar en las dos formas a la vez. De paso,
    /// en el mismo ciclo (mismo costo de un `Task.sleep`, sin sondeo
    /// adicional) tambien busca el iPod por disco completo via IOKit
    /// (`IPodDiskIdentifier`, que no necesita ningun volumen montado)
    /// cuando ni DiskArbitration ni el escaneo DFU encontraron nada --
    /// cubre el disco sin sistema de archivos valido (ver
    /// `DeviceState.diskModeNoFilesystem`).
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
                } else if case .found(let candidate) = IPodDiskIdentifier.identify(from: IPodDiskIdentifier.currentCandidates()) {
                    if !self.mountAttempted.contains(candidate.bsdName) {
                        // Primero intentar montar: si el disco tiene un
                        // sistema de archivos valido pero quedo
                        // desmontado, el montaje dispara el evento de
                        // DiskArbitration y el estado pasa a .diskMode
                        // solo -- sin formatear nada (D-182).
                        self.mountAttempted.insert(candidate.bsdName)
                        Self.attemptMount(bsdName: candidate.bsdName)
                    } else {
                        self.state = .diskModeNoFilesystem(candidate)
                    }
                } else if case .dfuMode = self.state {
                    self.state = .notConnected
                } else if case .diskModeNoFilesystem = self.state {
                    self.state = .notConnected
                } else if self.state == .detecting {
                    self.state = .notConnected
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    /// `diskutil mountDisk` no necesita privilegios para un disco
    /// removible. Corre desprendido: el resultado no se espera -- si el
    /// montaje funciona, DiskArbitration lo notifica solo (callback de
    /// cambio de descripcion, D-182) y el estado avanza por ese camino.
    private nonisolated static func attemptMount(bsdName: String) {
        Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            process.arguments = ["mountDisk", bsdName]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
        }
    }
}
