import SwiftUI
import AppKit

/// Ajustes de la APLICACION. Ojo con la distincion: los ajustes del
/// firmware (tema, animaciones, graficos, EQ...) viven en el iPod y se
/// cambian ahi -- aca solo esta lo que le toca decidir a Studio.
struct SettingsSectionView: View {
    @ObservedObject var preferences: AppPreferences
    @State private var tab: Tab = .general

    enum Tab: Hashable {
        case general, library, sources
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text(S.settingsGeneral.text).tag(Tab.general)
                Text(S.settingsLibrary.text).tag(Tab.library)
                Text(S.settingsSources.text).tag(Tab.sources)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(16)
            .frame(maxWidth: 420)

            Divider()

            ScrollView {
                Group {
                    switch tab {
                    case .general: generalTab
                    case .library: libraryTab
                    case .sources: SourcesSettingsView()
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
                Text("Todo lo que sueltas en Aura Studio se copia aqui -- tus archivos originales no se tocan. La biblioteca funciona aunque el iPod no este conectado, y se sincroniza al conectarlo.")
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
