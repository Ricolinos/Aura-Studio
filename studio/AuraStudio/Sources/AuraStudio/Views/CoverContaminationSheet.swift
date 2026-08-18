import SwiftUI
import AppKit

/// ST-012: revision de las entradas de Imagenes que parecen caratulas de
/// album importadas por el filtro viejo (por extension). Lista con vista
/// previa, marcadas por defecto solo las de evidencia fuerte; el boton
/// "Quitar de Imagenes" quita la ENTRADA de la biblioteca (nunca borra el
/// archivo original del usuario). Nunca hay borrado silencioso: sin esta
/// hoja no pasa nada.
struct CoverContaminationSheet: View {
    @ObservedObject var library: LibraryViewModel
    let onDismiss: () -> Void

    @State private var candidates: [LibraryViewModel.CoverContaminationCandidate] = []
    @State private var selection = Set<UUID>()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Carátulas en Imágenes")
                    .font(.title3.bold())
                Spacer()
                Button("Cerrar", action: onDismiss)
            }
            .padding()

            Text("Estas imágenes entraron a Imágenes por su extensión, pero parecen carátulas de álbum (por su nombre, o porque viven junto a canciones o videos). Revísalas: las que quites dejan de ser fotos de tu biblioteca; el archivo original en tu Mac no se toca. Si dudas, déjala.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 8)

            List(candidates, selection: $selection) { candidate in
                HStack(spacing: 12) {
                    Thumbnail(url: candidate.item.sourceURL)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.item.sourceURL.lastPathComponent)
                        Text(candidate.item.sourceURL.deletingLastPathComponent().path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Text(candidate.strong ? "Junto a música o video" : "Solo por el nombre")
                        .font(.caption)
                        .foregroundStyle(candidate.strong ? .primary : .secondary)
                }
                .padding(.vertical, 2)
            }

            HStack {
                Button("Quitar de Imágenes") {
                    library.removeFromImages(ids: selection)
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selection.isEmpty)
                Button("Dejar todo como está") {
                    library.dismissCoverContaminationOffer()
                    onDismiss()
                }
                Spacer()
                Text("\(selection.count) de \(candidates.count) seleccionadas")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .frame(width: 560, height: 440)
        .onAppear {
            candidates = library.coverContaminationCandidates()
            // Conservador: preseleccionadas solo las de evidencia fuerte.
            selection = Set(candidates.filter(\.strong).map(\.id))
        }
    }

    private struct Thumbnail: View {
        let url: URL
        @State private var image: NSImage?

        var body: some View {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(Color.secondary.opacity(0.15))
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .task {
                // Carga perezosa fuera del hilo principal: puede haber
                // decenas de candidatas.
                let loaded = await Task.detached(priority: .utility) { NSImage(contentsOf: url) }.value
                image = loaded
            }
        }
    }
}
