import SwiftUI

/// Barra SIEMPRE visible en General (PLAN-general-sync.md §7): en
/// reposo muestra el uso de almacenamiento -- mismos colores que la
/// barra de "Acerca de" del firmware (Música/Video/Fotos/Otro/Libre,
/// `aura_screens.c:1856-1930`) -- coherencia entre productos, en vez de
/// los colores de sistema que usaba la `StorageBarView` vieja (D-216).
/// Mientras sincroniza, el mismo espacio se convierte en la barra de
/// progreso: nunca hay un "0% atascado" -- si no hay nada corriendo,
/// siempre hay algo real que mostrar (el almacenamiento).
///
/// Simplificación deliberada frente al firmware: el C separa "Sistema"
/// (peso de `.rockbox/`) de "Otro" -- Studio los agrupa en un solo
/// segmento "Otro" en esta pasada, para no tener que recorrer el
/// directorio `.rockbox/` en el hilo principal solo para pintar una
/// barra (`.rockbox/` es chico frente a la música/video/fotos reales,
/// asi que la diferencia visual es minima). Separarlo de verdad
/// requeriría que `LibrarySync` lo mida UNA VEZ al sincronizar y lo
/// sume a `sync_summary.cfg` -- queda como mejora de una tanda futura,
/// no un cambio a medias: hoy "Otro" es exactamente lo que dice ser.
///
/// Estados cubiertos: sin dispositivo, en reposo, verificando,
/// sincronizando, cancelando, error (tanda 2 + tanda 3, `DeviceSyncIndex`).
/// "Pausado" queda documentado para una tanda futura -- todavía no hay
/// mecanismo de pausa, solo cancelar (ver PLAN-general-sync.md §12).
struct DeviceActivityBar: View {
    let device: AuraDevice?
    let syncProgress: SyncProgress?
    /// `true` mientras `LibraryViewModel.verifyDevice` recorre el
    /// dispositivo (PLAN-general-sync.md §4) -- estado "Verificando".
    let isVerifying: Bool
    let lastSyncSummary: String?
    let lastError: String?
    let pendingCount: Int
    /// Comparación contra el iPod (§4) -- `nil` antes de la primera
    /// verificación, cuando solo queda `pendingCount` como aproximación.
    let deviceSyncIndex: DeviceSyncIndex?
    let selectionCount: Int
    /// `true` = "Solo la selección" estaba elegido cuando se pulso
    /// Sincronizar.
    let onSync: (_ selectionOnly: Bool) -> Void
    let onCancel: () -> Void

    @State private var scopeChoice: ScopeChoice = .all
    @State private var isCancelling = false

    private enum ScopeChoice: Hashable {
        case all
        case selection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let syncProgress {
                syncingBar(syncProgress)
            } else {
                idleBar
                statusText
            }
        }
        .onChange(of: syncProgress == nil) { isIdleNow in
            if isIdleNow { isCancelling = false }
        }
        .onChange(of: selectionCount) { count in
            if count == 0 { scopeChoice = .all }
        }
    }

    // MARK: - En reposo (almacenamiento)

    @ViewBuilder
    private var idleBar: some View {
        if let device, device.capacityBytes > 0 {
            storageSegments(device)
            Text("\(byteString(device.usedBytes)) usados de \(byteString(device.capacityBytes)) -- \(byteString(device.freeBytes)) libres")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Capsule()
                .fill(AuraColors.light.progressTrack)
                .frame(height: 12)
        }

        if device != nil {
            HStack(spacing: 12) {
                Picker("Alcance", selection: $scopeChoice) {
                    Text("Toda la biblioteca").tag(ScopeChoice.all)
                    Text(selectionCount > 0 ? "Solo la selección (\(selectionCount))" : "Solo la selección")
                        .tag(ScopeChoice.selection)
                        .disabled(selectionCount == 0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(isVerifying)

                Spacer()

                Button("Sincronizar") {
                    onSync(scopeChoice == .selection)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isVerifying || (scopeChoice == .selection && selectionCount == 0))
            }
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if isVerifying {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Verificando el iPod...")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        } else if let lastError {
            Text(lastError).font(.callout).foregroundStyle(.red)
        } else if let lastSyncSummary {
            Text(lastSyncSummary).font(.callout).foregroundStyle(.secondary)
        } else if device == nil {
            Text("Conecta tu iPod para sincronizar.").font(.callout).foregroundStyle(.secondary)
        } else if let index = deviceSyncIndex {
            Text(summaryText(for: index)).font(.callout).foregroundStyle(.secondary)
        } else if pendingCount > 0 {
            Text("\(pendingCount) archivo(s) listo(s) para sincronizar.").font(.callout).foregroundStyle(.secondary)
        } else {
            Text("Todo sincronizado.").font(.callout).foregroundStyle(.secondary)
        }
    }

    /// Resume los estados de `deviceSyncIndex` (§4.1) -- solo lo que no
    /// es cero, para no decir "0 modificados" en el caso normal.
    private func summaryText(for index: DeviceSyncIndex) -> String {
        let counts = index.states.values.reduce(into: [SyncItemState: Int]()) { counts, state in
            counts[state, default: 0] += 1
        }
        var parts: [String] = []
        if let pending = counts[.pending], pending > 0 { parts.append("\(pending) pendiente(s)") }
        if let changed = counts[.changedLocally], changed > 0 { parts.append("\(changed) con cambios") }
        if let modified = counts[.modifiedOnDevice], modified > 0 { parts.append("\(modified) modificado(s) en el iPod") }
        if let removed = counts[.removedFromDevice], removed > 0 { parts.append("\(removed) quitado(s) del iPod") }
        return parts.isEmpty ? "Todo sincronizado." : parts.joined(separator: " · ")
    }

    // MARK: - Sincronizando / Cancelando

    private func syncingBar(_ progress: SyncProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: Double(progress.copied), total: Double(max(progress.total, 1)))
                .tint(AuraColors.light.accent)
            HStack {
                Text("Sincronizando \(progress.copied) de \(progress.total) archivo(s)...")
                Spacer()
                if let remaining = progress.estimatedSecondsRemaining, remaining > 1 {
                    Text(timeRemainingText(remaining))
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button(role: .destructive) {
                    isCancelling = true
                    onCancel()
                } label: {
                    if isCancelling {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.small)
                            Text("Cancelando...")
                        }
                    } else {
                        Text("Cancelar")
                    }
                }
                .disabled(isCancelling)
            }
        }
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func timeRemainingText(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = seconds >= 60 ? [.minute, .second] : [.second]
        formatter.maximumUnitCount = 2
        let text = formatter.string(from: seconds) ?? "\(Int(seconds))s"
        return "\(text) restante(s)"
    }

    // MARK: - Segmentos de almacenamiento

    private struct StorageSegment {
        let bytes: Int64
        let color: Color
        let label: String
    }

    /// Colores literales de `category_video`/`category_photos`/
    /// `category_extras_yellow` -- `CONTRATO-formato-tema.md` §B
    /// (`theme.cfg`), mismos valores que `aura_screens.c:1882-1887`
    /// dibuja en la barra de "Acerca de". Sin variante oscura: el
    /// formato de tema tampoco la tiene para estos tres tokens
    /// (a diferencia de los 8 roles de paleta), son fijos.
    private static let categoryVideo = Color(red: 0x1E / 255, green: 0x3A / 255, blue: 0x5F / 255)
    private static let categoryPhotos = Color(red: 0xFF / 255, green: 0x95 / 255, blue: 0x00 / 255)
    private static let categoryOther = Color(red: 0xFF / 255, green: 0xCC / 255, blue: 0x00 / 255)

    private static func segments(for device: AuraDevice) -> [StorageSegment] {
        let summary = device.librarySummary
        let music = summary?.music.bytes ?? 0
        let video = summary?.video.bytes ?? 0
        let photo = summary?.photo.bytes ?? 0
        let other = max(device.usedBytes - music - video - photo, 0)
        let free = max(device.capacityBytes - device.usedBytes, 0)
        return [
            StorageSegment(bytes: music, color: AuraColors.light.accent, label: "Música"),
            StorageSegment(bytes: video, color: categoryVideo, label: "Video"),
            StorageSegment(bytes: photo, color: categoryPhotos, label: "Fotos"),
            StorageSegment(bytes: other, color: categoryOther, label: "Otro"),
            StorageSegment(bytes: free, color: AuraColors.light.progressTrack, label: "Libre"),
        ]
    }

    private func storageSegments(_ device: AuraDevice) -> some View {
        let segments = Self.segments(for: device)
        let total = max(device.capacityBytes, 1)
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    ForEach(segments, id: \.label) { segment in
                        if segment.bytes > 0 {
                            segment.color
                                .frame(width: geometry.size.width * CGFloat(segment.bytes) / CGFloat(total))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 12)
            .clipShape(Capsule())
            .background(Capsule().fill(AuraColors.light.progressTrack))

            // Igual que la barra del firmware (D-282, about.md): "Libre"
            // no lleva fila de leyenda propia, es el resto implícito.
            HStack(spacing: 14) {
                ForEach(segments.filter { $0.bytes > 0 && $0.label != "Libre" }, id: \.label) { segment in
                    HStack(spacing: 5) {
                        Circle().fill(segment.color).frame(width: 7, height: 7)
                        Text(segment.label).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
