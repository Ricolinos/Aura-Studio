import Foundation
import Combine

/// Orquesta el asistente completo: detectar el iPod (modo disco normal,
/// corriendo su firmware original -- todavia no hace falta DFU),
/// preparar el disco si hace falta (formatear a FAT32) y copiar los
/// archivos del firmware, y recien al final guiarlo a modo DFU para
/// flashear (o quitar, en modo restore) el bootloader de Aura -- todo
/// dentro de la app, sin que el usuario toque una Terminal. El disco de
/// datos y el bootloader del iPod 6G viven en soportes fisicos
/// distintos (particion FAT32 vs. NOR flash interna), asi que no hace
/// falta esperar a DFU/bootloader para tocar el disco -- ese orden es
/// el que se verifico a mano en hardware real. Las operaciones que
/// necesitan privilegios de administrador (pausar agentes de macOS,
/// formatear el disco) pasan por `PendingAuthorization` +
/// `PrivilegedActionSheet`, que siempre explica antes de pedir la
/// contraseña.
@MainActor
final class InstallerViewModel: ObservableObject {
    @Published private(set) var step: InstallerStep = .welcome
    @Published private(set) var mode: InstallerMode = .install
    @Published private(set) var progressMessage: String = ""
    @Published private(set) var lastError: InstallerError?
    @Published var destroyOriginalFirmware: Bool = false
    @Published var pendingAuthorization: PendingAuthorization?

    /// Vuelve al selector de Instalar/Restaurar -- lo fija `InstallerHomeView`.
    /// Vive como closure (no como parte de la maquina de estados) porque
    /// esa eleccion pasa por fuera del asistente en si.
    var onExitToModePicker: (() -> Void)?

    let monitor: IPodMonitor
    private var cancellables: Set<AnyCancellable> = []
    private var runner: MKS5LBootRunner?
    private let executor: PrivilegedExecutor
    /// Evita que un segundo evento de `DiskArbitrationMonitor` (p.ej. el
    /// disco remontando dos veces seguidas tras `newfs_msdos`) dispare
    /// `copyFirmwareFiles` por duplicado mientras la primera copia
    /// todavia esta en curso.
    private var isCopyingFirmware = false

    init(monitor: IPodMonitor? = nil, executor: PrivilegedExecutor = PrivilegedExecutor()) {
        self.monitor = monitor ?? IPodMonitor()
        self.executor = executor
        self.runner = try? MKS5LBootRunner()
    }

    func start(mode: InstallerMode) {
        self.mode = mode
        self.lastError = nil
        isCopyingFirmware = false
        step = .welcome
        monitor.start()
        observeDeviceState()
    }

    /// Se llama SIEMPRE al salir del asistente, haya terminado bien o
    /// mal -- la garantia de "los agentes AMP se reactivan pase lo que
    /// pase" no depende solo de esto (el watchdog en el propio script
    /// privilegiado es la red de seguridad real ante un crash, y
    /// `AppDelegate.applicationShouldTerminate` bloquea el cierre de la
    /// app entera hasta que `AMPAgentsGuard` confirma la reactivacion
    /// si el usuario cierra con Cmd+Q en vez de navegar dentro del
    /// asistente), pero en el camino normal esto los reactiva de
    /// inmediato en vez de esperar cualquiera de esas dos redes de
    /// seguridad.
    func stop() {
        monitor.stop()
        cancellables.removeAll()
        Task { await AMPAgentsGuard.shared.resumeIfNeeded() }
    }

    func advanceFromWelcome() {
        switch mode {
        case .install:
            step = .chooseBootMode
        case .restore:
            step = .permissions
        }
    }

    /// El usuario ya eligio si conservar el firmware de Apple (dual
    /// boot, default seguro) o reemplazarlo por completo -- se guarda
    /// en `destroyOriginalFirmware`, que `runInstallOrRestore()` le pasa
    /// tal cual a `mks5lboot --bl-inst` (con o sin `--single`).
    func advanceFromBootMode(dualBoot: Bool) {
        destroyOriginalFirmware = !dualBoot
        step = .permissions
    }

    func backFromBootMode() {
        step = .welcome
    }

    func advanceFromPermissions() {
        step = .detectDevice
    }

    // MARK: - Volver atras
    //
    // Solo se ofrece antes de que arranque cualquier escritura real
    // (instalar/formatear/copiar) -- una vez que el bootloader ya se
    // esta flasheando, "volver" no tiene forma segura de deshacer nada,
    // asi que esos pasos no tienen boton de atras.

    func backFromWelcome() {
        monitor.stop()
        onExitToModePicker?()
    }

    func backFromPermissions() {
        step = mode == .install ? .chooseBootMode : .welcome
    }

    func backFromDetectDevice() {
        step = .permissions
    }

    /// Si ya se habian pausado los agentes AMP al entrar a este paso,
    /// los reactiva de una -- no tiene sentido dejarlos pausados si el
    /// usuario decide no seguir con la instalacion todavia.
    func backFromEnterDFU() {
        Task { await AMPAgentsGuard.shared.resumeIfNeeded() }
        step = .detectDevice
    }

    /// El usuario confirma que el iPod ya esta conectado y montado en
    /// modo disco normal (todavia con su firmware original, sin tocar
    /// DFU). En modo restore no hay nada que tocar del disco -- se va
    /// directo a preparar la entrada a DFU. En modo install, si el
    /// disco no esta en FAT32 pide formatearlo primero; si ya lo esta,
    /// copia los archivos del firmware directo.
    ///
    /// Casos de borde reales:
    /// - Volviendo "Atras" desde la guia de DFU si el iPod ya habia
    ///   entrado a ese modo: si el estado ya es `.dfuMode` en vez de
    ///   `.diskMode`, no hay disco que tocar -- se salta directo a la
    ///   autorizacion de DFU en vez de quedar en un boton que no hace
    ///   nada.
    /// - `.diskModeNoFilesystem`: el disco no tiene NINGUN volumen
    ///   montable (bootloader ya instalado pero la particion de datos
    ///   quedo invalida por una instalacion interrumpida, o un disco en
    ///   blanco de fabrica) -- mismo flujo de formateo que "no esta en
    ///   FAT32", solo que partiendo de un `DiskCandidateInfo` en vez de
    ///   un `DiskModeInfo` porque no hay volumen del que sacar uno.
    func acknowledgeDeviceReady() {
        switch mode {
        case .restore:
            proceedToDFU()
        case .install:
            switch monitor.state {
            case .dfuMode:
                proceedToDFU()
            case .diskMode(let info) where info.isFAT32:
                isCopyingFirmware = true
                Task { await copyFirmwareFiles(mountPath: info.mountPath) }
            case .diskMode(let info):
                beginFormat(volumeName: info.volumeName)
            case .diskModeNoFilesystem:
                beginFormat(volumeName: "iPod")
            default:
                break
            }
        }
    }

    /// Reidentifica el disco en el momento mismo de pedir autorizacion
    /// (nunca confia en un `bsdName` que pudo haber quedado desactualizado
    /// mientras el usuario miraba la pantalla) y arma el pedido de
    /// formateo. `volumeName` es el nombre a mostrarle al usuario en la
    /// hoja de autorizacion -- "iPod" generico cuando no hay un volumen
    /// montado del que sacar uno real.
    private func beginFormat(volumeName: String) {
        let candidates = IPodDiskIdentifier.currentCandidates()
        switch IPodDiskIdentifier.identify(from: candidates) {
        case .found(let candidate):
            step = .preparingDisk
            pendingAuthorization = .formatDisk(volumeName: volumeName, diskIdentifier: candidate.bsdName)
        case .notFound:
            lastError = .deviceNotFound
            step = .failed
        case .ambiguous(let matches):
            lastError = .diskAmbiguous(count: matches.count)
            step = .failed
        }
    }

    /// Disco (en modo install) ya preparado con los archivos del
    /// firmware copiados, o modo restore que nunca tocaba el disco:
    /// ofrece pausar los agentes AMP (D-041/D-044, no probado como
    /// necesario en el hardware de esta sesion, pero es una
    /// interferencia real documentada en otras Mac, y es
    /// barata/reversible) antes de mostrar la guia de DFU.
    /// `observeDeviceState()` hace avanzar la pantalla sola apenas
    /// `IPodMonitor` confirma el estado DFU real.
    private func proceedToDFU() {
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
            AMPAgentsGuard.shared.markPaused()
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
        case (.copyingFiles, .diskMode(let info)) where !isCopyingFirmware:
            isCopyingFirmware = true
            Task { await copyFirmwareFiles(mountPath: info.mountPath) }
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
                progressMessage = "Listo."
                step = .done

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

            progressMessage = "Archivos copiados. Ahora hace falta flashear el arranque por DFU."
            proceedToDFU()
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
        isCopyingFirmware = false
        step = .detectDevice
    }
}
