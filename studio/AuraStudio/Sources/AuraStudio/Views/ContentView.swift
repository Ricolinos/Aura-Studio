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
    /// PLAN-studio-rendimiento-2.md Fase 6 (ST-186): en `@State`, no en
    /// `@StateObject`.
    ///
    /// `@StateObject` suscribe a ESTA vista a todos los cambios del
    /// ViewModel, así que cualquier cambio de `items` -- una estrella,
    /// una importación, el relleno de tamaños en segundo plano --
    /// reevaluaba el `body` de la ventana entera: barra lateral, barra
    /// de herramientas, la sección visible y sus comandos de menú.
    /// `@State` sostiene la referencia con el mismo ciclo de vida y sin
    /// suscribir a nadie; quien de verdad necesita enterarse lo observa
    /// por su cuenta (las secciones ya lo hacen con `@ObservedObject`, y
    /// las dos piezas de acá abajo que sí dependen de él se movieron a
    /// vistas propias: `CoverNormalizationBarHost` y `SyncCommandRelay`).
    @State private var library = LibraryViewModel()
    @StateObject private var preferences = AppPreferences.shared
    /// PLAN-studio-rendimiento.md Fase 1: la selección de la biblioteca
    /// ya no vive en `library` (observado por toda esta vista) -- ver
    /// `SelectionStore`. Uno solo, compartido por las tres secciones de
    /// medios y sus vistas de grupo (Álbumes/Películas), igual que hacía
    /// `selectionForSync` antes.
    @StateObject private var selectionStore = SelectionStore()
    /// PLAN-studio-rendimiento-2.md Fase 1 (ST-181): a dónde publica la
    /// sección activa su resumen de barra de estado. Va en `@State` y no
    /// en `@StateObject` A PROPÓSITO: `@State` solo sostiene la
    /// referencia, sin suscribir a ESTA vista a sus cambios. Quien lo
    /// observa es `LibraryStatusBarHost`, la franja de 24 pt del pie
    /// (antes esto era un `onPreferenceChange` hacia un `@State` de acá,
    /// y cada clic costaba dos pasadas completas de `body` de toda la
    /// ventana -- diagnóstico §0.3).
    @State private var statusCenter = LibraryStatusCenter()
    /// ST-193: si hay una versión más nueva de Aura Studio. En `@State`
    /// y no en `@StateObject` por el mismo motivo que `statusCenter`:
    /// quien lo observa es la franja de 28 pt del pie
    /// (`AppUpdateBarHost`), no la ventana.
    @State private var appUpdates = AppUpdateChecker()
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
    /// ST-063: la hoja de "Elementos similares".
    @State private var showingSimilarItems = false
    /// ST-046: tag del Release mas nuevo conocido para la familia del
    /// firmware instalado, para poder nombrarlo en General.
    @State private var updateLatestTag: String?
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
        return !device.supportsAuraContract
    }

    var body: some View {
        #if DEBUG
        let _ = BodyEvaluationCounter.record("ContentView")
        #endif
        NavigationSplitView {
            SidebarView(selection: $selection,
                        device: deviceMonitor.device,
                        libraryLocked: libraryLocked,
                        onDropSelection: { category, ids in
                            library.setCategory(category, forItems: ids)
                        })
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            VStack(spacing: 0) {
                // ST-189: con el disco de la biblioteca desconectado, las
                // secciones que la necesitan lo DICEN en vez de mostrarse
                // vacías. La de abajo se sigue construyendo: al volver el
                // disco solo hay que dejar de taparla.
                LibraryAvailabilityGate(library: library,
                                        needsLibrary: (selection ?? .general).needsLibrary,
                                        libraryPath: preferences.libraryFolderPath,
                                        onChooseAnother: { chooseLibraryFolder() },
                                        onCreateNew: { createNewLibrary() }) {
                    detail
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                // ST-141: la migración única de carátulas, mientras
                // corre. Va ARRIBA de la barra de estado y no la
                // reemplaza: son dos cosas distintas (una resume la
                // sección, la otra informa un trabajo en curso que se
                // puede detener).
                CoverNormalizationBarHost(library: library)
                // ST-193: el aviso de versión nueva va ARRIBA de la
                // barra de estado, como la migración de carátulas, y por
                // el mismo motivo: son cosas distintas (una resume la
                // sección, la otra informa algo que pasó fuera).
                AppUpdateBarHost(checker: appUpdates)
                // ST-063: barra de estado estilo Finder, al pie de la
                // sección; "Visualización › Mostrar barra de estado" la
                // oculta. Solo aparece donde hay algo que resumir.
                if preferences.showStatusBar {
                    LibraryStatusBarHost(center: statusCenter)
                }
            }
        }
        .environment(\.libraryStatusCenter, statusCenter)
        // ST-193: el chequeo automático, una vez cada 24 h. Sale a la red
        // en segundo plano; sin red, calla.
        .onAppear { appUpdates.checkAutomaticallyIfDue() }
        // ST-188 (addendum): solo hace algo con AURA_UITEST_MAIN_SCREEN=1.
        .background(MainWindowPlacer())
        .background(AppUpdateCommandRelay(checker: appUpdates))
        .tint(AuraColors.light.accent)
        .toolbar {
            // PLAN-studio-rendimiento.md Fase 4 punto 4: centro de
            // tareas en segundo plano -- invisible sin nada corriendo.
            ToolbarItem(placement: .primaryAction) {
                BackgroundTaskCenterIndicator(center: library.taskCenter)
            }
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
        // ST-186: el estado de "se puede sincronizar" depende de
        // `library.isProcessing`/`syncProgress`, así que leerlo acá
        // volvería a suscribir toda la ventana. Lo publica una vista de
        // tamaño cero que sí observa.
        .background(SyncCommandRelay(
            library: library,
            canSyncDevice: deviceMonitor.device?.supportsAuraContract ?? false,
            action: { Task { await syncNow() } }))
        .focusedSceneValue(\.auraLibraryCommand, LibraryCommandContext(
            currentSection: selection ?? .general,
            navigate: { selection = $0 },
            addFiles: { addFilesFromOpenPanel() },
            showSimilarItems: { showingSimilarItems = true },
            revealLibraryFolder: { NSWorkspace.shared.activateFileViewerSelecting([library.libraryRoot]) }
        ))
        .sheet(isPresented: $showingSimilarItems) {
            SimilarItemsView(library: library, preferences: preferences,
                             initialKind: (selection ?? .general).libraryKind) {
                showingSimilarItems = false
            }
        }
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
               SidebarSection.deviceSections.contains(current) || current.isMusicSection
                || current.isVideoSection || current.isPhotosSection {
                selection = .general
            }
        }
        .onChange(of: deviceMonitor.device) { newDevice in
            refreshUpdateAvailability(for: newDevice)
            // PLAN-general-sync.md §4.2: "conexión" invalida el índice
            // de sincronización viejo. Sin dispositivo (o con firmware
            // no-Aura) no hay nada que verificar -- se limpia en vez de
            // dejar mostrando el estado de un iPod que ya no es este.
            if let newDevice, newDevice.supportsAuraContract {
                Task {
                    await ensureDeviceNameAssigned(for: newDevice)
                    await library.verifyDevice(at: URL(fileURLWithPath: newDevice.mountPath))
                }
            } else {
                library.clearDeviceSyncIndex()
            }
        }
    }

    /// §1.5/§9: la primera vez que Studio ve un iPod con Aura SIN
    /// nombre, le asigna el default y lo guarda de inmediato en el
    /// dispositivo -- así otra Mac que lo conecte después lo ve igual.
    /// Si ya tiene nombre, solo actualiza el reflejo local
    /// (`knownDeviceNames`) para la próxima vez que este iPod aparezca
    /// desconectado en otro contexto.
    private func ensureDeviceNameAssigned(for device: AuraDevice) async {
        if let identity = device.deviceIdentity {
            preferences.knownDeviceNames[identity.deviceID] = identity.deviceName
            return
        }
        // ST-013 (contrato v2 SS C bis): quien nombra primero es el
        // propietario del nombre -- solo esta instalacion podra cambiarlo.
        let identity = DeviceIdentity(deviceID: UUID().uuidString, deviceName: DeviceNameStore.defaultName(),
                                      updatedAt: Date(), ownerInstallationID: preferences.installationID)
        guard (try? DeviceNameStore.save(identity, volumeRoot: URL(fileURLWithPath: device.mountPath))) != nil else { return }
        preferences.knownDeviceNames[identity.deviceID] = identity.deviceName
        deviceMonitor.refreshDevice()
    }

    /// Edición in-place del nombre desde `DeviceGeneralView.header` --
    /// `newName` ya viene saneado (`DeviceNameStore.sanitize`, corrido
    /// en la propia vista para poder avisar de inmediato si se recortó
    /// algún emoji, sin esperar a este método asíncrono).
    private func renameDevice(_ device: AuraDevice, to newName: String) async {
        // ST-013: la UI ya no ofrece el campo si otra instalacion es la
        // propietaria; esta guarda es la red de seguridad. Un archivo v1
        // (sin propietario) se reclama en este guardado.
        if let current = device.deviceIdentity, !current.canRename(from: preferences.installationID) {
            library.lastError = "El nombre de este iPod se puso desde otra Mac; solo desde ahí se puede cambiar."
            return
        }
        let identity = DeviceIdentity(
            deviceID: device.deviceIdentity?.deviceID ?? UUID().uuidString,
            deviceName: newName,
            updatedAt: Date(),
            ownerInstallationID: device.deviceIdentity?.ownerInstallationID ?? preferences.installationID
        )
        guard (try? DeviceNameStore.save(identity, volumeRoot: URL(fileURLWithPath: device.mountPath))) != nil else {
            library.lastError = "No se pudo guardar el nombre en el iPod."
            return
        }
        preferences.knownDeviceNames[identity.deviceID] = identity.deviceName
        deviceMonitor.refreshDevice()
    }

    /// `forceRefresh`: `false` en el chequeo automatico (`.onChange(of:
    /// deviceMonitor.device)`, respeta la cache de 24h de
    /// `AuraUpdateChecker` a proposito -- evita pegarle a la API de
    /// GitHub en cada conexion del iPod); `true` cuando el usuario pide
    /// el chequeo EL MISMO explicitamente (boton "Buscar
    /// actualizaciones de Aura") -- ver nota de `forceRefresh` en
    /// `AuraUpdateChecker.checkForUpdate`.
    private func refreshUpdateAvailability(for device: AuraDevice?, forceRefresh: Bool = false) {
        guard let device, device.supportsAuraContract else {
            updateAvailable = false
            updateLatestTag = nil
            return
        }
        // ST-046: la familia decide a que repositorio se le pregunta. Antes
        // se le preguntaba siempre al de Aura, tambien con Metro instalado.
        let family = device.declaredFamily
        Task {
            updateAvailable = await AuraUpdateChecker.checkForUpdate(deviceMountPath: device.mountPath,
                                                                       family: family,
                                                                       forceRefresh: forceRefresh)
            updateLatestTag = AuraUpdateChecker.latestKnownTag(family: family)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .general {
        case .general:
            DeviceGeneralView(device: deviceMonitor.device,
                              state: deviceMonitor.state,
                              library: library,
                              selectionStore: selectionStore,
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
                              latestReleaseTag: updateLatestTag,
                              onCheckForUpdates: { refreshUpdateAvailability(for: deviceMonitor.device, forceRefresh: true) },
                              onRefreshDevice: { deviceMonitor.refreshDevice() },
                              onRenameDevice: { newName in
                                  guard let device = deviceMonitor.device else { return }
                                  Task { await renameDevice(device, to: newName) }
                              },
                              canRenameDevice: deviceMonitor.device?.deviceIdentity?.canRename(from: preferences.installationID) ?? true)
        case .music, .musicGroup:
            MediaSectionView(kind: .music, viewModel: library, device: deviceMonitor.device, preferences: preferences, selectionStore: selectionStore)
        case .musicArtists:
            // ST-031 / ST-032: Artistas con fotos de artista opcionales.
            ArtistsView(viewModel: library, device: deviceMonitor.device, preferences: preferences,
                        selectionStore: selectionStore,
                        onFetchArtistImages: { artists in
                            Task { await library.fetchArtistImages(for: artists) }
                        })
        case .musicAlbums:
            AlbumsView(viewModel: library, device: deviceMonitor.device, preferences: preferences, selectionStore: selectionStore)
        case .musicPlaylists:
            // D-228: "Listas" ahora se llega directo desde la barra
            // lateral, anidada bajo "Música" -- "onDismiss" vuelve a
            // Música (mismo destino al que apuntaba el boton "Listo" de
            // adentro de PlaylistsView cuando vivia como hoja/toggle).
            PlaylistsView(viewModel: library) { selection = .music }
        case .video, .videoGroup:
            MediaSectionView(kind: .video, viewModel: library, device: deviceMonitor.device, preferences: preferences, selectionStore: selectionStore)
        case .videoMovies:
            // Tanda 4 de PLAN-biblioteca-medios-v2.md: cuadrícula de
            // pósters en vez de la tabla plana (que sigue siendo lo que
            // usa Videoclips, abajo).
            MoviesView(viewModel: library, device: deviceMonitor.device, preferences: preferences, selectionStore: selectionStore)
        case .videoSeries:
            SeriesView(viewModel: library, device: deviceMonitor.device, preferences: preferences,
                       selectionStore: selectionStore)
        case .videoClips:
            // El bucket "Videoclips" de la barra lateral es el MISMO
            // que ya usa la heurística automática (MediaCategory.videos,
            // "Videos") -- así un item clasificado sin pasar por esta
            // subsección (p.ej. soltado en "Todos los videos") sigue
            // apareciendo aquí, en vez de partirse en dos categorías
            // que en el fondo son la misma cosa.
            MediaSectionView(kind: .video, viewModel: library, device: deviceMonitor.device, preferences: preferences,
                              selectionStore: selectionStore, presetCategory: MediaCategory.videos.displayName)
        case .photos, .photosGroup:
            MediaSectionView(kind: .photo, viewModel: library, device: deviceMonitor.device, preferences: preferences, selectionStore: selectionStore)
        case .photosPhotos:
            // Encargo del dueño (2026-08-18): cuadrícula de álbumes
            // "similar en uso al iPod Classic original" -- reemplaza la
            // tabla plana (que sigue siendo lo que usa "Todas las
            // fotos", arriba).
            PhotoAlbumsView(viewModel: library, device: deviceMonitor.device, preferences: preferences, category: "Fotos",
                            selectionStore: selectionStore)
        case .photosImages:
            PhotoAlbumsView(viewModel: library, device: deviceMonitor.device, preferences: preferences, category: "Imágenes",
                            selectionStore: selectionStore)
        case .photosAI:
            PhotoAlbumsView(viewModel: library, device: deviceMonitor.device, preferences: preferences, category: "IA",
                            selectionStore: selectionStore)
        case .extras:
            ExtrasView(device: deviceMonitor.device, preferences: preferences,
                       onSwitchFirmware: { family in await switchFirmware(to: family) },
                       onOpenInstaller: { selection = .installer })
        case .installer:
            InstallerHomeView(monitor: deviceMonitor, viewModel: installer)
        case .settings:
            SettingsSectionView(preferences: preferences, appUpdates: appUpdates)
        }
    }

    /// ST-189: "Elegir otra biblioteca..." de la pantalla de disco
    /// desconectado -- el mismo selector que Ajustes, para no tener dos
    /// formas distintas de hacer lo mismo.
    private func chooseLibraryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Usar esta carpeta"
        panel.message = "Elige (o crea) la carpeta donde vivira tu biblioteca Aura."
        if panel.runModal() == .OK, let url = panel.url {
            preferences.libraryFolderPath = url.path
        }
    }

    /// ST-189: "Crear una nueva" -- sin selector, a propósito (misma
    /// decisión que Windows en ST-171): quien aprieta eso no quiere
    /// elegir, quiere seguir trabajando. Va a la carpeta por omisión, y
    /// si ahí ya había una biblioteca **se abre esa**: crear no puede
    /// significar perder.
    private func createNewLibrary() {
        preferences.libraryFolderPath = AppPreferences.defaultLibraryFolderPath
    }

    /// ST-063: "Archivo › Agregar a la biblioteca..." (⌘O). Mismo camino
    /// que soltar archivos sobre la sección visible: el tipo lo decide
    /// la sección (Canciones → música, Video → video, Fotos → foto);
    /// desde General/Extras/Ajustes se acepta cualquier tipo y cada
    /// archivo cae en la biblioteca que le corresponde por extensión.
    private func addFilesFromOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Agregar"
        panel.message = "Elige archivos o carpetas para agregar a la biblioteca de Aura Studio."
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let section = selection ?? .general
        let target = section.libraryKind
        let category: String? = {
            switch section {
            case .videoMovies: return MediaCategory.movies.displayName
            case .videoSeries: return MediaCategory.series.displayName
            case .videoClips: return MediaCategory.videos.displayName
            case .photosPhotos: return "Fotos"
            case .photosImages: return "Imágenes"
            case .photosAI: return "IA"
            default: return nil
            }
        }()
        library.addDroppedFiles(panel.urls, into: target, category: category)
        Task { await library.processAll() }
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
    /// ST-056 / contrato v10: cambio de firmware por renombre y
    /// expulsion. Con el candado de escritura del instalador: nunca
    /// encima de una copia en curso. Devuelve un mensaje de error o nil.
    private func switchFirmware(to family: FirmwareFamily) async -> String? {
        guard let device = deviceMonitor.device, device.supportsAuraContract else {
            return "No hay un iPod con firmware de la familia Aura conectado."
        }
        guard InstallerFlowRegistry.shared.beginWriting() else {
            return "Hay una instalación en curso; espera a que termine."
        }
        defer { InstallerFlowRegistry.shared.endWriting() }
        do {
            try FirmwareSwitcher.switchActiveFirmware(to: family,
                                                      currentlyActive: device.declaredFamily,
                                                      volumeRoot: URL(fileURLWithPath: device.mountPath))
        } catch FirmwareSwitcher.SwitchError.dormantTreeMissing(let f) {
            return "\(f.displayName) no está instalado en el iPod; instálalo desde el Instalador."
        } catch {
            return "No se pudo cambiar de firmware: \(error.localizedDescription)"
        }
        _ = await deviceMonitor.unmountCurrentDisk()
        return nil
    }

    private func refreshNow() async {
        isRefreshing = true
        defer { isRefreshing = false }
        guard let device = deviceMonitor.device else { return }
        deviceMonitor.refreshDevice()
        updateAvailable = await AuraUpdateChecker.checkForUpdate(deviceMountPath: device.mountPath,
                                                                   family: device.declaredFamily,
                                                                   forceRefresh: true)
        updateLatestTag = AuraUpdateChecker.latestKnownTag(family: device.declaredFamily)
        if device.supportsAuraContract {
            await library.verifyDevice(at: URL(fileURLWithPath: device.mountPath))
        }
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

extension SidebarSection {
    /// ST-063: tipo de biblioteca que muestra la sección (nil en
    /// General/Extras/Instalador/Ajustes).
    var libraryKind: LibraryItemKind? {
        switch self {
        case .music, .musicGroup, .musicArtists, .musicAlbums, .musicPlaylists: return .music
        case .video, .videoGroup, .videoMovies, .videoSeries, .videoClips: return .video
        case .photos, .photosGroup, .photosPhotos, .photosImages, .photosAI: return .photo
        case .general, .extras, .installer, .settings: return nil
        }
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
    /// ST-031: "Artistas" y "Álbumes", anidadas bajo Música junto a
    /// Canciones (`.music`) y Listas -- mismo tratamiento que
    /// `.musicPlaylists` (no van en `deviceSections`, sí se bloquean con
    /// `libraryLocked`).
    case musicArtists
    case musicAlbums
    /// Rotulo del grupo "Música" en la barra lateral. Abre Canciones (la
    /// misma vista que `.music`) pero con identidad propia: si el rotulo
    /// y la fila "Canciones" compartieran `.music`, la lista resaltaria
    /// los dos a la vez.
    case musicGroup
    /// PLAN-biblioteca-medios-v2.md §3.2: Video pasa a ser un grupo,
    /// mismo tratamiento que Música -- `.video` ahora es "Todos los
    /// videos" (antes la sección plana completa); `.videoGroup` es el
    /// rótulo del grupo (mismo motivo que `.musicGroup`: identidad
    /// propia para no resaltar junto con la primera subsección).
    case videoMovies
    case videoSeries
    case videoClips
    case videoGroup
    case video
    /// Fotos, mismo patrón.
    case photosPhotos
    case photosImages
    case photosAI
    case photosGroup
    case photos
    case extras
    case installer
    case settings

    /// ST-189: ¿esta sección necesita la biblioteca para servir de algo?
    ///
    /// Las que NO -- General, Instalador, Extras y Ajustes -- siguen
    /// funcionando con el disco de la biblioteca desconectado, y eso es
    /// deliberado: son justamente lo que alguien puede querer usar en ese
    /// momento (instalar el firmware, o ir a Ajustes a elegir otra
    /// carpeta). Es lo que evita que un disco ausente convierta la app en
    /// un cartel.
    var needsLibrary: Bool {
        switch self {
        case .general, .extras, .installer, .settings:
            return false
        default:
            return true
        }
    }

    var title: String {
        switch self {
        case .general:        return S.general.text
        // `.music` es la tabla de Canciones; el rotulo del grupo
        // "Música" lo pone SidebarView (`S.music`).
        case .music:          return S.songs.text
        case .musicGroup:     return S.music.text
        case .musicArtists:   return S.artists.text
        case .musicAlbums:    return S.albums.text
        case .musicPlaylists: return S.playlists.text
        case .videoGroup:     return S.video.text
        case .video:          return S.videoAll.text
        case .videoMovies:    return MediaCategory.movies.displayName
        case .videoSeries:    return MediaCategory.series.displayName
        case .videoClips:     return S.videoClips.text
        case .photosGroup:    return S.photos.text
        case .photos:         return S.photosAll.text
        case .photosPhotos:   return "Fotos"
        case .photosImages:   return "Imágenes"
        case .photosAI:       return "IA"
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
        case .musicGroup:     return "music.note.house"
        case .musicArtists:   return "music.mic"
        case .musicAlbums:    return "square.stack"
        case .musicPlaylists: return "music.note.list"
        case .videoGroup:     return "play.rectangle"
        case .video:          return "play.rectangle"
        case .videoMovies:    return "film"
        case .videoSeries:    return "tv"
        case .videoClips:     return "music.note.tv"
        case .photosGroup:    return "photo"
        case .photos:         return "photo.on.rectangle"
        case .photosPhotos:   return "camera"
        case .photosImages:   return "photo"
        case .photosAI:       return "sparkles"
        case .extras:         return "square.grid.2x2"
        case .installer:      return "square.and.arrow.down"
        case .settings:       return "gear"
        }
    }

    static let deviceSections: [SidebarSection] = [.general, .music, .video, .photos, .extras]
    static let appSections: [SidebarSection] = [.installer, .settings]
    /// Filas anidadas bajo el grupo "Música", en este orden (captura de
    /// referencia del dueño: Artistas, Álbumes, Canciones; Listas al
    /// final).
    static let musicSubsections: [SidebarSection] = [.musicArtists, .musicAlbums, .music, .musicPlaylists]
    /// PLAN-biblioteca-medios-v2.md §3.2: Películas/Series/Videoclips
    /// primero (referencia del encargo), "Todos los videos" al final --
    /// mismo criterio que Música (subsecciones específicas antes que la
    /// tabla completa).
    static let videoSubsections: [SidebarSection] = [.videoMovies, .videoSeries, .videoClips, .video]
    static let photosSubsections: [SidebarSection] = [.photosPhotos, .photosImages, .photosAI, .photos]

    /// Todo lo que vive bajo el grupo Música (incluido el rotulo) -- se
    /// bloquea junto cuando `libraryLocked`.
    var isMusicSection: Bool {
        self == .musicGroup || Self.musicSubsections.contains(self)
    }

    /// Idem, para Video y Fotos -- mismo criterio que `isMusicSection`,
    /// usado en el mismo chequeo de `ContentView.body` que ya cubría
    /// Música (`deviceSections.contains(current) || current.isMusicSection`).
    var isVideoSection: Bool {
        self == .videoGroup || Self.videoSubsections.contains(self)
    }
    var isPhotosSection: Bool {
        self == .photosGroup || Self.photosSubsections.contains(self)
    }
}

private struct SidebarView: View {
    @Binding var selection: SidebarSection?
    let device: AuraDevice?
    let libraryLocked: Bool
    /// Soltar una selección múltiple arrastrada desde Álbumes/Series/
    /// Fotos... sobre una fila de Video o Fotos (encargo del dueño,
    /// 2026-08-19: "arrastrar la selección completa") -- reasigna la
    /// categoría de todos los items arrastrados de una vez. Música
    /// queda fuera a propósito (organiza por metadata de tag, no por
    /// `category`).
    let onDropSelection: (String, Set<UUID>) -> Void
    /// D-228: "Listas" nace expandida -- tiene que ser facil de
    /// encontrar, no un submenu escondido por default.
    @State private var musicExpanded = true
    /// PLAN-biblioteca-medios-v2.md §3.2: Video/Fotos nacen expandidos,
    /// mismo criterio que Música -- las subsecciones son justo lo que
    /// este plan agrega, esconderlas por default las haría invisibles.
    @State private var videoExpanded = true
    @State private var photosExpanded = true

    /// Fila de grupo (Música/Video/Fotos): rótulo con identidad propia
    /// (nunca comparte tag con su primera subsección) que abre/cierra un
    /// `DisclosureGroup` con las filas anidadas -- mismo patrón para los
    /// tres grupos, parametrizado para no triplicar el `body`.
    /// Categoría (`LibraryItem.category`) que corresponde a soltar una
    /// selección arrastrada sobre esta fila -- `nil` para las filas que
    /// no aceptan arrastre (Música, "Todos los videos"/"Todas las
    /// fotos", grupos).
    private func dropCategory(for section: SidebarSection) -> String? {
        switch section {
        case .videoMovies: return MediaCategory.movies.displayName
        case .videoSeries: return MediaCategory.series.displayName
        case .videoClips: return MediaCategory.videos.displayName
        case .photosPhotos: return "Fotos"
        case .photosImages: return "Imágenes"
        case .photosAI: return "IA"
        default: return nil
        }
    }

    @ViewBuilder
    private func groupRow(group: SidebarSection, subsections: [SidebarSection], isExpanded: Binding<Bool>) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            ForEach(subsections, id: \.self) { sub in
                Label(sub.title, systemImage: sub.symbol)
                    .tag(sub)
                    .disabled(libraryLocked)
                    .dropDestination(for: LibrarySelectionTransfer.self) { payloads, _ in
                        guard let category = dropCategory(for: sub) else { return false }
                        for payload in payloads {
                            onDropSelection(category, Set(payload.itemIDs))
                        }
                        return true
                    }
            }
        } label: {
            Label(group.title, systemImage: group.symbol)
                .tag(group)
                .disabled(libraryLocked)
        }
        .tag(group)
    }

    var body: some View {
        List(selection: $selection) {
            Section(header: deviceHeader) {
                ForEach(SidebarSection.deviceSections, id: \.self) { section in
                    switch section {
                    // ST-031 / PLAN-biblioteca-medios-v2.md §3.2: los
                    // tres grupos con subsecciones. El rótulo del grupo
                    // usa una etiqueta propia (`.musicGroup`/
                    // `.videoGroup`/`.photosGroup`) porque dentro de un
                    // `ForEach` la fila heredaría la etiqueta implícita
                    // de `section` y resaltaría junto con su primera
                    // subsección.
                    case .music:
                        groupRow(group: .musicGroup, subsections: SidebarSection.musicSubsections, isExpanded: $musicExpanded)
                    case .video:
                        groupRow(group: .videoGroup, subsections: SidebarSection.videoSubsections, isExpanded: $videoExpanded)
                    case .photos:
                        groupRow(group: .photosGroup, subsections: SidebarSection.photosSubsections, isExpanded: $photosExpanded)
                    default:
                        Label(section.title, systemImage: section.symbol)
                            .tag(section)
                            // General queda siempre accesible: es donde se
                            // explica QUE firmware hay y que hacer con el.
                            // ST-047: Extras queda FUERA del candado de
                            // biblioteca -- ahi vive el selector de
                            // firmware, que hace falta justamente con un
                            // iPod de fabrica; sus filas que escriben en
                            // el iPod (Temas) ya se deshabilitan solas.
                            .disabled(libraryLocked && section != .general && section != .extras)
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
            // §1.5: el nombre editable (`device.cfg`) manda sobre la
            // etiqueta de volumen en cuanto existe.
            Text(device?.displayName ?? S.noDevice.text)
                .lineLimit(1)
        }
    }
}


/// PLAN-studio-rendimiento-2.md Fase 6 (ST-186): la barra de la
/// migración de carátulas (ST-141), en su propia vista.
///
/// Existe para que `ContentView` no tenga que observar el ViewModel solo
/// por esto. Mismo patrón que `LibraryStatusBarHost` y
/// `SelectionStoreObserver`: quien observa es la pieza chica que dibuja,
/// no la ventana entera.
struct CoverNormalizationBarHost: View {
    @ObservedObject var library: LibraryViewModel

    var body: some View {
        if let normalization = library.coverNormalization {
            CoverNormalizationBar(progress: normalization) {
                library.cancelCoverNormalization()
            }
        }
    }
}

/// ST-186: publica el comando de sincronizar (⇧⌘S) al menú, observando
/// el ViewModel **en lugar de** `ContentView`. Vista de tamaño cero:
/// cuando cambia `isProcessing` o el progreso del sync, lo único que se
/// reevalúa es esto.
struct SyncCommandRelay: View {
    @ObservedObject var library: LibraryViewModel
    let canSyncDevice: Bool
    let action: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .focusedSceneValue(\.auraSyncCommand, SyncCommandContext(
                canSync: canSyncDevice && !library.isProcessing && library.syncProgress == nil,
                action: action))
    }
}


/// ST-189: tapa a su contenido mientras falte el disco de la biblioteca.
///
/// Observa **solo** `libraryAvailability` con `onReceive`, no el
/// ViewModel entero: si tuviera un `@ObservedObject`, cualquier cambio de
/// `items` volvería a construir el `detail` y perderíamos lo que ST-186
/// acaba de arreglar.
struct LibraryAvailabilityGate<Content: View>: View {
    let library: LibraryViewModel
    let needsLibrary: Bool
    let libraryPath: String
    let onChooseAnother: () -> Void
    let onCreateNew: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var availability: LibraryAvailability = .available

    var body: some View {
        content()
            .libraryUnavailableOverlay(needsLibrary ? availability : .available,
                                       libraryPath: libraryPath,
                                       onRetry: { library.refreshLibraryAvailability() },
                                       onChooseAnother: onChooseAnother,
                                       onCreateNew: onCreateNew)
            .onReceive(library.$libraryAvailability) { availability = $0 }
    }
}

/// ST-193: publica al menú de la app el comando "Buscar actualizaciones
/// de Aura Studio…", observando el comprobador **en lugar de**
/// `ContentView` -- mismo patrón que `SyncCommandRelay`.
struct AppUpdateCommandRelay: View {
    @ObservedObject var checker: AppUpdateChecker

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .focusedSceneValue(\.auraAppUpdateCommand, AppUpdateCommandContext(
                isChecking: checker.isChecking,
                check: { Task { await checker.checkNow() } }))
    }
}
