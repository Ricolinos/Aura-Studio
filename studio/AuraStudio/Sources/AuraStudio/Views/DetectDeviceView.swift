import SwiftUI

/// Espera a que `IPodMonitor` detecte el iPod conectado en modo disco,
/// y muestra en vivo lo que va encontrando -- incluyendo el caso de
/// error real (formato incorrecto) en vez de quedarse tildado.
struct DetectDeviceView: View {
    @ObservedObject var monitor: IPodMonitor
    let onBack: () -> Void
    let onDeviceReady: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            statusIcon
                .font(.system(size: 48))

            Text("Buscando tu iPod...")
                .font(.title.bold())

            statusText
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)

            Spacer()

            HStack {
                Button("Atrás", action: onBack)
                    .buttonStyle(.bordered)
                Spacer()
                Button("Ya lo conecte, continuar igual") {
                    onDeviceReady()
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: 460)
        }
        .onChange(of: monitor.state) { newValue in
            if case .diskMode(let info) = newValue, info.isFAT32 {
                onDeviceReady()
            }
        }
        // ST-052: si el iPod YA estaba conectado en modo disco al llegar a
        // este paso, `onChange` nunca dispara (nada cambia) y el texto
        // "Preparando el siguiente paso..." se quedaba ahi para siempre --
        // el dueño lo vivio como "instalar desde Studio no funciona". El
        // boton "Ya lo conecte, continuar igual" lo destrababa, pero el
        // texto no invitaba a pulsarlo. Mismo criterio que onChange: solo
        // FAT32 montado; los demas estados siguen pidiendo el clic
        // explicito porque implican formatear.
        .onAppear {
            if case .diskMode(let info) = monitor.state, info.isFAT32 {
                onDeviceReady()
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch monitor.state {
        case .diskMode(let info) where !info.isFAT32:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .diskModeNoFilesystem:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .diskMode:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        default:
            ProgressView().controlSize(.large)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch monitor.state {
        case .notConnected, .detecting:
            Text("Conecta tu iPod Classic 6G a este Mac por USB. Si iTunes/Music se abre solo, puedes cerrarlo -- no interfiere con Aura Studio.")
        case .diskMode(let info) where !info.isFAT32:
            Text("Encontramos \"\(info.volumeName)\", con el firmware original de Apple (no esta en FAT32 todavia). No hace falta que lo conviertas: haz clic en \"Ya lo conecte, continuar igual\" y Aura Studio lo formatea automaticamente en el paso de preparar el disco, mas adelante.")
        case .diskModeNoFilesystem:
            Text("Encontramos tu iPod, pero su disco no tiene un sistema de archivos legible (asi se ve en el modo bootloader, o si una instalacion quedo a medias). Haz clic en \"Ya lo conecte, continuar igual\" para prepararlo e instalar Aura.")
        case .diskMode(let info):
            Text("Encontramos \"\(info.volumeName)\". Preparando el siguiente paso...")
        case .dfuMode:
            Text("Tu iPod ya esta en modo DFU.")
        case .unknown:
            Text("Encontramos un dispositivo Apple, pero no pudimos confirmar que sea un iPod Classic 6G.")
        }
    }
}
