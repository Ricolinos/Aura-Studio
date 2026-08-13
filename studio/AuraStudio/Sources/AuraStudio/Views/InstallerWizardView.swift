import SwiftUI

/// Contenedor que muestra la pantalla correspondiente a `viewModel.step`
/// dentro de una barra de progreso comun -- el usuario siempre ve en que
/// paso esta y cuantos faltan, sin importar si es instalacion o
/// restauracion (el flujo visible es identico, ver InstallerViewModel).
struct InstallerWizardView: View {
    @ObservedObject var viewModel: InstallerViewModel

    private var visibleSteps: [InstallerStep] {
        switch viewModel.mode {
        case .install:
            return [
                .welcome, .chooseBootMode, .permissions, .detectDevice,
                .preparingDisk, .copyingFiles, .enterDFU, .installing, .done,
            ]
        case .restore:
            // La restauracion no termina en "done" dentro de la app: el
            // ultimo paso es la entrega a Finder (D-184).
            return [
                .welcome, .permissions, .detectDevice, .enterDFU,
                .installing, .restoreFormatting, .restoreHandoff,
            ]
        }
    }

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
                case .chooseBootMode:
                    BootModeView(onBack: viewModel.backFromBootMode, onContinue: viewModel.advanceFromBootMode)
                case .permissions:
                    PermissionsView(onBack: viewModel.backFromPermissions, onContinue: viewModel.advanceFromPermissions)
                case .detectDevice:
                    DetectDeviceView(monitor: viewModel.monitor, onBack: viewModel.backFromDetectDevice, onDeviceReady: viewModel.acknowledgeDeviceReady)
                case .enterDFU:
                    EnterDFUView(monitor: viewModel.monitor, onBack: viewModel.backFromEnterDFU)
                case .installing:
                    InstallingView(mode: viewModel.mode, message: viewModel.progressMessage)
                case .preparingDisk:
                    SimpleProgressView(title: "Preparando el disco", message: viewModel.progressMessage, progress: nil)
                case .copyingFiles:
                    SimpleProgressView(title: "Instalando Aura", message: viewModel.progressMessage, progress: viewModel.copyProgress)
                case .restoreFormatting:
                    SimpleProgressView(title: "Preparando para Finder", message: viewModel.progressMessage, progress: nil)
                case .restoreHandoff:
                    RestoreHandoffView()
                case .done:
                    // Si esta corrida no flasheo nada (recuperacion con
                    // el bootloader ya grabado), el modo de arranque lo
                    // decidio la instalacion anterior -- no se afirma
                    // dual boot que esta corrida no eligio.
                    DoneView(mode: viewModel.mode, dualBoot: !viewModel.destroyOriginalFirmware && !viewModel.bootloaderAlreadyInstalled)
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

private struct SimpleProgressView: View {
    let title: String
    let message: String
    /// 0...1 para barra determinada (extraccion del arbol .rockbox,
    /// medida contra el tamaño real escrito); nil = spinner.
    let progress: Double?

    var body: some View {
        VStack(spacing: 16) {
            if let progress {
                ProgressView(value: progress)
                    .frame(maxWidth: 320)
            } else {
                ProgressView().controlSize(.large)
            }
            Text(title).font(.title.bold())
            if !message.isEmpty {
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
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
