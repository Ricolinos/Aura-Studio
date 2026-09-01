import SwiftUI

/// "Buscar carátulas del álbum" (ST-104): busca varias tapas, las
/// muestra y aplica la que el usuario elija a todas las canciones del
/// álbum.
///
/// Mismo lugar en el flujo que "buscar póster en línea" de Películas y
/// Series, con una diferencia deliberada: el póster se aplica solo
/// porque TMDB identifica la película con bastante certeza, mientras que
/// dos ediciones de un mismo disco tienen tapas distintas y las dos son
/// "correctas". Ahí elegir no es un lujo, es la única forma de acertar,
/// así que esta pantalla nunca aplica nada por su cuenta.
///
/// R2-3 (ST-115) le agregó una **recomendación**: las candidatas vienen
/// ordenadas por puntaje y la primera se marca "Recomendada", con un
/// botón para usarla de una. Sigue sin aplicarse sola: la
/// recomendación acelera la decisión, no la reemplaza.
struct AlbumCoverPickerView: View {
    let request: AlbumCoverRequest
    var search = AlbumCoverSearch()
    let onApply: (Data) -> Void
    let onCancel: () -> Void

    @State private var candidates: [AlbumCoverSearch.Candidate] = []
    @State private var selectedID: AlbumCoverSearch.Candidate.ID?
    @State private var isSearching = true

    private var selectedCandidate: AlbumCoverSearch.Candidate? {
        candidates.first { $0.id == selectedID }
    }

    /// La primera de la lista: `AlbumCoverSearch.candidates` ya devuelve
    /// ordenado por recomendación.
    private var recommended: AlbumCoverSearch.Candidate? { candidates.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 620, height: 560)
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Carátulas para «\(request.albumTitle)»")
                .font(.headline)
            Text([request.albumArtist, request.albumYear].compactMap { $0 }.joined(separator: " · "))
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if isSearching {
            VStack(spacing: 10) {
                ProgressView()
                Text("Buscando carátulas en Cover Art Archive y Deezer...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if candidates.isEmpty {
            // Sin resultados se DICE; no se cierra la ventana sola ni se
            // deja la tapa vieja sin explicación.
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.secondary)
                Text("No se encontraron carátulas para este álbum.")
                    .foregroundStyle(.secondary)
                Text("Revisa que el título y el artista del álbum estén bien escritos; también puedes activar Deezer en Ajustes › Servicios para tener más resultados.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 170), spacing: 18, alignment: .top)],
                          alignment: .leading, spacing: 18) {
                    ForEach(candidates) { candidate in
                        candidateCell(candidate)
                    }
                }
                .padding(20)
            }
        }
    }

    private func candidateCell(_ candidate: AlbumCoverSearch.Candidate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverArtView(data: candidate.data, side: 140)
                .librarySelectionBorder(candidate.id == selectedID)
            if candidate.id == recommended?.id {
                Text("Recomendada")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(AuraColors.light.accent.opacity(0.18)))
                    .foregroundStyle(AuraColors.light.accent)
            }
            Text(candidate.source.displayName)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            if let detail = candidate.detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(width: 140, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { selectedID = candidate.id }
        .onTapGesture(count: 2) { apply(candidate) }
        .help(candidate.detail ?? candidate.source.displayName)
    }

    private var footer: some View {
        HStack {
            Text(request.trackCount == 1
                 ? "Se aplicará a 1 canción del álbum."
                 : "Se aplicará a \(request.trackCount) canciones del álbum.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancelar", role: .cancel, action: onCancel)
                .keyboardShortcut(.cancelAction)
            if let recommended, recommended.id != selectedID {
                Button("Usar recomendada") { apply(recommended) }
            }
            Button("Usar esta carátula") {
                if let selectedCandidate { apply(selectedCandidate) }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selectedCandidate == nil)
        }
        .padding(20)
    }

    private func apply(_ candidate: AlbumCoverSearch.Candidate) {
        onApply(candidate.data)
    }

    private func load() async {
        isSearching = true
        candidates = await search.candidates(
            for: AlbumCoverScoring.AlbumFacts(title: request.albumTitle,
                                              year: request.albumYear,
                                              trackCount: request.trackCount),
            artist: request.albumArtist)
        // Se preselecciona la RECOMENDADA para que "Usar esta carátula"
        // haga lo correcto de entrada, pero nunca se aplica sola.
        selectedID = candidates.first?.id
        isSearching = false
    }
}

/// Lo que hace falta para abrir `AlbumCoverPickerView` desde un menú
/// contextual: de qué álbum se buscan tapas y a qué canciones se aplica
/// la elegida. `Identifiable` para poder presentarlo con
/// `.sheet(item:)`, como el resto de las hojas de la biblioteca.
struct AlbumCoverRequest: Identifiable, Equatable {
    let id = UUID()
    let albumTitle: String
    let albumArtist: String
    /// Año y número de pistas del álbum EN LA BIBLIOTECA: es contra
    /// esto que se puntúa cada edición (R2-3, ver
    /// `docs/caratula-recomendada.md`).
    let albumYear: String?
    let trackIDs: Set<UUID>

    var trackCount: Int { trackIDs.count }

    /// El pedido para `selection`, o `nil` si no hay UN álbum que buscar.
    ///
    /// R2-2: la condición es que la selección **resuelva a exactamente
    /// un álbum**, no que traiga un solo elemento. Tres canciones del
    /// mismo disco son un álbum y la acción tiene todo el sentido; dos
    /// discos distintos no son ninguno (¿la tapa de cuál?) y aplicar una
    /// sola imagen a los dos sería lo contrario de lo pedido. Tampoco se
    /// busca para "Sin álbum", que no es un disco sino el cajón de lo
    /// que no tiene uno.
    ///
    /// Quien resuelve es `LibraryGrouping.albums(from:)`, el MISMO
    /// agrupador que pinta la vista Álbumes -- así "un álbum" significa
    /// aquí exactamente lo que el usuario ve como un álbum, con la
    /// homologación de artistas de R2-4 incluida.
    ///
    /// `library` sirve para APLICAR la tapa al álbum completo aunque la
    /// selección traiga solo unas pistas: una carátula de álbum a medias
    /// no es una carátula de álbum. Sin `library` se queda con lo
    /// seleccionado.
    static func forAlbum(of selection: [LibraryItem],
                         in library: [LibraryItem]? = nil,
                         options: ArtistGroupingOptions = .default) -> AlbumCoverRequest? {
        let groups = LibraryGrouping.albums(from: selection, options: options)
        guard groups.count == 1, let group = groups.first, !group.isUnknown else { return nil }

        let scope = library ?? selection
        let songs = scope.filter {
            $0.kind == .music && LibraryGrouping.albumKey(of: $0, options: options) == group.id
        }
        let resolved = songs.isEmpty ? group.items : songs
        guard !resolved.isEmpty else { return nil }

        return AlbumCoverRequest(
            albumTitle: group.title,
            albumArtist: group.artist,
            albumYear: group.year,
            trackIDs: Set(resolved.map(\.id)))
    }
}
