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

    @State private var ejectResult: String?

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
                    capacity(device)
                    Divider()
                    contents(device)
                } else {
                    disconnected
                }
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .navigationTitle("General")
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
                Text(device.volumeName).font(.title2.bold())
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
                    Text("Actualizacion de Aura disponible").font(.headline)
                    Text("Esta version de Aura Studio trae un firmware mas nuevo que el instalado en tu iPod. Actualizar no borra tu musica ni tus ajustes.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Actualizar Aura", action: onUpdateAura)
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.08)))
        } else {
            Label("Aura esta al dia con esta version de Aura Studio.", systemImage: "checkmark.seal")
                .font(.callout)
                .foregroundStyle(.secondary)
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

    private func capacity(_ device: AuraDevice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Capacidad").font(.headline)
            if device.capacityBytes > 0 {
                StorageBarView(device: device)
                Text("\(byteString(device.usedBytes)) usados de \(byteString(device.capacityBytes)) -- \(byteString(device.freeBytes)) libres")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("No se pudo leer la capacidad del volumen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
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

            if let pending = pendingLabel {
                Divider().padding(.vertical, 4)
                Text(pending).font(.callout).foregroundStyle(.secondary)
            }
            if let progress = library.syncProgress {
                Divider().padding(.vertical, 4)
                syncProgressSection(progress)
            }
            if let summary = library.lastSyncSummary {
                Text(summary).font(.callout).foregroundStyle(.secondary)
            }
            if let error = library.lastError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
    }

    /// D-217 (encargo del dueño): "una barra de progreso al
    /// sincronizar... para que sepamos cuantas canciones se estan
    /// sincronizando, y cuanto tiempo faltaria".
    private func syncProgressSection(_ progress: SyncProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: Double(progress.copied), total: Double(max(progress.total, 1)))
            HStack {
                Text("Sincronizando \(progress.copied) de \(progress.total) archivo(s)...")
                Spacer()
                if let remaining = progress.estimatedSecondsRemaining, remaining > 1 {
                    Text(timeRemainingText(remaining))
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private func timeRemainingText(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = seconds >= 60 ? [.minute, .second] : [.second]
        formatter.maximumUnitCount = 2
        let text = formatter.string(from: seconds) ?? "\(Int(seconds))s"
        return "\(text) restante(s)"
    }

    private var pendingLabel: String? {
        let ready = library.items.filter { $0.status == .ready }.count
        guard ready > 0 else { return nil }
        return "\(ready) archivo(s) preparado(s) esperando sincronizacion."
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

/// D-216 (encargo del dueño): la barra de capacidad, dividida por color
/// segun el tipo de contenido -- rosa musica, azul video, verde fotos,
/// naranja "Otro" (el resto de lo ocupado: `.rockbox/`, playlists,
/// archivos no reconocidos -- cualquier byte usado que `librarySummary`
/// no le atribuye a musica/video/fotos). Sin sistema de diseño propio
/// para esto en Aura Studio (la paleta compartida con el firmware,
/// `AuraColors`, no tiene tokens para "por tipo de medio" -- es
/// especifico de esta pantalla de macOS) se usan los colores de sistema
/// de SwiftUI mas cercanos a lo que pidio el dueño.
private struct StorageBarView: View {
    let device: AuraDevice

    private struct Segment {
        let bytes: Int64
        let color: Color
        let label: String
    }

    private var segments: [Segment] {
        let summary = device.librarySummary
        let music = summary?.music.bytes ?? 0
        let video = summary?.video.bytes ?? 0
        let photo = summary?.photo.bytes ?? 0
        // "Otro" sale de lo que el disco realmente reporta como usado
        // menos lo que la biblioteca de Aura le atribuye a cada tipo --
        // asi cubre .rockbox/, playlists, y cualquier archivo que el
        // usuario haya copiado por fuera de Aura Studio, sin inventar un
        // numero que no salga de una medicion real.
        let other = max(device.usedBytes - music - video - photo, 0)
        return [
            Segment(bytes: music, color: .pink, label: "Música"),
            Segment(bytes: video, color: .blue, label: "Video"),
            Segment(bytes: photo, color: .green, label: "Fotos"),
            Segment(bytes: other, color: .orange, label: "Otro"),
        ]
    }

    private var total: Int64 { max(device.capacityBytes, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        if segment.bytes > 0 {
                            segment.color
                                .frame(width: geometry.size.width * CGFloat(segment.bytes) / CGFloat(total))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
            .background(Capsule().fill(Color.secondary.opacity(0.15)))

            HStack(spacing: 14) {
                ForEach(segments.filter { $0.bytes > 0 }, id: \.label) { segment in
                    HStack(spacing: 5) {
                        Circle().fill(segment.color).frame(width: 7, height: 7)
                        Text(segment.label).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
