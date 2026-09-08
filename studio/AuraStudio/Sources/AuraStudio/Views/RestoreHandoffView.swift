import SwiftUI
import AppKit

/// Paso final de la restauracion (D-184): Aura Studio ya hizo todo lo
/// que le toca (bootloader de Apple restaurado en la NOR, disco
/// preparado con el doble formateo), pero la restauracion del firmware
/// original la TERMINA Finder -- y para que Finder detecte el iPod sin
/// interferencias, Aura Studio debe cerrarse (su sondeo USB/DFU y el
/// monitoreo de discos compiten con la deteccion de Finder).
struct RestoreHandoffView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text(LS("restore-handoff-view.continua-finder"))
                .font(.title.bold())
            Text(LS("restore-handoff-view.ipod-quedo-listo-se-quito-bootloader"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)

            VStack(alignment: .leading, spacing: 10) {
                HandoffStep(number: 1, text: LS("restore-handoff.step.close-app"))
                HandoffStep(number: 2, text: LS("restore-handoff.step.open-finder"))
                HandoffStep(number: 3, text: LS("restore-handoff.step.restore"))
            }
            .frame(maxWidth: 460, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))

            Button(LS("restore-handoff-view.cerrar-aura-studio-abrir-finder")) {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
                // applicationShouldTerminate (AppDelegate) reactiva los
                // agentes AMP pausados antes de dejar morir el proceso.
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

private struct HandoffStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(LSf("await-bootloader-u-s-b-view.texto", number))
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
