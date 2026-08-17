import SwiftUI

/// Raiz de la app. Estructura de barra lateral estilo Finder: cuando
/// conectas el iPod, el Finder no te muestra "pestañas de la app" sino
/// las secciones DEL DISPOSITIVO (General, Musica, Video, Fotos...), y
/// Aura Studio hace lo mismo. La deteccion es automatica: `IPodMonitor`
/// avisa cuando aparece el volumen y `AuraDeviceProbe` mira que firmware
/// tiene, asi que el usuario nunca elige nada a mano.
///
/// Las secciones de contenido siguen disponibles sin dispositivo: armar
/// la biblioteca es util offline y despues se sincroniza. Lo que cambia
/// sin iPod es lo que muestra General y que el boton de sincronizar
/// quede deshabilitado.
struct ContentView: View {
    @StateObject private var deviceMonitor: IPodMonitor
    /// El ViewModel del instalador vive AQUI y no dentro de
    /// `InstallerHomeView` (D-187): la vista del instalador se destruye
    /// cada vez que el usuario navega a otra seccion de la barra
    /// lateral, y con ella moria todo el estado del asistente -- al
    /// volver, la instalacion en curso "desaparecia" de la pantalla
    /// (aunque sus tareas seguian corriendo por detras, sin UI). Con el
    /// estado en el contenedor raiz, navegar y volver retoma la
    /// pantalla exacta donde iba.
    @StateObject private var installer: InstallerViewModel
    @StateObject private var library = LibraryViewModel()
    @StateObject private var preferences = AppPreferences.shared
    @State private var selection: SidebarSection? = .general

    init() {
        let monitor = IPodMonitor()
        _deviceMonitor = StateObject(wrappedValue: monitor)
        _installer = StateObject(wrappedValue: InstallerViewModel(monitor: monitor))
    }
    /// El firmware embebido en la app difiere del instalado en el iPod
    /// conectado (hash) -- alimenta el aviso de "Actualizar Aura" en
    /// General. Se recalcula al conectar/desconectar.
    @State private var updateAvailable = false
    /// Ya se navego automaticamente al Instalador por esta deteccion de
    /// disco ilegible -- no volver a saltar hasta que el estado cambie
    /// (el usuario debe poder irse a otra seccion sin que la app lo
    /// regrese a la fuerza).
    @State private var autoNavigatedToInstaller = false
    /// Spinner del boton "Actualizar" mientras `refreshNow()` corre.
    @State private var isRefreshing = false

    /// La biblioteca (Musica/Video/Fotos/Extras) se bloquea cuando hay
    /// un iPod conectado cuyo firmware NO es Aura: sincronizar contra el
    /// firmware original de Apple o un Rockbox ajeno no haria nada util
    /// y confunde (encargo del dueño, 2026-08-13). SIN dispositivo la
    /// biblioteca sigue abierta a proposito -- armarla offline es un
    /// caso de uso real, se sincroniza al conectar.
    private var libraryLocked: Bool {
        guard let device = deviceMonitor.device else { return false }
        return !device.isAura
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection,
                        device: deviceMonitor.device,
                        libraryLocked: libraryLocked)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detail
        }
        .tint(AuraColors.light.accent)
        .toolbar {
            // PLAN-general-sync.md §1.1: "Actualizar" (refresco
            // inofensivo, NUNCA escribe en el iPod) reemplaza al viejo
            // boton "Sincronizar" de la barra de herramientas -- la
            // sincronizacion real ahora vive en General, junto a la
            // barra de actividad (D-202 pedia poder dispararla tambien
            // desde Musica/Video/Fotos; eso lo cubre el comando de menu
            // ⇧⌘S y "Sincronizar la selección" del menu contextual).
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await refreshNow() }
                } label: {
                    if isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Actualizar", systemImage: "arrow.clockwise")
                    }
                }
                .help("Vuelve a leer el estado del iPod y de tu biblioteca. No copia ni borra nada.")
                .disabled(isRefreshing)
            }
        }
        .focusedSceneValue(\.auraSyncCommand, SyncCommandContext(
            canSync: (deviceMonitor.device?.isAura ?? false) && !library.isProcessing && library.syncProgress == nil,
            action: { Task { await syncNow() } }
        ))
        .onAppear { deviceMonitor.start() }
        .onDisappear { deviceMonitor.stop() }
        .onChange(of: deviceMonitor.state) { newState in
            switch newState {
            case .diskModeNoFilesystem:
                // Disco ilegible detectado: navegar a la seccion
                // Instalador -- SIN tomar la pantalla ni ocultar la
                // barra lateral (encargo del dueño, D-188: la toma de
                // pantalla completa de D-183 queda retirada mientras la
                // deteccion no sea 100% confiable) y sin arrancar nada
                // solo: el usuario decide. Una sola vez por deteccion,
                // y nunca encima de un flujo ya activo (D-185).
                if !autoNavigatedToInstaller
                    && !InstallerFlowRegistry.shared.flowActive {
                    autoNavigatedToInstaller = true
                    selection = .installer
                }
            case .diskMode, .notConnected:
                autoNavigatedToInstaller = false
            default:
                break
            }
        }
        .onChange(of: libraryLocked) { locked in
            // Si la seccion activa quedo bloqueada (p.ej. se conecto un
            // iPod con firmware original mientras se miraba Musica), la
            // seleccion salta a General en vez de quedarse en una vista
            // que ya no aplica. `.musicPlaylists` no esta en
            // `deviceSections` (se renderiza anidada, no como fila de
            // primer nivel -- ver SidebarView), pero debe bloquearse
            // igual que el resto de Música.
            if locked, let current = selection,
               current != .general,
               SidebarSection.deviceSections.contains(current) || current == .musicPlaylists {
                selection = .general
            }
        }
        .onChange(of: deviceMonitor.device) { newDevice in
            refreshUpdateAvailability(for: newDevice)
        }
    }

    private func refreshUpdateAvailability(for device: AuraDevice?) {
        guard let device, device.isAura else {
            updateAvailable = false
            return
        }
        Task {
            updateAvailable = await AuraUpdateChecker.checkForUpdate(deviceMountPath: device.mountPath)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .general {
        case .general:
            DeviceGeneralView(device: deviceMonitor.device,
                              state: deviceMonitor.state,
                              library: library,
                              onEject: { await deviceMonitor.unmountCurrentDisk() },
                              onUpdateAura: {
                                  // D-222: "Actualizar" ya no manda al
                                  // selector Instalar/Restaurar --
                                  // dispara la actualizacion automatica
                                  // (sin DFU, sin preguntar el modo de
                                  // nuevo) y navega directo a la barra
                                  // de progreso.
                                  installer.startAutomaticUpdate()
                                  selection = .installer
                              },
                              updateAvailable: updateAvailable,
                              onCheckForUpdates: { refreshUpdateAvailability(for: deviceMonitor.device) },
                              onRefreshDevice: { deviceMonitor.refreshDevice() })
        case .music:
            MediaSectionView(kind: .music, viewModel: library, device: deviceMonitor.device, preferences: preferences)
        case .musicPlaylists:
            // D-228: "Listas" ahora se llega directo desde la barra
            // lateral, anidada bajo "Música" -- "onDismiss" vuelve a
            // Música (mismo destino al que apuntaba el boton "Listo" de
            // adentro de PlaylistsView cuando vivia como hoja/toggle).
            PlaylistsView(viewModel: library) { selection = .music }
        case .video:
            MediaSectionView(kind: .video, viewModel: library, device: deviceMonitor.device, preferences: preferences)
        case .photos:
            MediaSectionView(kind: .photo, viewModel: library, device: deviceMonitor.device, preferences: preferences)
        case .extras:
            ExtrasView(device: deviceMonitor.device)
        case .installer:
            InstallerHomeView(monitor: deviceMonitor, viewModel: installer)
        case .settings:
            SettingsSectionView(preferences: preferences)
        }
    }

    /// El disparador REAL de sincronizacion (PLAN-general-sync.md §1.1)
    /// -- lo usa el comando de menu `Archivo → Sincronizar con el iPod`
    /// (⇧⌘S, via `auraSyncCommand`); el boton visible del dia a dia
    /// vive en General, junto a `DeviceActivityBar`, con la misma
    /// logica (ver `DeviceGeneralView.onSync`). Siempre alcance
    /// completo -- el menu no tiene forma de saber que hay seleccionado
    /// en Musica/Video/Fotos en este instante.
    private func syncNow() async {
        guard let device = deviceMonitor.device else { return }
        await library.sync(toVolumeAt: URL(fileURLWithPath: device.mountPath), scope: .all)
        // El disco no se desmonto, asi que DiskArbitration no va a
        // notificar nada -- hay que releer el resumen a mano.
        deviceMonitor.refreshDevice()
    }

    /// "Actualizar" (PLAN-general-sync.md §1.1): refresco inofensivo,
    /// nunca escribe en el iPod -- vuelve a sondear el dispositivo
    /// montado y consulta si hay firmware nuevo. Separado a proposito
    /// de `refreshUpdateAvailability` (que es fire-and-forget, pensado
    /// para el `.onChange(of: device)` automatico): aca se espera el
    /// resultado para que el spinner del boton dure lo que dura de
    /// verdad la consulta.
    private func refreshNow() async {
        isRefreshing = true
        defer { isRefreshing = false }
        guard let device = deviceMonitor.device else { return }
        deviceMonitor.refreshDevice()
        updateAvailable = await AuraUpdateChecker.checkForUpdate(deviceMountPath: device.mountPath)
    }
}

// MARK: - Comando de menu "Sincronizar con el iPod" (⇧⌘S)

/// PLAN-general-sync.md §1.1: D-202 puso el boton de sync en la barra
/// de herramientas para que se pudiera disparar desde Musica/Video/
/// Fotos sin ir a General -- ahora que esa barra es "Actualizar" (nunca
/// escribe), ese acceso rapido se cubre con un comando de menu real en
/// vez de duplicar el boton. `FocusedValue` porque el estado
/// (`deviceMonitor`/`library`) vive dentro de `ContentView`, no en
/// `AuraStudioApp` (D-187: el estado del instalador tambien vive en la
/// raiz por la misma razon -- una sola fuente de verdad que sobrevive a
/// la navegacion).
struct SyncCommandContext {
    let canSync: Bool
    let action: () -> Void
}

private struct AuraSyncCommandKey: FocusedValueKey {
    typealias Value = SyncCommandContext
}

extension FocusedValues {
    var auraSyncCommand: SyncCommandContext? {
        get { self[AuraSyncCommandKey.self] }
        set { self[AuraSyncCommandKey.self] = newValue }
    }
}

/// Vive en el menu Archivo (`AuraStudioApp.commands`). Deshabilitado
/// sin un iPod Aura conectado, o mientras ya hay un sync/proceso de
/// biblioteca en curso -- nunca dispara una segunda sincronizacion
/// encima de otra.
struct SyncMenuCommand: View {
    @FocusedValue(\.auraSyncCommand) private var context

    var body: some View {
        Button("Sincronizar con el iPod") {
            context?.action()
        }
        .keyboardShortcut("s", modifiers: [.command, .shift])
        .disabled(context?.canSync != true)
    }
}

enum SidebarSection: Hashable, CaseIterable {
    case general
    case music
    /// D-228: "Listas" (playlists), anidada bajo "Música" en la barra
    /// lateral -- antes solo se llegaba con un boton dentro de
    /// `MediaSectionView`. NO forma parte de `deviceSections` (ese
    /// array arma las filas de PRIMER NIVEL de la lista; esta se
    /// renderiza aparte, anidada, ver `SidebarView.body`), pero SI debe
    /// bloquearse junto con el resto cuando `libraryLocked` -- ver el
    /// chequeo explicito en `ContentView.body`.
    case musicPlaylists
    case video
    case photos
    case extras
    case installer
    case settings

    var title: String {
        switch self {
        case .general:        return S.general.text
        case .music:          return S.music.text
        case .musicPlaylists: return S.playlists.text
        case .video:          return S.video.text
        case .photos:         return S.photos.text
        case .extras:         return S.extras.text
        case .installer:      return S.installer.text
        case .settings:       return S.settings.text
        }
    }

    /// SF Symbols en variante lineal (docs/design/Reglas de diseno
    /// Apple2026 (v2).md SS4: "siempre la variante lineal, nunca
    /// .fill" -- una barra de navegacion es exactamente el caso de uso
    /// que esa regla describe, sea en el firmware o en Studio). `video`
    /// y `settings` usan los simbolos canonicos del propio documento
    /// (`play.rectangle` = Videos, `gear` = Configuracion); `extras`
    /// toma `square.grid.2x2`, tambien canonico ahi, en vez del
    /// generico `puzzlepiece.extension.fill` que tenia antes.
    /// `musicPlaylists` toma `music.note.list`, mismo simbolo que ya
    /// usaba el boton "Playlists" que reemplaza (`MediaSectionView`).
    var symbol: String {
        switch self {
        case .general:        return "info.circle"
        case .music:          return "music.note"
        case .musicPlaylists: return "music.note.list"
        case .video:          return "play.rectangle"
        case .photos:         return "photo"
        case .extras:         return "square.grid.2x2"
        case .installer:      return "square.and.arrow.down"
        case .settings:       return "gear"
        }
    }

    static let deviceSections: [SidebarSection] = [.general, .music, .video, .photos, .extras]
    static let appSections: [SidebarSection] = [.installer, .settings]
}

private struct SidebarView: View {
    @Binding var selection: SidebarSection?
    let device: AuraDevice?
    let libraryLocked: Bool
    /// D-228: "Listas" nace expandida -- tiene que ser facil de
    /// encontrar, no un submenu escondido por default.
    @State private var musicExpanded = true

    var body: some View {
        List(selection: $selection) {
            Section(header: deviceHeader) {
                ForEach(SidebarSection.deviceSections, id: \.self) { section in
                    if section == .music {
                        // "Música" se puede abrir/cerrar SIN cambiar la
                        // seleccion (el `DisclosureGroup` solo expande),
                        // pero tocar el label de "Música" en si sigue
                        // seleccionando `.music` directo -- son dos
                        // gestos independientes gracias al `.tag()`
                        // propio en el label Y en la fila anidada.
                        DisclosureGroup(isExpanded: $musicExpanded) {
                            Label(SidebarSection.musicPlaylists.title, systemImage: SidebarSection.musicPlaylists.symbol)
                                .tag(SidebarSection.musicPlaylists)
                                .disabled(libraryLocked)
                        } label: {
                            Label(section.title, systemImage: section.symbol)
                                .tag(section)
                                .disabled(libraryLocked && section != .general)
                        }
                    } else {
                        Label(section.title, systemImage: section.symbol)
                            .tag(section)
                            // General queda siempre accesible: es donde se
                            // explica QUE firmware hay y que hacer con el.
                            .disabled(libraryLocked && section != .general)
                    }
                }
            }
            Section("Aura Studio") {
                ForEach(SidebarSection.appSections, id: \.self) { section in
                    Label(section.title, systemImage: section.symbol).tag(section)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var deviceHeader: some View {
        HStack(spacing: 6) {
            /* "ipod.slash" no existe en SF Symbols (verificado contra el
             * catalogo real, no supuesto) -- mismo simbolo que ya usa
             * DeviceGeneralView para "sin dispositivo". */
            Image(systemName: device == nil ? "cable.connector.slash" : "ipod")
            Text(device?.volumeName ?? S.noDevice.text)
                .lineLimit(1)
        }
    }
}
