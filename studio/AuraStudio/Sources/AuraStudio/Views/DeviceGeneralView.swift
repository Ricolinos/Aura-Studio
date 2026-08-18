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
    /// "Buscar actualizaciones de Aura" manual (PLAN-general-sync.md
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

    private struct PendingSyncRequest: Identifiable {
        let id = UUID()
        let selectionOnly: Bool
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
                    if device.isAura {
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
                if device.isAura, canRenameDevice {
                    DeviceNameField(name: device.displayName, onRename: handleRename)
                } else if device.isAura {
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
    @ViewBuilder
    private var updateSection: some View {
        if updateAvailable {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Actualización de Aura disponible").font(.headline)
                    Text("Esta versión de Aura Studio trae un firmware más nuevo que el instalado en tu iPod. Actualizar no borra tu música ni tus ajustes.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // PLAN-general-sync.md §1.1: nombre distinto de
                // "Actualizar" a proposito -- instalar firmware tiene
                // consecuencias serias (un firmware mal instalado puede
                // inutilizar el iPod) y sigue siendo el UNICO disparador
                // de instalacion (ST-006), nunca el mismo verbo/boton
                // que el refresco inofensivo de la barra de herramientas.
                Button("Instalar actualización de Aura", action: onUpdateAura)
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.08)))
        } else {
            HStack {
                Label("Aura está al día con esta versión de Aura Studio.", systemImage: "checkmark.seal")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Buscar actualizaciones de Aura", action: onCheckForUpdates)
                    .buttonStyle(.borderless)
                    .font(.callout)
            }
        }
    }

    private func firmwareLabel(_ device: AuraDevice) -> String {
        switch device.firmware {
        case .aura(let hasBooted):
            let base = hasBooted ? "Firmware Aura instalado"
                                 : "Firmware Aura instalado -- todavia sin arrancar"
            return device.isDualBoot ? base + " (dual boot con Apple)" : base
        case .rockbox:
            return device.isDualBoot
                ? "Rockbox instalado (no es Aura), en dual boot con Apple"
                : "Rockbox instalado (no es Aura)"
        case .stock:
            return "Firmware original de Apple"
        case .empty:
            return "Disco vacio, sin firmware"
        }
    }

    @ViewBuilder
    private func contents(_ device: AuraDevice) -> some View {
        switch device.firmware {
        case .aura:
            auraContents(device)
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
            } else {
                Text("Todavia no sincronizaste este iPod con Aura Studio.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
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
        guard let device else { return }
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
