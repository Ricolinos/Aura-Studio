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
            if viewModel.isAutomaticUpdate {
                // D-222: "Actualizar" en General dispara esto en vez de
                // navegar aca con el selector -- pero el usuario SI
                // puede terminar viendo esta pantalla (navego a
                // Instalador mientras la actualizacion seguia en
                // curso), asi que tiene que verse bien por si sola.
                AutomaticUpdateView(viewModel: viewModel)
            } else if viewModel.chosenMode != nil {
                InstallerWizardView(viewModel: viewModel)
            } else {
                ModePickerView(device: monitor.device, state: monitor.state) { mode in
                    viewModel.beginFlow(mode: mode)
                }
            }
        }
        .animation(.default, value: viewModel.chosenMode)
        .animation(.default, value: viewModel.isAutomaticUpdate)
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
        guard let device else { return true }
        // ST-016: firmware de Apple en el disco Y nada de la familia
        // Rockbox atendiendo el USB -> ya es original, no hay que restaurar.
        return !(device.firmware == .stock && device.runningFirmware != .rockboxFamily)
    }

    /// "Reinstalar" solo cuando Aura esta instalada DE VERDAD (`isAura`,
    /// ST-016): archivos copiados sin evidencia de arranque se instalan,
    /// no se reinstalan -- y esa instalacion pasa por DFU.
    private var installTitle: String {
        device?.isAura == true ? "Reinstalar Aura" : "Instalar Aura"
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
        // ST-016: solo se afirma "instalado"/"dual boot" con evidencia
        // de arranque (USB atendido por Aura/Rockbox, o rastro en disco).
        switch device.firmware {
        case .stock:
            return device.runningFirmware == .rockboxFamily
                ? "Tu iPod tiene el firmware original de Apple en el disco, pero el USB lo atiende el bootloader de Aura/Rockbox."
                : "Tu iPod tiene el firmware original de Apple."
        case .aura where device.isAura:
            return device.isDualBoot
                ? "Tu iPod tiene Aura instalado, en dual boot con el firmware original de Apple."
                : "Tu iPod ya tiene Aura instalado."
        case .aura:
            return device.runningFirmware == .apple
                ? "Tu iPod tiene archivos de Aura en el disco, pero está corriendo el firmware de Apple y Aura nunca ha arrancado aquí -- no hay evidencia de que esté instalado."
                : "Tu iPod tiene archivos de Aura en el disco, pero Aura nunca ha arrancado aquí -- no hay evidencia de que esté instalado."
        case .rockbox where device.rockboxFamilyVerified:
            return device.isDualBoot
                ? "Tu iPod tiene Rockbox instalado (no es Aura), en dual boot con el firmware original."
                : "Tu iPod tiene Rockbox instalado (no es Aura)."
        case .rockbox:
            return "Tu iPod tiene archivos de Rockbox en el disco (no es Aura), sin evidencia de que arranquen."
        case .empty:
            return device.runningFirmware == .rockboxFamily
                ? "El disco de tu iPod esta vacio, pero el USB lo atiende el bootloader de Aura/Rockbox."
                : "El disco de tu iPod esta vacio, sin ningun firmware."
        }
    }

    /// Anticipa si hara falta DFU con el mismo criterio que va a aplicar
    /// el instalador (`AuraDevice.canSkipBootloaderFlash`) -- para no
    /// prometer "sin flashear" y despues pedirlo.
    private var installNote: String? {
        guard let device else { return nil }
        let recorded = AppPreferences.shared.isBootloaderVerified(diskKey: device.diskRecordKey)
        // Sin FAT32 el instalador formatea y pasa por DFU siempre
        // (`acknowledgeDeviceReady`), asi que ahi nunca se promete
        // "sin flashear".
        let skipsDFU = state.isReadyForInstall && device.canSkipBootloaderFlash(diskRecordedAsVerified: recorded)
        switch device.firmware {
        case .aura where device.isAura:
            return skipsDFU
                ? "Reinstalar solo reemplaza los archivos del firmware en el disco -- no hace falta flashear por DFU. Tus ajustes de Aura se conservan. Si al terminar tu iPod no arranca con Aura, la pantalla final ofrece completar el flasheo."
                : "Reinstalar reemplaza los archivos del firmware y, como Aura Studio no puede confirmar desde aquí que el bootloader siga grabado, vuelve a flashear el arranque por DFU (reflashear es inofensivo). Tus ajustes de Aura se conservan. Para saltarte el DFU, conecta el iPod mientras está encendido con Aura."
        case .aura:
            return "Hay archivos de Aura en el disco pero ninguna evidencia de que arranquen: instalar flashea el arranque por modo DFU y vuelve a copiar los archivos -- el asistente te guia paso a paso."
        case .rockbox:
            return skipsDFU
                ? "Instalar Aura no requiere flashear ni entrar a modo DFU: solo se reemplaza la carpeta .rockbox del disco por la de Aura."
                : "Instalar Aura reemplaza la carpeta .rockbox del disco por la de Aura y flashea el arranque por modo DFU, porque no hay evidencia suficiente de que el bootloader ya esté grabado. Para saltarte el DFU, conecta el iPod mientras está encendido con Rockbox."
        case .stock:
            return skipsDFU
                ? "El bootloader de Aura/Rockbox ya está atendiendo el USB: instalar solo copia los archivos, sin flashear."
                : "Instalar Aura requiere flashear el arranque por modo DFU -- el asistente te guia paso a paso."
        case .empty:
            return skipsDFU
                ? "El bootloader de Aura/Rockbox ya está atendiendo el USB: instalar solo copia los archivos, sin flashear."
                : nil
        }
    }
}

#Preview {
    ModePickerView(device: nil, state: .notConnected, onChoose: { _ in })
}
