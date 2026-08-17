import SwiftUI

/// Seccion Extras: lo que el firmware ofrece mas alla de la biblioteca
/// (juegos, temas, utilidades).
///
/// Hoy esta deliberadamente casi vacia y lo dice de frente en vez de
/// inventar filas: los juegos y el cronometro se decidieron NO
/// implementar (D-063) y los temas son dos, fijos, que se eligen en el
/// propio dispositivo. A medida que el firmware gane extras reales, cada
/// uno aparece aca -- pero la seccion no va a mostrar nada que el
/// dispositivo no tenga de verdad.
struct ExtrasView: View {
    let device: AuraDevice?
    @State private var showingThemes = false

    /// D-289 / ST-003: "Temas" ahora abre la gestión real (instalar,
    /// activar, eliminar, construir) -- necesita un iPod con Aura
    /// montado, mismo criterio que el resto de las acciones que
    /// escriben en el dispositivo.
    private var canManageThemes: Bool {
        guard let device else { return false }
        return device.isAura
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                available
                Divider()
                planned
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .navigationTitle("Extras")
        .sheet(isPresented: $showingThemes) {
            if let device, device.isAura {
                ThemesView(mountPath: device.mountPath)
            }
        }
    }

    private var available: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Disponible en el dispositivo").font(.headline)
            Button {
                showingThemes = true
            } label: {
                row("Temas", "circle.lefthalf.filled",
                    canManageThemes
                        ? "Tema integrado (Claro/Oscuro) más los que instales -- Ajustes > Estilo, en el iPod."
                        : "Conecta tu iPod con Aura instalado para instalar, activar o construir temas.")
            }
            .buttonStyle(.plain)
            .disabled(!canManageThemes)
            row("Animaciones y graficos", "wand.and.rays",
                "Tres niveles cada uno. Se eligen en Ajustes, en el iPod.")
        }
    }

    private var planned: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Todavia no").font(.headline)
            Text("Estos extras del iPod original no estan implementados en Aura. Cuando existan, se van a poder gestionar desde aca.")
                .font(.callout)
                .foregroundStyle(.secondary)
            row("Juegos", "gamecontroller",
                "No implementados.", muted: true)
            row("Cronometro y bloqueo de pantalla", "stopwatch",
                "No implementados.", muted: true)
        }
    }

    private func row(_ title: String, _ symbol: String, _ detail: String,
                     muted: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(muted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(muted ? .secondary : .primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
