import SwiftUI

/// Ajustes de organizacion y calidad de musica al sincronizar con el
/// iPod (encargo del dueño, 2026-08-13). Separado de `libraryTab` en
/// `SettingsSectionView` porque ya son bastantes controles como para
/// seguir amontonando todo en una sola pestaña.
struct MusicSettingsView: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Carpetas").font(.headline)
                Picker("Carpetas", selection: $preferences.musicOrganization) {
                    Text("Artista / Álbum (recomendado)").tag(AppPreferences.MusicOrganization.artistAlbum)
                    Text("Solo álbum").tag(AppPreferences.MusicOrganization.album)
                    Text("Solo artista").tag(AppPreferences.MusicOrganization.artist)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text(organizationDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Nombre del archivo").font(.headline)
                Picker("Nombre del archivo", selection: $preferences.musicFilenameFormat) {
                    Text("Solo el título (recomendado)").tag(AppPreferences.MusicFilenameFormat.titleOnly)
                    Text("Número de pista y título").tag(AppPreferences.MusicFilenameFormat.trackNumberTitle)
                    Text("Título - Artista").tag(AppPreferences.MusicFilenameFormat.titleArtist)
                    Text("Título - Álbum").tag(AppPreferences.MusicFilenameFormat.titleAlbum)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text(filenamePreview)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Calidad de audio").font(.headline)
                Picker("Calidad de audio", selection: $preferences.audioQuality) {
                    Text("Mantener formato original (recomendado)").tag(AppPreferences.AudioQuality.originalLossless)
                    Text("Comprimir a MP3 de buena calidad").tag(AppPreferences.AudioQuality.compressed)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text(preferences.audioQuality == .originalLossless
                     ? "FLAC, ALAC, WAV, AIFF, M4A y MP3 se copian tal cual -- el iPod con Aura los reproduce sin perder calidad. Ocupan más espacio."
                     : "Cada canción se convierte a MP3 256kbps antes de copiarla -- buena calidad, mucho menos espacio. El archivo original nunca se modifica.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var organizationDetail: String {
        switch preferences.musicOrganization {
        case .artistAlbum: return "Music/Artista/Álbum/ -- una carpeta por álbum dentro de cada artista."
        case .album: return "Music/Álbum/ -- todas las canciones agrupadas solo por álbum, sin carpeta de artista."
        case .artist: return "Music/Artista/ -- todas las canciones del artista juntas, sin carpeta de álbum."
        }
    }

    private var filenamePreview: String {
        switch preferences.musicFilenameFormat {
        case .titleOnly: return "Ejemplo: Bohemian Rhapsody.mp3"
        case .trackNumberTitle: return "Ejemplo: 11 Bohemian Rhapsody.mp3"
        case .titleArtist: return "Ejemplo: Bohemian Rhapsody - Queen.mp3"
        case .titleAlbum: return "Ejemplo: Bohemian Rhapsody - A Night at the Opera.mp3"
        }
    }
}
