import SwiftUI

/// Espera a que `IPodMonitor` detecte el iPod conectado en modo disco,
/// y muestra en vivo lo que va encontrando -- incluyendo el caso de
/// error real (formato incorrecto) en vez de quedarse tildado.
struct DetectDeviceView: View {
    @ObservedObject var monitor: IPodMonitor
    let onReadyForDFU: () -> Void

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

            Button("Ya lo conecte, continuar igual") {
                onReadyForDFU()
            }
            .buttonStyle(.bordered)
        }
        .onChange(of: monitor.state) { newValue in
            if case .diskMode(let info) = newValue, info.isFAT32 {
                onReadyForDFU()
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch monitor.state {
        case .diskMode(let info) where !info.isFAT32:
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
            Text("Conecta tu iPod Classic 6G a este Mac por USB. Si iTunes/Music se abre solo, podes cerrarlo -- no interfiere con Aura Studio.")
        case .diskMode(let info) where !info.isFAT32:
            Text("Encontramos \"\(info.volumeName)\", pero no esta formateado en FAT32. Convertilo a FAT32 antes de continuar (busca \"iPod FAT32\" en la guia de Aura para los pasos exactos).")
        case .diskMode(let info):
            Text("Encontramos \"\(info.volumeName)\". Preparando el siguiente paso...")
        case .dfuMode:
            Text("Tu iPod ya esta en modo DFU.")
        case .unknown:
            Text("Encontramos un dispositivo Apple, pero no pudimos confirmar que sea un iPod Classic 6G.")
        }
    }
}
