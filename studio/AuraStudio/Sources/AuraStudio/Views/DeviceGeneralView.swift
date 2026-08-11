import SwiftUI

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
    let onSync: () async -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let device {
                    header(device)
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
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await onSync() }
                } label: {
                    Label("Sincronizar", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(device == nil || library.isProcessing)
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
                Text(firmwareLabel(device.firmware))
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

    private func firmwareLabel(_ firmware: AuraDevice.Firmware) -> String {
        switch firmware {
        case .aura(let hasBooted):
            return hasBooted ? "Firmware Aura instalado"
                             : "Firmware Aura instalado -- todavia sin arrancar"
        case .rockbox:
            return "Rockbox instalado (no es Aura)"
        case .stock:
            return "Firmware original de Apple"
        }
    }

    private func capacity(_ device: AuraDevice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Capacidad").font(.headline)
            if device.capacityBytes > 0 {
                ProgressView(value: Double(device.usedBytes),
                             total: Double(device.capacityBytes))
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
        VStack(alignment: .leading, spacing: 8) {
            Text("En el iPod").font(.headline)
            if let summary = device.librarySummary {
                contentRow("Musica", "music.note", summary.music)
                contentRow("Video", "film.fill", summary.video)
                contentRow("Fotos", "photo.fill", summary.photo)
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
            if let summary = library.lastSyncSummary {
                Text(summary).font(.callout).foregroundStyle(.secondary)
            }
            if let error = library.lastError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
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
            Image(systemName: "ipod.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Conecta tu iPod").font(.title2.bold())
            Text(stateHint)
                .foregroundStyle(.secondary)
            Text("Mientras tanto podes ir armando la biblioteca en Musica, Video y Fotos: se sincroniza cuando conectes el dispositivo.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var stateHint: String {
        switch state {
        case .dfuMode:
            return "El iPod esta en modo DFU. Usa la seccion Instalador para instalar o restaurar el firmware."
        case .unknown:
            return "Hay un dispositivo Apple conectado, pero no se pudo identificar como un iPod Classic."
        case .detecting:
            return "Buscando dispositivos..."
        case .notConnected, .diskMode:
            return "Conectalo por USB y esperá a que aparezca como disco."
        }
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
