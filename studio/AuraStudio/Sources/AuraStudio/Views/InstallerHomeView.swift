import SwiftUI

/// Elegir entre Instalar y Restaurar lanza el mismo asistente
/// (`InstallerViewModel`) en el modo correspondiente -- ambos flujos
/// comparten deteccion, guia DFU y verificacion, solo cambia el
/// comando final que se le manda a mks5lboot.
struct InstallerHomeView: View {
    @StateObject private var viewModel = InstallerViewModel()
    @State private var chosenMode: InstallerMode?

    var body: some View {
        Group {
            if let chosenMode {
                InstallerWizardView(viewModel: viewModel)
                    .onAppear {
                        viewModel.onExitToModePicker = { self.chosenMode = nil }
                        viewModel.start(mode: chosenMode)
                    }
            } else {
                ModePickerView { mode in
                    chosenMode = mode
                }
            }
        }
        .animation(.default, value: chosenMode)
    }
}

struct ModePickerView: View {
    let onChoose: (InstallerMode) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "ipod")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Aura Studio")
                .font(.largeTitle.bold())
            Text("Instala el firmware Aura en tu iPod Classic 6G, o restaura el firmware original si quieres volver atras.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)

            HStack(spacing: 16) {
                Button {
                    onChoose(.install)
                } label: {
                    Label("Instalar Aura", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    onChoose(.restore)
                } label: {
                    Label("Restaurar iPod original", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .frame(maxWidth: 420)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ModePickerView(onChoose: { _ in })
}
