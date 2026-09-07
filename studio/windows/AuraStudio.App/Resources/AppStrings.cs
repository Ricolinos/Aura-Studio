using System.Globalization;
using AuraStudio.Core.Library;
using AuraStudio.Core.Resources;

namespace AuraStudio.App.Resources;

/// <summary>
/// Los textos de cara al usuario, uno por propiedad — equivalente de
/// <c>AppStrings.swift</c> (macOS).
///
/// <para><b>Qué era y qué es ahora.</b> Hasta ST-247 esta clase <i>era</i> la
/// tabla: cada propiedad devolvía su literal en español. ST-079 lo había
/// decidido así con tres argumentos, y el que dejó de valer es el tercero —
/// "esta app tiene un solo idioma". La ronda "ajustes 3" trae los demás
/// idiomas, y quinientas cadenas con un <c>if</c> por cadena no es una tabla,
/// es un problema. Los textos se mudaron a un <c>.resx</c> en Core; el porqué
/// de <c>.resx</c> y no <c>.resw</c> está en <see cref="Strings"/>.</para>
///
/// <para><b>Y por qué la clase sigue existiendo.</b> Los otros dos argumentos
/// de ST-079 siguen siendo buenos y no se pierden: cada texto es una
/// <b>propiedad</b>, así que una clave mal escrita es un error de compilación y
/// no un hueco en la pantalla; y el XAML sigue diciendo
/// <c>{x:Bind res:AppStrings.NavGeneral}</c> sin cambiar de forma. Lo único que
/// cambió es de dónde sale el texto.</para>
///
/// <para><b>Cero literales acá.</b> Un texto escrito en este archivo no llega
/// nunca a traducirse: no está en el <c>.resx</c> y nadie lo va a extrañar
/// hasta verlo en español en una pantalla en alemán. Lo comprueba una prueba
/// (<c>NoHayTextoEnEspanolEnElCodigo</c>), no la disciplina.</para>
///
/// <para><b>Plurales.</b> Nunca <c>count == 1 ? … : …</c>: eso es la regla del
/// español escrita a mano, y en ruso hacen falta tres formas y en japonés una.
/// Va por <see cref="Strings.Plural"/>, que elige la forma según la cultura
/// activa.</para>
/// </summary>
public static class AppStrings
{
    // MARK: - Identidad de la app

    public static string AppName => Strings.Get("app-strings.app-name");

    // MARK: - Barra de navegación (equivalente al sidebar de macOS)

    public static string NavGeneral => Strings.Get("app-strings.nav-general");
    public static string NavMusic => Strings.Get("app-strings.nav-music");
    public static string NavArtists => Strings.Get("app-strings.nav-artists");
    public static string NavAlbums => Strings.Get("app-strings.nav-albums");
    public static string NavSongs => Strings.Get("app-strings.nav-songs");
    public static string NavPlaylists => Strings.Get("app-strings.nav-playlists");
    public static string NavVideo => Strings.Get("app-strings.nav-video");
    public static string NavMovies => Strings.Get("app-strings.nav-movies");
    public static string NavSeries => Strings.Get("app-strings.nav-series");
    public static string NavClips => Strings.Get("app-strings.nav-clips");
    public static string NavAllVideos => Strings.Get("app-strings.nav-all-videos");
    public static string NavPhotos => Strings.Get("app-strings.nav-photos");
    public static string NavPhotosPhotos => Strings.Get("app-strings.nav-photos-photos");
    public static string NavPhotosImages => Strings.Get("app-strings.nav-photos-images");
    public static string NavPhotosAI => Strings.Get("app-strings.nav-photos-ai");
    public static string NavAllPhotos => Strings.Get("app-strings.nav-all-photos");
    public static string NavExtras => Strings.Get("app-strings.nav-extras");
    public static string NavInstaller => Strings.Get("app-strings.nav-installer");
    public static string NavThemes => Strings.Get("app-strings.nav-themes");
    public static string NavSettings => Strings.Get("app-strings.nav-settings");

    // MARK: - Estado del dispositivo

    public static string NoDevice => Strings.Get("app-strings.no-device");
    public static string DeviceDetecting => Strings.Get("app-strings.device-detecting");
    public static string DeviceNotConnected => Strings.Get("app-strings.device-not-connected");

    /// <summary>
    /// Regla de seguridad del repo: con dos discos que califican no se elige
    /// "el más probable" — se detiene y se le dice al usuario. Nunca se
    /// muestran los candidatos como seleccionables.
    /// </summary>
    public static string DeviceAmbiguous(int count) =>
        Strings.Format("app-strings.device-ambiguous", count);

    public static string DeviceConnected(string name) =>
        Strings.Format("app-strings.device-connected", name);

    /// <summary>
    /// Mismo criterio que macOS: la biblioteca se bloquea cuando hay un iPod
    /// conectado cuyo firmware NO habla el contrato de Aura. General y Extras
    /// quedan siempre accesibles (ahí se explica qué firmware hay y qué hacer).
    /// </summary>
    public static string LibraryLockedReason => Strings.Get("app-strings.library-locked-reason");

    public static string LibraryAvailableWithoutDevice => Strings.Get("app-strings.library-available-without-device");

    // MARK: - Biblioteca

    public static string LibraryEmpty => Strings.Get("app-strings.library-empty");

    // La biblioteca no está donde dice (ST-171). Un disco externo desconectado
    // es un estado normal, no un error: se cuenta en la ventana, con la ruta
    // completa —para que el usuario reconozca CUÁL biblioteca falta— y con lo
    // que puede hacer.

    public static string LibraryRootMissing(string root) =>
        string.IsNullOrWhiteSpace(root)
            ? Strings.Get("app-strings.library-root-missing-1")
            : Strings.Format("app-strings.library-root-missing-2", root);

    public static string LibraryRootMissingDetail => Strings.Get("library-unavailable-view.no-se-perdio-nada-tu-catalogo");

    public static string LibraryRootRetry => Strings.Get("done-view.reintentar");
    public static string LibraryRootChoose => Strings.Get("library-unavailable-view.elegir-otra-biblioteca");
    public static string LibraryRootCreate => Strings.Get("library-unavailable-view.crear-nueva");

    public static string LibraryDropHint(LibraryItemKind kind) => kind switch
    {
        LibraryItemKind.Music => Strings.Get("app-strings.library-drop-hint-libraryitemkind-music"),
        LibraryItemKind.Video => Strings.Get("app-strings.library-drop-hint-libraryitemkind-video"),
        LibraryItemKind.Photo => Strings.Get("app-strings.library-drop-hint-libraryitemkind-photo"),
        _ => Strings.Get("app-strings.library-drop-hint-texto")
    };

    /// <summary>
    /// Se dice de frente en cada sección: es la regla de ST-012 y explicarla
    /// antes evita que el usuario crea que la app perdió sus archivos.
    /// </summary>
    public static string LibrarySectionOnlyItsType(LibraryItemKind kind) => kind switch
    {
        LibraryItemKind.Music => Strings.Get("app-strings.library-section-only-its-type-libraryitemkind-music"),
        LibraryItemKind.Video => Strings.Get("app-strings.library-section-only-its-type-libraryitemkind-video"),
        LibraryItemKind.Photo => Strings.Get("app-strings.library-section-only-its-type-libraryitemkind-photo"),
        _ => ""
    };

    /// <summary>Versiones sin parámetro, para enlazar desde XAML con <c>x:Bind</c>.</summary>
    public static string LibrarySectionOnlyItsTypeMusic => LibrarySectionOnlyItsType(LibraryItemKind.Music);
    public static string LibrarySectionOnlyItsTypeVideo => LibrarySectionOnlyItsType(LibraryItemKind.Video);
    public static string LibrarySectionOnlyItsTypePhoto => LibrarySectionOnlyItsType(LibraryItemKind.Photo);

    public static string LibraryNothingHereYet => Strings.Get("app-strings.library-nothing-here-yet");

    public static string LibraryOpenFolder => Strings.Get("app-strings.library-open-folder");
    public static string LibraryAddFiles => Strings.Get("app-strings.library-add-files");
    public static string LibraryAddFolder => Strings.Get("app-strings.library-add-folder");
    public static string LibraryRemove => Strings.Get("app-strings.library-remove");

    // MARK: - Eliminar, con confirmación (ST-245)

    /// <summary>
    /// El título del diálogo de confirmación. Dice cuántos, no "esto no se
    /// puede deshacer" —para lo que sí va a la Papelera, se puede—.
    /// </summary>
    public static string DeleteConfirmTitle(int totalCount) =>
        Strings.Plural("app-strings.delete-confirm-title", totalCount);

    /// <summary>
    /// El cuerpo del diálogo (§0.4 del plan): cuántos archivos van a la
    /// Papelera y cuánto ocupan —lo único que de verdad se toca en disco—, y
    /// cuántos son puramente de catálogo. Un lote puede traer las dos cosas
    /// mezcladas.
    /// </summary>
    public static string DeleteConfirmMessage(DeletionPreview preview)
    {
        var parts = new List<string>();

        if (preview.CopyCount > 0)
        {
            string bytes = SimilarityText.FormatBytes(preview.CopyBytes);
            parts.Add(Strings.Plural("app-strings.delete-confirm-copy", preview.CopyCount, bytes));
        }

        if (preview.ReferenceCount > 0)
        {
            parts.Add(Strings.Plural("app-strings.delete-confirm-reference", preview.ReferenceCount));
        }

        return string.Join(" ", parts);
    }

    public static string DeleteConfirmPrimary => Strings.Get("artists-view.eliminar");
    public static string DeleteConfirmCancel => Strings.Get("background-task-center-indicator.cancelar");

    /// <summary>
    /// El aviso de duplicados por parecido, al terminar de soltar archivos
    /// (ST-243 dejó el gancho, B5 lo conecta): no hay pantalla nueva, solo
    /// apunta a la que ya existe.
    /// </summary>
    public static string LibrarySimilarFoundOnDrop(string summary) =>
        Strings.Format("app-strings.library-similar-found-on-drop", summary);
    public static string LibraryFavoritesOnly => Strings.Get("app-strings.library-favorites-only");
    public static string LibraryColumns => Strings.Get("app-strings.library-columns");
    public static string LibraryColumnsDetail => Strings.Get("app-strings.library-columns-detail");
    public static string LibrarySortBy => Strings.Get("app-strings.library-sort-by");
    public static string LibrarySortAscending => Strings.Get("app-strings.library-sort-ascending");
    public static string LibraryUnknownArtist => LibraryGrouping.UnknownArtistName;

    public static string LibraryTracks(int count) => Strings.Plural("conteo.canciones", count);
    public static string LibraryEpisodes(int count) => Strings.Plural("conteo.episodios", count);
    public static string LibraryPhotos(int count) => Strings.Plural("conteo.fotos", count);

    // "Sin temporada" y "Temporada 3" no son el singular y el plural de lo
    // mismo: son dos mensajes distintos que elige un centinela, no una
    // cantidad. Por eso van como dos claves y no como formas de plural.
    public static string LibrarySeason(int number) =>
        number == VideoCollectionGroup.NoSeasonNumber
            ? Strings.Get("app-strings.library-season-1")
            : Strings.Format("app-strings.library-season-2", number);

    public static string LibraryKind(LibraryItemKind kind) => kind switch
    {
        LibraryItemKind.Music => Strings.Get("app-strings.library-kind-libraryitemkind-music"),
        LibraryItemKind.Video => Strings.Get("app-strings.library-kind-libraryitemkind-video"),
        LibraryItemKind.Photo => Strings.Get("app-strings.library-kind-libraryitemkind-photo"),
        _ => Strings.Get("app-strings.library-kind-texto")
    };

    /// <summary>
    /// El estado en una frase corta. El transcodificado dice su avance porque
    /// es el único que puede tardar minutos y el usuario necesita ver que
    /// avanza; el fallido dice el motivo, nunca solo "falló".
    /// </summary>
    public static string LibraryStatus(LibraryItemStatus status) => status.State switch
    {
        LibraryItemState.Queued => Strings.Get("app-strings.library-status-libraryitemstate-queued"),
        LibraryItemState.Enriching => Strings.Get("app-strings.library-status-libraryitemstate-enrichi"),
        LibraryItemState.Transcoding => Strings.Format(
            "app-strings.library-status-libraryitemstate-transco",
            (status.Progress * 100).ToString("0", CultureInfo.CurrentCulture)),
        LibraryItemState.Ready => Strings.Get("app-strings.library-status-libraryitemstate-ready"),
        LibraryItemState.NeedsReview => Strings.Get("app-strings.library-status-libraryitemstate-needsre"),
        _ => status.Error is { Length: > 0 } error
            ? Strings.Format("app-strings.library-status-6", error)
            : Strings.Get("app-strings.library-status-7")
    };

    // MARK: - General (vista del dispositivo)

    public static string GeneralTitle => Strings.Get("app-strings.general-title");
    public static string GeneralSubtitle => Strings.Get("app-strings.general-subtitle");
    public static string SectionStorage => Strings.Get("app-strings.section-storage");
    public static string SectionContent => Strings.Get("app-strings.section-content");
    public static string LabelCapacity => Strings.Get("app-strings.label-capacity");
    public static string LabelUsed => Strings.Get("app-strings.label-used");
    public static string LabelFree => Strings.Get("app-strings.label-free");
    public static string LabelFileSystem => Strings.Get("app-strings.label-file-system");
    public static string LabelMusic => Strings.Get("app-strings.label-music");
    public static string LabelVideo => Strings.Get("app-strings.label-video");
    public static string LabelPhotos => Strings.Get("app-strings.label-photos");
    public static string LabelPlaylists => Strings.Get("app-strings.label-playlists");
    public static string ActionRefresh => Strings.Get("app-strings.action-refresh");
    public static string ActionRefreshHelp => Strings.Get("app-strings.action-refresh-help");
    public static string ActionOpenInExplorer => Strings.Get("app-strings.action-open-in-explorer");
    public static string ActionEject => Strings.Get("app-strings.action-eject");
    public static string EjectRequested => Strings.Get("app-strings.eject-requested");
    public static string EjectFailed => Strings.Get("app-strings.eject-failed");
    public static string NeverSynced => Strings.Get("app-strings.never-synced");
    public static string LastSyncSummary => Strings.Get("app-strings.last-sync-summary");
    public static string DeclaredFamilyLabel => Strings.Get("app-strings.declared-family-label");
    public static string NotAvailable => Strings.Get("app-strings.not-available");

    // MARK: - Ajustes

    public static string SettingsTitle => Strings.Get("app-strings.settings-title");
    public static string SettingsSubtitle => Strings.Get("app-strings.settings-subtitle");
    public static string SettingsAppearance => Strings.Get("app-strings.settings-appearance");
    public static string SettingsTheme => Strings.Get("app-strings.settings-theme");
    public static string SettingsThemeDetail => Strings.Get("app-strings.settings-theme-detail");
    /// <summary>
    /// macOS tiene selector de idioma (español/inglés). Windows no: por regla
    /// del repo esta app es de un solo idioma, y se decidió no traer el
    /// mecanismo de macOS sin quién lo consuma (ST-079). Se dice acá en vez de
    /// dejar la sección ausente sin explicación.
    /// </summary>
    public static string SettingsLanguageDetail => Strings.Get("app-strings.settings-language-detail");

    public static string ThemeSystem => Strings.Get("app-strings.theme-system");
    public static string ThemeLight => Strings.Get("app-strings.theme-light");
    public static string ThemeDark => Strings.Get("app-strings.theme-dark");
    public static string SettingsAbout => Strings.Get("app-strings.settings-about");

    // MARK: - Cómo guardar tu música (ST-245, plan §2 — texto compartido con la Mac)

    public static string StorageSectionTitle => Strings.Get("storage-section-title");

    /// <summary>
    /// Beneficios y desventajas de "Copiar a la Biblioteca de Aura" — texto
    /// fijado por la Maestra en el plan §2, el mismo en las dos plataformas.
    /// No es una decisión de Windows: si cambia, cambia en el plan primero.
    /// </summary>
    public static string StorageCopyExplainer => Strings.Get("storage-copy-explainer");

    /// <summary>Igual que <see cref="StorageCopyExplainer"/>, para "Referenciar en su lugar".</summary>
    public static string StorageReferenceExplainer => Strings.Get("storage-reference-explainer");

    public static string StorageChangeOnlyAffectsFuture => Strings.Get("storage-change-only-affects-future");

    // MARK: - Limpiar archivos huérfanos (ST-245)

    public static string OrphansTitle => Strings.Get("orphans-title");
    public static string OrphansDetail => Strings.Get("orphans-detail");

    public static string OrphansButton => Strings.Get("orphans-button");
    public static string OrphansCleanButton => Strings.Get("orphans-clean-button");

    public static string OrphansNoneFound => Strings.Get("orphans-none-found");

    public static string OrphansFound(OrphanScanResult scan) =>
        Strings.Plural("app-strings.orphans-found", scan.Count, SimilarityText.FormatBytes(scan.TotalBytes));

    public static string OrphansConfirmTitle(int count) =>
        Strings.Plural("app-strings.orphans-confirm-title", count);

    /// <summary>
    /// Se arma con DOS recursos y no con uno (decisión de la Maestra, ST-247).
    ///
    /// <para>La segunda oración es la misma que dice la Mac, palabra por
    /// palabra, así que es una clave compartida y se traduce una sola vez.
    /// Windows además antepone el conteo, que es una oración propia con su
    /// número. Metiendo el hueco dentro de la clave compartida el texto dejaba
    /// de ser idéntico al de la Mac y la comparación exacta no calzaba; unidas
    /// acá con un espacio, calza y cada mitad vive donde le toca.</para>
    /// </summary>
    public static string OrphansConfirmMessage(OrphanScanResult scan) =>
        OrphansFound(scan) + " " + Strings.Get("orphans-confirm-message");

    public static string OrphansCleaned(int count) =>
        Strings.Plural("app-strings.orphans-cleaned", count);

    // MARK: - Instalador

    public static string InstallerTitle => Strings.Get("app-strings.installer-title");
    public static string InstallerSubtitle => Strings.Get("app-strings.installer-subtitle");

    public static string InstallerWelcomeTitle => Strings.Get("app-strings.installer-welcome-title");
    public static string InstallerWelcomeDetail => Strings.Get("app-strings.installer-welcome-detail");
    public static string InstallerWelcomeWarning => Strings.Get("app-strings.installer-welcome-warning");
    public static string InstallerBegin => Strings.Get("app-strings.installer-begin");
    public static string InstallerFamilyLabel => Strings.Get("app-strings.installer-family-label");

    public static string InstallerPermissionsTitle => Strings.Get("app-strings.installer-permissions-title");
    public static string InstallerPermissionsDetail => Strings.Get("app-strings.installer-permissions-detail");
    public static string InstallerPermissionsContinue => Strings.Get("app-strings.installer-permissions-continue");

    public static string InstallerDetectTitle => Strings.Get("app-strings.installer-detect-title");
    public static string InstallerDetectDetail => Strings.Get("app-strings.installer-detect-detail");
    public static string InstallerNoDevice => Strings.Get("app-strings.installer-no-device");
    public static string InstallerNeedsMountedVolume => Strings.Get("app-strings.installer-needs-mounted-volume");

    public static string LabelDevice => Strings.Get("app-strings.label-device");
    public static string LabelUnit => Strings.Get("app-strings.label-unit");
    public static string LabelBus => Strings.Get("app-strings.label-bus");
    public static string LabelFirmware => Strings.Get("app-strings.label-firmware");

    /// <summary>
    /// Cambiar de familia no es un error (el árbol saliente se guarda entero y
    /// se puede volver a él), pero nunca puede pasar en silencio.
    /// </summary>
    public static string InstallerFamilyChange(string installed, string target) =>
        Strings.Format("app-strings.installer-family-change", installed, target);

    public static string InstallerPrepareDisk => Strings.Get("app-strings.installer-prepare-disk");
    public static string InstallerDryRun => Strings.Get("app-strings.installer-dry-run");
    public static string InstallerDryRunRunning => Strings.Get("app-strings.installer-dry-run-running");
    public static string InstallerDryRunOk => Strings.Get("app-strings.installer-dry-run-ok");
    public static string InstallerFormatRunning => Strings.Get("app-strings.installer-format-running");
    public static string InstallerFormatNeedsDryRun => Strings.Get("app-strings.installer-format-needs-dry-run");
    /// <summary>
    /// El botón destructivo **nombra el disco**. Un botón que dice "Dar formato
    /// ahora" a secas, con el estilo de acento y solo en la pantalla, tiene la
    /// forma de un "Continuar" — y el dueño formateó dos veces creyendo que solo
    /// estaba probando el software.
    /// </summary>
    public static string InstallerFormatNowOn(string target) =>
        Strings.Format("app-strings.installer-format-now-on", target);

    public static string InstallerFormatDangerHeading => Strings.Get("app-strings.installer-format-danger-heading");

    public static string InstallerFormatDangerDetail => Strings.Get("app-strings.installer-format-danger-detail");

    public static string InstallerFormatConfirm(string target) =>
        Strings.Format("app-strings.installer-format-confirm", target);

    public static string InstallerFormatNeedsConfirmation => Strings.Get("app-strings.installer-format-needs-confirmation");

    public static string InstallerDryRunHeading => Strings.Get("app-strings.installer-dry-run-heading");
    public static string InstallerPrivilegedLogHeading => Strings.Get("app-strings.installer-privileged-log-heading");

    public static string InstallerSafetyAbort(string reason) =>
        Strings.Format("app-strings.installer-safety-abort", reason);

    public static string InstallerUnknownDisk(string path) =>
        Strings.Format("app-strings.installer-unknown-disk", path);

    public static string InstallerCopyingTitle => Strings.Get("app-strings.installer-copying-title");
    public static string InstallerCopyFiles => Strings.Get("app-strings.installer-copy-files");
    public static string InstallerCopyFailed => Strings.Get("app-strings.installer-copy-failed");
    // Decía "1 archivos escritos" con uno solo. B7a lo dejó así a propósito
    // —mover no es redactar— y B7b lo arregla, que es cuando toca: el plural
    // del español deja de estar escrito a mano en la frase.
    public static string InstallerCopiedFiles(int count) =>
        Strings.Plural("app-strings.installer-copied-files", count);

    // Los pasos son los mismos de `EnterDFUView.swift` (macOS), que a su vez
    // sale del README de mks5lboot y de la guía de flasheo del firmware —
    // ninguno se inventa acá. Solo cambia el español: el original está en
    // voseo y el repo pide español de México sin voseo.
    public static string InstallerEnterDfuTitle => Strings.Get("app-strings.installer-enter-dfu-title");

    public static string InstallerEnterDfuWhen => Strings.Get("app-strings.installer-enter-dfu-when");

    public static string InstallerDfuStep1 => Strings.Get("app-strings.installer-dfu-step1");
    public static string InstallerDfuStep2 => Strings.Get("app-strings.installer-dfu-step2");
    public static string InstallerDfuStep3 => Strings.Get("app-strings.installer-dfu-step3");
    public static string InstallerDfuStep4 => Strings.Get("app-strings.installer-dfu-step4");

    /// <summary>El error más común: soltar en cuanto la pantalla se apaga.</summary>
    public static string InstallerDfuTimingWarning => Strings.Get("app-strings.installer-dfu-timing-warning");

    public static string InstallerDfuGuideLink => Strings.Get("app-strings.installer-dfu-guide-link");
    public static string InstallerDfuGuideUrl => Strings.Get("app-strings.installer-dfu-guide-url");

    public static string InstallerDfuWaiting => Strings.Get("app-strings.installer-dfu-waiting");

    // MARK: - Reconocimiento automático de DFU

    public static string InstallerDfuDetectedTitle => Strings.Get("app-strings.installer-dfu-detected-title");
    public static string InstallerDfuDetectedDetail => Strings.Get("app-strings.installer-dfu-detected-detail");
    public static string InstallerDfuDetectedInstall => Strings.Get("app-strings.installer-dfu-detected-install");
    public static string InstallerDfuDetectedDismiss => Strings.Get("app-strings.installer-dfu-detected-dismiss");
    public static string InstallerDfuNoFamilies => Strings.Get("app-strings.installer-dfu-no-families");
    public static string InstallerScanDfu => Strings.Get("app-strings.installer-scan-dfu");
    public static string InstallerScanningDfu => Strings.Get("app-strings.installer-scanning-dfu");
    public static string InstallerDfuFound(int? state) =>
        state is null
            ? Strings.Get("app-strings.installer-dfu-found-1")
            : Strings.Format("app-strings.installer-dfu-found-2", state);
    public static string InstallerDfuNotFound => Strings.Get("app-strings.installer-dfu-not-found");

    /// <summary>
    /// El controlador está y aun así Windows no ve ningún aparato de Apple. Muy
    /// probablemente el iPod sí entró en DFU pero su USB no llega hasta acá —
    /// el caso típico de una máquina virtual sin el dispositivo redirigido.
    /// </summary>
    public static string InstallerDfuNotSeenByWindows => Strings.Get("app-strings.installer-dfu-not-seen-by-windows");
    public static string InstallerDfuUnreadable => Strings.Get("app-strings.installer-dfu-unreadable");

    public static string InstallerFlash => Strings.Get("app-strings.installer-flash");
    public static string InstallerFlashing => Strings.Get("app-strings.installer-flashing");
    public static string InstallerFlashConfirm => Strings.Get("app-strings.installer-flash-confirm");
    public static string InstallerFlashNeedsConfirmation => Strings.Get("app-strings.installer-flash-needs-confirmation");
    public static string InstallerFlashFailed => Strings.Get("app-strings.installer-flash-failed");
    public static string InstallerAwaitingReboot => Strings.Get("app-strings.installer-awaiting-reboot");
    public static string InstallerRebooted => Strings.Get("app-strings.installer-rebooted");
    public static string InstallerStuckInDfu => Strings.Get("app-strings.installer-stuck-in-dfu");

    // MARK: - Actualizar el arranque (ST-143, ST-168)
    //
    // La pantalla responde las cuatro preguntas que cualquiera se hace antes de
    // apretar un botón que pide modo DFU: qué es el arranque, por qué hace falta
    // DFU, qué NO se toca y —la que evita una llamada de soporte— que no es
    // obligatorio.

    public static string BootloaderUpdateOffer => Strings.Get("app-strings.bootloader-update-offer");

    public static string BootloaderUpdateOfferDifferent => Strings.Get("app-strings.bootloader-update-offer-different");

    public static string BootloaderUpdateOfferUnknown => Strings.Get("app-strings.bootloader-update-offer-unknown");

    public static string BootloaderUpdateTitle => Strings.Get("app-strings.bootloader-update-title");

    public static string BootloaderUpdateWhatItIs => Strings.Get("app-strings.bootloader-update-what-it-is");

    public static string BootloaderUpdateWhyDfu => Strings.Get("app-strings.bootloader-update-why-dfu");

    public static string BootloaderUpdateNothingTouched => Strings.Get("app-strings.bootloader-update-nothing-touched");

    public static string BootloaderUpdateNotRequired => Strings.Get("app-strings.bootloader-update-not-required");

    public static string BootloaderUpdateNoPassword => Strings.Get("app-strings.bootloader-update-no-password");

    public static string BootloaderUpdateContinue => Strings.Get("app-strings.bootloader-update-continue");

    public static string BootloaderUpdateEnterDfuWhen => Strings.Get("app-strings.bootloader-update-enter-dfu-when");

    public static string BootloaderUpdateFlashConfirm => Strings.Get("app-strings.bootloader-update-flash-confirm");

    /// <summary>
    /// El nombre de la familia va adentro: se está regrabando SU arranque, no
    /// uno genérico — a un iPod con Metro se le graba el de Metro.
    /// </summary>
    public static string BootloaderUpdateFlashing(string? family) =>
        string.IsNullOrWhiteSpace(family)
            ? Strings.Get("app-strings.bootloader-update-flashing-1")
            : Strings.Format("app-strings.bootloader-update-flashing-2", family);

    public static string BootloaderUpdateAwaitingReboot => Strings.Get("app-strings.bootloader-update-awaiting-reboot");

    public static string BootloaderUpdateDoneTitle => Strings.Get("app-strings.bootloader-update-done-title");

    public static string BootloaderUpdateDoneDetail => Strings.Get("app-strings.bootloader-update-done-detail");

    // MARK: - La salida cuando el DFU no aparece (ST-169)

    public static string ServicePauseTitle => Strings.Get("app-strings.service-pause-title");

    public static string ServicePauseDetail => Strings.Get("app-strings.service-pause-detail");

    /// <summary>Se dice antes de apretar, no después: es el único permiso de este flujo.</summary>
    public static string ServicePauseAsksForPermission => Strings.Get("app-strings.service-pause-asks-for-permission");

    public static string ServicePauseButton => Strings.Get("app-strings.service-pause-button");

    public static string ServicePauseNotRunning => Strings.Get("app-strings.service-pause-not-running");

    public static string InstallerDoneTitle => Strings.Get("app-strings.installer-done-title");
    public static string InstallerDoneDetail => Strings.Get("app-strings.installer-done-detail");
    public static string InstallerFailedTitle => Strings.Get("app-strings.installer-failed-title");
    public static string InstallerRestart => Strings.Get("app-strings.installer-restart");
    public static string InstallerCancelled => Strings.Get("app-strings.installer-cancelled");
    public static string InstallerAlreadyWriting => Strings.Get("app-strings.installer-already-writing");
    public static string InstallerArtifactsInvalid => Strings.Get("app-strings.installer-artifacts-invalid");

    // MARK: - Controlador de DFU

    public static string DfuDriverHeading => Strings.Get("app-strings.dfu-driver-heading");

    public static string DfuDriverReady(string device) =>
        Strings.Format("app-strings.dfu-driver-ready", device);
    public static string DfuDriverMissing => Strings.Get("app-strings.dfu-driver-missing");
    public static string DfuDriverInstalledNoDevice => Strings.Get("app-strings.dfu-driver-installed-no-device");
    public static string DfuDriverPackageMissing => Strings.Get("app-strings.dfu-driver-package-missing");
    public static string DfuDriverUnknown => Strings.Get("app-strings.dfu-driver-unknown");

    // MARK: - Licencias (contrato §B, GPL v2)

    public static string LicensesTitle => Strings.Get("app-strings.licenses-title");
    public static string LicensesSubtitle => Strings.Get("app-strings.licenses-subtitle");
    public static string LicensesOpen => Strings.Get("app-strings.licenses-open");

    public static string LicensesIntro => Strings.Get("app-strings.licenses-intro");

    public static string LicensesFamiliesHeading => Strings.Get("app-strings.licenses-families-heading");
    public static string LicensesRepositoryLabel => Strings.Get("app-strings.licenses-repository-label");
    public static string LicensesTagLabel => Strings.Get("app-strings.licenses-tag-label");

    public static string LicensesUnknownTag => Strings.Get("app-strings.licenses-unknown-tag");

    public static string LicensesUnknownTagDetail => Strings.Get("app-strings.licenses-unknown-tag-detail");

    public static string LicensesDocumentPresent(string name) =>
        Strings.Format("app-strings.licenses-document-present", name);

    public static string LicensesDocumentMissing(string name) =>
        Strings.Format("app-strings.licenses-document-missing", name);

    public static string LicensesToolHeading => Strings.Get("app-strings.licenses-tool-heading");

    public static string LicensesToolFromRelease(string tag) =>
        Strings.Format("app-strings.licenses-tool-from-release", tag);

    public static string LicensesToolLocalPin(string tag) =>
        Strings.Format("app-strings.licenses-tool-local-pin", tag);

    public static string LicensesToolUnverified => Strings.Get("app-strings.licenses-tool-unverified");

    public static string LicensesToolMissing => Strings.Get("app-strings.licenses-tool-missing");

    // MARK: - Licencias: bibliotecas de terceros

    /// <summary>
    /// ST-082 dejó esta deuda anotada: TagLib# es LGPL y hay que declararlo.
    /// Se enlaza dinámicamente (paquete NuGet, DLL aparte), que es lo que hace
    /// compatible su uso con una app cerrada — y esa forma de enlace es
    /// justamente lo que la licencia obliga a decir.
    /// </summary>
    public static string LicensesLibrariesHeading => Strings.Get("app-strings.licenses-libraries-heading");

    public static string LicensesLibrariesIntro => Strings.Get("app-strings.licenses-libraries-intro");

    public static string LicensesTagLibName => Strings.Get("app-strings.licenses-tag-lib-name");

    public static string LicensesTagLibDetail => Strings.Get("app-strings.licenses-tag-lib-detail");

    public static string LicensesTagLibSource => Strings.Get("app-strings.licenses-tag-lib-source");

    // MARK: - Secciones todavía no construidas

    /// <summary>
    /// Una sección que aún no existe lo dice de frente en vez de fingir una
    /// pantalla vacía (mismo criterio que `ExtrasView` de macOS: no mostrar
    /// filas que el producto no tiene).
    /// </summary>
    public static string SectionPendingTitle => Strings.Get("app-strings.section-pending-title");

    public static string SectionPendingDetail(string phase) =>
        Strings.Format("app-strings.section-pending-detail", phase);
}
