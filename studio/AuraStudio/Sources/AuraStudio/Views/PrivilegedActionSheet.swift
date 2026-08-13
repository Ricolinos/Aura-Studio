import SwiftUI

/// Se muestra SIEMPRE antes de disparar el dialogo nativo de
/// autorizacion de administrador de macOS -- nunca se le pide la
/// contraseña al usuario sin explicarle antes, en español simple, que
/// se va a hacer, por que hace falta, y que pasa si cancela.
struct PrivilegedActionSheet: View {
    let authorization: PendingAuthorization
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(authorization.explanationTitle, systemImage: "lock.shield")
                .font(.title2.bold())

            Text(authorization.explanationBody)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Si cancelas:").font(.callout.bold())
                Text(authorization.cancelConsequence)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack {
                Button("Cancelar", role: .cancel, action: onCancel)
                Spacer()
                Button("Continuar") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 440)
    }
}
