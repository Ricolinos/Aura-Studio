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

            Text("Actualizar el arranque")
                .font(.largeTitle.bold())

            Text(reasonText)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)

            VStack(alignment: .leading, spacing: 14) {
                point("questionmark.circle",
                      "Qué es el arranque",
                      "El programa diminuto que corre apenas enciendes el iPod, antes que \(firmwareName): dibuja la pantalla de arranque y decide qué sistema iniciar. Vive en un chip aparte, no en el disco.")
                point("cable.connector",
                      "Por qué hace falta el modo DFU",
                      "Ese chip solo se puede escribir con el iPod en modo DFU. Es el mismo paso que hiciste al instalar; la app te va a guiar y son unos segundos.")
                point("music.note.list",
                      "Qué no se toca",
                      "Nada del disco: tu música, tus fotos, tus listas y tus ajustes se quedan exactamente como están. No se formatea ni se copia ningún archivo.")
                point("checkmark.shield",
                      "No es obligatorio",
                      "\(firmwareName) funciona igual con el arranque que ya tienes: lo único que cambia es la pantalla que ves al encender.")
            }
            .frame(maxWidth: 460, alignment: .leading)

            BackContinueRow(onBack: onBack, continueTitle: "Actualizar el arranque",
                            onContinue: onContinue)
                .frame(maxWidth: 460)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var reasonText: String {
        switch reason {
        case .differentBootloader:
            return "Esta versión de Aura Studio trae un arranque más nuevo que el que tiene grabado tu iPod."
        case .unknownBootloader:
            return "Aura Studio no sabe qué versión del arranque tiene grabada tu iPod -- lo instaló otra computadora, o una versión anterior de esta app que no lo anotaba. Actualizarlo lo deja al día; si ya lo estaba, no cambia nada."
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
