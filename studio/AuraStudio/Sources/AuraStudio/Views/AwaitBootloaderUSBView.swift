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
            Text(LS("await-bootloader-u-s-b-view.arranque-grabado"))
                .font(.title.bold())
            Text(LS("await-bootloader-u-s-b-view.bootloader-aura-ya-esta-tu-ipod"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            VStack(alignment: .leading, spacing: 14) {
                StepRow(number: 1, text: LS("await-bootloader.step.keep-cable"))
                StepRow(number: 2, text: LS("await-bootloader.step.if-black"))
                StepRow(number: 3, text: LS("await-bootloader.step.automatic"))
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
            Label(LS("await-bootloader-u-s-b-view.ipod-aparecio-con-firmware-apple-arranqu"), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.headline)
        case .diskMode:
            Label(LS("await-bootloader-u-s-b-view.disco-detectado-copiando-aura"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.headline)
        case .dfuMode:
            Label(LS("await-bootloader-u-s-b-view.ipod-sigue-dfu-reinicialo-con-select"), systemImage: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
        default:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(LS("await-bootloader-u-s-b-view.esperando-que-ipod-reaparezca-como-disco"))
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
            Text(LSf("await-bootloader-u-s-b-view.texto", number))
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
