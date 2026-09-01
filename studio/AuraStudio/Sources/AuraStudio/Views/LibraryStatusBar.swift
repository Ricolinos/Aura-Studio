import SwiftUI

/// Barra de estado al pie de la sección activa (ST-063), al estilo de
/// la de Finder: una franja angosta, texto secundario, total a la
/// izquierda, selección al centro y dato extra a la derecha. Se dibuja
/// una sola vez en `ContentView` con lo que publique la vista activa
/// vía `.libraryStatus(_:)`; "Visualización › Mostrar barra de estado"
/// (`AppPreferences.showStatusBar`) la oculta por completo.
struct LibraryStatusBar: View {
    let summary: LibraryStatusSummary

    var body: some View {
        HStack(spacing: 12) {
            Text(summary.total)
                .lineLimit(1)
            if let selection = summary.selection {
                Text("—")
                    .foregroundStyle(.tertiary)
                Text(selection)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 8)
            if let trailing = summary.trailing {
                Text(trailing)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Barra de estado")
    }
}
