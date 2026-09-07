import SwiftUI

/// La franja que aparece al pie mientras corre la migración única de
/// carátulas (ST-141). Vive junto a la barra de estado, con la misma
/// altura y el mismo tono secundario, porque es lo mismo que ella: algo
/// que la app cuenta sin interrumpir.
///
/// **No se puede ocultar con "Mostrar barra de estado"** (a diferencia
/// de `LibraryStatusBar`): mientras esto corre hay archivos
/// reescribiéndose y un botón para detenerlos: esconderlo dejaría al
/// usuario sin la única forma de cancelar.
struct CoverNormalizationBar: View {
    let progress: CoverNormalizationProgress
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ProgressView(value: progress.fraction)
                .progressViewStyle(.linear)
                .frame(width: 120)
            Text(progress.label)
                .lineLimit(1)
            Text(LS("cover-normalization-bar.caratulas-tu-biblioteca-pasan-ser-cuadra"))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 8)
            Button(LS("background-task-center-indicator.cancelar"), action: onCancel)
                .buttonStyle(.link)
                .help(LS("cover-normalization-bar.detiene-normalizacion-lo-que-ya-se"))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LSf("cover-normalization-bar.accesibilidad-progreso", progress.completed, progress.total))
    }
}
