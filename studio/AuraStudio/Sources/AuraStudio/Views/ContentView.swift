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

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection, device: deviceMonitor.device)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detail
        }
        .tint(AuraColors.light.accent)
        .onAppear { deviceMonitor.start() }
        .onDisappear { deviceMonitor.stop() }
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
            InstallerHomeView()
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

    /// SF Symbols, los mismos que usa el firmware para cada seccion
    /// (ver design-system/tokens.json).
    var symbol: String {
        switch self {
        case .general:   return "info.circle"
        case .music:     return "music.note"
        case .video:     return "film.fill"
        case .photos:    return "photo.fill"
        case .extras:    return "puzzlepiece.extension.fill"
        case .installer: return "square.and.arrow.down"
        case .settings:  return "gearshape.fill"
        }
    }

    static let deviceSections: [SidebarSection] = [.general, .music, .video, .photos, .extras]
    static let appSections: [SidebarSection] = [.installer, .settings]
}

private struct SidebarView: View {
    @Binding var selection: SidebarSection?
    let device: AuraDevice?

    var body: some View {
        List(selection: $selection) {
            Section(header: deviceHeader) {
                ForEach(SidebarSection.deviceSections, id: \.self) { section in
                    Label(section.title, systemImage: section.symbol).tag(section)
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
            Image(systemName: device == nil ? "ipod.slash" : "ipod")
            Text(device?.volumeName ?? S.noDevice.text)
                .lineLimit(1)
        }
    }
}
