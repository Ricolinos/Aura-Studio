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
    /// El flujo arranco desde `.diskModeNoFilesystem`, es decir el iPod
    /// ya esta corriendo el bootloader de Aura (su "Bootloader USB
    /// mode"): la NOR ya tiene lo que el paso de DFU iria a escribir.
    /// En ese caso, despues de formatear y copiar los archivos NO se
    /// pide DFU de nuevo -- se termina ahi. Pedirle al usuario repetir
    /// la combinacion de botones para reflashear byte a byte lo mismo
    /// que ya esta grabado es friccion pura (encargo del dueño,
    /// 2026-08-13, probando la recuperacion D-175/D-176 en vivo).
    @Published private(set) var bootloaderAlreadyInstalled = false
    /// Progreso de la extraccion del arbol .rockbox (0...1), o nil
    /// mientras no haya una medicion util (la UI muestra spinner
    /// indeterminado). Se mide comparando el tamaño real escrito en el
    /// iPod contra el tamaño descomprimido del zip -- `ditto` no
    /// reporta progreso propio.
    @Published private(set) var copyProgress: Double?

    init(monitor: IPodMonitor? = nil, executor: PrivilegedExecutor = PrivilegedExecutor()) {
        self.monitor = monitor ?? IPodMonitor()
        self.executor = executor
        self.runner = try? MKS5LBootRunner()
    }

    /// NO arranca ni detiene el monitor: desde que el `IPodMonitor` es
    /// compartido con toda la app (barra lateral, General, biblioteca),
    /// su ciclo de vida lo maneja `ContentView` -- el asistente solo lo
    /// observa. Antes cada `InstallerHomeView` creaba el suyo propio y
    /// habia dos sondeos DFU corriendo en paralelo.
    func start(mode: InstallerMode) {
        self.mode = mode
        self.lastError = nil
        isCopyingFirmware = false
        bootloaderAlreadyInstalled = false
        copyProgress = nil
        step = .welcome
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
                // Si el disco ya tiene Aura o un Rockbox comun, el
                // bootloader de la familia Rockbox ya esta grabado en la
                // NOR (asi llego ese arbol al disco) y arranca
                // /.rockbox/rockbox.ipod sin importar cual de los dos
                // arboles haya: instalar Aura es solo reemplazar la
                // carpeta, sin DFU (encargo del dueño: "no nos obligaria
                // a flashear el dispositivo").
                if monitor.device?.isRockboxFamily == true {
                    bootloaderAlreadyInstalled = true
                }
                isCopyingFirmware = true
                Task { await copyFirmwareFiles(mountPath: info.mountPath) }
            case .diskMode(let info):
                beginFormat(volumeName: info.volumeName)
            case .diskModeNoFilesystem:
                bootloaderAlreadyInstalled = true
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
            // mismo nombre. Dos caminos cubren la carrera (D-182): si
            // el montaje ya ocurrio MIENTRAS el paso seguia en
            // "preparando disco" (el evento llego y no habia nada
            // esperandolo), monitor.state ya es .diskMode y la copia
            // arranca aqui mismo; si todavia no monta, el paso queda en
            // .copyingFiles y reactToDeviceState() la arranca cuando
            // DiskArbitration confirme el montaje.
            step = .copyingFiles
            if case .diskMode(let info) = monitor.state, !isCopyingFirmware {
                isCopyingFirmware = true
                Task { await copyFirmwareFiles(mountPath: info.mountPath) }
            }
        } catch PrivilegedExecutor.ExecutorError.userCancelled {
            lastError = .authorizationCancelled
            step = .failed
        } catch PrivilegedExecutor.ExecutorError.fullDiskAccessRequired {
            lastError = .fullDiskAccessDenied
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
    /// volumen del iPod: `rockbox.ipod` suelto en la raiz (lo que el
    /// bootloader arranca) y el arbol `.rockbox/` completo extraido del
    /// zip embebido (fuentes a26, iconos/mascaras, codecs, plugins --
    /// D-045 cerrado en D-178: sin ese arbol el firmware arrancaba pero
    /// sin tipografias SF ni iconos, confirmado en hardware real). La
    /// extraccion es un merge (ditto no borra lo que ya este): un
    /// reinstalar encima NO pierde `aura.cfg` ni el cache de caratulas.
    private func copyFirmwareFiles(mountPath: String) async {
        do {
            guard let firmwareURL = BundledArtifacts.shared.url(for: .firmware) else {
                throw InstallerError.missingBundledArtifact(BundledArtifacts.Name.firmware.rawValue)
            }
            guard let treeURL = BundledArtifacts.shared.url(for: .rockboxTree) else {
                throw InstallerError.missingBundledArtifact(BundledArtifacts.Name.rockboxTree.rawValue)
            }
            step = .copyingFiles
            // En el camino de recuperacion (sin DFU) este es el unico
            // punto que escribe en el iPod -- la verificacion de
            // integridad no puede quedar solo en runInstallOrRestore().
            progressMessage = "Verificando integridad de los archivos..."
            try BundledArtifacts.shared.verifyAll()
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

            progressMessage = "Instalando Aura en el iPod (tipografías, iconos, códecs)... Esto toma unos minutos. No desconectes el iPod."

            // Barra de progreso real: ditto no reporta avance, asi que
            // se mide cuanto ya quedo escrito en el iPod contra el
            // tamaño total descomprimido del zip, cada ~1s.
            let expectedBytes = (try? await Self.zipUncompressedByteCount(of: treeURL)) ?? 0
            let treeDestPath = URL(fileURLWithPath: mountPath)
                .appendingPathComponent(".rockbox").path
            let poller: Task<Void, Never>? = expectedBytes > 0 ? Task { [weak self] in
                while !Task.isCancelled {
                    let written = await Self.directorySize(atPath: treeDestPath)
                    let fraction = min(0.99, Double(written) / Double(expectedBytes))
                    self?.copyProgress = fraction
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            } : nil

            do {
                try await Self.extractZip(at: treeURL, to: mountPath)
            } catch {
                poller?.cancel()
                copyProgress = nil
                throw error
            }
            poller?.cancel()
            copyProgress = 1

            // Centinela: una fuente del design system que el firmware
            // carga al arrancar -- si esta, el arbol se extrajo bien.
            let sentinel = URL(fileURLWithPath: mountPath)
                .appendingPathComponent(".rockbox/fonts/a26-title-20.fnt")
            guard fm.fileExists(atPath: sentinel.path) else {
                throw InstallerError.processFailed(exitCode: -1, output: "el árbol .rockbox no quedó completo tras extraerlo (falta \(sentinel.lastPathComponent))")
            }

            if bootloaderAlreadyInstalled {
                // El iPod llego aca desde el "Bootloader USB mode" de
                // Aura: la NOR ya tiene el bootloader grabado, y el DFU
                // solo reescribiria byte a byte lo mismo. Con los
                // archivos copiados no queda nada por hacer -- expulsar
                // el disco para que el bootloader (que sigue esperando
                // en su modo USB) suelte el volumen y pueda reiniciar a
                // Aura.
                progressMessage = "Listo."
                _ = await monitor.unmountCurrentDisk()
                step = .done
            } else {
                progressMessage = "Archivos copiados. Ahora hace falta flashear el arranque por DFU."
                proceedToDFU()
            }
        } catch let error as InstallerError {
            lastError = error
            step = .failed
        } catch {
            lastError = .processFailed(exitCode: -1, output: error.localizedDescription)
            step = .failed
        }
    }

    /// Extrae el zip del arbol `.rockbox` sobre el volumen del iPod con
    /// `/usr/bin/ditto -xk` (herramienta del sistema, presente en todo
    /// macOS: maneja el zip de 7800+ archivos sin cargarlo entero en
    /// memoria y hace merge sobre lo existente en vez de borrar).
    /// `nonisolated` + subproceso: la extraccion tarda (decenas de MB a
    /// un disco USB 2.0) y no debe congelar la UI, que mientras tanto
    /// muestra el mensaje de progreso.
    private nonisolated static func extractZip(at zipURL: URL, to destinationPath: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", zipURL.path, destinationPath]
        let errPipe = Pipe()
        process.standardError = errPipe

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { finished in
                if finished.terminationStatus == 0 {
                    continuation.resume(returning: ())
                } else {
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let message = String(data: errData, encoding: .utf8) ?? ""
                    continuation.resume(throwing: InstallerError.processFailed(
                        exitCode: finished.terminationStatus,
                        output: "ditto: \(message)"))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Tamaño total descomprimido de un zip, leyendo la linea de
    /// resumen de `unzip -l` ("48485954   7831 files"). 0 si no se pudo
    /// medir -- la UI cae al spinner indeterminado, nunca a una barra
    /// inventada.
    private nonisolated static func zipUncompressedByteCount(of zipURL: URL) async throws -> Int64 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-l", zipURL.path]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        try process.run()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let text = String(data: data, encoding: .utf8) else { return 0 }
        for line in text.split(separator: "\n").reversed() {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            if fields.count >= 2, fields.last == "files", let total = Int64(fields[0]) {
                return total
            }
        }
        return 0
    }

    /// Suma el tamaño de todos los archivos bajo `path`. `nonisolated`:
    /// recorre 7800+ archivos en un volumen USB, jamas en el hilo de la
    /// UI.
    private nonisolated static func directorySize(atPath path: String) async -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: path) else { return 0 }
        var total: Int64 = 0
        while let relative = enumerator.nextObject() as? String {
            let attrs = try? fm.attributesOfItem(atPath: (path as NSString).appendingPathComponent(relative))
            total += (attrs?[.size] as? Int64) ?? 0
        }
        return total
    }

    func retry() {
        lastError = nil
        isCopyingFirmware = false
        copyProgress = nil
        // Se reevalua al volver a confirmar el dispositivo: si el iPod
        // ya no esta en "Bootloader USB mode" (p.ej. se reconecto otro
        // aparato), no debe quedar un salto de DFU heredado del intento
        // anterior.
        bootloaderAlreadyInstalled = false
        step = .detectDevice
    }
}
