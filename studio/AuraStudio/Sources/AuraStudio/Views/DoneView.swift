import SwiftUI
import AppKit

struct DoneView: View {
    let mode: InstallerMode
    /// Solo relevante en modo instalar -- si se eligio dual boot en
    /// `BootModeView`, el usuario necesita saber la combinacion de
    /// botones para volver a Apple alguna vez.
    let dualBoot: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text(mode == .install ? "Aura instalado" : "iPod restaurado")
                .font(.title.bold())
            Text(mode == .install
                 ? "Todos los archivos quedaron instalados: ya puedes desconectar el cable con seguridad. El iPod va a arrancar con Aura -- si no reinicia solo, mantén SELECT + MENU unos segundos. Despues puedes usar la pestana Biblioteca de Aura Studio para sincronizar tu musica, fotos y videos."
                 : "Tu iPod va a reiniciar y arrancar con el firmware original de Apple. Ya puedes desconectar el cable.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)

            if mode == .install && dualBoot {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Instalaste en modo dual boot", systemImage: "arrow.triangle.branch")
                        .font(.headline)
                    Text("Para volver a Apple en cualquier momento, mantén SELECT + MENU presionados unos 5 segundos al encender el iPod. Cualquier otra combinacion (o nada) arranca Aura.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: 420, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
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
                Button("Instalar solo Aura en este iPod", action: onSwitchToSingleBoot)
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
