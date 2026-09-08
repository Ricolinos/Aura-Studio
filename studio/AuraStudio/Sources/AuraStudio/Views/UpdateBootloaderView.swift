import SwiftUI

/// La pantalla con la que arranca "Actualizar el arranque" (ST-143).
/// Reemplaza a `WelcomeView` cuando el asistente corre en modo
/// `.updateBootloader`.
///
/// Tiene que responder tres cosas antes de que el usuario apriete nada,
/// porque las tres son razonables de preguntarse: **qué es el arranque**
/// (no es el firmware, es lo que se ejecuta antes), **por qué hace falta
/// el modo DFU** (vive en un chip que no se puede escribir de otra
/// forma) y **qué NO se toca** (la música, las fotos, los ajustes: esto
/// no escribe una sola cosa en el disco).
struct UpdateBootloaderView: View {
    let firmwareName: String
    /// Por qué se está ofreciendo. Cambia una frase, no la pantalla.
    let reason: BootloaderUpdate.Reason
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "power.circle")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text(LS("installer-home-view.actualizar-arranque"))
                .font(.largeTitle.bold())

            Text(reasonText)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)

            VStack(alignment: .leading, spacing: 14) {
                point("questionmark.circle",
                      LS("update-bootloader.what-is.title"),
                      LSf("update-bootloader.what-is.body", firmwareName))
                point("cable.connector",
                      LS("update-bootloader.why-dfu.title"),
                      LS("update-bootloader.why-dfu.body"))
                point("music.note.list",
                      LS("update-bootloader.untouched.title"),
                      LS("update-bootloader.untouched.body"))
                point("checkmark.shield",
                      LS("update-bootloader.optional.title"),
                      LSf("update-bootloader.optional.body", firmwareName))
            }
            .frame(maxWidth: 460, alignment: .leading)

            BackContinueRow(onBack: onBack, continueTitle: LS("installer-home-view.actualizar-arranque"),
                            onContinue: onContinue)
                .frame(maxWidth: 460)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var reasonText: String {
        switch reason {
        case .differentBootloader:
            return LS("update-bootloader.reason.newer")
        case .unknownBootloader:
            return LS("update-bootloader.reason.unknown")
        }
    }

    private func point(_ symbol: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(body).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
