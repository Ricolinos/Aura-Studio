import SwiftUI

struct VideoSettingsView: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(LS("video-settings-view.organizar-por-categoria-biblioteca"), isOn: $preferences.organizeVideosByCategory)
                Text(LS("video-settings-view.separa-tus-videos-videos-series-pelicula"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text(LS("video-settings-view.formato-video")).font(.headline)
                Text(LS("video-settings-view.todo-video-se-convierte-320x240-mpeg"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
