import SwiftUI

/// ST-017 (Solo Aura): el bootloader ya quedo grabado por DFU y falta
/// copiar Aura. El iPod se reinicia solo; como todavia no tiene
/// `rockbox.ipod`, su bootloader cae en `fatal_error(ERR_RB)` y entra
/// automaticamente a "Bootloader USB mode" (`bootloader/ipod-s5l87xx.c`),
/// exponiendo el disco por USB con los descriptores de Rockbox. Apenas
/// `IPodMonitor` lo ve montado, `InstallerViewModel` arranca la copia
/// solo -- esta pantalla explica que esperar y que hacer si no aparece.
struct AwaitBootloaderUSBView: View {
    @ObservedObject var monitor: IPodMonitor

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("Arranque grabado")
                .font(.title.bold())
            Text("El bootloader de Aura ya está en tu iPod. Ahora falta copiar Aura al disco.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            VStack(alignment: .leading, spacing: 14) {
                StepRow(number: 1, text: "Deja el cable USB conectado. El iPod se reinicia solo y, como todavía no tiene Aura, su pantalla dice \"Bootloader USB mode\" y aparece como disco.")
                StepRow(number: 2, text: "Si en unos 30 segundos la pantalla del iPod sigue negra o no aparece como disco, mantén SELECT + MENU unos 5 segundos para reiniciarlo, sin desconectar el cable.")
                StepRow(number: 3, text: "Aura Studio detecta el disco y copia Aura automáticamente -- no hay que tocar nada más.")
            }
            .frame(maxWidth: 460, alignment: .leading)

            statusBadge

            Spacer()
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch monitor.state {
        case .diskMode(let info) where info.usb?.runningFirmware == .apple:
            Label("El iPod apareció con el firmware de Apple -- el arranque no se grabó", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.headline)
        case .diskMode:
            Label("Disco detectado -- copiando Aura...", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.headline)
        case .dfuMode:
            Label("El iPod sigue en DFU. Reinícialo con SELECT + MENU.", systemImage: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
        default:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Esperando a que el iPod reaparezca como disco...")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
