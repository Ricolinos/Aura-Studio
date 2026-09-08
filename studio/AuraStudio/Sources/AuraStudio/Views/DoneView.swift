import SwiftUI
import AppKit

struct DoneView: View {
    let mode: InstallerMode
    /// ST-047/ST-052: "Aura" o "Metro" -- lo que se acaba de instalar.
    var firmwareName: String = "Aura"
    /// Solo relevante en modo instalar -- si se eligio dual boot en
    /// `BootModeView`, el usuario necesita saber la combinacion de
    /// botones para volver a Apple alguna vez.
    let dualBoot: Bool
    /// D-273: true cuando este "Listo" viene de la ruta rapida sin DFU
    /// (`InstallerViewModel.bootloaderAlreadyInstalled`) -- ahi solo
    /// hay EVIDENCIA de que el bootloader se grabo alguna vez (archivos
    /// en el disco), no confirmacion de que sigue en la NOR ahora mismo
    /// (eso no se puede leer desde modo disco). Caso real en hardware:
    /// esa evidencia quedo obsoleta -- el bootloader se perdio despues
    /// de la instalacion original -- y el iPod siguio arrancando con
    /// Apple aunque los archivos SI se copiaron bien. `onBootloaderMissing`
    /// deja al usuario terminar el trabajo por DFU sin reiniciar todo
    /// el asistente.
    var assumedBootloaderWithoutVerifying: Bool = false
    var onBootloaderMissing: (() -> Void)? = nil
    /// ST-017 (Solo Aura): los archivos se copiaron via el "Bootloader
    /// USB mode"; al expulsar el disco el bootloader queda mostrando
    /// "Hold MENU+SELECT to reboot" -- NO reinicia solo, hay que decirlo.
    var needsManualReboot: Bool = false

    private var doneTitle: String {
        switch mode {
        case .install: return LSf("done.title.install", firmwareName)
        case .restore: return LS("done.title.restore")
        // ST-143: no se instaló ni se restauró nada -- solo cambió el
        // arranque, y decirle "restaurado" al usuario sería mentirle.
        case .updateBootloader: return LS("done.title.update-bootloader")
        }
    }

    private var doneMessage: String {
        switch (mode, needsManualReboot) {
        case (.restore, _):
            return LS("done.message.restore")
        case (.install, true):
            return LSf("done.message.install-manual-reboot", firmwareName)
        case (.updateBootloader, _):
            return LS("done.message.update-bootloader")
        case (.install, false):
            return LSf("done.message.install", firmwareName)
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text(doneTitle)
                .font(.title.bold())
            Text(doneMessage)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)

            if mode == .install && dualBoot {
                VStack(alignment: .leading, spacing: 6) {
                    Label(LS("done-view.instalaste-modo-dual-boot"), systemImage: "arrow.triangle.branch")
                        .font(.headline)
                    Text(LSf("done-view.para-volver-apple-cualquier-momento-mant", firmwareName))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: 420, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
            }

            if mode == .install, assumedBootloaderWithoutVerifying, let onBootloaderMissing {
                VStack(alignment: .leading, spacing: 8) {
                    Label(LS("done-view.tu-ipod-sigue-mostrando-firmware-origina"), systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text(LSf("done-view.detectamos-que-firmware-ya-habia-estado", firmwareName))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button(LSf("done-view.no-arranco-con-terminar-por-dfu", firmwareName), action: onBootloaderMissing)
                        .buttonStyle(.bordered)
                }
                .padding(14)
                .frame(maxWidth: 420, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.1)))
            }
        }
    }
}

struct FailedView: View {
    let error: InstallerError?
    let onRetry: () -> Void
    /// Solo se usa cuando `error == .dualBootRequiresWinpod` (D-190):
    /// atajo directo a Solo Aura sin pasar por Modo de arranque a mano.
    var onSwitchToSingleBoot: (() -> Void)? = nil

    /// El disco no tiene una estructura compatible con dual boot NO es
    /// una falla de la app -- es una decision que depende de como esta
    /// preparado el iPod, y no hay nada seguro que formatear ahi (D-190:
    /// formatear a ciegas destruiria la particion de firmware de Apple
    /// en un winpod real, o produciria un dual boot que aparenta
    /// funcionar pero nunca arranca Apple, porque esa particion la
    /// puede escribir de verdad unicamente iTunes). Por eso, a
    /// diferencia de una instalacion normal, este caso NO pide la misma
    /// autorizacion de administrador que "Solo Aura" -- no es una falla
    /// del boton, es que no hay nada que autorizar todavia.
    private var isCalmDecision: Bool { error == .dualBootRequiresWinpod }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: isCalmDecision ? "arrow.triangle.branch" : "xmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(isCalmDecision ? Color.accentColor : Color.red)
            Text(isCalmDecision
                 ? LS("done.failure.title.not-ready")
                 : LS("done.failure.title.generic"))
                .font(.title.bold())
            Text(error?.localizedDescription ?? LS("done.failure.unknown-error"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            if error == .fullDiskAccessDenied {
                Button(LS("done-view.abrir-acceso-total-al-disco")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
            if isCalmDecision, let onSwitchToSingleBoot {
                Button(LS("done-view.instalar-solo-este-firmware-ipod"), action: onSwitchToSingleBoot)
                    .buttonStyle(.borderedProminent)
                Button(LS("done-view.reintentar-ya-prepare-ipod-con-itunes"), action: onRetry)
                    .buttonStyle(.bordered)
            } else {
                Button(LS("done-view.reintentar"), action: onRetry)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
