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
    /// ST-053: se pulso "Continuar" sin marcar la casilla. Antes el boton
    /// estaba DESHABILITADO hasta marcarla, y un boton gris que no
    /// responde se lee como "la app se quedo pasmada" (reporte del dueño).
    /// Ahora responde siempre y, si falta la casilla, lo dice.
    @State private var showAcknowledgeHint = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: mode == .install ? "square.and.arrow.down.on.square" : "arrow.uturn.backward.circle")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text(mode == .install
                 ? LSf("welcome.title.install", firmwareName)
                 : LS("welcome.title.restore"))
                .font(.title.bold())

            Text(mode == .install
                 ? LSf("welcome.body.install", firmwareName)
                 : LS("welcome.body.restore"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)

            if mode == .install {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(LSf("welcome-view.firmware-original-apple-se-borra-arranqu", firmwareName))
                            .font(.callout)
                    }
                    Toggle(LS("welcome-view.entiendo-que-arranque-apple-se-borra"), isOn: $acknowledgedErase)
                        .toggleStyle(.checkbox)
                        .onChange(of: acknowledgedErase) { on in
                            if on { showAcknowledgeHint = false }
                        }
                    if showAcknowledgeHint && !acknowledgedErase {
                        Label(LS("welcome-view.marca-casilla-arriba-para-continuar"), systemImage: "arrow.up")
                            .font(.callout.bold())
                            .foregroundStyle(.red)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.red.opacity(0.5), lineWidth: 1))
                .frame(maxWidth: 460)
            }

            Spacer()

            BackContinueRow(onBack: onBack, continueTitle: LS("installer-wizard-view.continuar"), onContinue: {
                if mode == .install && !acknowledgedErase {
                    withAnimation { showAcknowledgeHint = true }
                } else {
                    onContinue()
                }
            })
                .frame(maxWidth: 460)
        }
    }
}
