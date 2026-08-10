import Foundation
import Combine

/// Orquesta el asistente completo: detectar el iPod, guiarlo a modo DFU,
/// instalar (o desinstalar, en modo restore) el bootloader Aura, y
/// verificar el resultado. No implementa nada de bajo nivel -- delega en
/// `IPodMonitor` (deteccion) y `MKS5LBootRunner` (el binario ya probado
/// de la Fase 8); esta clase solo es la maquina de estados del asistente
/// y el pegamento entre las dos.
@MainActor
final class InstallerViewModel: ObservableObject {
    @Published private(set) var step: InstallerStep = .welcome
    @Published private(set) var mode: InstallerMode = .install
    @Published private(set) var progressMessage: String = ""
    @Published private(set) var lastError: InstallerError?
    @Published var destroyOriginalFirmware: Bool = false

    let monitor: IPodMonitor
    private var cancellables: Set<AnyCancellable> = []
    private var runner: MKS5LBootRunner?

    init(monitor: IPodMonitor? = nil) {
        self.monitor = monitor ?? IPodMonitor()
        self.runner = try? MKS5LBootRunner()
    }

    func start(mode: InstallerMode) {
        self.mode = mode
        self.lastError = nil
        step = .welcome
        monitor.start()
        observeDeviceState()
    }

    func stop() {
        monitor.stop()
        cancellables.removeAll()
    }

    func advanceFromWelcome() {
        step = .permissions
    }

    func advanceFromPermissions() {
        step = .detectDevice
    }

    /// El usuario confirma que ya combino los botones para entrar a
    /// modo DFU (SELECT+MENU ~12s segun el README de mks5lboot); a
    /// partir de aca `observeDeviceState()` hace avanzar la pantalla
    /// sola apenas `IPodMonitor` confirma el estado DFU real.
    func acknowledgeEnteringDFU() {
        step = .enterDFU
    }

    private func observeDeviceState() {
        monitor.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.reactToDeviceState(state)
            }
            .store(in: &cancellables)
    }

    private func reactToDeviceState(_ state: DeviceState) {
        switch (step, state) {
        case (.detectDevice, .diskMode(let info)) where info.isFAT32:
            // Disco detectado y en el formato correcto: no hace falta
            // pasar por DFU si el usuario solo quiere reinstalar sobre
            // un Aura ya presente -- pero instalar el bootloader por
            // primera vez SI requiere DFU, asi que igual lo guiamos.
            step = .enterDFU
        case (.enterDFU, .dfuMode):
            Task { await runInstallOrRestore() }
        default:
            break
        }
    }

    private func runInstallOrRestore() async {
        step = .installing
        lastError = nil
        do {
            progressMessage = "Verificando integridad de los archivos..."
            try BundledArtifacts.shared.verifyAll()

            guard let runner else {
                throw InstallerError.missingBundledArtifact("mks5lboot")
            }

            switch mode {
            case .install:
                progressMessage = "Instalando el bootloader de Aura..."
                let result = try runner.installBootloader(single: destroyOriginalFirmware)
                guard result.exitCode == 0 else {
                    throw InstallerError.processFailed(exitCode: result.exitCode, output: result.stdout + result.stderr)
                }
            case .restore:
                progressMessage = "Quitando el bootloader de Aura..."
                let result = try runner.uninstallBootloader()
                guard result.exitCode == 0 else {
                    throw InstallerError.processFailed(exitCode: result.exitCode, output: result.stdout + result.stderr)
                }
            }

            progressMessage = "Listo."
            step = .done
        } catch let error as InstallerError {
            lastError = error
            step = .failed
        } catch {
            lastError = .processFailed(exitCode: -1, output: error.localizedDescription)
            step = .failed
        }
    }

    func retry() {
        lastError = nil
        step = .detectDevice
    }
}
