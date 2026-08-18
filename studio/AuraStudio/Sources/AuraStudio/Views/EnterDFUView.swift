import SwiftUI

/// Guia visual paso a paso para entrar a modo DFU, con deteccion de
/// estado automatica: apenas `IPodMonitor` confirma modo DFU real (no
/// que el usuario "dice" haberlo hecho), `InstallerViewModel` avanza
/// solo a instalar -- ver la combinacion exacta de botones en el README
/// de mks5lboot (SELECT+MENU ~12s).
struct EnterDFUView: View {
    @ObservedObject var monitor: IPodMonitor
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("Entra a modo DFU")
                .font(.title.bold())

            VStack(alignment: .leading, spacing: 14) {
                DFUStepRow(number: 1, text: "Si tu iPod esta reproduciendo musica, deten la reproduccion.")
                DFUStepRow(number: 2, text: "Manten presionados SELECT + MENU al mismo tiempo.")
                DFUStepRow(number: 3, text: "Segui presionando ambos botones durante unos 12 segundos, hasta despues de que la pantalla se ponga negra.")
                DFUStepRow(number: 4, text: "Soltalos. Aura Studio va a detectar el modo DFU automaticamente.")
            }
            .frame(maxWidth: 460, alignment: .leading)

            statusBadge

            Spacer()

            HStack {
                Button("Atrás", action: onBack)
                    .buttonStyle(.bordered)
                Spacer()
            }
            .frame(maxWidth: 460)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch monitor.state {
        case .dfuMode:
            Label("Modo DFU detectado", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.headline)
        default:
            if let problem = monitor.dfuScannerProblem {
                // ST-018: si la herramienta de deteccion no puede
                // correr, decirlo -- "Esperando modo DFU..." con el
                // iPod ya en DFU era una espera sin salida.
                VStack(spacing: 8) {
                    Label("Aura Studio no puede detectar el modo DFU", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.headline)
                    Text(problem)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                }
            } else {
                Label("Esperando modo DFU...", systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DFUStepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))
            Text(text)
        }
    }
}
