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
    /// ST-047: que familia instalaria "Instalar" ahora mismo (Extras ›
    /// Firmware). Se lee al construir la vista -- cambiarla en Extras y
    /// volver aqui la reconstruye, asi que siempre esta al dia sin
    /// observar el singleton desde esta vista (ver ST-051).
    private var family: FirmwareFamily { AppPreferences.shared.firmwareFamilyToInstall }
    private var name: String { family.displayName }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "ipod")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text(LS("content-view.aura-studio"))
                .font(.largeTitle.bold())
            Text(detectionText)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            // ST-047: decir con todas sus letras cual de los firmwares
            // va a instalar el boton -- la eleccion vive en Extras.
            Label(LSf("installer-home-view.firmware-instalar-se-elige-extras-firmwa", name),
                  systemImage: family.symbolName)
                .font(.callout)
                .foregroundStyle(.secondary)

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
                        Label(LS("installer-home-view.restaurar-ipod-original"), systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .frame(maxWidth: 440)

            // ST-143: la oferta de actualizar el arranque. Va DEBAJO de
            // los botones y con estilo discreto a propósito: no es una
            // acción que haya que hacer -- el firmware funciona igual
            // con el arranque viejo, solo cambia la pantalla de arranque.
            if let reason = InstallerViewModel.bootloaderUpdateReason(for: device) {
                VStack(spacing: 6) {
                    Button {
                        onChoose(.updateBootloader)
                    } label: {
                        Label(LS("installer-home-view.actualizar-arranque"), systemImage: "power.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Text(reason == .differentBootloader
                         ? LS("installer-home.bootloader-reason.newer")
                         : LS("installer-home.bootloader-reason.unknown"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }
            }

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

    /// "Reinstalar" solo cuando Aura esta instalada DE VERDAD
    /// (`supportsAuraContract`, ST-016): archivos copiados sin evidencia de
    /// arranque se instalan, no se reinstalan -- y esa instalacion pasa por
    /// DFU.
    ///
    /// ST-046: y ademas tiene que ser Aura. Un iPod con Metro-Aura cumple
    /// `supportsAuraContract` (comparten el contrato de §D), asi que este
    /// boton decia "Reinstalar Aura" sobre un firmware que no era Aura --
    /// justo el texto que hace creer que se va a conservar algo. Lo que ahi
    /// ocurre es una instalacion que REEMPLAZA Metro.
    private var installTitle: String {
        // ST-047: "Reinstalar" solo si lo que hay es LA MISMA familia que
        // se va a instalar; sobre otra familia es instalar (y reemplazar).
        let same = device?.supportsAuraContract == true && device?.declaredFamily == family
        return same ? LSf("installer-home.action.reinstall", name)
                    : LSf("installer-home.action.install", name)
    }

    private var detectionText: String {
        if case .diskModeNoFilesystem = state {
            return LSf("installer-home.detection.no-filesystem", name)
        }
        if case .dfuMode = state {
            return LS("installer-home.detection.dfu")
        }
        guard let device else {
            return LSf("installer-home.detection.no-device", name)
        }
        // ST-016: solo se afirma "instalado"/"dual boot" con evidencia
        // de arranque (USB atendido por Aura/Rockbox, o rastro en disco).
        switch device.firmware {
        case .stock:
            return device.runningFirmware == .rockboxFamily
                ? LS("installer-home.detection.stock-usb-rockbox")
                : LS("installer-home.detection.stock")
        // ST-046/ST-047: se nombra lo que HAY por lo que declara, y se
        // dice sin rodeos si instalar lo elegido lo reemplaza.
        case .aura where device.supportsAuraContract:
            // ST-227 (A7d): el "en dual boot..." era un trozo que se
            // pegaba al final de la frase ya armada. Una frase entera
            // por caso -- en alemán la subordinada no va donde el
            // español la deja, y un fragmento cosido no se puede mover.
            let installed = device.declaredFamily.displayName
            if device.declaredFamily == family {
                return device.isDualBoot
                    ? LSf("installer-home.detection.installed-dual", installed)
                    : LSf("installer-home.detection.installed", installed)
            }
            return device.isDualBoot
                ? LSf("installer-home.detection.installed-dual-replace", installed, name)
                : LSf("installer-home.detection.installed-replace", installed, name)
        case .aura:
            return device.runningFirmware == .apple
                ? LS("installer-home.detection.aura-files-apple-running")
                : LS("installer-home.detection.aura-files-never-booted")
        case .rockbox where device.rockboxFamilyVerified:
            return device.isDualBoot
                ? LS("installer-home.detection.rockbox-dual")
                : LS("installer-home.detection.rockbox")
        case .rockbox:
            return LS("installer-home.detection.rockbox-files")
        case .empty:
            return device.runningFirmware == .rockboxFamily
                ? LS("installer-home.detection.empty-usb-rockbox")
                : LS("installer-home.detection.empty")
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
        case .aura where device.supportsAuraContract && device.declaredFamily == family:
            return skipsDFU
                ? LSf("installer-home.note.reinstall-no-dfu", name)
                : LSf("installer-home.note.reinstall-dfu", name)
        // ST-046/ST-047: otra familia de la misma casa. El bootloader es el
        // mismo de Rockbox, asi que el DFU se salta igual; lo que NO se
        // conserva son los ajustes, porque el firmware que los escribio se
        // va (el instalador borra su aura.cfg a proposito).
        case .aura where device.supportsAuraContract:
            let installed = device.declaredFamily.displayName
            return skipsDFU
                ? LSf("installer-home.note.replace-family-no-dfu", name, installed)
                : LSf("installer-home.note.replace-family-dfu", name, installed)
        case .aura:
            return LS("installer-home.note.aura-files-needs-dfu")
        case .rockbox:
            return skipsDFU
                ? LSf("installer-home.note.rockbox-no-dfu", name)
                : LSf("installer-home.note.rockbox-dfu", name)
        case .stock:
            return skipsDFU
                ? LS("installer-home.note.usb-already-bootloader")
                : LSf("installer-home.note.stock-needs-dfu", name)
        case .empty:
            return skipsDFU
                ? LS("installer-home.note.usb-already-bootloader")
                : nil
        }
    }
}

#Preview {
    ModePickerView(device: nil, state: .notConnected, onChoose: { _ in })
}
