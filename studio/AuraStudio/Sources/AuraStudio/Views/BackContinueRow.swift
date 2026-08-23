import SwiftUI

/// Fila reutilizable de "Atras"/"Continuar" para los pasos del
/// asistente donde todavia no arranco ninguna escritura real (una vez
/// que empieza a instalar/formatear/copiar, no hay forma segura de
/// "volver", asi que esos pasos no usan esto).
struct BackContinueRow: View {
    let onBack: () -> Void
    let continueTitle: String
    let onContinue: () -> Void
    /// ST-050: "Continuar" bloqueado hasta que el paso cumpla su
    /// condicion (la Bienvenida exige reconocer que el arranque de Apple
    /// se borra).
    var continueDisabled: Bool = false

    var body: some View {
        HStack {
            Button("Atrás", action: onBack)
                .buttonStyle(.bordered)
            Spacer()
            Button(continueTitle, action: onContinue)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(continueDisabled)
        }
    }
}
