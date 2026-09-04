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
        case .install: return "\(firmwareName) instalado"
        case .restore: return "iPod restaurado"
        // ST-143: no se instaló ni se restauró nada -- solo cambió el
        // arranque, y decirle "restaurado" al usuario sería mentirle.
        case .updateBootloader: return "Arranque actualizado"
        }
    }

    private var doneMessage: String {
        switch (mode, needsManualReboot) {
        case (.restore, _):
            return "Tu iPod va a reiniciar y arrancar con el firmware original de Apple. Ya puedes desconectar el cable."
        case (.install, true):
            return "\(firmwareName) quedó instalado. Ya puedes desconectar el cable con seguridad. El iPod se quedó esperando en \"Bootloader USB mode\": mantén SELECT + MENU unos 5 segundos para reiniciarlo y arranca con \(firmwareName). Después puedes usar la biblioteca de Aura Studio para sincronizar tu música, fotos y videos."
        case (.updateBootloader, _):
            return "El arranque quedó actualizado. Tu música, tus fotos y tus ajustes siguen exactamente donde estaban -- esto no tocó el disco. Ya puedes desconectar el cable; si el iPod no reinicia solo, mantén SELECT + MENU unos segundos."
        case (.install, false):
            return "Todos los archivos quedaron instalados: ya puedes desconectar el cable con seguridad. El iPod va a arrancar con \(firmwareName) -- si no reinicia solo, mantén SELECT + MENU unos segundos. Despues puedes usar la pestana Biblioteca de Aura Studio para sincronizar tu musica, fotos y videos."
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
                    Label("Instalaste en modo dual boot", systemImage: "arrow.triangle.branch")
                        .font(.headline)
                    Text("Para volver a Apple en cualquier momento, mantén SELECT + MENU presionados unos 5 segundos al encender el iPod. Cualquier otra combinacion (o nada) arranca \(firmwareName).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: 420, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
            }

            if mode == .install, assumedBootloaderWithoutVerifying, let onBootloaderMissing {
                VStack(alignment: .leading, spacing: 8) {
                    Label("¿Tu iPod sigue mostrando el firmware original?", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text("Detectamos que el firmware ya había estado instalado antes, así que solo actualizamos los archivos sin volver a grabar el arranque. Si al desconectar el cable tu iPod NO arranca con \(firmwareName), el arranque se perdió desde la instalación anterior y hace falta grabarlo de nuevo por DFU.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("No arrancó con \(firmwareName) -- terminar por DFU", action: onBootloaderMissing)
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
            Text(isCalmDecision ? "Este iPod no está listo para dual boot" : "Algo salio mal")
                .font(.title.bold())
            Text(error?.localizedDescription ?? "Error desconocido.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            if error == .fullDiskAccessDenied {
                Button("Abrir Acceso total al disco") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
            if isCalmDecision, let onSwitchToSingleBoot {
                Button("Instalar solo este firmware en el iPod", action: onSwitchToSingleBoot)
                    .buttonStyle(.borderedProminent)
                Button("Reintentar (ya preparé el iPod con iTunes)", action: onRetry)
                    .buttonStyle(.bordered)
            } else {
                Button("Reintentar", action: onRetry)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
