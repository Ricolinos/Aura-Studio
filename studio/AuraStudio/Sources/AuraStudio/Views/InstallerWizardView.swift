import SwiftUI

/// Contenedor que muestra la pantalla correspondiente a `viewModel.step`
/// dentro de una barra de progreso comun -- el usuario siempre ve en que
/// paso esta y cuantos faltan, sin importar si es instalacion o
/// restauracion (el flujo visible es identico, ver InstallerViewModel).
struct InstallerWizardView: View {
    @ObservedObject var viewModel: InstallerViewModel

    private let visibleSteps: [InstallerStep] = [.welcome, .permissions, .detectDevice, .enterDFU, .installing, .done]

    var body: some View {
        VStack(spacing: 0) {
            StepProgressBar(steps: visibleSteps, current: viewModel.step)
                .padding(.top, 20)
                .padding(.horizontal, 32)

            Divider().padding(.top, 16)

            Group {
                switch viewModel.step {
                case .welcome:
                    WelcomeView(mode: viewModel.mode, onContinue: viewModel.advanceFromWelcome)
                case .permissions:
                    PermissionsView(onContinue: viewModel.advanceFromPermissions)
                case .detectDevice:
                    DetectDeviceView(monitor: viewModel.monitor, onReadyForDFU: viewModel.acknowledgeEnteringDFU)
                case .enterDFU:
                    EnterDFUView(monitor: viewModel.monitor)
                case .installing:
                    InstallingView(mode: viewModel.mode, message: viewModel.progressMessage)
                case .done:
                    DoneView(mode: viewModel.mode)
                case .failed:
                    FailedView(error: viewModel.lastError, onRetry: viewModel.retry)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
        }
        .onDisappear { viewModel.stop() }
    }
}

private struct StepProgressBar: View {
    let steps: [InstallerStep]
    let current: InstallerStep

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                Capsule()
                    .fill(color(for: step))
                    .frame(maxWidth: .infinity)
                    .frame(height: 4)
            }
        }
    }

    private func color(for step: InstallerStep) -> Color {
        if step.rawValue < current.rawValue { return .accentColor }
        if step == current { return .accentColor }
        return Color.secondary.opacity(0.25)
    }
}
