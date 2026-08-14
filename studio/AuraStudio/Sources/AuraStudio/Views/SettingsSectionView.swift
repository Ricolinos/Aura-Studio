import SwiftUI
import AppKit

/// Ajustes de la APLICACION. Ojo con la distincion: los ajustes del
/// firmware (tema, animaciones, graficos, EQ...) viven en el iPod y se
/// cambian ahi -- aca solo esta lo que le toca decidir a Studio.
struct SettingsSectionView: View {
    @ObservedObject var preferences: AppPreferences
    @State private var tab: Tab = .general

    enum Tab: Hashable {
        case general, library, music, photos, video, services
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text(S.settingsGeneral.text).tag(Tab.general)
                Text(S.settingsLibrary.text).tag(Tab.library)
                Text(S.music.text).tag(Tab.music)
                Text(S.photos.text).tag(Tab.photos)
                Text(S.video.text).tag(Tab.video)
                Text(S.settingsServices.text).tag(Tab.services)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(16)
            .frame(maxWidth: 760)

            Divider()

            ScrollView {
                Group {
                    switch tab {
                    case .general: generalTab
                    case .library: libraryTab
                    case .music: MusicSettingsView(preferences: preferences)
                    case .photos: PhotoSettingsView(preferences: preferences)
                    case .video: VideoSettingsView(preferences: preferences)
                    case .services: ServicesSettingsView(preferences: preferences)
                    }
                }
                .padding(24)
                .frame(maxWidth: 620, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .navigationTitle(S.settings.text)
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(S.language.text).font(.headline)
            Picker(S.language.text, selection: $preferences.language) {
                Text(S.languageSystem.text).tag(AppLanguage.system)
                Text(S.languageSpanish.text).tag(AppLanguage.spanish)
                Text(S.languageEnglish.text).tag(AppLanguage.english)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Text(S.languageNote.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var libraryTab: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Carpeta de la biblioteca Aura").font(.headline)
                Text("Aquí vive el catálogo de tu biblioteca -- funciona aunque el iPod no esté conectado, y se sincroniza al conectarlo. Que además copie tus archivos aquí depende del ajuste de abajo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Image(systemName: "folder")
                        .foregroundStyle(.tint)
                    Text(preferences.libraryFolderPath)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Mostrar en Finder") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: preferences.libraryFolderPath, isDirectory: true))
                    }
                    Button("Cambiar...") {
                        chooseLibraryFolder()
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))

                Toggle("Crear copias de los medios en la Biblioteca de Aura", isOn: $preferences.copyMediaIntoLibrary)
                Text(preferences.copyMediaIntoLibrary
                     ? "Cada canción, foto o video que sueltas en Aura Studio se copia dentro de la carpeta de arriba -- el original queda intacto donde estaba. Usa más espacio en disco, pero la biblioteca queda autocontenida en un solo lugar."
                     : "Nada se copia: la biblioteca referencia tus archivos donde ya están. Aquí solo se guarda la configuración que los liga a Aura (metadata, letras, portadas). Al sincronizar con el iPod, Aura Studio arma el archivo final leyendo el original en ese momento -- un poco más lento la primera vez, pero tu disco nunca termina con una copia duplicada de tu biblioteca completa.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text(S.coverArt.text).font(.headline)
                Picker(S.coverArt.text, selection: $preferences.coverArtPolicy) {
                    Text(S.coverArtAlbumOnly.text).tag(AppPreferences.CoverArtPolicy.albumOnly)
                    Text(S.coverArtPerTrack.text).tag(AppPreferences.CoverArtPolicy.perTrack)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                Text(preferences.coverArtPolicy == .albumOnly
                     ? S.coverArtAlbumOnlyDetail.text
                     : S.coverArtPerTrackDetail.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text(S.importing.text).font(.headline)

                Toggle(S.enrichOnline.text, isOn: $preferences.enrichOnline)
                Text(S.enrichOnlineDetail.text)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(S.fetchLyrics.text, isOn: $preferences.fetchSyncedLyrics)
                    .disabled(!preferences.enrichOnline)
                Text(S.fetchLyricsDetail.text)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func chooseLibraryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Usar esta carpeta"
        panel.message = "Elige (o crea) la carpeta donde vivira tu biblioteca Aura."
        panel.directoryURL = URL(fileURLWithPath: preferences.libraryFolderPath, isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url {
            preferences.libraryFolderPath = url.path
        }
    }
}
