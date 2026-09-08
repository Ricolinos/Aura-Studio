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
    /// ST-227 (A7b): se acaba de cambiar el idioma y falta preguntar si
    /// reiniciar.
    @State private var askToRestart = false

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
                Text(LS("settings.settings-general")).tag(Tab.general)
                    .accessibilityIdentifier("ajustes.pestana.general")
                Text(LS("settings.settings-library")).tag(Tab.library)
                    .accessibilityIdentifier("ajustes.pestana.almacenamiento")
                Text(LS("settings.music")).tag(Tab.music)
                    .accessibilityIdentifier("ajustes.pestana.musica")
                Text(LS("settings.photos")).tag(Tab.photos)
                    .accessibilityIdentifier("ajustes.pestana.fotos")
                Text(LS("settings.video")).tag(Tab.video)
                    .accessibilityIdentifier("ajustes.pestana.video")
                Text(LS("settings.settings-services")).tag(Tab.services)
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
        .navigationTitle(LS("settings.settings"))
    }

    /// Cierra la app. **No la relanza** (ST-227, A7c addendum; mismo
    /// contrato que Windows).
    ///
    /// A7b relanzaba: abría el proceso nuevo y recién entonces cerraba
    /// este. Suena mejor y es peor. Aura Studio puede tener una
    /// operación de disco a medias --un sync, una conversión, un
    /// flasheo-- y ahí un relanzamiento no se puede prometer: o se
    /// cancela lo que está corriendo, o el proceso nuevo pelea con el
    /// viejo por el mismo iPod. Un botón que a veces no hace lo que dice
    /// enseña a desconfiar de todos los botones. Cierra, y el usuario la
    /// vuelve a abrir.
    ///
    /// Con tareas en curso este camino ni se ofrece -- ver
    /// `hasWorkInFlight`.
    private func closeApp() {
        NSApp.terminate(nil)
    }

    /// Si hay algo corriendo que no se puede cortar a la ligera. El
    /// centro de tareas es la única fuente: si algo no está ahí, es que
    /// no le avisa al usuario tampoco, y eso sería otro bug.
    /// Los publicables, más el que el usuario ya tenga elegido aunque no
    /// esté en la lista. Si alguien probó japonés en una versión
    /// anterior, su `Picker` no puede quedarse en blanco: se lo sigue
    /// mostrando --con su "(beta)" y su advertencia-- hasta que elija
    /// otro. Quitarle de la vista lo que él eligió sería peor que
    /// mantener la fila.
    private var offeredLanguages: [AppLanguage] {
        let publicables = AppLanguage.selectable
        return publicables.contains(preferences.language)
            ? publicables
            : publicables + [preferences.language]
    }

    private var hasWorkInFlight: Bool {
        !library.taskCenter.isEmpty
    }

    /// El título y el mensaje se eligen **acá**, con una clave literal en
    /// cada rama, y no con un ternario adentro de `LS(...)`.
    ///
    /// No es estilo: el inventario de claves
    /// (`LocalizationCatalogTests`) lee el código con una expresión
    /// regular, así que una clave que no sea un literal se vuelve
    /// invisible para él -- y entonces ni la prueba de "no falta
    /// ninguna" ni la de "no sobra ninguna" valen nada. Hay una prueba
    /// que falla si alguien vuelve a meter una clave calculada.
    private var languageAlertTitle: String {
        hasWorkInFlight ? LS("settings.language-busy-title") : LS("settings.language-apply-title")
    }

    private var languageAlertMessage: String {
        hasWorkInFlight ? LS("settings.language-busy-message") : LS("settings.language-apply-message")
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LS("settings.language")).font(.headline)
            // ST-227 (A7b): cada idioma se lista **en su propio
            // idioma**. Alguien que abrió la app en un idioma que no
            // entiende tiene que poder encontrar el suyo, y "Japonés"
            // escrito en español no le sirve de nada.
            Picker(LS("settings.language"), selection: $preferences.language) {
                // ST-227 (A7c, cierre): solo los publicables. Los cuatro
                // traducidos a máquina existen en el catálogo y en el
                // `.app`, pero no se ofrecen hasta que A7d traduzca lo
                // que quedó fuera del catálogo (instalador, DFU,
                // errores) -- media app en japonés es peor que ninguna.
                ForEach(offeredLanguages) { language in
                    Text(language.nativeName).tag(language)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .accessibilityIdentifier("ajustes.general.idioma")
            .onChange(of: preferences.language) { _, _ in askToRestart = true }
            // El idioma no se aplica a medias: o toda la app en el
            // idioma nuevo, o ninguna parte. `AppleLanguages` lo lee el
            // sistema al arrancar, así que hay que volver a abrirla.
            //
            // Con tareas en curso NO se ofrece cerrar: el ajuste ya
            // quedó guardado, y ofrecer un botón que cortaría un sync a
            // la mitad sería ofrecer un daño. Se dice lo que va a pasar
            // y ya.
            .alert(languageAlertTitle, isPresented: $askToRestart) {
                if hasWorkInFlight {
                    Button(LS("themes-view.entendido"), role: .cancel) { }
                        .accessibilityIdentifier("ajustes.general.idioma.entendido")
                } else {
                    Button(LS("settings.language-close-now")) { closeApp() }
                        .accessibilityIdentifier("ajustes.general.idioma.cerrar")
                    Button(LS("settings.language-restart-later"), role: .cancel) { }
                        .accessibilityIdentifier("ajustes.general.idioma.masTarde")
                }
            } message: {
                Text(languageAlertMessage)
            }

            // ST-227 (A7c addendum): se dice que son automáticas. La
            // línea aparece siempre, no solo con uno de esos idiomas
            // elegido: quien está por elegir japonés tiene que verlo
            // ANTES de elegirlo, no después.
            if offeredLanguages.contains(where: \.isMachineTranslated) {
                Text(LS("settings.language-machine-translated"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ajustes.general.idioma.automatica")
            }

            Text(LS("settings.language-note-new"))
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
            Text(LS("settings-page.migrar-version-anterior")).font(.headline)
            Text(LS("settings.migrate-settings-detail"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(LS("settings-page.migrar-biblioteca")) { library.migrateLibrary() }
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
            Text(LS("orphans-title")).font(.headline)
            Text(LS("orphans-detail"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let scan = library.orphanScan {
                if scan.isEmpty {
                    Text(LS("orphans-none-found")).font(.caption)
                } else {
                    Text("\(scan.count) archivos, \(ByteCountFormatter.string(fromByteCount: Int64(scan.totalBytes), countStyle: .file))")
                        .font(.caption.monospaced())
                    Text(LS("orphans-confirm-message"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    if !scan.isEmpty {
                        Button(LS("orphans-clean-button"), role: .destructive) {
                            library.deleteFoundOrphans()
                        }
                        .accessibilityIdentifier("ajustes.almacenamiento.limpiarHuerfanos")
                    }
                    Button("Cancelar") { library.dismissOrphanScan() }
                }
            } else {
                Button(LS("orphans-button")) { library.scanForOrphans() }
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
                Text(LS("storage-section-title")).font(.headline).padding(.top, 4)
                    .accessibilityIdentifier("ajustes.almacenamiento.seccion")
                Toggle(LS("settings-section-view.crear-copias-medios-biblioteca-aura"), isOn: $preferences.copyMediaIntoLibrary)
                VStack(alignment: .leading, spacing: 6) {
                    Text(LS("storage-copy-explainer"))
                    Text(LS("storage-reference-explainer"))
                    Text(LS("storage-change-only-affects-future"))
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
                Text(LS("settings.cover-art")).font(.headline)
                Picker(LS("settings.cover-art"), selection: $preferences.coverArtPolicy) {
                    Text(LS("settings.cover-art-album-only")).tag(AppPreferences.CoverArtPolicy.albumOnly)
                    Text(LS("settings.cover-art-per-track")).tag(AppPreferences.CoverArtPolicy.perTrack)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                Text(preferences.coverArtPolicy == .albumOnly
                     ? LS("settings.cover-art-album-only-detail")
                     : LS("settings.cover-art-per-track-detail"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text(LS("settings.importing")).font(.headline)

                Toggle(LS("settings.enrich-online"), isOn: $preferences.enrichOnline)
                Text(LS("settings.enrich-online-detail"))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(LS("settings.fetch-lyrics"), isOn: $preferences.fetchSyncedLyrics)
                    .disabled(!preferences.enrichOnline)
                Text(LS("settings.fetch-lyrics-detail"))
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
