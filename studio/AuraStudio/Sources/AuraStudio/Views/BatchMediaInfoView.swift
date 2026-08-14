import SwiftUI

/// D-218 (encargo del dueño, con captura de referencia del panel de
/// edición en lote de Música.app): editar varias canciones a la vez
/// desde "Obtener información" del menú contextual, con dos piezas --
/// el aviso previo (`BatchEditWarningSheet`, con "No volver a mostrar")
/// y la ventana de edición en sí (`BatchMediaInfoView`), que muestra
/// "Mixto" en los campos que difieren entre las canciones seleccionadas
/// y dos campos bloqueados a propósito (Título y N.º de pista -- se
/// editan de a una canción, nunca en lote, mismo ejemplo que dio el
/// dueño: "bloqueando atributos importantes, como el nombre de las
/// canciones").
///
/// Solo música: video/fotos no tienen suficientes atributos propios
/// (categoría, ya editable en lote desde "Cambiar categoría" del menú
/// contextual) como para justificar una ventana de lote aparte.

/// Cambios a aplicar sobre todas las canciones seleccionadas -- `nil`
/// en cualquier campo significa "no tocar ese atributo" (la canción se
/// queda con lo que ya tenía). No hay forma de BORRAR un campo en lote
/// a propósito (solo de asignarle un valor real): si quedó "Mixto" y
/// el usuario no escribió nada, ese campo no se toca; vaciar un campo
/// para borrarlo en varias canciones a la vez es un caso raro que
/// habría complicado bastante el modelo para poco beneficio real.
struct BatchMetadataChanges: Equatable {
    var artist: String?
    var album: String?
    var albumArtist: String?
    var year: String?
    var genre: String?
    var composer: String?
    var rating: Int?

    var isEmpty: Bool {
        artist == nil && album == nil && albumArtist == nil
            && year == nil && genre == nil && composer == nil && rating == nil
    }
}

/// Estado de un campo de texto en el formulario de lote: si todas las
/// canciones seleccionadas ya comparten el mismo valor, arranca
/// relleno con ese valor (y cualquier edición se aplica a todas, aunque
/// técnicamente ya coincidían). Si difieren, arranca vacío mostrando
/// "Mixto" como placeholder -- `touched` distingue "el usuario no tocó
/// este campo todavía" (no se aplica nada al guardar) de "el usuario
/// escribió algo, aunque sea para volver a dejarlo vacío por error"
/// (ahí sí se aplica, con el criterio de "vacío = no tocar" de
/// `BatchMetadataChanges`).
private struct BatchField {
    var text: String
    let isMixed: Bool
    var touched: Bool = false

    static func compute(_ items: [LibraryItem], _ keyPath: KeyPath<TrackMetadata, String?>) -> BatchField {
        let values = Set(items.map { ($0.metadata ?? TrackMetadata())[keyPath: keyPath] ?? "" })
        if values.count <= 1 {
            return BatchField(text: values.first ?? "", isMixed: false)
        }
        return BatchField(text: "", isMixed: true)
    }

    /// `nil` = no tocar este campo al aplicar.
    var valueToApply: String? {
        if isMixed {
            return touched && !text.isEmpty ? text : nil
        }
        return text.isEmpty ? nil : text
    }
}

/// Aviso previo -- "¿Quieres editar varios elementos?" con "No volver a
/// mostrar" (persistido en UserDefaults, `MediaSectionView` decide
/// cuándo saltárselo).
struct BatchEditWarningSheet: View {
    let count: Int
    let onCancel: () -> Void
    let onConfirm: (_ suppressFutureWarnings: Bool) -> Void

    @State private var dontShowAgain = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("¿Quieres editar varios elementos?").font(.title3.bold())
            Text("Vas a editar \(count) canciones a la vez. Los campos que no coincidan entre todas se muestran como \"Mixto\" -- lo que escribas se aplica a las \(count). El título y el número de pista no se pueden editar en lote.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("No volver a mostrar", isOn: $dontShowAgain)
            HStack {
                Spacer()
                Button("Cancelar", action: onCancel)
                Button("Editar elementos") { onConfirm(dontShowAgain) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

struct BatchMediaInfoView: View {
    let items: [LibraryItem]
    let onApply: (BatchMetadataChanges) -> Void
    let onCancel: () -> Void

    @State private var artist: BatchField
    @State private var album: BatchField
    @State private var albumArtist: BatchField
    @State private var year: BatchField
    @State private var genre: BatchField
    @State private var composer: BatchField
    /// `nil` = "Mixto"/sin tocar; 0 no es un valor valido para
    /// calificacion aca (a diferencia de `TrackMetadata.rating`, en
    /// lote no hay gesto para "borrar la calificacion de N canciones a
    /// la vez", mismo criterio que el resto de los campos).
    @State private var rating: Int?
    @State private var ratingIsMixed: Bool

    init(items: [LibraryItem], onApply: @escaping (BatchMetadataChanges) -> Void, onCancel: @escaping () -> Void) {
        self.items = items
        self.onApply = onApply
        self.onCancel = onCancel
        _artist = State(initialValue: BatchField.compute(items, \.artist))
        _album = State(initialValue: BatchField.compute(items, \.album))
        _albumArtist = State(initialValue: BatchField.compute(items, \.albumArtist))
        _year = State(initialValue: BatchField.compute(items, \.year))
        _genre = State(initialValue: BatchField.compute(items, \.genre))
        _composer = State(initialValue: BatchField.compute(items, \.composer))
        let ratings = Set(items.map { $0.metadata?.rating ?? 0 })
        _rating = State(initialValue: ratings.count == 1 ? ratings.first : nil)
        _ratingIsMixed = State(initialValue: ratings.count != 1)
    }

    private var titleIsMixed: Bool {
        Set(items.map { $0.metadata?.title ?? $0.sourceURL.deletingPathExtension().lastPathComponent }).count > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ratingSection
                    Divider()
                    lockedFieldsSection
                    Divider()
                    editableFieldsForm
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .frame(width: 460, height: 520)
    }

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                )
                .overlay(
                    // Mismo criterio visual que el mockup de referencia
                    // (borde de color marcando "hay campos mixtos"):
                    // Aura usa el acento de la app en vez del rojo de
                    // Musica.app, para quedarse dentro de su propia
                    // paleta.
                    RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 2)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("\(items.count) canciones seleccionadas").font(.title3.bold())
                Text("Editar varios elementos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
    }

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Calificación").font(.callout)
            HStack(spacing: 8) {
                StarRatingView(rating: Binding(
                    get: { rating ?? 0 },
                    set: { rating = $0; ratingIsMixed = false }
                ))
                if ratingIsMixed {
                    Text("Mixto").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Se aplica a las \(items.count) canciones seleccionadas.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// D-218: "bloqueando atributos importantes, como el nombre de las
    /// canciones" -- Título y N.º de pista se muestran (el dueño pidió
    /// verlos, no ocultarlos) pero deshabilitados: cada canción se
    /// edita de a una desde "Cambiar nombre..."/"Más información...".
    private var lockedFieldsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No editables en lote").font(.callout)
            Form {
                TextField("Título", text: .constant(titleIsMixed ? "" : (items.first?.metadata?.title ?? "")))
                    .disabled(true)
                    .overlay(alignment: .trailing) {
                        if titleIsMixed {
                            Text("Mixto").font(.caption).foregroundStyle(.secondary).padding(.trailing, 6)
                        }
                    }
                TextField("N.º de pista", text: .constant("Distinto por canción"))
                    .disabled(true)
            }
            Text("Se editan de a una canción -- usa \"Cambiar nombre...\" o \"Más información...\" sobre un solo elemento.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var editableFieldsForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Metadata").font(.callout)
            Form {
                batchTextField("Artista", field: $artist)
                batchTextField("Álbum", field: $album)
                batchTextField("Artista del álbum", field: $albumArtist)
                batchTextField("Año", field: $year)
                batchTextField("Género", field: $genre)
                batchTextField("Autor", field: $composer)
            }
        }
    }

    private func batchTextField(_ label: String, field: Binding<BatchField>) -> some View {
        TextField(field.wrappedValue.isMixed && !field.wrappedValue.touched ? "Mixto" : label,
                  text: Binding(
                    get: { field.wrappedValue.text },
                    set: { field.wrappedValue.text = $0; field.wrappedValue.touched = true }
                  ))
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancelar", action: onCancel)
            Button("Editar elementos") {
                var changes = BatchMetadataChanges()
                changes.artist = artist.valueToApply
                changes.album = album.valueToApply
                changes.albumArtist = albumArtist.valueToApply
                changes.year = year.valueToApply
                changes.genre = genre.valueToApply
                changes.composer = composer.valueToApply
                changes.rating = ratingIsMixed ? nil : rating
                onApply(changes)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }
}
