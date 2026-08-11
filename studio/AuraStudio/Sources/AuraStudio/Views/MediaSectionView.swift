import SwiftUI
import UniformTypeIdentifiers

/// Una seccion de contenido del dispositivo (Musica, Video o Fotos).
/// Las tres comparten exactamente el mismo flujo -- soltar archivos, que
/// el pipeline los prepare, revisar lo que quedo incompleto -- asi que
/// son la misma vista parametrizada por `kind` en vez de tres copias.
struct MediaSectionView: View {
    let kind: LibraryItemKind
    @ObservedObject var viewModel: LibraryViewModel

    @State private var isTargeted = false
    @State private var reviewingItem: LibraryItem?
    @State private var showingPlaylists = false

    private var items: [LibraryItem] {
        viewModel.items.filter { $0.kind == kind }
    }

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                dropZone
                    .padding(24)
                    .frame(maxHeight: .infinity)
            } else {
                dropZone
                    .frame(height: 96)
                    .padding([.horizontal, .top], 16)
                List(items) { item in
                    MediaItemRow(item: item) { reviewingItem = item }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(title)
        .toolbar {
            if kind == .music {
                ToolbarItem {
                    Button {
                        showingPlaylists = true
                    } label: {
                        Label("Playlists", systemImage: "music.note.list")
                    }
                }
            }
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
    }

    private var title: String {
        switch kind {
        case .music: return "Musica"
        case .video: return "Video"
        case .photo: return "Fotos"
        case .unsupported: return "Otros"
        }
    }

    private var prompt: String {
        switch kind {
        case .music: return "Solta canciones aca"
        case .video: return "Solta videos aca"
        case .photo: return "Solta fotos aca"
        case .unsupported: return "Solta archivos aca"
        }
    }

    private var dropZone: some View {
        DropZone(isTargeted: $isTargeted, prompt: prompt, symbol: symbolName) { urls in
            viewModel.addDroppedFiles(urls)
            Task { await viewModel.processAll() }
        }
    }

    private var symbolName: String {
        switch kind {
        case .music: return "music.note"
        case .video: return "film.fill"
        case .photo: return "photo.fill"
        case .unsupported: return "questionmark"
        }
    }
}

private struct DropZone: View {
    @Binding var isTargeted: Bool
    let prompt: String
    let symbol: String
    let onDrop: ([URL]) -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
            .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: symbol).font(.largeTitle)
                    Text(prompt)
                }
                .foregroundStyle(.secondary)
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                loadURLs(from: providers)
                return true
            }
    }

    /// Los items del drop se resuelven de forma asincronica, cada uno en
    /// su propio hilo y en cualquier orden. Antes esto acumulaba en un
    /// `var urls` capturado por todos los callbacks a la vez: carrera de
    /// datos real (soltar varios archivos podia perder alguno o corromper
    /// el array) que solo denuncia `xcodebuild` con la concurrencia
    /// estricta de Swift 6, no `swift build` -- mismo caso que D-034.
    ///
    /// `DropCollector` serializa la escritura con un lock y ademas guarda
    /// cada URL en la posicion de SU provider, asi el orden en que el
    /// usuario solto los archivos se respeta aunque los callbacks
    /// vuelvan desordenados (importa al soltar un album entero).
    private func loadURLs(from providers: [NSItemProvider]) {
        let collector = DropCollector(count: providers.count)
        let group = DispatchGroup()
        for (index, provider) in providers.enumerated() {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { collector.set(url, at: index) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            onDrop(collector.ordered())
        }
    }
}

private final class DropCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var slots: [URL?]

    init(count: Int) {
        slots = Array(repeating: nil, count: count)
    }

    func set(_ url: URL, at index: Int) {
        lock.lock(); defer { lock.unlock() }
        guard slots.indices.contains(index) else { return }
        slots[index] = url
    }

    func ordered() -> [URL] {
        lock.lock(); defer { lock.unlock() }
        return slots.compactMap { $0 }
    }
}

private struct MediaItemRow: View {
    let item: LibraryItem
    var onReviewTapped: () -> Void = {}

    var body: some View {
        HStack {
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
