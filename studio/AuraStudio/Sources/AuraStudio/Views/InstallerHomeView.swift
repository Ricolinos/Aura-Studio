import SwiftUI

/// Elegir entre Instalar y Restaurar lanza el mismo asistente
/// (`InstallerViewModel`) en el modo correspondiente -- ambos flujos
/// comparten deteccion, guia DFU y verificacion, solo cambia el
/// comando final que se le manda a mks5lboot.
///
/// El selector se ADAPTA a lo que el monitor compartido ya sabe del
/// iPod conectado (encargo del dueño, 2026-08-13: "que la interfaz sea
/// muy intuitiva"): con el firmware original de Apple no se ofrece
/// "Restaurar iPod original" (ya lo es); con Aura o un Rockbox comun se
/// avisa que instalar no requiere flashear (solo se reemplaza la
/// carpeta .rockbox); sin dispositivo se muestran las dos opciones
/// genericas de siempre.
struct InstallerHomeView: View {
    @ObservedObject var monitor: IPodMonitor
    /// Compartido y propiedad de `ContentView` (D-187): esta vista se
    /// destruye al navegar a otra seccion, pero el asistente en curso
    /// (paso actual, progreso de copia, espera de DFU) NO debe morir
    /// con ella -- al volver, se retoma exactamente donde iba. El
    /// estado del selector (`chosenMode`) y el registro global de flujo
    /// activo tambien viven en el ViewModel por lo mismo.
    @ObservedObject var viewModel: InstallerViewModel

    var body: some View {
        Group {
            if viewModel.chosenMode != nil {
                InstallerWizardView(viewModel: viewModel)
            } else {
                ModePickerView(device: monitor.device, state: monitor.state) { mode in
                    viewModel.beginFlow(mode: mode)
                }
            }
        }
        .animation(.default, value: viewModel.chosenMode)
    }
}

struct ModePickerView: View {
    let device: AuraDevice?
    let state: DeviceState
    let onChoose: (InstallerMode) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "ipod")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Aura Studio")
                .font(.largeTitle.bold())
            Text(detectionText)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)

            HStack(spacing: 16) {
                Button {
                    onChoose(.install)
                } label: {
                    Label(installTitle, systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if showRestore {
                    Button {
                        onChoose(.restore)
                    } label: {
                        Label("Restaurar iPod original", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .frame(maxWidth: 440)

            if let note = installNote {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Con el firmware original de Apple no tiene caso ofrecer
    /// "Restaurar iPod original": ya lo es. En cualquier otro estado
    /// (Aura, Rockbox, disco vacio, bootloader, DFU, sin dispositivo)
    /// la opcion queda disponible -- incluso con el disco vacio puede
    /// haber un bootloader grabado en la NOR que quitar.
    private var showRestore: Bool {
        device?.firmware != .stock
    }

    private var installTitle: String {
        if case .aura = device?.firmware { return "Reinstalar Aura" }
        return "Instalar Aura"
    }

    private var detectionText: String {
        if case .diskModeNoFilesystem = state {
            return "Tu iPod esta conectado, pero su disco no tiene un sistema de archivos legible -- instalar Aura lo prepara desde cero."
        }
        if case .dfuMode = state {
            return "Tu iPod esta conectado en modo DFU, listo para flashear."
        }
        guard let device else {
            return "Instala el firmware Aura en tu iPod Classic 6G, o restaura el firmware original si quieres volver atras."
        }
        switch device.firmware {
        case .stock:
            return "Tu iPod tiene el firmware original de Apple."
        case .aura:
            return device.isDualBoot
                ? "Tu iPod tiene Aura instalado, en dual boot con el firmware original de Apple."
                : "Tu iPod ya tiene Aura instalado."
        case .rockbox:
            return device.isDualBoot
                ? "Tu iPod tiene Rockbox instalado (no es Aura), en dual boot con el firmware original."
                : "Tu iPod tiene Rockbox instalado (no es Aura)."
        case .empty:
            return "El disco de tu iPod esta vacio, sin ningun firmware."
        }
    }

    private var installNote: String? {
        guard let device else { return nil }
        switch device.firmware {
        case .aura:
            return "Reinstalar no requiere flashear ni entrar a modo DFU: solo se reemplazan los archivos del firmware en el disco. Tus ajustes de Aura se conservan."
        case .rockbox:
            return "Instalar Aura no requiere flashear ni entrar a modo DFU: solo se reemplaza la carpeta .rockbox del disco por la de Aura."
        case .stock:
            return "Instalar Aura requiere flashear el arranque por modo DFU -- el asistente te guia paso a paso."
        case .empty:
            return nil
        }
    }
}

#Preview {
    ModePickerView(device: nil, state: .notConnected, onChoose: { _ in })
}
