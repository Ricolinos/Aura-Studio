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
    @Published private(set) var step: InstallerStep = .welcome {
        didSet {
            // Fin de flujo (exito, falla, o entrega a Finder): los
            // agentes AMP pausados se reactivan aqui, en el punto unico
            // por el que pasan todos los caminos -- ya NO al
            // desaparecer la vista (D-187: la vista desaparece con
            // solo navegar a otra seccion, y eso reactivaba los
            // agentes a mitad de una instalacion en curso).
            if step == .done || step == .failed || step == .restoreHandoff {
                Task { await AMPAgentsGuard.shared.resumeIfNeeded() }
            }
        }
    }
    @Published private(set) var mode: InstallerMode = .install
    /// Modo elegido en el selector (nil = selector visible). Vive en el
    /// ViewModel y no como @State de la vista para que navegar a otra
    /// seccion y volver retome el asistente donde iba (D-187).
    @Published var chosenMode: InstallerMode? {
        didSet { InstallerFlowRegistry.shared.flowActive = (chosenMode != nil) }
    }
    @Published private(set) var progressMessage: String = ""
    @Published private(set) var lastError: InstallerError?
    /// ST-050: SIEMPRE true en una instalacion nueva. El paso "Modo de
    /// arranque" (dual boot vs Solo Aura) se quito: el dual boot solo
    /// funciona con un iPod en formato "winpod", y un iPod restaurado
    /// desde Mac -- el caso de este proyecto -- no lo es; el dueño lo
    /// confirmo en hardware. Sigue existiendo como variable porque
    /// `startAutomaticUpdate()` lo pone en false cuando el iPod YA esta
    /// en dual boot funcional (instalado desde Windows): actualizar no
    /// debe destruir un arranque de Apple que si sirve.
    @Published var destroyOriginalFirmware: Bool = true
    @Published var pendingAuthorization: PendingAuthorization?

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
    /// El doble formateo de restauracion (D-184) ya se disparo -- evita
    /// que cada evento de disco durante el proceso (el puente FAT
    /// monta, se borra, monta el HFS+...) vuelva a pedir autorizacion.
    private var restoreFormatStarted = false
    /// Cancelacion pedida por el usuario (D-188). Los trabajos en vuelo
    /// la observan en sus puntos seguros: la extraccion se termina de
    /// inmediato (se mata el proceso ditto), pero un comando de disco
    /// privilegiado en curso se deja TERMINAR y la cancelacion aplica
    /// justo despues -- matar un formateo a la mitad es exactamente el
    /// daño del que advierte el dialogo de confirmar.
    private var cancelRequested = false
    /// Proceso de extraccion en curso (ditto), para poder terminarlo si
    /// el usuario cancela.
    private var extractProcess: Process?
    /// Contador de archivos que `ditto -V` va confirmando por stderr
    /// durante la extraccion en curso -- fuente de la barra de progreso
    /// real (D-191). Vive fuera de `extractZip` para que el poller de
    /// `copyFirmwareFiles` lo lea mientras el proceso sigue corriendo.
    private var extractionProgressCounter: DittoProgressCounter?
    /// Un comando de disco privilegiado (formateo) esta corriendo ahora
    /// mismo -- la cancelacion espera a que termine.
    private var formatInFlight = false
    /// Progreso de la extraccion del arbol .rockbox (0...1), o nil
    /// mientras no haya una medicion util (la UI muestra spinner
    /// indeterminado). Se mide comparando el tamaño real escrito en el
    /// iPod contra el tamaño descomprimido del zip -- `ditto` no
    /// reporta progreso propio.
    @Published private(set) var copyProgress: Double?
    /// D-222 (encargo del dueño, 2026-08-14): "Actualizar" en General ya
    /// no debe mandar al selector Instalar/Restaurar -- con Aura YA
    /// instalado, reinstalar es sin DFU (ver `acknowledgeDeviceReady()`,
    /// `AuraDevice.canSkipBootloaderFlash`), así que alcanza con
    /// mostrar una barra de progreso automática, sin ningún paso manual.
    /// `InstallerHomeView` consulta esto para decidir si dibuja el
    /// selector/asistente normal o `AutomaticUpdateView`.
    @Published private(set) var isAutomaticUpdate = false
    /// ST-016: clave del ultimo disco visto montado (`DiskModeInfo.diskRecordKey`)
    /// -- se anota en `AppPreferences.bootloaderVerifiedDisks` cuando el
    /// flasheo por DFU termina bien (el aparato salio de DFU), y se borra
    /// al restaurar. Se captura en cada cambio de estado porque en el
    /// momento del flasheo el disco ya no esta montado.
    private var lastSeenDiskKey: String?
    /// ST-017 (Solo Aura): el flasheo va antes que la copia. `true` desde
    /// que se decide ese orden hasta que los archivos quedan copiados via
    /// "Bootloader USB mode".
    @Published private(set) var flashFirst = false
    /// ST-017: el bootloader se grabo EN ESTA CORRIDA (`--bl-inst` con
    /// exito y el aparato salio de DFU). Distinto de
    /// `bootloaderAlreadyInstalled` (evidencia previa, no verificada
    /// ahora): con esto `DoneView` no muestra la advertencia de "solo
    /// asumimos que el bootloader estaba".
    @Published private(set) var bootloaderFlashedThisFlow = false
    /// ST-017: el disco ya se formateo en esta corrida -- un reintento
    /// (p. ej. el DFU no aplico) no vuelve a pedir contraseña para
    /// formatear lo que ya esta listo.
    private var diskPreparedThisFlow = false

    /// ST-047: que familia se va a instalar en ESTE flujo. La fija
    /// `start(mode:)` a partir de la preferencia de Extras
    /// (`AppPreferences.firmwareFamilyToInstall`); `startAutomaticUpdate()`
    /// la sobreescribe con la familia DETECTADA en el iPod -- una
    /// actualizacion nunca cambia de firmware a nadie. Artefactos, runner
    /// (mks5lboot + bootloader), centinela del arbol y textos salen de
    /// aqui.
    @Published private(set) var targetFamily: FirmwareFamily = .aura

    var artifacts: BundledArtifacts { BundledArtifacts.forFamily(targetFamily) }

    /// Nombre para los textos del asistente ("Instalando Metro...").
    var targetName: String { targetFamily.displayName }

    init(monitor: IPodMonitor? = nil, executor: PrivilegedExecutor = PrivilegedExecutor()) {
        self.monitor = monitor ?? IPodMonitor()
        self.executor = executor
        self.runner = try? MKS5LBootRunner()
    }

    /// ST-047: cambia la familia objetivo y rehace el runner con los
    /// artefactos de esa familia. Solo tiene efecto fuera de un flujo en
    /// curso -- en medio de una instalacion seria cambiarle el bootloader
    /// a mitad de camino.
    func setTargetFamily(_ family: FirmwareFamily) {
        guard family.isInstallable else { return }
        targetFamily = family
        runner = try? MKS5LBootRunner(artifacts: BundledArtifacts.forFamily(family))
    }

    /// NO arranca ni detiene el monitor: desde que el `IPodMonitor` es
    /// compartido con toda la app (barra lateral, General, biblioteca),
    /// su ciclo de vida lo maneja `ContentView` -- el asistente solo lo
    /// observa. Antes cada `InstallerHomeView` creaba el suyo propio y
    /// habia dos sondeos DFU corriendo en paralelo.
    func start(mode: InstallerMode) {
        self.mode = mode
        self.lastError = nil
        // ST-047: la eleccion de Extras manda en una instalacion nueva.
        setTargetFamily(AppPreferences.shared.firmwareFamilyToInstall)
        isCopyingFirmware = false
        bootloaderAlreadyInstalled = false
        flashFirst = false
        bootloaderFlashedThisFlow = false
        diskPreparedThisFlow = false
        restoreFormatStarted = false
        cancelRequested = false
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
        // ST-050: sin paso de "Modo de arranque" -- instalar es siempre
        // Solo firmware (la Bienvenida ya exigio confirmar que el
        // arranque de Apple se borra).
        if mode == .install {
            destroyOriginalFirmware = true
        }
        step = .permissions
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
        chosenMode = nil
    }

    /// Cancela el flujo en curso (boton "Cancelar" de los pasos largos,
    /// D-188). La UI ya advirtio que detener a la mitad puede dejar el
    /// disco con errores; aqui se hace de la forma menos dañina: la
    /// copia se corta de inmediato (ditto es re-ejecutable sin drama),
    /// pero un comando de disco privilegiado en curso se deja terminar
    /// y la cancelacion aplica al regresar. Si no hay trabajo en vuelo
    /// (esperando autorizacion, esperando DFU, esperando el montaje),
    /// se cierra de una vez.
    func cancelFlow() {
        cancelRequested = true
        pendingAuthorization = nil
        if let process = extractProcess {
            // La extraccion se corta de inmediato; el catch de
            // copyFirmwareFiles observa la bandera y cierra limpio.
            process.terminate()
            return
        }
        if formatInFlight {
            // Un comando de disco privilegiado NO se mata a la mitad
            // (ese si es el daño real del que advierte el dialogo):
            // runFormatDisk / runRestoreFormat revisan la bandera al
            // terminar y cierran ahi.
            return
        }
        // Nada en vuelo (esperando autorizacion, DFU o montaje):
        // cerrar de una vez.
        finishCancel()
    }

    private func finishCancel() {
        cancelRequested = false
        isCopyingFirmware = false
        restoreFormatStarted = false
        bootloaderAlreadyInstalled = false
        flashFirst = false
        bootloaderFlashedThisFlow = false
        diskPreparedThisFlow = false
        copyProgress = nil
        lastError = nil
        chosenMode = nil
        isAutomaticUpdate = false
        step = .welcome
    }

    /// Punto de entrada del selector: fija el modo Y arranca el flujo
    /// en una sola operacion -- la vista ya no llama a start() desde
    /// onAppear, porque onAppear vuelve a dispararse cada vez que el
    /// usuario navega de regreso a la seccion y reiniciaria un
    /// asistente en curso (D-187).
    func beginFlow(mode: InstallerMode) {
        isAutomaticUpdate = false
        chosenMode = mode
        start(mode: mode)
    }

    /// D-222: cierra una actualización automática ya terminada (éxito o
    /// error) y deja el ViewModel listo para que, si el usuario vuelve
    /// a entrar a Instalador manualmente, encuentre el selector normal
    /// -- no la barra de progreso ni un error viejo.
    func dismissAutomaticUpdate() {
        isAutomaticUpdate = false
        chosenMode = nil
        lastError = nil
        copyProgress = nil
        step = .welcome
    }

    /// Arranque directo para la instalacion automatica desde el modo
    /// bootloader (D-183): salta Bienvenida/Modo de arranque/Permisos y
    /// va directo a confirmar el dispositivo con el estado que el
    /// monitor ya conoce. La unica interaccion que queda es la hoja de
    /// autorizacion + contraseña del formateo -- esa es la puerta de
    /// consentimiento real y no se salta nunca. Si mientras tanto el
    /// disco monto (el intento de montaje de D-182 lo logro), el mismo
    /// camino resuelve copiar sin formatear.
    func startAutoInstall() {
        start(mode: .install)
        step = .detectDevice
        acknowledgeDeviceReady()
    }

    /// D-222 (encargo del dueño): "al darle al botón de 'actualizar',
    /// en lugar de mandarnos a la sección de instalación... solo
    /// deberá aparecer una barra de progreso... deberá ser automática
    /// la instalación". Solo tiene sentido con Aura YA instalado (si no
    /// hay Aura, no hay "actualizar" -- `updateSection` de
    /// `DeviceGeneralView` ya solo se muestra en ese caso). Preserva el
    /// modo dual/solo que el dispositivo YA tiene (`device.isDualBoot`)
    /// en vez de volver a preguntarlo -- reutiliza exactamente el mismo
    /// camino sin-DFU que `acknowledgeDeviceReady()` ya tomaba para
    /// "Reinstalar Aura" manual (`bootloaderAlreadyInstalled`), solo
    /// que saltando el selector/asistente por completo, mismo patrón
    /// que `startAutoInstall()` (D-183) usa para el salto desde modo
    /// bootloader.
    func startAutomaticUpdate() {
        isAutomaticUpdate = true
        destroyOriginalFirmware = !(monitor.device?.isDualBoot ?? false)
        chosenMode = .install
        start(mode: .install)
        // ST-047: actualizar = la MISMA familia que ya esta en el iPod,
        // diga lo que diga la preferencia de Extras. Una familia
        // desconocida no llega aqui (General no ofrece el boton).
        if let detected = monitor.device?.declaredFamily, detected.isInstallable {
            setTargetFamily(detected)
        }
        step = .detectDevice
        acknowledgeDeviceReady()
    }

    func backFromPermissions() {
        step = .welcome
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
                // Ya en DFU al confirmar: se flashea primero y los
                // archivos se copian despues, cuando el bootloader
                // exponga el disco (ST-017) -- antes esto terminaba en
                // "Listo" sin haber copiado nada.
                flashFirst = !bootloaderFlashedThisFlow
                proceedToDFU()
            case .diskMode, .diskModeNoFilesystem:
                applyInstallPlan()
            default:
                break
            }
        }
    }

    /// Traduce el estado del monitor a la primera accion del instalador
    /// (`InstallPlanner`, puro y testeado) y la ejecuta.
    ///
    /// Saltar el DFU solo con EVIDENCIA de que un bootloader de la
    /// familia Rockbox ya esta grabado en la NOR -- que no es lo mismo
    /// que "hay archivos de Rockbox en el disco" (D-186, visto en
    /// hardware real: una extraccion interrumpida dejo un .rockbox
    /// parcial en un iPod cuya NOR era 100% de Apple; saltarse el DFU
    /// ahi produce una instalacion que jamas arranca). ST-016 endurece
    /// la regla (`AuraDevice.canSkipBootloaderFlash`): o el USB lo esta
    /// atendiendo Aura/Rockbox ahora mismo, o hay rastro de arranque en
    /// el disco Y ADEMAS registro local de haber verificado el bootloader
    /// en ese mismo disco. D-179 ("instalar sobre Rockbox no obliga a
    /// flashear") queda supeditado a esa evidencia.
    ///
    /// Sin volumen legible NO hay forma de saber que hay en la NOR: no se
    /// asume bootloader presente (el viejo supuesto de D-177 resulto
    /// falso en hardware). Con dual boot elegido, formatear es un
    /// callejon sin salida y hay que decirlo ANTES de borrar nada
    /// (D-185): el formateo reescribe el disco ENTERO con MBR/FAT32,
    /// destruyendo la particion de firmware donde vive el sistema de
    /// Apple -- exactamente lo que dual boot promete conservar; y un
    /// iPod restaurado desde Mac (particiones Apple/HFS+) tampoco sirve
    /// tal cual (Rockbox solo lee tablas MBR/GPT).
    private func applyInstallPlan() {
        let volumeIsFAT32: Bool?
        let volumeName: String
        switch monitor.state {
        case .diskMode(let info):
            volumeIsFAT32 = info.isFAT32
            volumeName = info.volumeName
        case .diskModeNoFilesystem:
            volumeIsFAT32 = nil
            volumeName = "iPod"
        default:
            return
        }

        let device = monitor.device
        let canSkip = device.map {
            $0.canSkipBootloaderFlash(diskRecordedAsVerified: AppPreferences.shared.isBootloaderVerified(diskKey: $0.diskRecordKey))
        } ?? false
        if canSkip { bootloaderAlreadyInstalled = true }

        let plan = InstallPlanner.plan(volumeIsFAT32: volumeIsFAT32,
                                       singleBoot: destroyOriginalFirmware,
                                       canSkipFlash: canSkip,
                                       deviceIsAura: device?.supportsAuraContract == true,
                                       bootloaderFlashedThisFlow: bootloaderFlashedThisFlow,
                                       diskPreparedThisFlow: diskPreparedThisFlow)
        if plan.flashFirst { flashFirst = true }

        switch plan.action {
        case .copyFiles:
            guard case .diskMode(let info) = monitor.state else { return }
            isCopyingFirmware = true
            Task { await copyFirmwareFiles(mountPath: info.mountPath) }
        case .enterDFU:
            proceedToDFU()
        case .formatThenFlash, .formatThenCopy:
            beginFormat(volumeName: volumeName)
        case .refuseDualBootRequiresWinpod:
            lastError = .dualBootRequiresWinpod
            step = .failed
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

    /// Boton de rescate en `DoneView` (D-273): la ruta rapida sin DFU
    /// (`bootloaderAlreadyInstalled`, ver `acknowledgeDeviceReady()`)
    /// solo tiene EVIDENCIA de que el bootloader de la familia Rockbox
    /// se grabo alguna vez en este iPod (aura.cfg/.rockbox en el disco)
    /// -- no puede confirmar que sigue ahi AHORA, porque la NOR no se
    /// puede leer desde modo disco. Caso real (dueño, hardware real):
    /// una instalacion previa de Aura dejo esa evidencia en el disco,
    /// pero el bootloader se perdio despues (ej. una restauracion desde
    /// iTunes que solo toca la particion de firmware) y el iPod volvio
    /// a arrancar con Apple por defecto -- la ruta rapida copio los
    /// archivos y reporto "Listo" sin haber arreglado lo que de verdad
    /// hacia falta. Este metodo le da al usuario una salida de un clic
    /// desde DoneView si nota que su iPod NO arranco con Aura: fuerza
    /// la misma ruta de DFU que se hubiera tomado si la evidencia nunca
    /// hubiera existido.
    func retryWithBootloaderFlash() {
        bootloaderAlreadyInstalled = false
        // `AutomaticUpdateView` no tiene el `.sheet(item:)` que muestra
        // la autorizacion de DFU (solo `InstallerWizardView` lo trae) --
        // pasar a la ruta manual para que la hoja de permiso y la guia
        // de DFU si aparezcan cuando este boton se toca desde ahi.
        isAutomaticUpdate = false
        proceedToDFU()
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
        case .restoreFormatDisk(let diskIdentifier):
            Task { await runRestoreFormat(diskIdentifier: diskIdentifier) }
        }
    }

    func cancelPendingAuthorization() {
        pendingAuthorization = nil
        // Pausar agentes AMP es una optimizacion, no un requisito: si
        // el usuario cancela, se sigue igual a esperar DFU. Formatear
        // el disco SI es un paso obligatorio de su etapa -- cancelarlo
        // aborta la instalacion/restauracion, dejando el iPod como
        // estaba en ese momento.
        if step == .preparingDisk || step == .restoreFormatting {
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
        // El ViewModel ahora vive toda la sesion (D-187) y start() se
        // llama una vez por flujo: sin esta limpieza, cada flujo
        // agregaria OTRA suscripcion y las reacciones se duplicarian.
        cancellables.removeAll()
        monitor.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.reactToDeviceState(state)
            }
            .store(in: &cancellables)
    }

    private func reactToDeviceState(_ state: DeviceState) {
        if case .diskMode(let info) = state, let key = info.diskRecordKey {
            lastSeenDiskKey = key
        }
        switch (step, state) {
        case (.copyingFiles, .diskMode(let info)) where !isCopyingFirmware && !cancelRequested:
            isCopyingFirmware = true
            Task { await copyFirmwareFiles(mountPath: info.mountPath) }
        case (.awaitingBootloaderUSB, .diskMode(let info)) where !isCopyingFirmware && !cancelRequested:
            // ST-017: el iPod reaparecio como disco tras el flasheo
            // `--single`. Si lo atiende el firmware de Apple, el
            // bootloader NO quedo grabado (con --single, Apple ya no
            // deberia arrancar) -- se dice, no se copia a ciegas.
            if info.usb?.runningFirmware == .apple {
                bootloaderFlashedThisFlow = false
                lastError = .bootloaderNotApplied
                step = .failed
                return
            }
            if info.isFAT32 {
                isCopyingFirmware = true
                step = .copyingFiles
                Task { await copyFirmwareFiles(mountPath: info.mountPath) }
            } else {
                // Llego a DFU sin pasar por el disco (p. ej. el usuario
                // ya estaba en DFU al empezar): preparar el disco ahora
                // que el bootloader lo expone; despues, la copia.
                beginFormat(volumeName: info.volumeName)
            }
        case (.awaitingBootloaderUSB, .diskModeNoFilesystem):
            beginFormat(volumeName: "iPod")
        case (.enterDFU, .dfuMode):
            Task { await runInstallOrRestore() }
        case (.restoreFormatting, .diskMode) where !restoreFormatStarted,
             (.restoreFormatting, .diskModeNoFilesystem) where !restoreFormatStarted:
            beginRestoreFormat()
        default:
            break
        }
    }

    /// El iPod reaparecio como disco tras quitar el bootloader:
    /// reidentificarlo y pedir autorizacion para el doble formateo de
    /// restauracion (D-184).
    private func beginRestoreFormat() {
        restoreFormatStarted = true
        let candidates = IPodDiskIdentifier.currentCandidates()
        switch IPodDiskIdentifier.identify(from: candidates) {
        case .found(let candidate):
            pendingAuthorization = .restoreFormatDisk(diskIdentifier: candidate.bsdName)
        case .notFound:
            lastError = .deviceNotFound
            step = .failed
        case .ambiguous(let matches):
            lastError = .diskAmbiguous(count: matches.count)
            step = .failed
        }
    }

    private func runRestoreFormat(diskIdentifier: String) async {
        do {
            let candidates = IPodDiskIdentifier.currentCandidates()
            guard case .found(let candidate) = IPodDiskIdentifier.identify(from: candidates),
                  candidate.bsdName == diskIdentifier else {
                throw InstallerError.deviceNotFound
            }
            progressMessage = "Formateando el disco (puente FAT y despues Mac OS Plus)..."
            formatInFlight = true
            defer { formatInFlight = false }
            try await executor.formatDiskForAppleRestore(candidate: candidate)
            if cancelRequested { finishCancel(); return }
            step = .restoreHandoff
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

    private func runInstallOrRestore() async {
        step = .installing
        lastError = nil
        do {
            progressMessage = "Verificando integridad de los archivos..."
            try artifacts.verifyAll()

            guard let runner else {
                throw InstallerError.missingBundledArtifact("mks5lboot")
            }

            switch mode {
            case .install:
                progressMessage = "Instalando el bootloader de \(targetName)..."
                let result = try runner.installBootloader(single: destroyOriginalFirmware)
                guard result.exitCode == 0 else {
                    throw InstallerError.processFailed(exitCode: result.exitCode, output: result.stdout + result.stderr)
                }
                // mks5lboot solo confirma que TERMINO DE ENVIAR los
                // datos por USB (`ipoddfu_send` en main.c devuelve
                // exito en cuanto el envio se completa) -- no espera a
                // que el aparato aplique el flasheo ni reinicie. Eso lo
                // confirma un tono de sonido en el propio iPod que la
                // app nunca escucha. Visto en hardware real (D-191):
                // "envio exitoso" con el aparato atascado en DFU, sin
                // aplicar nada -- Aura Studio decia "instalado" con el
                // iPod en pantalla negra. Se espera aca a que el
                // aparato realmente ABANDONE el modo DFU antes de
                // declarar exito.
                progressMessage = "Firmware enviado. Esperando a que el iPod confirme y reinicie..."
                guard await waitForDeviceToLeaveDFU(timeoutSeconds: 45) else {
                    throw InstallerError.deviceStuckInDFU
                }
                // ST-016: el bootloader quedo grabado en este iPod --
                // anotar el disco para que la proxima reinstalacion
                // pueda saltarse el DFU con fundamento (la NOR no se
                // puede releer; este registro es lo que lo sustituye).
                AppPreferences.shared.recordBootloaderVerified(diskKey: lastSeenDiskKey)
                bootloaderFlashedThisFlow = true
                if flashFirst {
                    // ST-017 (Solo Aura): el arranque ya esta grabado;
                    // faltan los archivos. El iPod se reinicia solo,
                    // no encuentra rockbox.ipod y su bootloader entra a
                    // "Bootloader USB mode" -- se espera ese disco.
                    progressMessage = "Arranque grabado. Esperando a que el iPod reaparezca como disco..."
                    step = .awaitingBootloaderUSB
                    // Si el disco ya monto mientras se salia de DFU, el
                    // evento ya paso -- reaccionar ahora.
                    reactToDeviceState(monitor.state)
                } else {
                    progressMessage = "Listo."
                    step = .done
                }

            case .restore:
                progressMessage = "Quitando el bootloader de \(targetName)..."
                let result = try runner.uninstallBootloader()
                guard result.exitCode == 0 else {
                    throw InstallerError.processFailed(exitCode: result.exitCode, output: result.stdout + result.stderr)
                }
                // Misma verificacion que en install (arriba): el exito
                // de mks5lboot solo confirma el envio por USB, no que
                // el aparato aplico el cambio y reinicio.
                progressMessage = "Firmware enviado. Esperando a que el iPod confirme y reinicie..."
                guard await waitForDeviceToLeaveDFU(timeoutSeconds: 45) else {
                    throw InstallerError.deviceStuckInDFU
                }
                // ST-016: ya no hay bootloader de Aura en la NOR -- el
                // registro local deja de ser cierto.
                AppPreferences.shared.forgetBootloaderVerified(diskKey: lastSeenDiskKey)
                // El bootloader de Apple quedo restaurado en la NOR,
                // pero la restauracion COMPLETA la termina Finder
                // (D-184): falta preparar el disco (doble formateo) y
                // entregarle el aparato.
                progressMessage = "Bootloader eliminado. Esperando a que el iPod reaparezca como disco... Si no aparece solo, mantén SELECT + PLAY al encenderlo para entrar a modo disco."
                step = .restoreFormatting
            }
        } catch let error as InstallerError {
            lastError = error
            step = .failed
        } catch {
            lastError = .processFailed(exitCode: -1, output: error.localizedDescription)
            step = .failed
        }
    }

    /// `true` en cuanto `mks5lboot --dfuscan` deja de ver el aparato en
    /// DFU (senal de que empezo a aplicar el flasheo y reiniciar);
    /// `false` si sigue detectandose DFU tras `timeoutSeconds` (D-191).
    /// Un respiro inicial antes del primer chequeo: el aparato tarda un
    /// instante en empezar a procesar apenas termina el envio USB.
    private func waitForDeviceToLeaveDFU(timeoutSeconds: Int) async -> Bool {
        guard let runner else { return false }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            if (try? runner.scanDFU()) == nil {
                return true
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return false
    }

    private func runFormatDisk(volumeName: String, diskIdentifier: String) async {
        do {
            let candidates = IPodDiskIdentifier.currentCandidates()
            guard case .found(let candidate) = IPodDiskIdentifier.identify(from: candidates),
                  candidate.bsdName == diskIdentifier else {
                throw InstallerError.deviceNotFound
            }
            progressMessage = "Formateando el disco..."
            formatInFlight = true
            defer { formatInFlight = false }
            try await executor.eraseAndFormatDisk(candidate: candidate, volumeName: volumeName)
            if cancelRequested { finishCancel(); return }
            diskPreparedThisFlow = true
            if flashFirst && !bootloaderFlashedThisFlow {
                // ST-017 (Solo Aura): disco listo -- ahora el flasheo.
                // La copia va despues, cuando el iPod reaparezca en
                // "Bootloader USB mode".
                progressMessage = "Disco listo. Ahora hace falta grabar el arranque por DFU."
                proceedToDFU()
                return
            }
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
        // Candado GLOBAL entre instancias (D-185): dos ViewModels
        // extrayendo el arbol a la vez sobre el mismo volumen producen
        // los "File exists" de ditto en carrera. Si otro flujo ya esta
        // escribiendo, este se retira sin tocar nada.
        guard InstallerFlowRegistry.shared.beginWriting() else {
            isCopyingFirmware = false
            return
        }
        defer { InstallerFlowRegistry.shared.endWriting() }
        do {
            guard let firmwareURL = artifacts.url(for: .firmware) else {
                throw InstallerError.missingBundledArtifact(BundledArtifacts.Name.firmware.rawValue)
            }
            guard let treeURL = artifacts.url(for: .rockboxTree) else {
                throw InstallerError.missingBundledArtifact(BundledArtifacts.Name.rockboxTree.rawValue)
            }
            step = .copyingFiles
            // En el camino de recuperacion (sin DFU) este es el unico
            // punto que escribe en el iPod -- la verificacion de
            // integridad no puede quedar solo en runInstallOrRestore().
            progressMessage = "Verificando integridad de los archivos..."
            try artifacts.verifyAll()
            progressMessage = "Copiando el firmware al iPod..."

            let destination = URL(fileURLWithPath: mountPath).appendingPathComponent("rockbox.ipod")
            let fm = FileManager.default
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: firmwareURL, to: destination)

            // ST-047: CAMBIO de familia (habia Metro y se instala Aura, o
            // al reves): el `aura.cfg` que dejo el firmware anterior no le
            // sirve al nuevo (sus ajustes son de otro programa) y ademas
            // engañaria a la deteccion de Studio hasta el primer arranque
            // -- Aura encontraria un `firmware_family: metro` que no es
            // suyo y Studio lo seguiria llamando Metro. Se borra SOLO en
            // ese caso; reinstalar la misma familia conserva los ajustes,
            // como siempre prometio este instalador.
            if let detected = monitor.device?.declaredFamily,
               monitor.device?.supportsAuraContract == true,
               detected != targetFamily {
                let staleCfg = URL(fileURLWithPath: mountPath)
                    .appendingPathComponent(".rockbox/aura/aura.cfg")
                try? fm.removeItem(at: staleCfg)
            }

            guard fm.fileExists(atPath: destination.path) else {
                throw InstallerError.processFailed(exitCode: -1, output: "no se pudo verificar rockbox.ipod tras copiarlo")
            }

            progressMessage = "Instalando \(targetName) en el iPod (tipografías, iconos, códecs)... Puede tardar varios minutos por USB -- no desconectes el iPod."

            // Barra de progreso real (D-191): se cuentan los archivos
            // que `ditto -V` va confirmando por stderr A MEDIDA que
            // ocurren, no los bytes escritos. Con 7800+ archivos
            // chicos, cada uno cuesta casi lo mismo en tiempo (una ida
            // y vuelta USB) sin importar su tamaño -- medir bytes hacia
            // que la barra llegara a 99% en los primeros segundos (los
            // archivos grandes se copian rapido) y despues se quedara
            // quieta varios minutos mientras ditto seguia escribiendo
            // miles de archivos chicos uno por uno, dando la impresion
            // de que el programa se colgo (reportado por el dueño en
            // hardware real). Contar archivos copiados sigue el ritmo
            // real del trabajo restante.
            let expectedFiles = (try? await Self.zipEntryCount(of: treeURL)) ?? 0
            let poller: Task<Void, Never>? = expectedFiles > 0 ? Task { [weak self] in
                while !Task.isCancelled {
                    if let copied = self?.extractionProgressCounter?.snapshotFilesCopied() {
                        let fraction = min(0.99, Double(copied) / Double(expectedFiles))
                        self?.copyProgress = fraction
                    }
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
            } : nil

            // Un solo reintento automatico (D-189): ditto hace merge,
            // asi que repetirlo tras una falla transitoria es seguro y
            // retoma justo donde quedo. Si el volumen ya no responde en
            // absoluto, reintentar es inutil -- eso se reporta como
            // desconexion real, no como error generico.
            var lastExtractError: Error?
            for attempt in 1...2 {
                do {
                    try await extractZip(at: treeURL, to: mountPath)
                    lastExtractError = nil
                    break
                } catch {
                    if cancelRequested { break }
                    lastExtractError = error
                    let stillReachable = FileManager.default.fileExists(atPath: mountPath)
                    if !stillReachable || attempt == 2 { break }
                    progressMessage = "La copia se interrumpió -- reintentando..."
                }
            }

            if cancelRequested {
                poller?.cancel()
                copyProgress = nil
                finishCancel()
                return
            }
            if let lastExtractError {
                poller?.cancel()
                copyProgress = nil
                if !FileManager.default.fileExists(atPath: mountPath) {
                    throw InstallerError.deviceDisconnectedDuringCopy
                }
                throw lastExtractError
            }
            poller?.cancel()
            copyProgress = 1

            // Centinela: una fuente que el firmware carga al arrancar --
            // si esta, el arbol se extrajo bien. Por familia (ST-047):
            // cada una trae sus propias fuentes.
            let sentinel = URL(fileURLWithPath: mountPath)
                .appendingPathComponent(targetFamily.installedTreeSentinel ?? ".rockbox/rockbox.ipod")
            guard fm.fileExists(atPath: sentinel.path) else {
                throw InstallerError.processFailed(exitCode: -1, output: "el árbol .rockbox no quedó completo tras extraerlo (falta \(sentinel.lastPathComponent))")
            }

            // D-194: crear de una vez las carpetas de medios -- reporte
            // del dueño en hardware real: podia copiar musica/fotos/
            // video al iPod en modo disco (Finder los ve bien), pero el
            // firmware no los reconocia. La carpeta correcta ya existia
            // como convencion (PHOTOS_DIR "/Photos"/VIDEOS_DIR "/Videos"
            // en aura_photos.c/aura_video.c, y LibrarySync ya escribe
            // exactamente estos cuatro nombres) pero nunca se creaba de
            // antemano -- si el usuario arrastraba archivos sueltos a la
            // raiz del disco en vez de adivinar el nombre exacto de una
            // carpeta que ni existia, el firmware nunca los encontraba.
            // Crearlas ahora, vacias, hace el destino obvio en Finder.
            for folder in ["Music", "Photos", "Videos", "Playlists"] {
                try? fm.createDirectory(at: URL(fileURLWithPath: mountPath).appendingPathComponent(folder, isDirectory: true),
                                         withIntermediateDirectories: true)
            }

            // Encargo 2026-08-18: siembra la hora/zona del Mac en
            // aura.cfg desde la instalación misma -- así el primer
            // arranque ya trae el reloj correcto (ver
            // ClockSyncWriter/CONTRATO-firmware-studio.md §D.4), sin
            // esperar a una reconexión posterior con el firmware ya
            // corriendo. El candado de escritura ya está tomado por esta
            // misma función (línea ~799).
            try? ClockSyncWriter.writeToDisk(mountPath: mountPath)

            if bootloaderAlreadyInstalled || bootloaderFlashedThisFlow {
                // El iPod llego aca desde el "Bootloader USB mode" de
                // Aura (o el flasheo ya se hizo en esta misma corrida,
                // ST-017): la NOR ya tiene el bootloader grabado, y el
                // DFU solo reescribiria byte a byte lo mismo. Con los
                // archivos copiados no queda nada por hacer -- expulsar
                // el disco para que el bootloader (que sigue esperando
                // en su modo USB) suelte el volumen y pueda reiniciar a
                // Aura.
                progressMessage = "Listo."
                _ = await monitor.unmountCurrentDisk()
                flashFirst = false
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
    /// memoria y hace merge sobre lo existente en vez de borrar). El
    /// subproceso corre solo (run() no bloquea) y se espera su
    /// terminacion -- la UI sigue viva mostrando el progreso. Metodo de
    /// instancia (no static) para exponer el proceso en
    /// `extractProcess`: es lo que permite que Cancelar lo termine de
    /// inmediato (D-188).
    private func extractZip(at zipURL: URL, to destinationPath: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        // -V (no solo -v): una linea por archivo copiado a stderr, en
        // vivo -- es lo que alimenta la barra de progreso real (D-191,
        // ver `extractionProgressCounter`).
        process.arguments = ["-xkV", zipURL.path, destinationPath]
        let errPipe = Pipe()
        process.standardError = errPipe

        let counter = DittoProgressCounter()
        extractionProgressCounter = counter
        extractProcess = process
        defer {
            extractProcess = nil
            extractionProgressCounter = nil
        }

        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            counter.consume(data)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { finished in
                errPipe.fileHandleForReading.readabilityHandler = nil
                if finished.terminationStatus == 0 {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: InstallerError.processFailed(
                        exitCode: finished.terminationStatus,
                        output: "ditto: \(counter.recentOutput())"))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Cantidad de archivos dentro del zip, leyendo la linea de resumen
    /// de `unzip -l` ("48485954   7831 files"). 0 si no se pudo medir
    /// -- la UI cae al spinner indeterminado, nunca a una barra
    /// inventada.
    private nonisolated static func zipEntryCount(of zipURL: URL) async throws -> Int64 {
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
            if fields.count >= 2, fields.last == "files", let count = Int64(fields[fields.count - 2]) {
                return count
            }
        }
        return 0
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
        // ST-017: `flashFirst`, `diskPreparedThisFlow` y
        // `bootloaderFlashedThisFlow` describen lo que YA paso en esta
        // corrida y se conservan a proposito -- un reintento retoma
        // desde donde quedo (no vuelve a formatear ni a flashear lo que
        // ya esta hecho).
        step = .detectDevice
    }

    /// Atajo desde la pantalla de "necesita winpod" (D-190): cambia a
    /// Solo Aura y reintenta de una, sin que el usuario tenga que
    /// volver atras manualmente por Modo de arranque. Solo tiene
    /// sentido llegando desde ese error especifico -- en cualquier otra
    /// falla, `retry()` normal es lo correcto.
    func switchToSingleBootAndRetry() {
        destroyOriginalFirmware = true
        retry()
    }
}

/// Cuenta en vivo las lineas "copying file ..." que `ditto -V` escribe
/// a stderr, una por archivo copiado (D-191) -- es la fuente de la
/// barra de progreso real durante la extraccion. `readabilityHandler`
/// de `FileHandle` llama desde una cola en segundo plano, y el poller
/// de `copyFirmwareFiles` lee desde el actor principal; el candado
/// evita la carrera entre ambos. Los datos pueden llegar en cualquier
/// tamaño de trozo (no una linea completa por callback), asi que se
/// bufferean hasta encontrar cada salto de linea.
private final class DittoProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var filesCopied = 0
    private var recentLines: [String] = []

    func consume(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newlineIndex]
            buffer.removeSubrange(buffer.startIndex...newlineIndex)
            guard let line = String(data: lineData, encoding: .utf8), !line.isEmpty else { continue }
            if line.hasPrefix("copying file ") {
                filesCopied += 1
            }
            recentLines.append(line)
            if recentLines.count > 15 { recentLines.removeFirst() }
        }
    }

    func snapshotFilesCopied() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return filesCopied
    }

    /// Ultimas lineas vistas -- contexto para el mensaje de error si
    /// ditto termina con un codigo distinto de cero.
    func recentOutput() -> String {
        lock.lock()
        defer { lock.unlock() }
        return recentLines.joined(separator: "\n")
    }
}
