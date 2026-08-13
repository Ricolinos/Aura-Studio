import SwiftUI

/// Raiz de la app. Estructura de barra lateral estilo Finder: cuando
/// conectas el iPod, el Finder no te muestra "pestañas de la app" sino
/// las secciones DEL DISPOSITIVO (General, Musica, Video, Fotos...), y
/// Aura Studio hace lo mismo. La deteccion es automatica: `IPodMonitor`
/// avisa cuando aparece el volumen y `AuraDeviceProbe` mira que firmware
/// tiene, asi que el usuario nunca elige nada a mano.
///
/// Las secciones de contenido siguen disponibles sin dispositivo: armar
/// la biblioteca es util offline y despues se sincroniza. Lo que cambia
/// sin iPod es lo que muestra General y que el boton de sincronizar
/// quede deshabilitado.
struct ContentView: View {
    @StateObject private var deviceMonitor = IPodMonitor()
    @StateObject private var library = LibraryViewModel()
    @StateObject private var preferences = AppPreferences.shared
    @State private var selection: SidebarSection? = .general

    /// La biblioteca (Musica/Video/Fotos/Extras) se bloquea cuando hay
    /// un iPod conectado cuyo firmware NO es Aura: sincronizar contra el
    /// firmware original de Apple o un Rockbox ajeno no haria nada util
    /// y confunde (encargo del dueño, 2026-08-13). SIN dispositivo la
    /// biblioteca sigue abierta a proposito -- armarla offline es un
    /// caso de uso real, se sincroniza al conectar.
    private var libraryLocked: Bool {
        guard let device = deviceMonitor.device else { return false }
        return !device.isAura
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection,
                        device: deviceMonitor.device,
                        libraryLocked: libraryLocked)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detail
        }
        .tint(AuraColors.light.accent)
        .onAppear { deviceMonitor.start() }
        .onDisappear { deviceMonitor.stop() }
        .onChange(of: libraryLocked) { locked in
            // Si la seccion activa quedo bloqueada (p.ej. se conecto un
            // iPod con firmware original mientras se miraba Musica), la
            // seleccion salta a General en vez de quedarse en una vista
            // que ya no aplica.
            if locked, let current = selection,
               current != .general, SidebarSection.deviceSections.contains(current) {
                selection = .general
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .general {
        case .general:
            DeviceGeneralView(device: deviceMonitor.device,
                              state: deviceMonitor.state,
                              library: library) {
                await syncNow()
            }
        case .music:
            MediaSectionView(kind: .music, viewModel: library)
        case .video:
            MediaSectionView(kind: .video, viewModel: library)
        case .photos:
            MediaSectionView(kind: .photo, viewModel: library)
        case .extras:
            ExtrasView(device: deviceMonitor.device)
        case .installer:
            InstallerHomeView(monitor: deviceMonitor)
        case .settings:
            SettingsSectionView(preferences: preferences)
        }
    }

    private func syncNow() async {
        guard let device = deviceMonitor.device else { return }
        await library.sync(toVolumeAt: URL(fileURLWithPath: device.mountPath))
        // El disco no se desmonto, asi que DiskArbitration no va a
        // notificar nada -- hay que releer el resumen a mano.
        deviceMonitor.refreshDevice()
    }
}

enum SidebarSection: Hashable, CaseIterable {
    case general
    case music
    case video
    case photos
    case extras
    case installer
    case settings

    var title: String {
        switch self {
        case .general:   return S.general.text
        case .music:     return S.music.text
        case .video:     return S.video.text
        case .photos:    return S.photos.text
        case .extras:    return S.extras.text
        case .installer: return S.installer.text
        case .settings:  return S.settings.text
        }
    }

    /// SF Symbols en variante lineal (docs/design/Reglas de diseno
    /// Apple2026 (v2).md SS4: "siempre la variante lineal, nunca
    /// .fill" -- una barra de navegacion es exactamente el caso de uso
    /// que esa regla describe, sea en el firmware o en Studio). `video`
    /// y `settings` usan los simbolos canonicos del propio documento
    /// (`play.rectangle` = Videos, `gear` = Configuracion); `extras`
    /// toma `square.grid.2x2`, tambien canonico ahi, en vez del
    /// generico `puzzlepiece.extension.fill` que tenia antes.
    var symbol: String {
        switch self {
        case .general:   return "info.circle"
        case .music:     return "music.note"
        case .video:     return "play.rectangle"
        case .photos:    return "photo"
        case .extras:    return "square.grid.2x2"
        case .installer: return "square.and.arrow.down"
        case .settings:  return "gear"
        }
    }

    static let deviceSections: [SidebarSection] = [.general, .music, .video, .photos, .extras]
    static let appSections: [SidebarSection] = [.installer, .settings]
}

private struct SidebarView: View {
    @Binding var selection: SidebarSection?
    let device: AuraDevice?
    let libraryLocked: Bool

    var body: some View {
        List(selection: $selection) {
            Section(header: deviceHeader) {
                ForEach(SidebarSection.deviceSections, id: \.self) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                        // General queda siempre accesible: es donde se
                        // explica QUE firmware hay y que hacer con el.
                        .disabled(libraryLocked && section != .general)
                }
            }
            Section("Aura Studio") {
                ForEach(SidebarSection.appSections, id: \.self) { section in
                    Label(section.title, systemImage: section.symbol).tag(section)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var deviceHeader: some View {
        HStack(spacing: 6) {
            /* "ipod.slash" no existe en SF Symbols (verificado contra el
             * catalogo real, no supuesto) -- mismo simbolo que ya usa
             * DeviceGeneralView para "sin dispositivo". */
            Image(systemName: device == nil ? "cable.connector.slash" : "ipod")
            Text(device?.volumeName ?? S.noDevice.text)
                .lineLimit(1)
        }
    }
}
