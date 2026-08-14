import SwiftUI

/// D-222 (encargo del dueño, 2026-08-14): "al darle al botón de
/// 'actualizar', en lugar de mandarnos a la sección de instalación >
/// reinstalar aura > seleccionar el modo... solo deberá aparecer una
/// barra de progreso... deberá ser automática la instalación". A
/// diferencia de `InstallerWizardView` (que muestra `StepProgressBar` y
/// deja que el usuario navegue paso a paso, con botones "Atrás"), esto
/// solo dibuja el contenido del paso ACTUAL -- sin barra de pasos, sin
/// navegación manual. `InstallerViewModel.startAutomaticUpdate()` ya
/// dejó todo encaminado (modo dual/solo preservado del dispositivo,
/// saltó directo a `acknowledgeDeviceReady()`); esta vista solo
/// refleja lo que va pasando.
struct AutomaticUpdateView: View {
    @ObservedObject var viewModel: InstallerViewModel

    var body: some View {
        Group {
            switch viewModel.step {
            case .done:
                VStack(spacing: 20) {
                    DoneView(mode: .install, dualBoot: !viewModel.destroyOriginalFirmware)
                    Button("Listo") {
                        viewModel.dismissAutomaticUpdate()
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .failed:
                FailedView(error: viewModel.lastError,
                           onRetry: viewModel.startAutomaticUpdate,
                           onSwitchToSingleBoot: viewModel.switchToSingleBootAndRetry)
            case .enterDFU:
                // Caso de borde raro (ver nota abajo): si llega aca, no
                // hay forma automatica de continuar -- se le devuelve
                // el control al usuario con la guia real de DFU en vez
                // de dejarlo mirando un progreso que nunca avanza.
                EnterDFUView(monitor: viewModel.monitor, onBack: viewModel.dismissAutomaticUpdate)
            default:
                // .detectDevice/.preparingDisk/.copyingFiles/.installing:
                // todos se ven como el mismo progreso generico -- el
                // boton "Actualizar" solo aparece con Aura YA instalado
                // Y arrancado al menos una vez (`updateSection` en
                // DeviceGeneralView), asi que el camino real casi
                // siempre es copyingFiles sin pasar por DFU
                // (`acknowledgeDeviceReady()`, caso
                // `bootloaderAlreadyInstalled`).
                SimpleProgressView(title: "Actualizando Aura",
                                    message: viewModel.progressMessage,
                                    progress: viewModel.copyProgress)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
