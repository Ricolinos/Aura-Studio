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
                Text(LS("music-settings-view.carpetas")).font(.headline)
                Picker(LS("music-settings-view.carpetas"), selection: $preferences.musicOrganization) {
                    Text(LS("music-settings-view.artista-album-recomendado")).tag(AppPreferences.MusicOrganization.artistAlbum)
                    Text(LS("music-settings-view.solo-album")).tag(AppPreferences.MusicOrganization.album)
                    Text(LS("music-settings-view.solo-artista")).tag(AppPreferences.MusicOrganization.artist)
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
                Text(LS("music-settings-view.nombre-archivo")).font(.headline)
                Picker(LS("music-settings-view.nombre-archivo"), selection: $preferences.musicFilenameFormat) {
                    Text(LS("music-settings-view.solo-titulo-recomendado")).tag(AppPreferences.MusicFilenameFormat.titleOnly)
                    Text(LS("music-settings-view.numero-pista-titulo")).tag(AppPreferences.MusicFilenameFormat.trackNumberTitle)
                    Text(LS("music-settings-view.titulo-artista")).tag(AppPreferences.MusicFilenameFormat.titleArtist)
                    Text(LS("music-settings-view.titulo-album")).tag(AppPreferences.MusicFilenameFormat.titleAlbum)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text(filenamePreview)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text(LS("music-settings-view.calidad-audio")).font(.headline)
                Picker(LS("music-settings-view.calidad-audio"), selection: $preferences.audioQuality) {
                    Text(LS("music-settings-view.mantener-formato-original-recomendado")).tag(AppPreferences.AudioQuality.originalLossless)
                    Text(LS("music-settings-view.comprimir-mp3-buena-calidad")).tag(AppPreferences.AudioQuality.compressed)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                // ST-223: el aviso sale de `AudioConversionRule`, que es
                // quien de verdad decide -- tener el texto acá y la regla
                // en otro lado es como se llega a que la pantalla prometa
                // una cosa y la app haga otra.
                Text(AudioConversionRule.settingsNotice(audioQuality: preferences.audioQuality))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            artistHomologationSection
        }
    }

    // MARK: - R2-4: homologación de artistas

    @State private var newException = ""

    @ViewBuilder
    private var artistHomologationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LS("music-settings-view.artistas-invitados")).font(.headline)
            Toggle(LS("music-settings-view.agrupar-colaboraciones-bajo-artista-prin"),
                   isOn: $preferences.homologateArtistCollaborations)
            Text(LS("music-settings-view.gorillaz-feat-soul-se-agrupa-junto"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // ST-227: el borrador de la extracción se comió el trozo
            // CALCULADO del medio (la lista de separadores), así que su
            // texto con marcadores no tenía `%@` y la lista habría
            // desaparecido de la pantalla. La clave lleva el marcador.
            // ST-227 (A7c, cierre 6): las DOS listas salen del código.
            // La de "nunca agrupan" estaba escrita a mano en el texto y
            // ya se había desfasado: nombraba «vs.» y «versus», y
            // `neverSeparators` tiene tres entradas -- también el «vs»
            // sin punto. Mismo defecto que Windows encontró de su lado.
            Text(LSf("music-settings-view.separadores-que-agrupan-vs-versus-nunca",
                     Sentence.commaList(ArtistNameNormalizer.collaborationSeparators),
                     Sentence.list(ArtistNameNormalizer.neverSeparators)))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if preferences.homologateArtistCollaborations {
                Text(LS("music-settings-view.excepciones")).font(.subheadline.weight(.medium))
                    .padding(.top, 4)
                Text(LS("music-settings-view.nombres-que-no-se-deben-recortar"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    TextField("Nombre del artista tal como aparece", text: $newException)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addException)
                    Button(LS("music-settings-view.agregar"), action: addException)
                        .disabled(newException.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if preferences.artistHomologationExceptions.isEmpty {
                    Text(LS("music-settings-view.todavia-no-hay-excepciones"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(preferences.artistHomologationExceptions, id: \.self) { name in
                        HStack {
                            Text(name)
                            Spacer()
                            Button {
                                preferences.removeArtistHomologationException(name)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .help(LSf("music-settings-view.quitar-excepciones", name))
                        }
                        .padding(.vertical, 1)
                    }
                }
            }
        }
    }

    private func addException() {
        preferences.addArtistHomologationException(newException)
        newException = ""
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
