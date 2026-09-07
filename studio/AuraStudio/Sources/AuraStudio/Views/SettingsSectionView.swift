import SwiftUI
import AppKit

/// Ajustes de la APLICACION. Ojo con la distincion: los ajustes del
/// firmware (tema, animaciones, graficos, EQ...) viven en el iPod y se
/// cambian ahi -- aca solo esta lo que le toca decidir a Studio.
struct SettingsSectionView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var library: LibraryViewModel
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
            // ST-225 (addendum): identificadores estables para el arnés
            // de capturas. Mismo esquema que la barra lateral de ST-188:
            // sin ellos no se puede llegar a Ajustes › Biblioteca desde
            // fuera, y una captura que hay que tomar a mano es una que
            // deja de tomarse.
            Picker("", selection: $tab) {
                Text(S.settingsGeneral.text).tag(Tab.general)
                    .accessibilityIdentifier("ajustes.pestana.general")
                Text(S.settingsLibrary.text).tag(Tab.library)
                    .accessibilityIdentifier("ajustes.pestana.almacenamiento")
                Text(S.music.text).tag(Tab.music)
                    .accessibilityIdentifier("ajustes.pestana.musica")
                Text(S.photos.text).tag(Tab.photos)
                    .accessibilityIdentifier("ajustes.pestana.fotos")
                Text(S.video.text).tag(Tab.video)
                    .accessibilityIdentifier("ajustes.pestana.video")
                Text(S.settingsServices.text).tag(Tab.services)
                    .accessibilityIdentifier("ajustes.pestana.servicios")
            }
            .accessibilityIdentifier("ajustes.pestanas")
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

    /// ST-226: "Migrar biblioteca", siempre disponible.
    ///
    /// Está acá **además** de en la franja porque hay un caso que la
    /// detección barata no ve: una copia cuyas etiquetas no coinciden con
    /// el catálogo solo se detecta abriendo el archivo, y eso no se hace
    /// al arrancar. Una biblioteca cuyo único problema sea ese no dispara
    /// la franja, y sin este botón no habría forma de arreglarla.
    @ViewBuilder
    private var migrationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(S.migrateSectionTitle.text).font(.headline)
            Text(S.migrateSettingsDetail.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(S.migrateButton.text) { library.migrateLibrary() }
                .accessibilityIdentifier("ajustes.almacenamiento.migrar")
                .disabled(library.isMigrating)
        }
    }

    /// ST-225: "Limpiar archivos huérfanos".
    ///
    /// Dos pasos a propósito: primero se busca y se dice **cuántos son y
    /// cuánto ocupan**, y solo después se borra. Un botón que borra sin
    /// decir qué no se puede usar con confianza -- y estos archivos son
    /// nuestros, pero están dentro de la carpeta del usuario.
    @ViewBuilder
    private var orphansSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(S.orphansTitle.text).font(.headline)
            Text(S.orphansDetail.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let scan = library.orphanScan {
                if scan.isEmpty {
                    Text(S.orphansNoneFound.text).font(.caption)
                } else {
                    Text("\(scan.count) archivos, \(ByteCountFormatter.string(fromByteCount: Int64(scan.totalBytes), countStyle: .file))")
                        .font(.caption.monospaced())
                    Text(S.orphansConfirmMessage.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    if !scan.isEmpty {
                        Button(S.orphansCleanButton.text, role: .destructive) {
                            library.deleteFoundOrphans()
                        }
                        .accessibilityIdentifier("ajustes.almacenamiento.limpiarHuerfanos")
                    }
                    Button("Cancelar") { library.dismissOrphanScan() }
                }
            } else {
                Button(S.orphansButton.text) { library.scanForOrphans() }
                    .accessibilityIdentifier("ajustes.almacenamiento.buscarHuerfanos")
            }
        }
    }

    private var libraryTab: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text(LS("settings-section-view.carpeta-biblioteca-aura")).font(.headline)
                Text(LS("settings-section-view.aqui-vive-catalogo-tu-biblioteca-funcion"))
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
                    Button(LS("albums-view.mostrar-finder")) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: preferences.libraryFolderPath, isDirectory: true))
                    }
                    Button(LS("settings-section-view.cambiar")) {
                        chooseLibraryFolder()
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))

                // ST-225: los dos modos se explican con sus beneficios
                // Y sus desventajas, y los dos se leen SIEMPRE -- no solo
                // el que está activo. Elegir entre dos opciones viendo lo
                // que dice una sola no es elegir.
                Text(S.storageSectionTitle.text).font(.headline).padding(.top, 4)
                    .accessibilityIdentifier("ajustes.almacenamiento.seccion")
                Toggle(LS("settings-section-view.crear-copias-medios-biblioteca-aura"), isOn: $preferences.copyMediaIntoLibrary)
                VStack(alignment: .leading, spacing: 6) {
                    Text(S.storageCopyExplainer.text)
                    Text(S.storageReferenceExplainer.text)
                    Text(S.storageChangeOnlyAffectsFuture.text)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            orphansSection

            Divider()

            migrationSection

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
            Text(LS("settings-section-view.bibliotecas-vinculadas")).font(.headline)
            Text(LS("settings-section-view.carpetas-externas-que-arrastraste-aura-c"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if preferences.linkedLibraryFolders.isEmpty {
                Text(LS("settings-section-view.todavia-no-arrastraste-ninguna-carpeta-c"))
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
                            .help(LS("settings-section-view.dejar-mostrar-esta-carpeta-aca"))
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
            Text(LS("settings-section-view.actualizaciones-aura-studio")).font(.headline)

            HStack(spacing: 10) {
                Text(LSf("settings-section-view.version-instalada", AppVersion.current))
                    .font(.callout.monospaced())
                Spacer()
                Button(LS("settings-section-view.buscar-actualizaciones")) {
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

            Toggle(LS("settings-section-view.avisarme-tambien-versiones-beta"), isOn: $includePrereleases)
            Text(LS("settings-section-view.hoy-todas-versiones-publicadas-aura-stud"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func outcomeText(_ outcome: AppUpdateDecision.Outcome) -> some View {
        switch outcome {
        case .upToDate:
            Text(LS("settings-section-view.ya-tienes-version-mas-nueva"))
                .foregroundStyle(.secondary)
        case .available(let update):
            Text(LSf("settings-section-view.hay-version-nueva-aviso-esta-al", update.version.releaseString))
                .foregroundStyle(AuraColors.light.accent)
        case .couldNotCheck(let reason):
            // Se dice QUE no se pudo y POR QUÉ. "No hay novedades" sería
            // una respuesta distinta y no es la que tenemos.
            Text(LSf("settings-section-view.no-se-pudo-comprobar", reason))
                .foregroundStyle(.secondary)
        }
    }
}
