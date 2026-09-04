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

    /// Por que el sondeo DFU no puede funcionar, cuando no puede
    /// (ST-029): `mks5lboot` ausente, sin bit de ejecucion, o un
    /// `Process` que no arranca. nil mientras el escaneo corre bien
    /// (encuentre o no un iPod). Las pantallas que esperan DFU lo
    /// muestran en vez de "Esperando modo DFU..." -- esperar algo que
    /// nunca va a llegar, sin decirlo, era el sintoma exacto reportado.
    @Published private(set) var dfuScannerProblem: String?

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
    /// Ticks consecutivos viendo el disco sin ningun volumen montado.
    /// Declarar "sin sistema de archivos" exige varios segundos de
    /// evidencia sostenida (D-188): al conectar el iPod, macOS tarda
    /// varios segundos en verificar (fsck) y montar un FAT32 de 125GB
    /// -- con solo 1s de gracia, esa ventana transitoria producia el
    /// falso "modo bootloader" que el dueño reporto dos veces.
    private var noFilesystemStreak = 0
    private static let noFilesystemStreakRequired = 5
    /// El usuario (o el instalador) EXPULSO el disco a proposito: no
    /// volver a intentarle un montaje ni declararlo "sin sistema de
    /// archivos" mientras siga fisicamente conectado -- acaba de
    /// decirsele que ya puede desconectar el cable, y remontarlo por
    /// detras convertiria ese aviso en mentira. Se limpia cuando el
    /// disco desaparece de verdad (se desconecto) o cuando un volumen
    /// vuelve a montar por otra via.
    private var ejectRequested = false

    init() {
        do {
            runner = try MKS5LBootRunner()
        } catch {
            runner = nil
            dfuScannerProblem = error.localizedDescription
        }
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
        ejectRequested = true
        return await withCheckedContinuation { continuation in
            diskMonitor.unmount { ok in
                continuation.resume(returning: ok)
            }
        }
    }

    private func handleDiskChange(_ info: DiskModeInfo?) {
        lastDiskInfo = info
        if let info {
            state = .diskMode(info)
            // ST-056 / contrato v10: un cambio de firmware que quedo a
            // medias (sin `/.rockbox/` pero con un arbol dormido) se
            // repara aqui, antes de sondear, para que el sondeo vea un
            // iPod sano. Nunca mientras un flujo de instalacion escribe.
            if !InstallerFlowRegistry.shared.flowActive, !info.mountPath.isEmpty, info.mountPath.hasPrefix("/") {
                let root = URL(fileURLWithPath: info.mountPath)
                _ = try? FirmwareSwitcher.repairIfNeeded(volumeRoot: root)
                // ST-061: un arbol activo sin los archivos del contrato
                // (instalacion fresca de otra familia) los hereda del
                // dormido, que si los tiene -- sin esto, Metro decia
                // "sin sincronizar todavia" y perdia fotos de artista y
                // categorias hasta el siguiente sync completo.
                _ = FirmwareSwitcher.seedContractFilesToActiveTree(volumeRoot: root)
            }
            let probed = AuraDeviceProbe.probe(diskInfo: info)
            device = probed
            // ST-016: ver este disco con Aura/Rockbox atendiendo el USB
            // es prueba de bootloader grabado -- se anota para que la
            // proxima reinstalacion (aunque llegue en modo disco de
            // Apple) pueda saltarse el DFU con fundamento.
            if let probed, probed.runningFirmware == .rockboxFamily {
                AppPreferences.shared.recordBootloaderVerified(diskKey: probed.diskRecordKey)
            }
            if let probed, probed.supportsAuraContract {
                syncClockIfNeeded(mountPath: probed.mountPath)
            }
            ejectRequested = false
            noFilesystemStreak = 0
        } else if case .diskMode = state {
            state = .notConnected
            device = nil
            mountAttempted.removeAll()
            noFilesystemStreak = 0
        }
    }

    /// Hora y zona horaria del Mac hacia `aura.cfg` (encargo 2026-08-18,
    /// ver `ClockSyncWriter`): en cada conexion con CUALQUIER familia
    /// corriendo (Aura, Metro, moonlit -- ST-146/maestro §B; las tres
    /// hablan el mismo contrato de `aura.cfg`, `supportsAuraContract` no
    /// distingue cual), para que el dueño nunca tenga que configurarlas a
    /// mano. Cede el candado sin quejarse si otro flujo (instalacion,
    /// sync) ya lo tiene -- el proximo connect lo vuelve a intentar.
    private func syncClockIfNeeded(mountPath: String) {
        guard InstallerFlowRegistry.shared.beginWriting() else { return }
        defer { InstallerFlowRegistry.shared.endWriting() }
        try? ClockSyncWriter.writeToDisk(mountPath: mountPath)
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
                if let dfu = self.scanDFUReportingProblems() {
                    self.state = .dfuMode(dfu)
                } else if case .found(let candidate) = IPodDiskIdentifier.identify(from: IPodDiskIdentifier.currentCandidates()) {
                    if self.ejectRequested {
                        // Expulsado a proposito: dejarlo en paz hasta
                        // que se desconecte fisicamente.
                    } else if !self.mountAttempted.contains(candidate.bsdName) {
                        // Primero intentar montar: si el disco tiene un
                        // sistema de archivos valido pero quedo
                        // desmontado, el montaje dispara el evento de
                        // DiskArbitration y el estado pasa a .diskMode
                        // solo -- sin formatear nada (D-182).
                        self.mountAttempted.insert(candidate.bsdName)
                        self.noFilesystemStreak = 0
                        Self.attemptMount(bsdName: candidate.bsdName)
                    } else {
                        // Evidencia sostenida antes de declarar el disco
                        // ilegible (D-188): el fsck + montaje de un
                        // FAT32 grande tarda varios segundos al
                        // conectar, y un solo tick sin volumen NO
                        // significa que no haya sistema de archivos.
                        self.noFilesystemStreak += 1
                        if self.noFilesystemStreak >= Self.noFilesystemStreakRequired {
                            self.state = .diskModeNoFilesystem(candidate)
                        }
                    }
                } else {
                    // Ni DFU ni disco: si habia una expulsion pedida,
                    // el aparato ya se desconecto de verdad -- limpiar
                    // para que una reconexion futura se procese normal.
                    self.ejectRequested = false
                    self.noFilesystemStreak = 0
                    switch self.state {
                    case .dfuMode, .diskModeNoFilesystem, .detecting:
                        self.state = .notConnected
                    default:
                        break
                    }
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    /// Un escaneo que termina (con o sin iPod) es un escaneo sano.
    /// Un escaneo que ni siquiera puede correr -- `Process.run()`
    /// tira, p. ej. "permission denied" por un binario sin bit de
    /// ejecucion (ST-029) -- se reporta en `dfuScannerProblem` en vez
    /// de confundirse con "no hay iPod en DFU".
    private func scanDFUReportingProblems() -> DFUModeInfo? {
        guard let runner else { return nil }
        do {
            let dfu = try runner.scanDFU()
            if dfuScannerProblem != nil { dfuScannerProblem = nil }
            return dfu
        } catch {
            let message = "No se pudo ejecutar la herramienta de detección DFU (mks5lboot): \(error.localizedDescription)"
            if dfuScannerProblem != message { dfuScannerProblem = message }
            return nil
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
