import SwiftUI

/// Recorrido de instalacion automatica a pantalla completa (D-183):
/// cuando el monitor detecta el iPod en modo bootloader (el disco
/// expuesto por el bootloader de Aura/Rockbox, sin volumen montable),
/// `ContentView` reemplaza TODA la ventana -- barra lateral incluida --
/// por esta vista, que guia la instalacion de principio a fin y
/// devuelve la interfaz normal al terminar.
///
/// "Automatica" con una puerta honesta: el recorrido arranca solo tras
/// una cuenta regresiva visible (con botones para empezar ya o
/// cancelar), y la autorizacion de administrador del formateo NUNCA se
/// salta -- esa es la puerta de consentimiento real.
struct AutoInstallView: View {
    @ObservedObject var monitor: IPodMonitor
    @StateObject private var viewModel: InstallerViewModel
    /// Cierra el recorrido y restaura la ventana normal.
    let onFinish: () -> Void

    @State private var began = false
    @State private var countdown = 5
    @State private var countdownTask: Task<Void, Never>?

    init(monitor: IPodMonitor, onFinish: @escaping () -> Void) {
        self.monitor = monitor
        self.onFinish = onFinish
        _viewModel = StateObject(wrappedValue: InstallerViewModel(monitor: monitor))
    }

    var body: some View {
        Group {
            if began {
                VStack(spacing: 0) {
                    InstallerWizardView(viewModel: viewModel)
                    if viewModel.step == .done {
                        Button("Finalizar") { onFinish() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .padding(.bottom, 28)
                    } else if viewModel.step == .failed {
                        Button("Salir del instalador") { onFinish() }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .padding(.bottom, 28)
                    }
                }
            } else {
                intro
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { startCountdown() }
        .onDisappear { countdownTask?.cancel() }
    }

    private var intro: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "ipod")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Encontramos tu iPod en modo bootloader")
                .font(.largeTitle.bold())
            Text("A continuacion instalaremos Aura automaticamente. Cuando terminemos te avisaremos para que desconectes tu iPod y lo reinicies (manteniendo SELECT + MENU unos segundos).")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520)
            Text("Comenzando en \(countdown)...")
                .font(.headline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            HStack(spacing: 16) {
                Button("Cancelar") {
                    countdownTask?.cancel()
                    onFinish()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                Button("Comenzar ahora") {
                    begin()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            Spacer()
        }
        .padding(40)
    }

    private func startCountdown() {
        countdownTask?.cancel()
        countdownTask = Task {
            while countdown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                countdown -= 1
            }
            begin()
        }
    }

    private func begin() {
        guard !began else { return }
        countdownTask?.cancel()
        began = true
        viewModel.startAutoInstall()
    }
}
