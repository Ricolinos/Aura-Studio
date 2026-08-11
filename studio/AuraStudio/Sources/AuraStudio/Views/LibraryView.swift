import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @StateObject private var deviceMonitor = IPodMonitor()
    @State private var isTargeted = false
    @State private var showingAPIKeySettings = false
    @State private var showingPlaylists = false
    @State private var reviewingItem: LibraryItem?

    var body: some View {
        VStack(spacing: 0) {
            header

            DropZone(isTargeted: $isTargeted) { urls in
                viewModel.addDroppedFiles(urls)
                Task { await viewModel.processAll() }
            }
            .frame(height: viewModel.items.isEmpty ? .infinity : 120)
            .padding()

            if !viewModel.items.isEmpty {
                List(viewModel.items) { item in
                    LibraryItemRow(item: item) {
                        reviewingItem = item
                    }
                }
                .listStyle(.inset)
            }

            footer
        }
        .sheet(isPresented: $showingAPIKeySettings) {
            APIKeySettingsView()
        }
        .sheet(isPresented: $showingPlaylists) {
            PlaylistsView(viewModel: viewModel) { showingPlaylists = false }
        }
        .sheet(item: $reviewingItem) { item in
            MetadataReviewView(item: item) { metadata in
                viewModel.applyReview(id: item.id, metadata: metadata)
                reviewingItem = nil
            } onCancel: {
                reviewingItem = nil
            }
        }
        .onAppear { deviceMonitor.start() }
        .onDisappear { deviceMonitor.stop() }
    }

    private var header: some View {
        HStack {
            Text("Biblioteca")
                .font(.title2.bold())
            Spacer()
            Button {
                showingPlaylists = true
            } label: {
                Label("Playlists", systemImage: "music.note.list")
            }
            .buttonStyle(.link)
            Button {
                showingAPIKeySettings = true
            } label: {
                Label("Letras (opcional)", systemImage: "key")
            }
            .buttonStyle(.link)
        }
        .padding([.horizontal, .top])
    }

    /// Fase 23 (PLAN-UX.md): antes el usuario escribia la ruta del
    /// volumen a mano pese a que IPodMonitor (Fase 9) ya sabe detectarlo
    /// solo -- se reusa el mismo monitor que usa el instalador en vez de
    /// duplicar logica de deteccion de disco.
    private var footer: some View {
        VStack(spacing: 8) {
            if let summary = viewModel.lastSyncSummary {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let error = viewModel.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                deviceStatusLabel
                Spacer()
                Button("Sincronizar al iPod") {
                    guard case .diskMode(let info) = deviceMonitor.state else { return }
                    let url = URL(fileURLWithPath: info.mountPath)
                    Task { await viewModel.sync(toVolumeAt: url) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!deviceMonitor.state.isReadyForInstall || viewModel.isProcessing)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var deviceStatusLabel: some View {
        switch deviceMonitor.state {
        case .notConnected, .detecting:
            Label("Conecta tu iPod para sincronizar", systemImage: "cable.connector.slash")
                .foregroundStyle(.secondary)
        case .diskMode(let info) where info.isFAT32:
            Label("\(info.volumeName) listo", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .diskMode:
            Label("iPod detectado, pero no esta en FAT32", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .dfuMode:
            Label("iPod en modo DFU -- usa la pestana Instalador", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .unknown:
            Label("Dispositivo Apple sin clasificar", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }
}

private struct DropZone: View {
    @Binding var isTargeted: Bool
    let onDrop: ([URL]) -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
            .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down.on.square.fill")
                        .font(.largeTitle)
                    Text("Soltá musica, videos o fotos aca")
                }
                .foregroundStyle(.secondary)
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                loadURLs(from: providers)
                return true
            }
    }

    private func loadURLs(from providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            onDrop(urls)
        }
    }
}

private struct LibraryItemRow: View {
    let item: LibraryItem
    var onReviewTapped: () -> Void = {}

    var body: some View {
        HStack {
            Image(systemName: iconName)
                .frame(width: 20)
            VStack(alignment: .leading) {
                Text(item.metadata?.title ?? item.sourceURL.lastPathComponent)
                    .font(.body)
                if let artist = item.metadata?.artist {
                    Text(artist).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            statusView
        }
    }

    private var iconName: String {
        switch item.kind {
        case .music: return "music.note"
        case .video: return "film"
        case .photo: return "photo"
        case .unsupported: return "questionmark"
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch item.status {
        case .queued:
            Text("En cola").foregroundStyle(.secondary)
        case .enriching:
            ProgressView().controlSize(.small)
        case .transcoding(let progress):
            ProgressView(value: progress).frame(width: 80)
        case .ready:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .needsReview:
            Button(action: onReviewTapped) {
                Label("Revisar", systemImage: "exclamationmark.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.orange)
        case .failed(let message):
            Label(message, systemImage: "xmark.circle").foregroundStyle(.red)
        }
    }
}
