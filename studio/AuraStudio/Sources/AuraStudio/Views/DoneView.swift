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

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.red)
            Text("Algo salio mal")
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
            Button("Reintentar", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
    }
}
