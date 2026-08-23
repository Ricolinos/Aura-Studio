import SwiftUI
import AppKit

/// Seccion General: la identidad del dispositivo y que hay adentro.
/// Equivalente a la pestaña General del Finder cuando detecta un iPod.
///
/// Los contadores NO se calculan recorriendo el disco: salen del
/// `sync_summary.cfg` que dejo el ultimo sync (el mismo archivo que lee
/// el firmware para su pantalla "Acerca de"). Si nunca se sincronizo, se
/// dice eso en vez de mostrar ceros que parecerian "esta vacio".
struct DeviceGeneralView: View {
    let device: AuraDevice?
    let state: DeviceState
    @ObservedObject var library: LibraryViewModel
    /// Expulsa el volumen del iPod (desmonta el disco completo) --
    /// disponible con CUALQUIER firmware: desconectar sin expulsar es
    /// el clasico camino a un FAT32 corrupto, asi que el boton no
    /// depende de que el iPod tenga Aura.
    let onEject: () async -> Bool
    /// Lanza la reinstalacion/actualizacion de Aura (va a la seccion
    /// Instalador, que ya sabe hacerlo sin flashear cuando Aura esta
    /// en el disco -- D-179).
    let onUpdateAura: () -> Void
    /// true cuando el firmware que trae la app embebido difiere del
    /// instalado en el iPod (comparacion por hash, no por fecha).
    let updateAvailable: Bool
    /// ST-046: tag del Release mas nuevo conocido para la familia del
    /// firmware instalado, para poder nombrarlo. `nil` = sin cache
    /// vigente; la UI cae a un texto generico.
    var latestReleaseTag: String? = nil
    /// "Buscar actualizaciones" manual (PLAN-general-sync.md
    /// §1.1) -- antes solo corria solo al conectar el dispositivo.
    let onCheckForUpdates: () -> Void
    /// Despues de sincronizar hay que releer `sync_summary.cfg` a mano:
    /// el disco no se desmonta, asi que DiskArbitration no dispara
    /// ningun evento por si solo (D-217).
    let onRefreshDevice: () -> Void
    /// Edición in-place del nombre del iPod (§1.5) -- ya llega saneado
    /// (`DeviceNameStore.sanitize`, corrido aquí mismo para poder avisar
    /// de un emoji recortado sin esperar el guardado async).
    let onRenameDevice: (String) -> Void
    /// ST-013 (`CONTRATO-dispositivo.md` v2 SS C bis): false cuando otra
    /// instalacion de Aura Studio nombro este iPod -- el nombre se ve
    /// pero no se edita, con la explicacion en pantalla.
    var canRenameDevice: Bool = true

    @State private var ejectResult: String?
    @State private var deviceNameNotice: String?
    /// No-nil cuando el usuario pulsó Sincronizar y `deviceSyncIndex`
    /// tiene conflictos (§0.1/§1.2) -- dispara la hoja "Antes de
    /// sincronizar" en vez de sincronizar directo.
    @State private var pendingSyncRequest: PendingSyncRequest?
    @State private var showForeignContentSheet = false
    /// Encargo del dueño: "Eliminar todos los archivos, o por tipos de
    /// medios" -- no-nil mientras se confirma un borrado (mismo
    /// criterio de dos pasos que `ForeignContentSheet`: el botón solo
    /// arma la solicitud, la alerta es la que de verdad borra).
    @State private var pendingDelete: PendingDelete?

    private struct PendingSyncRequest: Identifiable {
        let id = UUID()
        let selectionOnly: Bool
    }

    private struct PendingDelete: Identifiable {
        let id = UUID()
        let kinds: Set<LibraryItemKind>
        let label: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let device {
                    header(device)
                    if let ejectResult {
                        Label(ejectResult, systemImage: "eject")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if device.supportsAuraContract {
                        updateSection
                    }
                    Divider()
                    contents(device)
                    Divider()
                } else {
                    disconnected
                    Divider()
                }
                // PLAN-general-sync.md §1.2/§7: siempre visible, con o
                // sin dispositivo -- "Sincronizar" (el disparador real,
                // spec §2) vive aqui junto a la barra, no en la barra de
                // herramientas de la ventana (esa ahora es "Actualizar",
                // un refresco inofensivo -- ver ContentView).
                DeviceActivityBar(
                    device: device,
                    syncProgress: library.syncProgress,
                    isVerifying: library.isVerifyingDevice,
                    lastSyncSummary: library.lastSyncSummary,
                    lastError: library.lastError,
                    pendingCount: pendingCount,
                    deviceSyncIndex: library.deviceSyncIndex,
                    selectionCount: library.selectionForSync.count,
                    onSync: { selectionOnly in
                        // §0.1/§1.2: si hay conflictos (algo modificado
                        // en el iPod, o huérfanos), se pregunta ANTES de
                        // tocar el dispositivo -- sin conflictos, sigue
                        // siendo un solo clic.
                        if library.deviceSyncIndex?.hasConflicts == true {
                            pendingSyncRequest = PendingSyncRequest(selectionOnly: selectionOnly)
                        } else {
                            performSync(selectionOnly: selectionOnly, resolvedConflicts: .none)
                        }
                    },
                    onCancel: { library.cancelSync() }
                )

                if let index = library.deviceSyncIndex, !index.foreignFiles.isEmpty {
                    Button("Contenido solo en el iPod (\(index.foreignFiles.count))…") {
                        showForeignContentSheet = true
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                }
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .navigationTitle("General")
        .sheet(item: $pendingSyncRequest) { request in
            if let index = library.deviceSyncIndex {
                SyncConflictSheet(index: index, onCancel: {
                    pendingSyncRequest = nil
                }, onConfirm: { resolution in
                    pendingSyncRequest = nil
                    performSync(selectionOnly: request.selectionOnly, resolvedConflicts: resolution)
                })
            }
        }
        .sheet(isPresented: $showForeignContentSheet) {
            if let device, let index = library.deviceSyncIndex {
                ForeignContentSheet(
                    volumeRoot: URL(fileURLWithPath: device.mountPath),
                    files: index.foreignFiles,
                    library: library,
                    onDismiss: { showForeignContentSheet = false },
                    onDeleted: { Task { await library.verifyDevice(at: URL(fileURLWithPath: device.mountPath)) } }
                )
            }
        }
        .alert(
            pendingDelete.map { "¿Eliminar \($0.label) del iPod?" } ?? "",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
        ) {
            Button("Cancelar", role: .cancel) { pendingDelete = nil }
            Button("Eliminar", role: .destructive) { confirmDelete() }
        } message: {
            Text("Esta acción no se puede deshacer -- los archivos borrados del iPod no se pueden recuperar. Tu biblioteca en esta Mac no se toca; puedes volver a sincronizar cuando quieras.")
        }
        .toolbar {
            // El boton "Sincronizar" vive ahora en ContentView (barra de
            // herramientas de toda la app, no solo de esta seccion) para
            // que este disponible tambien desde Musica/Video/Fotos, no
            // solo desde General.
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        let ok = await onEject()
                        ejectResult = ok
                            ? "Disco expulsado. Ya puedes desconectar el cable."
                            : "No se pudo expulsar -- cierra cualquier app que este usando el iPod y reintenta."
                    }
                } label: {
                    Label("Expulsar", systemImage: "eject")
                }
                .disabled(device == nil)
            }
        }
    }

    private func header(_ device: AuraDevice) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "ipod")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                // §1.5: editable solo con Aura instalada -- device.cfg
                // vive bajo .rockbox/aura/, que recien existe ahi. Sin
                // Aura, sigue mostrando la etiqueta de volumen de
                // siempre, sin edición.
                if device.supportsAuraContract, canRenameDevice {
                    DeviceNameField(name: device.displayName, onRename: handleRename)
                } else if device.supportsAuraContract {
                    Text(device.displayName).font(.title2.bold())
                    Text("El nombre de este iPod se puso desde otra Mac; solo desde ahí se puede cambiar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(device.volumeName).font(.title2.bold())
                }
                if let deviceNameNotice {
                    Text(deviceNameNotice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(firmwareLabel(device))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if !device.isFAT32 {
                    Label("El volumen no esta en FAT32", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
        }
    }

    private func handleRename(_ raw: String) {
        let (sanitized, strippedEmoji) = DeviceNameStore.sanitize(raw)
        guard !sanitized.isEmpty else { return }
        deviceNameNotice = strippedEmoji ? "El iPod no puede mostrar emoji; se guardó sin ellos." : nil
        onRenameDevice(sanitized)
    }

    /// Solo visible con Aura instalado. "Actualizar" dispara
    /// `AuraUpdateChecker.checkForUpdate` (ST-006): compara el ultimo
    /// tag publicado en GitHub contra `.rockbox/aura/version.txt` del
    /// dispositivo cuando ambos estan disponibles; si el dispositivo
    /// no tiene ese marcador (instalado antes de esta funcionalidad) o
    /// no hay red, cae al hash de `rockbox.ipod` contra el firmware
    /// embebido en esta version de la app -- nunca se queda sin poder
    /// decidir.
    ///
    /// ST-046 descubrio que "Instalar actualizacion" sobre un iPod con
    /// Metro lo habria REEMPLAZADO por Aura (el unico firmware embebido
    /// entonces) y quito el boton para toda familia que no fuera Aura.
    /// ST-047 embebe las dos, asi que el boton vuelve para cualquier
    /// familia que esta version sepa instalar -- `startAutomaticUpdate()`
    /// reinstala LA MISMA familia detectada, nunca la preferencia de
    /// Extras. Una familia desconocida sigue sin boton: se la manda a su
    /// Release, si se sabe cual es.
    @ViewBuilder
    private var updateSection: some View {
        let family = device?.declaredFamily ?? .aura
        let name = family.displayName
        let version = latestReleaseTag.map { " \($0)" } ?? ""

        if updateAvailable {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Actualización de \(name)\(version) disponible").font(.headline)
                    if family.isInstallable {
                        Text("Esta versión de Aura Studio trae un \(name) más nuevo que el instalado en tu iPod. Actualizar no borra tu música ni tus ajustes.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Tu iPod tiene \(name), un firmware que esta versión de Aura Studio no trae embebido. Te avisa de sus actualizaciones pero no puede aplicarlas: descárgala de su repositorio e instálala como de costumbre. Tu biblioteca no se toca.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                // PLAN-general-sync.md §1.1: nombre distinto de
                // "Actualizar" a proposito -- instalar firmware tiene
                // consecuencias serias (un firmware mal instalado puede
                // inutilizar el iPod) y sigue siendo el UNICO disparador
                // de instalacion (ST-006), nunca el mismo verbo/boton
                // que el refresco inofensivo de la barra de herramientas.
                if family.isInstallable {
                    Button("Instalar actualización de \(name)", action: onUpdateAura)
                        .buttonStyle(.borderedProminent)
                } else if let repo = family.releaseRepository,
                          let url = URL(string: "https://github.com/\(repo)/releases") {
                    Button("Ver el Release de \(name)") { NSWorkspace.shared.open(url) }
                        .buttonStyle(.bordered)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.08)))
        } else {
            HStack {
                Label(family.isInstallable
                        ? "\(name) está al día con esta versión de Aura Studio."
                        : "\(name) está al día.",
                      systemImage: "checkmark.seal")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Buscar actualizaciones de \(name)", action: onCheckForUpdates)
                    .buttonStyle(.borderless)
                    .font(.callout)
            }
        }
    }

    /// ST-016: dice exactamente lo que se sabe y lo que no. Dos fuentes:
    /// que archivos hay en el disco (`firmware`) y que firmware esta
    /// atendiendo el USB ahora (`runningFirmware`, lectura real). Solo
    /// se afirma "instalado"/"dual boot" con evidencia de arranque; unos
    /// archivos copiados a mano se describen como eso.
    private func firmwareLabel(_ device: AuraDevice) -> String {
        let dual = device.isDualBoot ? " (dual boot con Apple)" : ""
        switch device.firmware {
        case .aura(let hasBooted):
            // ST-046: el nombre sale de lo que el firmware DECLARA
            // (`firmware_family`), no de que exista `.rockbox/aura/` --
            // Metro-Aura escribe ese mismo arbol y hasta ahora se
            // reportaba como "Firmware Aura instalado". Sin arrancar
            // todavia no hay `aura.cfg` que leer, asi que ahi se dice
            // "de la familia Aura" en vez de arriesgar un nombre.
            let name = device.declaredFamily.displayName
            switch (device.runningFirmware, hasBooted) {
            case (.rockboxFamily, true):
                return "Firmware \(name) instalado -- conectado desde \(name)" + dual
            case (.rockboxFamily, false):
                return "Firmware de la familia Aura instalado -- conectado desde el firmware, todavía sin escribir su configuración" + dual
            case (.apple, true):
                return "Firmware \(name) instalado -- conectado desde el modo disco de Apple" + dual
            case (.unknown, true):
                return "Firmware \(name) instalado" + dual
            case (.apple, false):
                return "Archivos de la familia Aura en el disco, pero el iPod está corriendo el firmware de Apple y ese firmware nunca ha arrancado aquí -- no hay evidencia de que esté instalado"
            case (.unknown, false):
                return "Archivos de la familia Aura en el disco -- todavía sin arrancar (sin evidencia de que el bootloader esté instalado)"
            }
        case .rockbox(let hasBooted):
            switch (device.runningFirmware, hasBooted) {
            case (.rockboxFamily, _):
                return "Rockbox instalado (no es Aura) -- conectado desde Rockbox" + dual
            case (_, true):
                return "Rockbox instalado (no es Aura)" + dual
            case (.apple, false):
                return "Archivos de Rockbox en el disco (no es Aura), pero el iPod está corriendo el firmware de Apple y Rockbox nunca ha arrancado aquí"
            case (.unknown, false):
                return "Archivos de Rockbox en el disco (no es Aura) -- sin evidencia de arranque"
            }
        case .stock:
            return device.runningFirmware == .rockboxFamily
                ? "Firmware original de Apple en el disco -- pero el USB lo atiende el bootloader de Aura/Rockbox (modo USB del bootloader)"
                : "Firmware original de Apple"
        case .empty:
            return device.runningFirmware == .rockboxFamily
                ? "Disco vacío -- el USB lo atiende el bootloader de Aura/Rockbox (modo USB del bootloader)"
                : "Disco vacio, sin firmware"
        }
    }

    @ViewBuilder
    private func contents(_ device: AuraDevice) -> some View {
        switch device.firmware {
        case .aura where device.supportsAuraContract:
            auraContents(device)
        case .aura:
            // ST-016: archivos sin evidencia de arranque -- la biblioteca
            // esta bloqueada (ContentView.libraryLocked) y aca se explica
            // por que, en vez de mostrar contadores de un Aura que no
            // corre.
            VStack(alignment: .leading, spacing: 10) {
                Text("Contenido").font(.headline)
                Text("Hay archivos de Aura en el disco, pero no hay evidencia de que Aura arranque en este iPod: está corriendo el firmware de Apple y Aura nunca escribió su configuración aquí. Instala Aura desde la sección Instalador (flashea el arranque por DFU y vuelve a copiar los archivos) para activar la biblioteca. Si ya lo instalaste, enciende el iPod con Aura una vez y vuelve a conectarlo.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .stock:
            VStack(alignment: .leading, spacing: 10) {
                Text("Contenido").font(.headline)
                Text("La musica de este iPod la administra el firmware original de Apple -- se sincroniza con Finder (o la app Musica), no con Aura Studio. Si instalas Aura desde la seccion Instalador, la biblioteca de Aura Studio se activa.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: device.mountPath))
                } label: {
                    Label("Administrar contenido", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.bordered)
            }
        case .rockbox:
            VStack(alignment: .leading, spacing: 10) {
                Text("Contenido").font(.headline)
                Text("Este iPod tiene un Rockbox que no es Aura: la biblioteca de Aura Studio no aplica a esta instalacion. En la seccion Instalador puedes instalar Aura (sin flashear -- solo se reemplaza la carpeta .rockbox) o restaurar el firmware original.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .empty:
            VStack(alignment: .leading, spacing: 10) {
                Text("Contenido").font(.headline)
                Text("El disco esta vacio. Instala Aura desde la seccion Instalador para empezar a usarlo.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func auraContents(_ device: AuraDevice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("En el iPod").font(.headline)
            if let summary = device.librarySummary {
                contentRow("Musica", "music.note", summary.music)
                contentRow("Video", "play.rectangle", summary.video)
                contentRow("Fotos", "photo", summary.photo)
                HStack {
                    Label("Playlists", systemImage: "music.note.list")
                    Spacer()
                    Text("\(summary.playlistCount)").foregroundStyle(.secondary)
                }
                deleteContentSection
            } else {
                Text("Todavia no sincronizaste este iPod con Aura Studio.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Encargo del dueño: "una opción en General para eliminar todos
    /// los archivos, o por tipos de medios". Cada botón solo ARMA la
    /// solicitud (`pendingDelete`) -- la alerta de `.alert(...)` en
    /// `body` es la que de verdad confirma y ejecuta, mismo criterio de
    /// dos pasos que `ForeignContentSheet`. Deshabilitados si esa
    /// sección ya está en 0 (nada que borrar).
    private var deleteContentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Eliminar contenido").font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            HStack(spacing: 8) {
                deleteButton("Música", kinds: [.music])
                deleteButton("Videos", kinds: [.video])
                deleteButton("Fotos", kinds: [.photo])
                Spacer()
                deleteButton("Eliminar todo", kinds: [.music, .video, .photo], prominent: true)
            }
        }
    }

    @ViewBuilder
    private func deleteButton(_ title: String, kinds: Set<LibraryItemKind>, prominent: Bool = false) -> some View {
        if prominent {
            Button(title, role: .destructive) { requestDelete(kinds: kinds, label: deleteLabel(for: kinds)) }
                .buttonStyle(.borderedProminent)
        } else {
            Button(title, role: .destructive) { requestDelete(kinds: kinds, label: deleteLabel(for: kinds)) }
                .buttonStyle(.bordered)
        }
    }

    private func deleteLabel(for kinds: Set<LibraryItemKind>) -> String {
        if kinds == [.music, .video, .photo] { return "todo el contenido (música, videos y fotos)" }
        if kinds == [.music] { return "toda la música" }
        if kinds == [.video] { return "todos los videos" }
        if kinds == [.photo] { return "todas las fotos" }
        return "el contenido seleccionado"
    }

    private func requestDelete(kinds: Set<LibraryItemKind>, label: String) {
        pendingDelete = PendingDelete(kinds: kinds, label: label)
    }

    private func confirmDelete() {
        guard let request = pendingDelete, let device else { pendingDelete = nil; return }
        pendingDelete = nil
        Task {
            await library.deleteAllDeviceContent(toVolumeAt: URL(fileURLWithPath: device.mountPath), kinds: request.kinds)
            onRefreshDevice()
        }
    }

    /// Respaldo de `DeviceActivityBar` para antes de la primera
    /// verificación (`deviceSyncIndex == nil`, p. ej. justo al conectar,
    /// mientras `verifyDevice` todavía corre) -- misma aproximación que
    /// el `pendingLabel` viejo (D-217): un item `.ready` puede ya estar
    /// sincronizado con ESTE dispositivo, `deviceSyncIndex` (una vez
    /// listo) es la fuente exacta.
    private var pendingCount: Int {
        library.items.filter { $0.status == .ready }.count
    }

    private func performSync(selectionOnly: Bool, resolvedConflicts: LibraryViewModel.ConflictResolution) {
        // ST-012: segunda barrera ademas del boton deshabilitado en
        // DeviceActivityBar -- nunca se toca el disco de un iPod sin
        // Aura, sin importar por donde llegue la llamada.
        guard let device, device.supportsAuraContract else { return }
        let scope: LibraryViewModel.SyncScope = selectionOnly ? .selection(library.selectionForSync) : .all
        Task {
            await library.sync(toVolumeAt: URL(fileURLWithPath: device.mountPath), scope: scope, resolvedConflicts: resolvedConflicts)
            onRefreshDevice()
        }
    }

    private func contentRow(_ title: String, _ symbol: String, _ summary: CatalogTypeSummary) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text("\(summary.count)")
            Text(byteString(summary.bytes))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
        }
    }

    private var disconnected: some View {
        VStack(alignment: .leading, spacing: 12) {
            /* "ipod.slash" no existe en SF Symbols (verificado contra
             * el catalogo real, Fase 26) -- mismo simbolo que la
             * barra lateral (ContentView.swift) para "sin dispositivo". */
            Image(systemName: "cable.connector.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Conecta tu iPod").font(.title2.bold())
            Text(stateHint)
                .foregroundStyle(.secondary)
            Text("Mientras tanto puedes ir armando la biblioteca en Musica, Video y Fotos: se sincroniza cuando conectes el dispositivo.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var stateHint: String {
        switch state {
        case .dfuMode:
            return "El iPod esta en modo DFU. Usa la seccion Instalador para instalar o restaurar el firmware."
        case .diskModeNoFilesystem:
            return "El disco del iPod no tiene un sistema de archivos legible. Usa la seccion Instalador para prepararlo e instalar Aura."
        case .unknown:
            return "Hay un dispositivo Apple conectado, pero no se pudo identificar como un iPod Classic."
        case .detecting:
            return "Buscando dispositivos..."
        case .notConnected, .diskMode:
            return "Conéctalo por USB y espera a que aparezca como disco."
        }
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// D-216 (barra de capacidad por color) se retiro -- reemplazada por
// `DeviceActivityBar` (PLAN-general-sync.md §7), que en reposo cumple
// exactamente el mismo rol con los colores del firmware (§1.6/P6) en
// vez de los colores de sistema de SwiftUI.
