import SwiftUI

struct DoneView: View {
    let mode: InstallerMode

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text(mode == .install ? "Aura instalado" : "iPod restaurado")
                .font(.title.bold())
            Text(mode == .install
                 ? "Tu iPod va a reiniciar y arrancar con Aura. Ahora podes usar la pestana Biblioteca de Aura Studio para sincronizar tu musica, fotos y videos."
                 : "Tu iPod va a reiniciar y arrancar con el firmware original de Apple.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
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
                .frame(maxWidth: 420)
            Button("Reintentar", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
    }
}
