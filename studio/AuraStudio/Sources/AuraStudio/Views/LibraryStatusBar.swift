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
        // ST-188: la prueba de interfaz lee acá cuántos hay
        // seleccionados -- es la forma de comprobar un arrastre sin
        // meterse en el estado interno de la vista.
        .accessibilityIdentifier(UITestEnvironment.ID.statusBar)
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

/// PLAN-studio-rendimiento-2.md Fase 1, addendum (ST-181): el puente
/// entre un `GridStatusModel` y `.libraryStatus(_:)`, en una vista de
/// tamaño cero.
///
/// Existe por el mismo motivo que `LibraryStatusBarHost`: si la vista de
/// sección observara su propio modelo de resumen (`@StateObject`),
/// publicar el resumen la invalidaría entera, y cada clic costaría DOS
/// pasadas de `body` -- una por el cambio de selección y otra por el
/// resumen que ese cambio produce. La sección guarda el modelo en un
/// `@State` (que no suscribe) y pone esto de fondo: el único que se
/// reevalúa al cambiar el resumen es este `Color.clear`.
struct LibraryStatusRelay: View {
    @ObservedObject var model: GridStatusModel

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .libraryStatus(model.summary)
    }
}
