import SwiftUI

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
}
