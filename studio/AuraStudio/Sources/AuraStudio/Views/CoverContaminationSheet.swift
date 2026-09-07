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
                Text(LS("cover-contamination-sheet.caratulas-imagenes"))
                    .font(.title3.bold())
                Spacer()
                Button(LS("cover-contamination-sheet.cerrar"), action: onDismiss)
            }
            .padding()

            Text(LS("cover-contamination-sheet.estas-imagenes-entraron-imagenes-por-su"))
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
                Button(LS("cover-contamination-sheet.quitar-imagenes")) {
                    library.removeFromImages(ids: selection)
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selection.isEmpty)
                Button(LS("cover-contamination-sheet.dejar-todo-como-esta")) {
                    library.dismissCoverContaminationOffer()
                    onDismiss()
                }
                Spacer()
                Text(LSf("cover-contamination-sheet.seleccionadas", selection.count, candidates.count))
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
