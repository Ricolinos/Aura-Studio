import SwiftUI

/// Fila reutilizable de "Atras"/"Continuar" para los pasos del
/// asistente donde todavia no arranco ninguna escritura real (una vez
/// que empieza a instalar/formatear/copiar, no hay forma segura de
/// "volver", asi que esos pasos no usan esto).
struct BackContinueRow: View {
    let onBack: () -> Void
    let continueTitle: String
    let onContinue: () -> Void

    var body: some View {
        HStack {
            Button("Atrás", action: onBack)
                .buttonStyle(.bordered)
            Spacer()
            Button(continueTitle, action: onContinue)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}
