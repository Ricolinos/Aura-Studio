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
