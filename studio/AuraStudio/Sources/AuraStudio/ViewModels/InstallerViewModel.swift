import Foundation
import Combine

/// Orquesta el asistente completo: detectar el iPod, guiarlo a modo
/// DFU, instalar (o desinstalar, en modo restore) el bootloader Aura,
/// reconectar en modo Bootloader USB, preparar el disco si hace falta,
/// copiar los archivos del firmware, y verificar el resultado -- todo
/// dentro de la app, sin que el usuario toque una Terminal. Las
/// operaciones que necesitan privilegios de administrador (pausar
/// agentes de macOS, formatear el disco) pasan por `PendingAuthorization`
/// + `PrivilegedActionSheet`, que siempre explica antes de pedir la
/// contraseña.
@MainActor
final class InstallerViewModel: ObservableObject {
    @Published private(set) var step: InstallerStep = .welcome
    @Published private(set) var mode: InstallerMode = .install
    @Published private(set) var progressMessage: String = ""
    @Published private(set) var lastError: InstallerError?
    @Published var destroyOriginalFirmware: Bool = false
    @Published var pendingAuthorization: PendingAuthorization?

    let monitor: IPodMonitor
    private var cancellables: Set<AnyCancellable> = []
    private var runner: MKS5LBootRunner?
    private let executor: PrivilegedExecutor
    private var ampAgentsPaused = false

    init(monitor: IPodMonitor? = nil, executor: PrivilegedExecutor = PrivilegedExecutor()) {
        self.monitor = monitor ?? IPodMonitor()
        self.executor = executor
        self.runner = try? MKS5LBootRunner()
    }

    func start(mode: InstallerMode) {
        self.mode = mode
        self.lastError = nil
        step = .welcome
        monitor.start()
        observeDeviceState()
    }

    /// Se llama SIEMPRE al salir del asistente, haya terminado bien o
    /// mal -- la garantia de "los agentes AMP se reactivan pase lo que
    /// pase" no depende solo de esto (el watchdog en el propio script
    /// privilegiado es la red de seguridad real ante un crash), pero
    /// en el camino normal esto los reactiva de inmediato en vez de
    /// esperar el timeout del watchdog.
    func stop() {
        monitor.stop()
        cancellables.removeAll()
        if ampAgentsPaused {
            Task { try? await executor.resumeAMPAgents() }
            ampAgentsPaused = false
        }
    }

    func advanceFromWelcome() {
        step = .permissions
    }

    func advanceFromPermissions() {
        step = .detectDevice
    }

    /// El usuario confirma que ya combino los botones para entrar a
    /// modo DFU; a partir de aca `observeDeviceState()` hace avanzar
    /// la pantalla sola apenas `IPodMonitor` confirma el estado DFU
    /// real. Antes de eso, ofrece pausar los agentes AMP (D-041/D-044):
    /// no probado como necesario en el hardware de esta sesion, pero
    /// es una interferencia real documentada en otras Mac, y es
    /// barata/reversible.
    func acknowledgeEnteringDFU() {
        pendingAuthorization = .pauseAMPAgents()
    }

    /// El usuario confirma la explicacion del sheet -> ahora si se
    /// dispara el dialogo nativo de contraseña de macOS.
    func confirmPendingAuthorization() {
        guard let pending = pendingAuthorization else { return }
        pendingAuthorization = nil

        switch pending.kind {
        case .pauseAMPAgents:
            Task { await runPauseAMPAgents() }
        case .formatDisk(let volumeName, let diskIdentifier):
            Task { await runFormatDisk(volumeName: volumeName, diskIdentifier: diskIdentifier) }
        }
    }

    func cancelPendingAuthorization() {
        pendingAuthorization = nil
        // Pausar agentes AMP es una optimizacion, no un requisito: si
        // el usuario cancela, se sigue igual a esperar DFU. Formatear
        // el disco SI es un paso obligatorio de su etapa -- cancelarlo
        // aborta la instalacion, dejando el iPod sin ningun cambio.
        if step == .preparingDisk {
            lastError = .authorizationCancelled
            step = .failed
        } else {
            step = .enterDFU
        }
    }

    private func runPauseAMPAgents() async {
        do {
            try await executor.pauseAMPAgents()
            ampAgentsPaused = true
        } catch PrivilegedExecutor.ExecutorError.userCancelled {
            // No bloqueante: seguimos a esperar DFU igual.
        } catch {
            // Tampoco bloqueante -- si pausar los agentes falla por
            // cualquier otra razon, la deteccion DFU se intenta lo
            // mismo (puede funcionar bien sin este paso, como paso en
            // el hardware real de esta sesion).
        }
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
            step = .enterDFU
        case (.enterDFU, .dfuMode):
            Task { await runInstallOrRestore() }
        case (.bootloaderUSBMode, .diskMode(let info)):
            Task { await proceedAfterBootloaderUSBMode(info) }
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
                progressMessage = "Bootloader instalado. Reconectá el iPod en modo Bootloader USB."
                step = .bootloaderUSBMode

            case .restore:
                progressMessage = "Quitando el bootloader de Aura..."
                let result = try runner.uninstallBootloader()
                guard result.exitCode == 0 else {
                    throw InstallerError.processFailed(exitCode: result.exitCode, output: result.stdout + result.stderr)
                }
                progressMessage = "Listo."
                step = .done
            }
        } catch let error as InstallerError {
            lastError = error
            step = .failed
        } catch {
            lastError = .processFailed(exitCode: -1, output: error.localizedDescription)
            step = .failed
        }
    }

    /// Con el disco ya montado en modo Bootloader USB: si ya esta en
    /// FAT32 (el caso mas comun -- cualquier iPod que ya tuvo Rockbox,
    /// o que ya venia en FAT32 de fabrica), salta directo a copiar los
    /// archivos. Si no, pide autorizacion para formatearlo primero.
    private func proceedAfterBootloaderUSBMode(_ info: DiskModeInfo) async {
        if info.isFAT32 {
            await copyFirmwareFiles(mountPath: info.mountPath)
            return
        }

        let candidates = IPodDiskIdentifier.currentCandidates()
        switch IPodDiskIdentifier.identify(from: candidates) {
        case .found(let candidate):
            step = .preparingDisk
            pendingAuthorization = .formatDisk(volumeName: info.volumeName, diskIdentifier: candidate.bsdName)
        case .notFound:
            lastError = .deviceNotFound
            step = .failed
        case .ambiguous(let matches):
            lastError = .diskAmbiguous(count: matches.count)
            step = .failed
        }
    }

    private func runFormatDisk(volumeName: String, diskIdentifier: String) async {
        do {
            let candidates = IPodDiskIdentifier.currentCandidates()
            guard case .found(let candidate) = IPodDiskIdentifier.identify(from: candidates),
                  candidate.bsdName == diskIdentifier else {
                throw InstallerError.deviceNotFound
            }
            progressMessage = "Formateando el disco..."
            try await executor.eraseAndFormatDisk(candidate: candidate, volumeName: volumeName)
            progressMessage = "Disco listo. Copiando archivos..."

            // Tras formatear, el volumen se vuelve a montar con el
            // mismo nombre -- se espera a que IPodMonitor lo confirme
            // en vez de asumir la ruta de montaje.
            step = .copyingFiles
        } catch PrivilegedExecutor.ExecutorError.userCancelled {
            lastError = .authorizationCancelled
            step = .failed
        } catch let error as PrivilegedExecutor.ExecutorError {
            lastError = .privilegedOperationFailed(error.localizedDescription)
            step = .failed
        } catch let error as InstallerError {
            lastError = error
            step = .failed
        } catch {
            lastError = .privilegedOperationFailed(error.localizedDescription)
            step = .failed
        }
    }

    /// Copia lo que la app trae embebido (ver `BundledArtifacts`) al
    /// volumen del iPod. NOTA de alcance (ver D-045 en DECISIONS.md):
    /// hoy Aura Studio solo embebe `rockbox.ipod` suelto, no el arbol
    /// `.rockbox/` completo (fuentes, codecs, temas, plugins) que un
    /// `make install` real genera -- eso es un gap conocido, pendiente
    /// de una fase futura, no algo que este cambio resuelve.
    private func copyFirmwareFiles(mountPath: String) async {
        do {
            guard let firmwareURL = BundledArtifacts.shared.url(for: .firmware) else {
                throw InstallerError.missingBundledArtifact(BundledArtifacts.Name.firmware.rawValue)
            }
            step = .copyingFiles
            progressMessage = "Copiando el firmware al iPod..."

            let destination = URL(fileURLWithPath: mountPath).appendingPathComponent("rockbox.ipod")
            let fm = FileManager.default
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: firmwareURL, to: destination)

            guard fm.fileExists(atPath: destination.path) else {
                throw InstallerError.processFailed(exitCode: -1, output: "no se pudo verificar rockbox.ipod tras copiarlo")
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
