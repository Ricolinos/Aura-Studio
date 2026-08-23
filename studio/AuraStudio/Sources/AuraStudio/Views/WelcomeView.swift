import SwiftUI

struct WelcomeView: View {
    let mode: InstallerMode
    /// ST-047/ST-050: "Aura" o "Metro", segun lo elegido en Extras.
    var firmwareName: String = "Aura"
    let onBack: () -> Void
    let onContinue: () -> Void

    /// ST-050: la instalacion borra el arranque original de Apple, sin
    /// opcion de conservarlo (ver InstallerViewModel.destroyOriginalFirmware).
    /// Eso antes lo confirmaba la tarjeta "Solo Aura" del paso "Modo de
    /// arranque"; al quitar el paso, la confirmacion explicita vive aqui.
    @State private var acknowledgedErase = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: mode == .install ? "square.and.arrow.down.on.square" : "arrow.uturn.backward.circle")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text(mode == .install ? "Instalar \(firmwareName)" : "Restaurar iPod original")
                .font(.title.bold())

            Text(mode == .install
                 ? "Este asistente va a instalar el bootloader y el firmware \(firmwareName) en tu iPod Classic 6G. Vas a necesitar el dispositivo conectado por USB en los proximos pasos."
                 : "Este asistente va a quitar el bootloader y devolver tu iPod al arranque original de Apple. El firmware no se borra del disco, solo dejas de arrancarlo.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)

            if mode == .install {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text("El firmware original de Apple se borra del arranque del iPod. Una vez instalado, el iPod solo arranca \(firmwareName); para volver a Apple hay que restaurarlo con iTunes/Finder desde cero. (El dual boot necesita un iPod en formato \"winpod\" -- restaurado desde Windows --, y un iPod restaurado desde Mac no lo es, asi que Aura Studio ya no lo ofrece.)")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Toggle("Entiendo que el arranque de Apple se borra", isOn: $acknowledgedErase)
                        .toggleStyle(.checkbox)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.red.opacity(0.5), lineWidth: 1))
                .frame(maxWidth: 460)
            }

            Spacer()

            BackContinueRow(onBack: onBack, continueTitle: "Continuar", onContinue: onContinue,
                            continueDisabled: mode == .install && !acknowledgedErase)
                .frame(maxWidth: 460)
        }
    }
}
