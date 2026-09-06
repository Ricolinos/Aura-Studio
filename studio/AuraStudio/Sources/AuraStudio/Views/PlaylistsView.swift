import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Fase 24 (PLAN-UX.md): editor de playlists. Arma listas ordenadas a
/// partir de la musica ya agregada en esta sesion (`viewModel.items`) --
/// se resuelven a `.m3u8` recien al sincronizar (`LibrarySync`), asi que
/// esta vista solo maneja el modelo en memoria (`Playlist`), no toca
/// disco.
///
/// Fase 1B/D-193: tambien se puede IMPORTAR una playlist M3U/M3U8 de
/// otro programa (iTunes, Music.app, VLC, exportadores de servicios de
/// streaming) -- las pistas que ya esten en esta biblioteca se ligan
/// solas; las que no, quedan listadas para agregarlas a mano.
struct PlaylistsView: View {
    @ObservedObject var viewModel: LibraryViewModel
    let onDismiss: () -> Void

    @State private var newPlaylistName = ""
    @State private var selectedPlaylistID: UUID?
    @State private var importSummary: String?
    /// PLAN-studio-rendimiento-2.md Fase 1 (ST-181): el resumen de la
    /// barra de estado, memoizado -- antes se armaba en el `body`, y con
    /// él un diccionario de TODAS las canciones de la biblioteca en cada
    /// pasada (ver `GridStatusModel`).
    @StateObject private var statusModel = GridStatusModel()

    private var musicItems: [LibraryItem] {
        viewModel.items.filter { $0.kind == .music }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Playlists")
                    .font(.title2.bold())
                Spacer()
                Button("Importar...", action: importPlaylist)
                Button("Listo", action: onDismiss)
            }
            .padding()

            if let importSummary {
                Text(importSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            HStack(spacing: 0) {
                playlistList
                    .frame(width: 200)
                Divider()
                if let selectedPlaylistID,
                   let playlist = viewModel.playlists.first(where: { $0.id == selectedPlaylistID }) {
                    PlaylistTrackEditor(viewModel: viewModel, playlist: playlist, musicItems: musicItems)
                } else {
                    VStack {
                        Spacer()
                        Text("Elige o crea una playlist")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(width: 600, height: 420)
        // ST-063: barra de estado -- listas y canciones; la lista abierta.
        .libraryStatus(statusModel.summary)
        .onAppear(perform: refreshStatus)
        .onReceive(viewModel.$playlists) { _ in refreshStatus() }
        .onChange(of: selectedPlaylistID) { refreshStatus() }
        .onChange(of: viewModel.playlists.map(\.id)) { ids in
            if let selectedPlaylistID, !ids.contains(selectedPlaylistID) {
                self.selectedPlaylistID = nil
            }
        }
    }

    private func refreshStatus() {
        let playlists = viewModel.playlists
        statusModel.recomputeTotal { LibraryStats.playlistsTotal(playlists) }
        let selected = playlists.first { $0.id == selectedPlaylistID }
        let items = musicItems
        statusModel.recomputeSelection(cost: selected?.trackItemIDs.count ?? 0) {
            LibraryStats.playlistSelectionText(selected, musicItems: items)
        }
    }

    private func importPlaylist() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.init(filenameExtension: "m3u")!, .init(filenameExtension: "m3u8")!]
        panel.prompt = "Importar"
        panel.message = "Elige una playlist M3U/M3U8 exportada de otro programa o servicio."
        guard panel.runModal() == .OK, let fileURL = panel.url else { return }

        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            importSummary = "No se pudo leer \(fileURL.lastPathComponent)."
            return
        }
        let paths = PlaylistImporter.parseTrackPaths(contents: contents, playlistDirectory: fileURL.deletingLastPathComponent())
        guard !paths.isEmpty else {
            importSummary = "\(fileURL.lastPathComponent) no tiene pistas."
            return
        }
        let name = PlaylistImporter.suggestedName(for: fileURL)
        let result = viewModel.importPlaylist(name: name, trackPaths: paths)
        selectedPlaylistID = result.playlistID
        importSummary = result.unmatchedPaths.isEmpty
            ? "\"\(name)\" importada: \(result.matchedCount) de \(paths.count) pista(s) ligadas."
            : "\"\(name)\" importada: \(result.matchedCount) de \(paths.count) pista(s) ligadas. \(result.unmatchedPaths.count) no están en tu biblioteca Aura todavía -- suéltalas en Música y vuelve a importar para completarlas."
    }

    private var playlistList: some View {
        VStack(alignment: .leading, spacing: 8) {
            List(viewModel.playlists, selection: $selectedPlaylistID) { playlist in
                Text(playlist.name).tag(playlist.id)
            }
            .listStyle(.sidebar)

            HStack {
                TextField("Nueva playlist", text: $newPlaylistName)
                    .textFieldStyle(.roundedBorder)
                Button {
                    let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    selectedPlaylistID = viewModel.addPlaylist(name: name)
                    newPlaylistName = ""
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 8)

            if let selectedPlaylistID {
                Button(role: .destructive) {
                    viewModel.removePlaylist(id: selectedPlaylistID)
                    self.selectedPlaylistID = nil
                } label: {
                    Label("Borrar playlist", systemImage: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .padding(.horizontal, 8)
            }
        }
        .padding(.bottom, 8)
    }
}

private struct PlaylistTrackEditor: View {
    @ObservedObject var viewModel: LibraryViewModel
    let playlist: Playlist
    let musicItems: [LibraryItem]

    private var includedItems: [LibraryItem] {
        playlist.trackItemIDs.compactMap { id in musicItems.first { $0.id == id } }
    }

    private var availableItems: [LibraryItem] {
        musicItems.filter { !playlist.trackItemIDs.contains($0.id) }
    }

    /// Preview de la portada elegida a mano (encargo del dueno,
    /// 2026-08-14) -- se relee del disco cada vez que `playlist` cambia,
    /// no se cachea en memoria: es una imagen chica (128px) y esta vista
    /// no se redibuja seguido.
    private var customImage: NSImage? {
        guard let relative = playlist.imageRelativePath else { return nil }
        return NSImage(contentsOf: viewModel.libraryRoot.appendingPathComponent(relative))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Group {
                    if let customImage {
                        Image(nsImage: customImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.15))
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(playlist.name).font(.headline)
                Spacer()
                Button("Elegir imagen...", action: chooseImage)
                if playlist.imageRelativePath != nil {
                    Button("Quitar imagen") { viewModel.clearPlaylistImage(id: playlist.id) }
                }
            }
            .padding([.top, .horizontal])

            Text("En la playlist (\(includedItems.count))")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            List {
                ForEach(Array(includedItems.enumerated()), id: \.element.id) { _, item in
                    HStack {
                        Text(item.metadata?.title ?? item.sourceURL.lastPathComponent)
                        Spacer()
                        Button {
                            viewModel.removeTrack(item.id, fromPlaylist: playlist.id)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onMove { offsets, destination in
                    viewModel.moveTracks(inPlaylist: playlist.id, from: offsets, to: destination)
                }
            }
            .frame(minHeight: 120)

            if !availableItems.isEmpty {
                Text("Agregar")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                List(availableItems) { item in
                    HStack {
                        Text(item.metadata?.title ?? item.sourceURL.lastPathComponent)
                        Spacer()
                        Button {
                            viewModel.addTrack(item.id, toPlaylist: playlist.id)
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(minHeight: 100)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Elegir imagen..." (encargo del dueno, 2026-08-14) -- mismo patron
    /// de NSOpenPanel que `PlaylistsView.importPlaylist()`, filtrado a
    /// imagenes en vez de M3U/M3U8.
    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "Elegir"
        panel.message = "Elige una imagen para esta playlist."
        guard panel.runModal() == .OK, let fileURL = panel.url else { return }
        viewModel.setPlaylistImage(id: playlist.id, sourceURL: fileURL)
    }
}
