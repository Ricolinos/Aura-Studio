import SwiftUI
import AppKit

/// Hoja "Elementos similares" (ST-063): lista los grupos que
/// `SimilarItemsDetector` juzgó sospechosamente parecidos, explica por
/// qué, marca cuál sugiere conservar y deja decidir: conservar uno y
/// eliminar el resto, aplicar la metadata sugerida (unificar artista/
/// álbum, limpiar el número de pista del título), editar cada
/// elemento a mano, o ignorar el grupo para siempre.
///
/// Nunca borra sin confirmación, y la eliminación pasa por
/// `LibraryViewModel.deleteItems` (que solo borra archivos DENTRO de
/// la carpeta de la biblioteca -- los originales del usuario fuera de
/// ella jamás se tocan).
struct SimilarItemsView: View {
    @ObservedObject var library: LibraryViewModel
    @ObservedObject var preferences: AppPreferences
    /// Tipo con el que arranca filtrada (la sección desde la que se abrió).
    var initialKind: LibraryItemKind? = nil
    let onDismiss: () -> Void

    @State private var groups: [SimilarItemsGroup] = []
    @State private var isScanning = false
    @State private var hasScanned = false
    @State private var kindFilter: LibraryItemKind?
    @State private var minimumConfidence: SimilarityConfidence = .possible
    @State private var selectedGroupID: String?
    /// Elemento marcado "conservar" por grupo (arranca en el sugerido).
    @State private var keepChoice: [String: UUID] = [:]
    /// ST-225 (addendum): lo que se dirá **si** el usuario confirma. La
    /// confirmación en sí es la del modelo (`library.pendingDeletion`),
    /// que es la única que sabe cuántos archivos van a la Papelera y
    /// cuántos bytes -- y la única cuyo texto es verdad en los dos modos
    /// de guardado. Acá solo se guarda la frase del resumen, porque el
    /// modelo no sabe (ni tiene por qué) que esto vino de un grupo de
    /// parecidos.
    @State private var summaryIfConfirmed: String?
    @State private var editingItem: LibraryItem?
    @State private var lastActionSummary: String?

    private var visibleGroups: [SimilarItemsGroup] {
        groups.filter { group in
            (kindFilter == nil || group.kind == kindFilter) && group.confidence >= minimumConfidence
        }
    }

    private var selectedGroup: SimilarItemsGroup? {
        guard let selectedGroupID else { return nil }
        return visibleGroups.first { $0.id == selectedGroupID }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isScanning && !hasScanned {
                scanningState
            } else if visibleGroups.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    groupList
                        .frame(width: 300)
                    Divider()
                    if let group = selectedGroup {
                        groupDetail(group)
                    } else {
                        Text(LS("similar-items-view.elige-grupo-lista"))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: 900, idealWidth: 980, minHeight: 560, idealHeight: 620)
        .onAppear {
            kindFilter = initialKind
            rescan()
        }
        .onChange(of: visibleGroups.map(\.id)) { ids in
            if let selectedGroupID, !ids.contains(selectedGroupID) {
                self.selectedGroupID = ids.first
            } else if selectedGroupID == nil {
                selectedGroupID = ids.first
            }
        }
        // ST-225 (addendum): la confirmación de eliminar se presenta
        // DESDE ACÁ y no desde `ContentView`.
        //
        // `DeletionConfirmationHost` vive en el fondo de `ContentView`, y
        // esta vista es una **hoja** encima de ella: una hoja tapa a
        // quien la presenta, así que una alerta colgada del presentador
        // no aparece mientras la hoja está arriba. Los demás sitios que
        // eliminan (álbumes, artistas, series, películas, fotos, la
        // tabla) viven dentro de `ContentView`, no encima; éste era el
        // único tapado.
        //
        // La regla de ST-225 no cambia: el plan, los números y el texto
        // siguen saliendo del modelo. Lo que cambia es quién lo dibuja.
        .alert(library.pendingDeletion?.title ?? "",
               isPresented: Binding(get: { library.pendingDeletion != nil },
                                    set: { if !$0 { cancelDeletion() } })) {
            Button(LS("background-task-center-indicator.cancelar"), role: .cancel) { cancelDeletion() }
            Button(LS("artists-view.eliminar"), role: .destructive) { confirmDeletion() }
        } message: {
            Text(library.pendingDeletion?.message ?? "")
        }
        .sheet(item: $editingItem) { item in
            let categories: [String]? = item.kind == .video
                ? MediaCategory.videoCategories.map(\.displayName)
                : (item.kind == .photo ? preferences.photoCollections : nil)
            let videoInfoHandler: ((String?, String?, Int?, Int?) -> Void)? = item.kind == .video
                ? { title, seriesName, season, episode in
                    library.updateVideoInfo(id: item.id, title: title, seriesName: seriesName, season: season, episode: episode)
                    editingItem = nil
                    rescan()
                }
                : nil
            MediaInfoView(item: item,
                          availableCategories: categories,
                          onCategoryChanged: { category in library.setCategory(category, forItem: item.id) },
                          onRatingChanged: { rating in Task { await library.setRating(rating, forItem: item.id) } },
                          onVideoInfoChanged: videoInfoHandler,
                          onSave: { metadata in
                              Task {
                                  await library.applyReview(id: item.id, metadata: metadata)
                                  editingItem = nil
                                  rescan()
                              }
                          },
                          onCancel: { editingItem = nil })
        }
    }

    // MARK: - Cabecera / pie

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LS("similar-items-view.elementos-similares"))
                    .font(.title2.bold())
                Text(LS("similar-items-view.canciones-videos-o-fotos-que-parecen"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker(LS("media-section-view.tipo"), selection: $kindFilter) {
                Text(LS("similar-items-view.todo")).tag(LibraryItemKind?.none)
                Text(LS("similar-items-view.musica")).tag(LibraryItemKind?.some(.music))
                Text(LS("similar-items-view.video")).tag(LibraryItemKind?.some(.video))
                Text(LS("similar-items-view.fotos")).tag(LibraryItemKind?.some(.photo))
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Picker(LS("similar-items-view.confianza"), selection: $minimumConfidence) {
                Text(LS("similar-items-view.solo-duplicados")).tag(SimilarityConfidence.duplicate)
                Text(LS("similar-items-view.probables-duplicados")).tag(SimilarityConfidence.probable)
                Text(LS("similar-items-view.todos-parecidos")).tag(SimilarityConfidence.possible)
            }
            .fixedSize()
            Button {
                rescan()
            } label: {
                Label(LS("similar-items-view.volver-buscar"), systemImage: "arrow.clockwise")
            }
            .disabled(isScanning)
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            if isScanning {
                ProgressView().controlSize(.small)
                Text(LS("similar-items-view.buscando-parecidos"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let lastActionSummary {
                Text(lastActionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if hasScanned {
                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !preferences.ignoredSimilarGroups.isEmpty {
                Button(LSf("similar-items-view.volver-mostrar-ignorados", preferences.ignoredSimilarGroups.count)) {
                    preferences.ignoredSimilarGroups = []
                    rescan()
                }
            }
            Button(LS("automatic-update-view.listo"), action: onDismiss)
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    private var summaryText: String {
        let counts = SimilarityConfidence.allCases.map { level -> String? in
            let n = groups.filter { $0.confidence == level }.count
            return n == 0 ? nil : level.countText(n)
        }
        let total = groups.count
        if total == 0 { return LS("similar-items-view.no-se-encontraron-elementos-parecidos") }
        return Sentence.titled(LSf("similar-items-view.plural.grupos", total),
                               Sentence.commaList(counts.compactMap { $0 }))
    }

    private var scanningState: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(LS("similar-items-view.comparando-titulos-artistas-duraciones-t"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text(groups.isEmpty ? "No se encontraron elementos parecidos en tu biblioteca." : "Nada que mostrar con este filtro.")
                .foregroundStyle(.secondary)
            if groups.isEmpty && !preferences.ignoredSimilarGroups.isEmpty {
                Text(LSf("similar-items-view.hay-grupo-s-ignorado-s", preferences.ignoredSimilarGroups.count))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Lista de grupos

    private var groupList: some View {
        List(visibleGroups, selection: $selectedGroupID) { group in
            HStack(spacing: 10) {
                confidenceBadge(group.confidence)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle(group.items[0]))
                        .lineLimit(1)
                    Text(groupSubtitle(group))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: kindSymbol(group.kind))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
            .tag(group.id)
        }
        .listStyle(.inset)
    }

    private func groupSubtitle(_ group: SimilarItemsGroup) -> String {
        let n = group.items.count
        var parts = [LSf("similar-items-view.plural.elementos", n)]
        if group.kind == .music, let artist = group.items[0].metadata?.artist, !artist.isEmpty {
            parts.insert(artist, at: 0)
        }
        return Sentence.fields(parts)
    }

    private func confidenceBadge(_ confidence: SimilarityConfidence) -> some View {
        Text(confidence.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(confidenceColor(confidence).opacity(0.18), in: Capsule())
            .foregroundStyle(confidenceColor(confidence))
            .help(confidence.detail)
    }

    private func confidenceColor(_ confidence: SimilarityConfidence) -> Color {
        switch confidence {
        case .duplicate: return .red
        case .probable: return .orange
        case .possible: return .secondary
        }
    }

    private func kindSymbol(_ kind: LibraryItemKind) -> String {
        switch kind {
        case .music: return "music.note"
        case .video: return "play.rectangle"
        case .photo: return "photo"
        case .unsupported: return "questionmark"
        }
    }

    // MARK: - Detalle de un grupo

    private func groupDetail(_ group: SimilarItemsGroup) -> some View {
        let keepID = keepChoice[group.id] ?? group.suggestedKeepID
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    confidenceBadge(group.confidence)
                    Text(group.confidence.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(LS("similar-items-view.por-que-se-parecen"))
                        .font(.headline)
                    ForEach(group.reasons, id: \.self) { reason in
                        Label(reason, systemImage: "circle.fill")
                            .labelStyle(ReasonLabelStyle())
                            .font(.callout)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label(LS("similar-items-view.sugerencia"), systemImage: "lightbulb")
                        .font(.headline)
                    Text(group.suggestion)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AuraColors.light.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 8) {
                    Text(LS("similar-items-view.elementos"))
                        .font(.headline)
                    ForEach(group.items) { item in
                        candidateRow(item, group: group, isKept: item.id == keepID)
                    }
                }

                if !group.proposedEdits.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(LS("similar-items-view.metadata-sugerida"))
                            .font(.headline)
                        ForEach(group.proposedEdits) { edit in
                            HStack(spacing: 6) {
                                Text(edit.fieldTitle + ":")
                                    .foregroundStyle(.secondary)
                                Text(LSf("similar-items-view.texto", edit.currentValue))
                                    .strikethrough()
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Text(LSf("similar-items-view.texto-2", edit.proposedValue))
                                Spacer()
                                Text(displayTitle(group.items.first { $0.id == edit.itemID } ?? group.items[0]))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                            .font(.callout)
                        }
                        Button(LS("similar-items-view.aplicar-metadata-sugerida")) {
                            // PLAN-studio-rendimiento.md Fase 4 paso 3:
                            // applySimilarityEdits es async ahora (corre en
                            // fileWorker) -- rescan() espera a que termine,
                            // igual que antes esperaba a que terminara el
                            // camino síncrono.
                            Task {
                                await library.applySimilarityEdits(group.proposedEdits)
                                lastActionSummary = "Metadata unificada en \(Set(group.proposedEdits.map(\.itemID)).count) elemento(s)."
                                rescan()
                            }
                        }
                        .help(LS("similar-items-view.aplica-solo-estos-cambios-artista-album"))
                    }
                }

                HStack(spacing: 10) {
                    Button(role: .destructive) {
                        requestDeletionOfOthers(in: group)
                    } label: {
                        Label(LS("similar-items-view.conservar-marcado-eliminar-resto"), systemImage: "trash")
                    }
                    Button(LS("similar-items-view.ignorar-este-grupo")) {
                        preferences.ignoredSimilarGroups.append(group.id)
                        groups.removeAll { $0.id == group.id }
                        lastActionSummary = "Grupo ignorado. Puedes volver a mostrarlo desde el pie de esta ventana."
                    }
                    .help(LS("similar-items-view.no-son-lo-mismo-no-volver"))
                    Spacer()
                    Button(LS("albums-view.mostrar-finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting(group.items.map(\.sourceURL))
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func candidateRow(_ item: LibraryItem, group: SimilarItemsGroup, isKept: Bool) -> some View {
        let meta = item.metadata
        let size = SimilarItemsDetector.fileSize(of: item.sourceURL)
        return HStack(alignment: .top, spacing: 12) {
            Button {
                keepChoice[group.id] = item.id
            } label: {
                Image(systemName: isKept ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isKept ? AuraColors.light.accent : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(isKept ? "Este es el que se conserva" : "Conservar este en lugar del marcado")

            if let cover = meta?.loadCoverData(), let image = NSImage(data: cover) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 44, height: 44)
                    .overlay { Image(systemName: kindSymbol(item.kind)).foregroundStyle(.secondary) }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(displayTitle(item))
                        .fontWeight(isKept ? .semibold : .regular)
                        .lineLimit(1)
                    if item.id == group.suggestedKeepID {
                        Text(LS("similar-items-view.sugerido"))
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                if item.kind == .music {
                    Text(LibraryStats.join([meta?.artist.nonEmpty ?? "Sin artista", meta?.album.nonEmpty ?? "Sin álbum",
                                            meta?.year.nonEmpty, meta?.trackNumber.map { "pista \($0)" }]))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if item.kind == .video {
                    Text(LibraryStats.join([item.category ?? "Sin categoría",
                                            item.seriesName.map { "\($0) T\(item.season ?? 0)E\(item.episode ?? 0)" }]))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(LibraryStats.join([item.category, item.photoAlbum.nonEmpty]))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(LibraryStats.join([
                    item.sourceURL.pathExtension.uppercased(),
                    (meta?.durationSeconds).flatMap { $0 > 0 ? String(format: LS("similar-items-detector.d-02d"), Int($0.rounded()) / 60, Int($0.rounded()) % 60) : nil },
                    LibraryStats.sizeText(bytes: size),
                    meta?.hasCover == true ? (item.kind == .music ? "carátula" : "póster") : nil,
                    meta?.syncedLyrics != nil ? "letra" : nil,
                    item.metadataEditedByUser ? "corregido a mano" : nil,
                    meta?.isFavorite == true ? "favorito" : nil,
                ]))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                Text(item.sourceURL.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.sourceURL.path)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Button(LS("similar-items-view.editar")) { editingItem = item }
                Button(LS("similar-items-view.eliminar-solo-este"), role: .destructive) {
                    // ST-225 (addendum): `deleteItems` PIDE confirmación,
                    // no borra. Escribir el resumen y rescanear acá era
                    // decirle al usuario que se eliminó algo que todavía
                    // no se eliminó -- y que no se eliminaba nunca si
                    // cancelaba.
                    // ST-225 (addendum, decisión común con Windows): el
                    // resumen dice lo que pasó con la BIBLIOTECA y nada
                    // sobre dónde quedó el archivo. Dónde quedó ya lo
                    // dijo el diálogo un segundo antes, y ahí sí es
                    // verdad en cada modo; repetirlo acá con una sola
                    // frase para los dos modos era la mentira que
                    // Windows encontró de su lado.
                    summaryIfConfirmed = "Se quitó «\(displayTitle(item))» de la biblioteca."
                    library.deleteItems(ids: [item.id])
                }
                .disabled(group.items.count < 2)
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(isKept ? AuraColors.light.accent.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isKept ? AuraColors.light.accent.opacity(0.5) : Color.secondary.opacity(0.2)))
    }

    // MARK: - Acciones

    private func displayTitle(_ item: LibraryItem) -> String {
        item.metadata?.title.nonEmpty ?? item.sourceURL.deletingPathExtension().lastPathComponent
    }

    private func rescan() {
        isScanning = true
        let items = library.items
        let ignored = Set(preferences.ignoredSimilarGroups)
        Task.detached(priority: .userInitiated) {
            let found = SimilarItemsDetector.detect(in: items, ignoredGroupIDs: ignored)
            await MainActor.run {
                groups = found
                for group in found where keepChoice[group.id] == nil {
                    keepChoice[group.id] = group.suggestedKeepID
                }
                isScanning = false
                hasScanned = true
                if selectedGroupID == nil || !found.contains(where: { $0.id == selectedGroupID }) {
                    selectedGroupID = visibleGroups.first?.id
                }
            }
        }
    }

    /// Pide la confirmación del modelo. No borra: `deleteItems` deja
    /// `library.pendingDeletion` puesto y la alerta de arriba lo dibuja.
    private func requestDeletionOfOthers(in group: SimilarItemsGroup) {
        let keepID = keepChoice[group.id] ?? group.suggestedKeepID
        let losers = Set(group.items.map(\.id)).subtracting([keepID])
        guard !losers.isEmpty else { return }
        let kept = group.items.first { $0.id == keepID }.map(displayTitle) ?? ""
        // Forma de etiqueta, invariable: "Elementos quitados de la
        // biblioteca: 1" y "...: 3" son los dos correctos. Pegar el
        // número delante de un plural ("1 elemento quitados") es
        // justamente el error que ST-227 tuvo que deshacer diez veces.
        summaryIfConfirmed = "Elementos quitados de la biblioteca: \(losers.count). Se conservó «\(kept)»."
        library.deleteItems(ids: losers)
    }

    /// El resumen se escribe con lo que de verdad pasó. Si nada se movió
    /// a la Papelera y nada falló, no se inventa un "se eliminó".
    private func confirmDeletion() {
        let outcome = library.confirmPendingDeletion()
        if outcome.itemsRemoved > 0 { lastActionSummary = summaryIfConfirmed }
        summaryIfConfirmed = nil
        rescan()
    }

    private func cancelDeletion() {
        library.cancelPendingDeletion()
        summaryIfConfirmed = nil
    }
}

private struct ReasonLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon
                .font(.system(size: 5))
                .foregroundStyle(.secondary)
            configuration.title
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
