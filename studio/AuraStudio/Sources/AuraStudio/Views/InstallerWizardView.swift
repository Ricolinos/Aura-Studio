import SwiftUI

/// Contenedor que muestra la pantalla correspondiente a `viewModel.step`
/// dentro de una barra de progreso comun -- el usuario siempre ve en que
/// paso esta y cuantos faltan, sin importar si es instalacion o
/// restauracion (el flujo visible es identico, ver InstallerViewModel).
struct InstallerWizardView: View {
    @ObservedObject var viewModel: InstallerViewModel

    private let visibleSteps: [InstallerStep] = [
        .welcome, .permissions, .detectDevice, .enterDFU, .installing,
        .bootloaderUSBMode, .preparingDisk, .copyingFiles, .done,
    ]

    var body: some View {
        VStack(spacing: 0) {
            StepProgressBar(steps: visibleSteps, current: viewModel.step)
                .padding(.top, 20)
                .padding(.horizontal, 32)

            Divider().padding(.top, 16)

            Group {
                switch viewModel.step {
                case .welcome:
                    WelcomeView(mode: viewModel.mode, onBack: viewModel.backFromWelcome, onContinue: viewModel.advanceFromWelcome)
                case .permissions:
                    PermissionsView(onBack: viewModel.backFromPermissions, onContinue: viewModel.advanceFromPermissions)
                case .detectDevice:
                    DetectDeviceView(monitor: viewModel.monitor, onBack: viewModel.backFromDetectDevice, onReadyForDFU: viewModel.acknowledgeEnteringDFU)
                case .enterDFU:
                    EnterDFUView(monitor: viewModel.monitor, onBack: viewModel.backFromEnterDFU)
                case .installing:
                    InstallingView(mode: viewModel.mode, message: viewModel.progressMessage)
                case .bootloaderUSBMode:
                    BootloaderUSBModeView()
                case .preparingDisk:
                    SimpleProgressView(title: "Preparando el disco", message: viewModel.progressMessage)
                case .copyingFiles:
                    SimpleProgressView(title: "Copiando archivos", message: viewModel.progressMessage)
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
        .sheet(item: $viewModel.pendingAuthorization) { authorization in
            PrivilegedActionSheet(
                authorization: authorization,
                onConfirm: viewModel.confirmPendingAuthorization,
                onCancel: viewModel.cancelPendingAuthorization
            )
        }
    }
}

private struct BootloaderUSBModeView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "cable.connector")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Reconectá el iPod")
                .font(.title.bold())
            VStack(alignment: .leading, spacing: 10) {
                Text("1. Desconectá el cable USB del iPod.")
                Text("2. Con el iPod apagado, mantené presionados SELECT + RIGHT.")
                Text("3. Conectá el cable mientras mantenés esos botones.")
                Text("4. Aura Studio detecta el modo Bootloader USB automáticamente.")
            }
            .frame(maxWidth: 420, alignment: .leading)
            ProgressView().controlSize(.small)
        }
    }
}

private struct SimpleProgressView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text(title).font(.title.bold())
            if !message.isEmpty {
                Text(message).foregroundStyle(.secondary)
            }
        }
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
