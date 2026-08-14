import SwiftUI

/// D-199 (encargo del dueño): "Más información..." del menú contextual
/// de la biblioteca -- a diferencia del "Editar" rápido (D-193), esto
/// muestra TODOS los atributos del elemento: metadata completa, datos
/// del archivo en disco, categoría (fotos/video) y -- solo música -- la
/// calificación de estrellas que se sincroniza con el iPod. Reemplaza
/// a `MetadataReviewView` como superconjunto de lo mismo.
struct MediaInfoView: View {
    let item: LibraryItem
    /// Solo no-nil para fotos/video (D-192). Foto: colecciones libres de
    /// `AppPreferences.photoCollections` (D-228); video: los 3 nombres
    /// fijos de `MediaCategory`.
    var availableCategories: [String]?
    var onCategoryChanged: (String) -> Void = { _ in }
    var onRatingChanged: (Int?) -> Void = { _ in }
    let onSave: (TrackMetadata) -> Void
    let onCancel: () -> Void

    @State private var title: String
    @State private var artist: String
    @State private var album: String
    @State private var albumArtist: String
    @State private var year: String
    @State private var genre: String
    @State private var trackNumber: String
    /// Letra sin sincronizar (D-193): el usuario la puede pegar/editar a
    /// mano. Se guarda como el mismo `syncedLyrics` que ya escribe
    /// `LibraryViewModel.prepareMusic` como sidecar `.lrc`.
    @State private var lyrics: String
    @State private var rating: Int

    init(item: LibraryItem, availableCategories: [String]? = nil,
         onCategoryChanged: @escaping (String) -> Void = { _ in },
         onRatingChanged: @escaping (Int?) -> Void = { _ in },
         onSave: @escaping (TrackMetadata) -> Void, onCancel: @escaping () -> Void) {
        self.item = item
        self.availableCategories = availableCategories
        self.onCategoryChanged = onCategoryChanged
        self.onRatingChanged = onRatingChanged
        self.onSave = onSave
        self.onCancel = onCancel
        let metadata = item.metadata ?? TrackMetadata()
        _title = State(initialValue: metadata.title ?? "")
        _artist = State(initialValue: metadata.artist ?? "")
        _album = State(initialValue: metadata.album ?? "")
        _albumArtist = State(initialValue: metadata.albumArtist ?? "")
        _year = State(initialValue: metadata.year ?? "")
        _genre = State(initialValue: metadata.genre ?? "")
        _trackNumber = State(initialValue: metadata.trackNumber.map(String.init) ?? "")
        _lyrics = State(initialValue: metadata.syncedLyrics ?? "")
        _rating = State(initialValue: metadata.rating ?? 0)
    }

    private var isComplete: Bool {
        guard item.kind == .music else { return true }
        return !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !artist.trimmingCharacters(in: .whitespaces).isEmpty
            && !album.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if item.kind == .music {
                        ratingSection
                        Divider()
                        metadataForm
                        Divider()
                        lyricsSection
                    }
                    if let availableCategories {
                        Divider()
                        categorySection(availableCategories)
                    }
                    Divider()
                    fileSection
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .frame(width: 460, height: 560)
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let cover = item.metadata?.coverArtData, let image = NSImage(data: cover) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: symbolName).foregroundStyle(.secondary))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Más información").font(.title3.bold())
                Text(item.sourceURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(16)
    }

    private var symbolName: String {
        switch item.kind {
        case .music: return "music.note"
        case .video: return "play.rectangle"
        case .photo: return "photo"
        case .unsupported: return "questionmark"
        }
    }

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Calificación").font(.callout)
            StarRatingView(rating: $rating)
            Text("Se sincroniza con el iPod: la misma calificación que se elige acá o en \"Ahora suena\" del aparato.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var metadataForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Metadata").font(.callout)
            Form {
                TextField("Título", text: $title)
                TextField("Artista", text: $artist)
                TextField("Álbum", text: $album)
                TextField("Artista del álbum (opcional)", text: $albumArtist)
                TextField("Número de pista (opcional)", text: $trackNumber)
                    .onChange(of: trackNumber) { _, newValue in
                        trackNumber = String(newValue.filter(\.isNumber).prefix(3))
                    }
                TextField("Año (opcional)", text: $year)
                TextField("Género (opcional)", text: $genre)
            }
            if !isComplete {
                Label("Título, artista y álbum son obligatorios para sincronizar.", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var lyricsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Letra (opcional)").font(.callout)
            TextEditor(text: $lyrics)
                .font(.callout.monospaced())
                .frame(height: 100)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            Text("Se guarda junto a la canción y se muestra en pantalla mientras suena en el iPod.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func categorySection(_ categories: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Categoría").font(.callout)
            Picker("Categoría", selection: Binding(
                get: { item.category ?? categories.first ?? "" },
                set: { onCategoryChanged($0) }
            )) {
                ForEach(categories, id: \.self) { category in
                    Text(category).tag(category)
                }
            }
            .labelsHidden()
            .pickerStyle(.radioGroup)
        }
    }

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Archivo").font(.callout)
            infoRow("Ubicación", item.sourceURL.path)
            infoRow("Formato", item.sourceURL.pathExtension.uppercased())
            infoRow("Tamaño", fileSizeText)
            if let duration = item.metadata?.durationSeconds, duration > 0 {
                infoRow("Duración", MediaTableRow(item: item).durationText)
            }
            infoRow("Estado", statusText)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private var fileSizeText: String {
        guard let size = try? FileManager.default.attributesOfItem(atPath: item.sourceURL.path)[.size] as? Int64 else {
            return "--"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private var statusText: String {
        switch item.status {
        case .queued: return "En cola"
        case .enriching: return "Buscando información..."
        case .transcoding: return "Convirtiendo..."
        case .ready: return "Listo para sincronizar"
        case .needsReview: return "Falta completar información"
        case .failed(let message): return "Error: \(message)"
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancelar", action: onCancel)
            if item.kind == .music {
                Button("Guardar") {
                    var metadata = item.metadata ?? TrackMetadata()
                    metadata.title = title.isEmpty ? nil : title
                    metadata.artist = artist.isEmpty ? nil : artist
                    metadata.album = album.isEmpty ? nil : album
                    metadata.albumArtist = albumArtist.isEmpty ? nil : albumArtist
                    metadata.trackNumber = Int(trackNumber)
                    metadata.year = year.isEmpty ? nil : year
                    metadata.genre = genre.isEmpty ? nil : genre
                    let trimmedLyrics = lyrics.trimmingCharacters(in: .whitespacesAndNewlines)
                    metadata.syncedLyrics = trimmedLyrics.isEmpty ? nil : lyrics
                    let newRating = rating == 0 ? nil : rating
                    if newRating != item.metadata?.rating {
                        onRatingChanged(newRating)
                    }
                    metadata.rating = newRating
                    onSave(metadata)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isComplete)
            } else {
                Button("Listo", action: onCancel)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }
}

/// Cinco estrellas tocables (D-199) -- tocar la N-esima pone la
/// calificacion en N; tocar la ya activa la borra (vuelve a 0, "sin
/// calificar"), mismo gesto que Música.app.
struct StarRatingView: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .foregroundStyle(star <= rating ? .yellow : Color.secondary.opacity(0.5))
                    .onTapGesture {
                        rating = (rating == star) ? 0 : star
                    }
            }
        }
        .font(.title3)
    }
}
