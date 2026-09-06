import SwiftUI
import AppKit

/// Ajustes de la APLICACION. Ojo con la distincion: los ajustes del
/// firmware (tema, animaciones, graficos, EQ...) viven en el iPod y se
/// cambian ahi -- aca solo esta lo que le toca decidir a Studio.
struct SettingsSectionView: View {
    @ObservedObject var preferences: AppPreferences
    /// ST-193: el comprobador de versiones nuevas de la app, para el
    /// botón "Buscar actualizaciones" de la pestaña General. Opcional
    /// para que las vistas previas y cualquier uso suelto sigan
    /// construyendo esta pantalla sin él.
    var appUpdates: AppUpdateChecker?

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

            Divider()

            if let appUpdates {
                AppUpdateSettingsSection(checker: appUpdates,
                                         includePrereleases: $preferences.appUpdatesIncludePrereleases)
                Divider()
            }

            GitHubTokenSettingsView()
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

            linkedFoldersSection

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

    /// Encargo del dueño (2026-08-14): carpetas externas que se
    /// arrastraron a Aura con "Crear copias..." apagado -- solo lectura
    /// mas un boton de quitar, nada de rescanear ni vigilar cambios (ver
    /// `AppPreferences.linkedLibraryFolders`). Se muestra siempre, no
    /// solo con el ajuste apagado: apagarlo despues de haber vinculado
    /// carpetas no debería hacerlas desaparecer de esta lista.
    private var linkedFoldersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bibliotecas vinculadas").font(.headline)
            Text("Carpetas externas que arrastraste a Aura con \"Crear copias de los medios...\" apagado -- Aura no copia nada de ahí, solo las recuerda acá. Quitar una carpeta de esta lista no borra ni desvincula lo que ya importaste desde ella, solo deja de mostrarla.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if preferences.linkedLibraryFolders.isEmpty {
                Text("Todavía no arrastraste ninguna carpeta con ese ajuste apagado.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(preferences.linkedLibraryFolders, id: \.self) { path in
                        HStack(spacing: 10) {
                            Image(systemName: "folder")
                                .foregroundStyle(.tint)
                            Text((path as NSString).abbreviatingWithTildeInPath)
                                .font(.callout.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                preferences.removeLinkedLibraryFolder(path)
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Dejar de mostrar esta carpeta acá")
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
                    }
                }
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

/// ST-193: "Buscar actualizaciones" en Ajustes › General.
///
/// A diferencia del chequeo automático, éste **siempre contesta algo** --
/// el usuario preguntó. Y distingue "no pude preguntar" de "no hay
/// novedades": decir "ya tienes la más nueva" cuando en realidad no hubo
/// red es mentir, y es el defecto que Windows arregló en ST-210 para el
/// chequeo del firmware.
struct AppUpdateSettingsSection: View {
    @ObservedObject var checker: AppUpdateChecker
    @Binding var includePrereleases: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Actualizaciones de Aura Studio").font(.headline)

            HStack(spacing: 10) {
                Text("Versión instalada: \(AppVersion.current)")
                    .font(.callout.monospaced())
                Spacer()
                Button("Buscar actualizaciones") {
                    Task { await checker.checkNow() }
                }
                .disabled(checker.isChecking)
                if checker.isChecking {
                    ProgressView().controlSize(.small)
                }
            }

            if let outcome = checker.lastManualOutcome {
                outcomeText(outcome)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle("Avisarme también de versiones beta", isOn: $includePrereleases)
            Text("Hoy todas las versiones publicadas de Aura Studio son beta, así que conviene dejarlo activado. "
                 + "Aura Studio nunca se actualiza sola: solo te avisa y te deja bajar el instalador.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func outcomeText(_ outcome: AppUpdateDecision.Outcome) -> some View {
        switch outcome {
        case .upToDate:
            Text("Ya tienes la versión más nueva.")
                .foregroundStyle(.secondary)
        case .available(let update):
            Text("Hay una versión nueva: \(update.version.releaseString). El aviso está al pie de la ventana.")
                .foregroundStyle(AuraColors.light.accent)
        case .couldNotCheck(let reason):
            // Se dice QUE no se pudo y POR QUÉ. "No hay novedades" sería
            // una respuesta distinta y no es la que tenemos.
            Text("No se pudo comprobar: \(reason)")
                .foregroundStyle(.secondary)
        }
    }
}
