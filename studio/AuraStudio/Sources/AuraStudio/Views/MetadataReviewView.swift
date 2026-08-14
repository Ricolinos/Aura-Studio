import SwiftUI

/// Fase 23 (PLAN-UX.md): pantalla de revision/edicion de metadata --
/// `LibraryViewModel.applyReview(id:metadata:)` ya existia desde antes,
/// pero ninguna vista lo llamaba (un pipeline "arrastra y listo" que
/// nunca dejaba corregir el caso `.needsReview` a mano, salvo borrando
/// el item y arreglando el archivo original fuera de la app).
struct MetadataReviewView: View {
    let item: LibraryItem
    let onSave: (TrackMetadata) -> Void
    let onCancel: () -> Void

    @State private var title: String
    @State private var artist: String
    @State private var album: String
    @State private var albumArtist: String
    @State private var year: String
    @State private var genre: String
    /// Letra sin sincronizar (D-193): el usuario la puede pegar/editar
    /// a mano, sin depender de que LRCLIB tenga una version para esta
    /// cancion. Se guarda como el mismo `syncedLyrics` que ya escribe
    /// `LibraryViewModel.prepareMusic` como sidecar `.lrc` -- el
    /// firmware no distingue si vino de la red o la escribio el usuario.
    @State private var lyrics: String

    init(item: LibraryItem, onSave: @escaping (TrackMetadata) -> Void, onCancel: @escaping () -> Void) {
        self.item = item
        self.onSave = onSave
        self.onCancel = onCancel
        let metadata = item.metadata ?? TrackMetadata()
        _title = State(initialValue: metadata.title ?? "")
        _artist = State(initialValue: metadata.artist ?? "")
        _album = State(initialValue: metadata.album ?? "")
        _albumArtist = State(initialValue: metadata.albumArtist ?? "")
        _year = State(initialValue: metadata.year ?? "")
        _genre = State(initialValue: metadata.genre ?? "")
        _lyrics = State(initialValue: metadata.syncedLyrics ?? "")
    }

    private var isComplete: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !artist.trimmingCharacters(in: .whitespaces).isEmpty
            && !album.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Revisar metadata")
                .font(.title2.bold())
            Text(item.sourceURL.lastPathComponent)
                .font(.callout)
                .foregroundStyle(.secondary)

            Form {
                TextField("Titulo", text: $title)
                TextField("Artista", text: $artist)
                TextField("Album", text: $album)
                TextField("Artista del album (opcional)", text: $albumArtist)
                TextField("Ano (opcional)", text: $year)
                TextField("Genero (opcional)", text: $genre)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Letra (opcional)").font(.callout)
                TextEditor(text: $lyrics)
                    .font(.callout.monospaced())
                    .frame(height: 120)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                Text("Se guarda junto a la canción y se muestra en pantalla mientras suena en el iPod. Puedes pegar una letra con tiempos LRC o texto simple.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !isComplete {
                Label("Titulo, artista y album son obligatorios para sincronizar.", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancelar", action: onCancel)
                Button("Guardar") {
                    var metadata = item.metadata ?? TrackMetadata()
                    metadata.title = title.isEmpty ? nil : title
                    metadata.artist = artist.isEmpty ? nil : artist
                    metadata.album = album.isEmpty ? nil : album
                    metadata.albumArtist = albumArtist.isEmpty ? nil : albumArtist
                    metadata.year = year.isEmpty ? nil : year
                    metadata.genre = genre.isEmpty ? nil : genre
                    let trimmedLyrics = lyrics.trimmingCharacters(in: .whitespacesAndNewlines)
                    metadata.syncedLyrics = trimmedLyrics.isEmpty ? nil : lyrics
                    onSave(metadata)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isComplete)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
