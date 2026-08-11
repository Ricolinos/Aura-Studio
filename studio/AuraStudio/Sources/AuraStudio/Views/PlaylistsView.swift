import SwiftUI

/// Fase 24 (PLAN-UX.md): editor de playlists. Arma listas ordenadas a
/// partir de la musica ya agregada en esta sesion (`viewModel.items`) --
/// se resuelven a `.m3u8` recien al sincronizar (`LibrarySync`), asi que
/// esta vista solo maneja el modelo en memoria (`Playlist`), no toca
/// disco.
struct PlaylistsView: View {
    @ObservedObject var viewModel: LibraryViewModel
    let onDismiss: () -> Void

    @State private var newPlaylistName = ""
    @State private var selectedPlaylistID: UUID?

    private var musicItems: [LibraryItem] {
        viewModel.items.filter { $0.kind == .music }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Playlists")
                    .font(.title2.bold())
                Spacer()
                Button("Listo", action: onDismiss)
            }
            .padding()

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
                        Text("Elegi o crea una playlist")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(width: 600, height: 420)
        .onChange(of: viewModel.playlists.map(\.id)) { ids in
            if let selectedPlaylistID, !ids.contains(selectedPlaylistID) {
                self.selectedPlaylistID = nil
            }
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(playlist.name).font(.headline).padding([.top, .horizontal])

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
}
