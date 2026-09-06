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

/// PLAN-studio-rendimiento-2.md Fase 1 (ST-181): el único observador del
/// `LibraryStatusCenter`. Existe para que publicar un resumen invalide
/// esta franja de 24 pt y NADA más -- si `ContentView` observara el
/// centro, cada cambio de selección volvería a evaluar la ventana
/// entera, que es justo lo que se quitó al eliminar el
/// `onPreferenceChange` (diagnóstico §0.3).
struct LibraryStatusBarHost: View {
    @ObservedObject var center: LibraryStatusCenter

    var body: some View {
        if let summary = center.summary {
            LibraryStatusBar(summary: summary)
        }
    }
}
