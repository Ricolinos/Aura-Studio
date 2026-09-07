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

            Text(LS("detect-device-view.buscando-tu-ipod"))
                .font(.title.bold())

            statusText
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)

            Spacer()

            HStack {
                Button(LS("back-continue-row.atras"), action: onBack)
                    .buttonStyle(.bordered)
                Spacer()
                Button(LS("detect-device-view.ya-lo-conecte-continuar-igual")) {
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
            Text(LS("detect-device-view.conecta-tu-ipod-classic-6g-este"))
        case .diskMode(let info) where !info.isFAT32:
            Text(LSf("detect-device-view.encontramos-con-firmware-original-apple", info.volumeName))
        case .diskModeNoFilesystem:
            Text(LS("detect-device-view.encontramos-tu-ipod-pero-su-disco"))
        case .diskMode(let info):
            Text(LSf("detect-device-view.encontramos-preparando-siguiente-paso", info.volumeName))
        case .dfuMode:
            Text(LS("detect-device-view.tu-ipod-ya-esta-modo-dfu"))
        case .unknown:
            Text(LS("detect-device-view.encontramos-dispositivo-apple-pero-no-pu"))
        }
    }
}
