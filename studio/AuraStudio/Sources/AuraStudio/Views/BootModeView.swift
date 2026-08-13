import SwiftUI

/// Elegir entre conservar el firmware original de Apple (dual boot) o
/// reemplazarlo por completo. Solo aparece en modo instalar -- restaurar
/// nunca toca esta decision. El bootloader de Aura (`mks5lboot`, ver su
/// README) ya sabe hacer las dos cosas: por defecto instala en modo dual
/// (no requiere ninguna configuracion extra en el dispositivo, el
/// arranque se elige solo con una combinacion de botones al encender) y
/// solo destruye el NOR original de Apple si se le pasa `--single`
/// explicitamente.
struct BootModeView: View {
    let onBack: () -> Void
    let onContinue: (_ dualBoot: Bool) -> Void

    @State private var dualBoot = true

    var body: some View {
        VStack(spacing: 20) {
            Text("Modo de arranque")
                .font(.title.bold())
            Text("Elige que pasa con el firmware original de Apple al instalar Aura.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)

            VStack(spacing: 12) {
                BootModeCard(
                    icon: "arrow.triangle.branch",
                    title: "Dual boot",
                    badge: "Recomendado",
                    explanation: "Conserva el firmware original de Apple junto con Aura. Al encender el iPod, mantén SELECT + MENU presionados unos 5 segundos para arrancar Apple -- cualquier otra combinacion (o nada) arranca Aura. Requiere que el iPod este en formato \"winpod\" (restaurado con iTunes en una PC con Windows): un iPod restaurado desde Mac usa particiones que Rockbox no puede leer, y el asistente se detendra antes de borrar nada si no es compatible.",
                    isSelected: dualBoot,
                    accent: false
                ) { dualBoot = true }

                BootModeCard(
                    icon: "exclamationmark.triangle.fill",
                    title: "Solo Aura",
                    badge: nil,
                    explanation: "Borra el firmware original de Apple del NOR interno del iPod. Una vez instalado, el iPod solo puede arrancar Aura -- no hay forma de volver a Apple sin restaurarlo con iTunes/Finder desde cero. Elige esto solo si estás seguro de que no vas a querer volver.",
                    isSelected: !dualBoot,
                    accent: true
                ) { dualBoot = false }
            }
            .frame(maxWidth: 480)

            Spacer()

            BackContinueRow(onBack: onBack, continueTitle: "Continuar", onContinue: { onContinue(dualBoot) })
                .frame(maxWidth: 480)
        }
    }
}

private struct BootModeCard: View {
    let icon: String
    let title: String
    let badge: String?
    let explanation: String
    let isSelected: Bool
    /// Estilo de advertencia (borde/icono en rojo) para la opcion
    /// destructiva -- coherente con como el resto del asistente marca
    /// cualquier paso que borra datos sin vuelta atras.
    let accent: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(accent ? Color.red : Color.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title).font(.headline)
                        if let badge {
                            Text(badge)
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Text(explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? (accent ? Color.red : Color.accentColor) : Color.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(isSelected ? 0.12 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? (accent ? Color.red : Color.accentColor) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    BootModeView(onBack: {}, onContinue: { _ in })
        .padding(40)
}
