import SwiftUI

struct WelcomeView: View {
    let mode: InstallerMode
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: mode == .install ? "square.and.arrow.down.on.square" : "arrow.uturn.backward.circle")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text(mode == .install ? "Instalar Aura" : "Restaurar iPod original")
                .font(.title.bold())

            Text(mode == .install
                 ? "Este asistente va a instalar el bootloader y el firmware de Aura en tu iPod Classic 6G. Vas a necesitar el dispositivo conectado por USB en los proximos pasos."
                 : "Este asistente va a quitar el bootloader de Aura y devolver tu iPod al arranque original de Apple. El firmware de Aura no se borra del disco, solo dejas de arrancarlo.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)

            Spacer()

            BackContinueRow(onBack: onBack, continueTitle: "Continuar", onContinue: onContinue)
                .frame(maxWidth: 460)
        }
    }
}
