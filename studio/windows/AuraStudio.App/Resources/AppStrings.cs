using AuraStudio.Core.Library;

namespace AuraStudio.App.Resources;

/// <summary>
/// Tabla de cadenas de cara al usuario, centralizada — equivalente de
/// <c>AppStrings.swift</c> (macOS) y con el mismo criterio que la del firmware
/// (`aura_lang.c`, D-013): una tabla chica y explícita en vez del mecanismo de
/// recursos de la plataforma.
///
/// **Por qué una clase estática y no `.resw`** (decisión de la Fase 1, ST-079):
/// esta app tiene un solo idioma por regla del repo (español de México), así
/// que lo que aporta MRT — resolución por idioma del sistema, `x:Uid` por
/// elemento — no se usa, y a cambio cobra: sin verificación en tiempo de
/// compilación (una clave mal escrita en un `x:Uid` falla en silencio, dejando
/// el texto vacío en pantalla), un archivo XML aparte por cada string, y
/// nombres de recurso acoplados a la propiedad del control
/// (`MiBoton.Content`). Con una clase estática, cada cadena es una propiedad:
/// el compilador atrapa el error, se puede componer con interpolación y se
/// lee junto al código que la usa. Es además lo que ya hace la app de macOS,
/// que decidió lo mismo frente a los `.strings` de Apple.
///
/// **Si algún día hace falta un segundo idioma** (macOS ya tiene ES/EN con un
/// selector en Ajustes): se agrega acá el mismo patrón del Swift — un
/// resolvedor de idioma activo y una segunda tabla — sin migrar a `.resw`. No
/// se agregó ahora porque no hay selector de idioma en la app de Windows y una
/// tabla bilingüe sin quién la consuma es código muerto.
///
/// **Uso desde XAML**: `Text="{x:Bind res:AppStrings.NavGeneral}"` (x:Bind
/// resuelve propiedades estáticas; su modo por omisión, OneTime, es justo lo
/// que corresponde a una constante).
/// </summary>
public static class AppStrings
{
    // MARK: - Identidad de la app

    public static string AppName => "Aura Studio";

    // MARK: - Barra de navegación (equivalente al sidebar de macOS)

    public static string NavGeneral => "General";
    public static string NavMusic => "Música";
    public static string NavArtists => "Artistas";
    public static string NavAlbums => "Álbumes";
    public static string NavSongs => "Canciones";
    public static string NavPlaylists => "Listas";
    public static string NavVideo => "Video";
    public static string NavMovies => "Películas";
    public static string NavSeries => "Series";
    public static string NavClips => "Videoclips";
    public static string NavAllVideos => "Todos los videos";
    public static string NavPhotos => "Fotos";
    public static string NavPhotosPhotos => "Fotos";
    public static string NavPhotosImages => "Imágenes";
    public static string NavPhotosAI => "IA";
    public static string NavAllPhotos => "Todas las fotos";
    public static string NavExtras => "Extras";
    public static string NavInstaller => "Instalador";
    public static string NavThemes => "Temas";
    public static string NavSettings => "Ajustes";

    // MARK: - Estado del dispositivo

    public static string NoDevice => "Sin dispositivo";
    public static string DeviceDetecting => "Buscando tu iPod…";
    public static string DeviceNotConnected =>
        "No hay ningún iPod conectado. Conecta tu iPod Classic por USB.";

    /// <summary>
    /// Regla de seguridad del repo: con dos discos que califican no se elige
    /// "el más probable" — se detiene y se le dice al usuario. Nunca se
    /// muestran los candidatos como seleccionables.
    /// </summary>
    public static string DeviceAmbiguous(int count) =>
        $"Se encontraron {count} discos que podrían ser tu iPod. Por seguridad, " +
        "Aura Studio no elige uno solo — desconecta los demás discos externos y vuelve a intentar.";

    public static string DeviceConnected(string name) => $"Conectado: {name}";

    /// <summary>
    /// Mismo criterio que macOS: la biblioteca se bloquea cuando hay un iPod
    /// conectado cuyo firmware NO habla el contrato de Aura. General y Extras
    /// quedan siempre accesibles (ahí se explica qué firmware hay y qué hacer).
    /// </summary>
    public static string LibraryLockedReason =>
        "El iPod conectado no tiene un firmware de la familia Aura corriendo. " +
        "Instálalo desde el Instalador para administrar y sincronizar tu biblioteca.";

    public static string LibraryAvailableWithoutDevice =>
        "Puedes armar tu biblioteca sin el iPod conectado; se sincroniza cuando lo conectes.";

    // MARK: - Biblioteca

    public static string LibraryEmpty => "Tu biblioteca está vacía.";

    // La biblioteca no está donde dice (ST-171). Un disco externo desconectado
    // es un estado normal, no un error: se cuenta en la ventana, con la ruta
    // completa —para que el usuario reconozca CUÁL biblioteca falta— y con lo
    // que puede hacer.

    public static string LibraryRootMissing(string root) =>
        string.IsNullOrWhiteSpace(root)
            ? "No hay ninguna carpeta de biblioteca configurada."
            : $"La biblioteca está en un disco que no está conectado: {root}";

    public static string LibraryRootMissingDetail =>
        "No se perdió nada: el catálogo y tus archivos siguen en ese disco. Conéctalo y la " +
        "biblioteca vuelve sola.";

    public static string LibraryRootRetry => "Conectar el disco y reintentar";
    public static string LibraryRootChoose => "Elegir otra biblioteca";
    public static string LibraryRootCreate => "Crear una nueva";

    public static string LibraryDropHint(LibraryItemKind kind) => kind switch
    {
        LibraryItemKind.Music => "Arrastra aquí tu música o una carpeta de álbumes.",
        LibraryItemKind.Video => "Arrastra aquí tus películas, series o videos.",
        LibraryItemKind.Photo => "Arrastra aquí tus fotos o una carpeta de imágenes.",
        _ => "Arrastra aquí tus archivos."
    };

    /// <summary>
    /// Se dice de frente en cada sección: es la regla de ST-012 y explicarla
    /// antes evita que el usuario crea que la app perdió sus archivos.
    /// </summary>
    public static string LibrarySectionOnlyItsType(LibraryItemKind kind) => kind switch
    {
        LibraryItemKind.Music => "Esta sección solo acepta música. Las carátulas que vengan junto a un álbum se guardan como portada, no como fotos.",
        LibraryItemKind.Video => "Esta sección solo acepta video. Una imagen con el mismo nombre que un video se guarda como su póster.",
        LibraryItemKind.Photo => "Esta sección solo acepta imágenes.",
        _ => ""
    };

    /// <summary>Versiones sin parámetro, para enlazar desde XAML con <c>x:Bind</c>.</summary>
    public static string LibrarySectionOnlyItsTypeMusic => LibrarySectionOnlyItsType(LibraryItemKind.Music);
    public static string LibrarySectionOnlyItsTypeVideo => LibrarySectionOnlyItsType(LibraryItemKind.Video);
    public static string LibrarySectionOnlyItsTypePhoto => LibrarySectionOnlyItsType(LibraryItemKind.Photo);

    public static string LibraryNothingHereYet => "Todavía no hay nada en esta sección.";

    public static string LibraryOpenFolder => "Abrir la carpeta de la biblioteca";
    public static string LibraryAddFiles => "Agregar archivos";
    public static string LibraryAddFolder => "Agregar carpeta";
    public static string LibraryRemove => "Quitar de la biblioteca";
    public static string LibraryRemoveDetail =>
        "Se quita del catálogo de Aura Studio. El archivo sigue en tu computadora.";
    public static string LibraryFavoritesOnly => "Solo favoritos";
    public static string LibraryColumns => "Columnas";
    public static string LibraryColumnsDetail =>
        "Elige qué columnas ver. Título siempre está y va primero.";
    public static string LibrarySortBy => "Ordenar por";
    public static string LibrarySortAscending => "Ascendente";
    public static string LibraryUnknownArtist => LibraryGrouping.UnknownArtistName;

    public static string LibraryTracks(int count) => count == 1 ? "1 canción" : $"{count} canciones";
    public static string LibraryEpisodes(int count) => count == 1 ? "1 episodio" : $"{count} episodios";
    public static string LibraryPhotos(int count) => count == 1 ? "1 foto" : $"{count} fotos";
    public static string LibrarySeason(int number) =>
        number == VideoCollectionGroup.NoSeasonNumber ? "Sin temporada" : $"Temporada {number}";

    public static string LibraryKind(LibraryItemKind kind) => kind switch
    {
        LibraryItemKind.Music => "Música",
        LibraryItemKind.Video => "Video",
        LibraryItemKind.Photo => "Imagen",
        _ => "No compatible"
    };

    /// <summary>
    /// El estado en una frase corta. El transcodificado dice su avance porque
    /// es el único que puede tardar minutos y el usuario necesita ver que
    /// avanza; el fallido dice el motivo, nunca solo "falló".
    /// </summary>
    public static string LibraryStatus(LibraryItemStatus status) => status.State switch
    {
        LibraryItemState.Queued => "En cola",
        LibraryItemState.Enriching => "Buscando información",
        LibraryItemState.Transcoding => $"Convirtiendo… {status.Progress * 100:0}%",
        LibraryItemState.Ready => "Listo",
        LibraryItemState.NeedsReview => "Necesita revisión",
        _ => status.Error is { Length: > 0 } error ? $"Error: {error}" : "Error"
    };

    // MARK: - General (vista del dispositivo)

    public static string GeneralTitle => "General";
    public static string GeneralSubtitle => "Administra tu iPod y revisa su estado";
    public static string SectionStorage => "Almacenamiento";
    public static string SectionContent => "Contenido en el iPod";
    public static string LabelCapacity => "Capacidad";
    public static string LabelUsed => "Usado";
    public static string LabelFree => "Disponible";
    public static string LabelFileSystem => "Sistema de archivos";
    public static string LabelMusic => "Música";
    public static string LabelVideo => "Video";
    public static string LabelPhotos => "Fotos";
    public static string LabelPlaylists => "Listas";
    public static string ActionRefresh => "Actualizar";
    public static string ActionRefreshHelp =>
        "Vuelve a leer el estado del iPod y de tu biblioteca. No copia ni borra nada.";
    public static string ActionOpenInExplorer => "Abrir en el Explorador";
    public static string ActionEject => "Expulsar";
    public static string EjectRequested =>
        "Se solicitó la expulsión. Ya puedes desconectar el iPod cuando Windows lo indique.";
    public static string EjectFailed =>
        "No se pudo expulsar el iPod. Cierra las aplicaciones que estén usando la unidad y vuelve a intentarlo.";
    public static string NeverSynced => "Este iPod todavía no se ha sincronizado con Aura Studio.";
    public static string LastSyncSummary => "Resumen de la última sincronización";
    public static string DeclaredFamilyLabel => "Familia declarada";
    public static string NotAvailable => "No disponible";

    // MARK: - Ajustes

    public static string SettingsTitle => "Ajustes";
    public static string SettingsSubtitle => "Preferencias de Aura Studio";
    public static string SettingsAppearance => "Apariencia";
    public static string SettingsTheme => "Tema";
    public static string SettingsThemeDetail =>
        "Aura Studio sigue el tema de Windows. Puedes fijarlo en claro u oscuro solo para esta app.";
    /// <summary>
    /// macOS tiene selector de idioma (español/inglés). Windows no: por regla
    /// del repo esta app es de un solo idioma, y se decidió no traer el
    /// mecanismo de macOS sin quién lo consuma (ST-079). Se dice acá en vez de
    /// dejar la sección ausente sin explicación.
    /// </summary>
    public static string SettingsLanguageDetail =>
        "Aura Studio para Windows está en español de México. No hay selector de idioma: " +
        "a diferencia de la versión para Mac, esta app se hizo en un solo idioma.";

    public static string ThemeSystem => "Igual que el sistema";
    public static string ThemeLight => "Claro";
    public static string ThemeDark => "Oscuro";
    public static string SettingsAbout => "Acerca de";

    // MARK: - Instalador

    public static string InstallerTitle => "Instalador";
    public static string InstallerSubtitle => "Instala el firmware en tu iPod, paso a paso";

    public static string InstallerWelcomeTitle => "Vamos a instalar el firmware en tu iPod";
    public static string InstallerWelcomeDetail =>
        "Aura Studio va a preparar el disco de tu iPod, grabar el arranque y copiar el firmware. " +
        "Te va a ir explicando cada paso antes de hacerlo, y no toca nada hasta que confirmes.";
    public static string InstallerWelcomeWarning =>
        "Instalar borra todo lo que haya en el iPod y reemplaza su arranque original de Apple. " +
        "Si tienes música solo ahí, cópiala antes.";
    public static string InstallerBegin => "Comenzar";
    public static string InstallerFamilyLabel => "Firmware que se va a instalar";

    public static string InstallerPermissionsTitle => "Permisos que hacen falta";
    public static string InstallerPermissionsDetail =>
        "Para preparar el disco del iPod, Windows te va a pedir permiso de administrador con su propio " +
        "aviso. Aura Studio hace todo desde aquí: nunca vas a tener que abrir una consola ni escribir un " +
        "comando. El permiso se pide solo para dos cosas concretas — dar formato al disco del iPod y, " +
        "durante el grabado, pausar el servicio de Apple que podría quedarse con el puerto USB. " +
        "Cada vez que se use queda anotado en la bitácora de la aplicación.";
    public static string InstallerPermissionsContinue => "Entendido, continuar";

    public static string InstallerDetectTitle => "Confirma que este es tu iPod";
    public static string InstallerDetectDetail =>
        "Revisa estos datos con cuidado. Lo que sigue borra el contenido del disco que aparece aquí.";
    public static string InstallerNoDevice =>
        "No hay ningún iPod conectado. Conéctalo por USB y espera a que Windows lo reconozca.";
    public static string InstallerNeedsMountedVolume =>
        "El iPod no tiene un volumen que Windows pueda leer. Prepara el disco antes de copiar los archivos.";

    public static string LabelDevice => "Dispositivo";
    public static string LabelUnit => "Unidad";
    public static string LabelBus => "Conexión";
    public static string LabelFirmware => "Firmware detectado";

    /// <summary>
    /// Cambiar de familia no es un error (el árbol saliente se guarda entero y
    /// se puede volver a él), pero nunca puede pasar en silencio.
    /// </summary>
    public static string InstallerFamilyChange(string installed, string target) =>
        $"Este iPod tiene {installed} instalado y vas a instalar {target}. " +
        $"{installed} se guarda completo, con sus ajustes, y puedes volver a él desde Extras cuando quieras.";

    public static string InstallerPrepareDisk => "Preparar el disco";
    public static string InstallerDryRun => "Ensayar sin escribir";
    public static string InstallerDryRunRunning => "Ensayando la preparación del disco…";
    public static string InstallerDryRunOk =>
        "El ensayo salió bien: el disco se volvió a verificar con permisos de administrador y el plan de " +
        "formateo es válido. No se escribió nada todavía.";
    public static string InstallerFormatRunning => "Dando formato al disco del iPod…";
    public static string InstallerFormatNeedsDryRun =>
        "Primero hay que ensayar la preparación del disco. Así se comprueba todo sin escribir nada.";
    /// <summary>
    /// El botón destructivo **nombra el disco**. Un botón que dice "Dar formato
    /// ahora" a secas, con el estilo de acento y solo en la pantalla, tiene la
    /// forma de un "Continuar" — y el dueño formateó dos veces creyendo que solo
    /// estaba probando el software.
    /// </summary>
    public static string InstallerFormatNowOn(string target) => $"Borrar y formatear {target}";

    public static string InstallerFormatDangerHeading => "Esto sí borra el iPod";

    public static string InstallerFormatDangerDetail =>
        "El ensayo de arriba no tocó nada. Lo que sigue borra todo el contenido del disco y no se " +
        "puede deshacer. Revisa que sea el iPod correcto antes de continuar.";

    public static string InstallerFormatConfirm(string target) =>
        $"Entiendo que se va a borrar todo el contenido de {target}.";

    public static string InstallerFormatNeedsConfirmation =>
        "Falta tu confirmación para borrar el iPod. Aura Studio no formatea nada sin que confirmes antes " +
        "sobre qué disco va a actuar.";

    public static string InstallerDryRunHeading => "Ensayo terminado — no se tocó el disco";
    public static string InstallerPrivilegedLogHeading => "Lo que hizo la operación con permisos";

    public static string InstallerSafetyAbort(string reason) =>
        $"Aura Studio se detuvo por seguridad antes de tocar el disco: {reason}.";

    public static string InstallerUnknownDisk(string path) =>
        $"No se pudo identificar el número de disco de «{path}», así que no se toca nada.";

    public static string InstallerCopyingTitle => "Copiando el firmware al iPod…";
    public static string InstallerCopyFiles => "Copiar el firmware";
    public static string InstallerCopyFailed => "No se pudo copiar el firmware al iPod.";
    public static string InstallerCopiedFiles(int count) => $"{count} archivos escritos en el iPod.";

    // Los pasos son los mismos de `EnterDFUView.swift` (macOS), que a su vez
    // sale del README de mks5lboot y de la guía de flasheo del firmware —
    // ninguno se inventa acá. Solo cambia el español: el original está en
    // voseo y el repo pide español de México sin voseo.
    public static string InstallerEnterDfuTitle => "Ahora pon el iPod en modo DFU";

    public static string InstallerEnterDfuWhen =>
        "Este es el momento: el disco ya está listo y lo que sigue es grabar el arranque. " +
        "El iPod tiene que estar conectado por USB mientras lo haces.";

    public static string InstallerDfuStep1 => "Si tu iPod está reproduciendo música, detén la reproducción.";
    public static string InstallerDfuStep2 => "Mantén presionados SELECT + MENU al mismo tiempo.";
    public static string InstallerDfuStep3 =>
        "Sigue presionando ambos botones unos 12 segundos, hasta después de que la pantalla se ponga negra.";
    public static string InstallerDfuStep4 =>
        "Suéltalos. Aura Studio va a detectar el modo DFU automáticamente.";

    /// <summary>El error más común: soltar en cuanto la pantalla se apaga.</summary>
    public static string InstallerDfuTimingWarning =>
        "Si sueltas los botones antes de unos 12 segundos, el iPod se reinicia normalmente y NO entra en " +
        "modo DFU. Que la pantalla se ponga negra no es la señal de soltar: sigue presionando después de eso.";

    public static string InstallerDfuGuideLink => "Guía de flasheo y restauración (repositorio del firmware)";
    public static string InstallerDfuGuideUrl =>
        "https://github.com/Ricolinos/Aura-Firmware/blob/main/docs/guia-flasheo-restauracion.md";

    public static string InstallerDfuWaiting => "Esperando el modo DFU…";

    // MARK: - Reconocimiento automático de DFU

    public static string InstallerDfuDetectedTitle => "Tu iPod está en modo DFU";
    public static string InstallerDfuDetectedDetail =>
        "Aura Studio lo reconoció al conectarlo. ¿Quieres instalarle un firmware? " +
        "No se hace nada hasta que elijas.";
    public static string InstallerDfuDetectedInstall => "Sí, instalar";
    public static string InstallerDfuDetectedDismiss => "Ahora no";
    public static string InstallerDfuNoFamilies =>
        "No hay ningún firmware disponible para instalar: falta poblar la carpeta de artefactos.";
    public static string InstallerScanDfu => "Buscar el iPod en DFU";
    public static string InstallerScanningDfu => "Buscando el iPod en modo DFU…";
    public static string InstallerDfuFound(int? state) =>
        state is null ? "iPod detectado en modo DFU." : $"iPod detectado en modo DFU (estado {state}).";
    public static string InstallerDfuNotFound =>
        "No se ve ningún iPod en modo DFU todavía. Repite la combinación de botones y vuelve a buscar. " +
        "Recuerda seguir presionando después de que la pantalla se ponga negra.";

    /// <summary>
    /// El controlador está y aun así Windows no ve ningún aparato de Apple. Muy
    /// probablemente el iPod sí entró en DFU pero su USB no llega hasta acá —
    /// el caso típico de una máquina virtual sin el dispositivo redirigido.
    /// </summary>
    public static string InstallerDfuNotSeenByWindows =>
        "El controlador de Apple está instalado, pero Windows no ve ningún dispositivo de Apple. " +
        "Si ya hiciste la combinación de botones y la pantalla del iPod está en negro, es probable que " +
        "esté en modo DFU y que su conexión USB no esté llegando hasta aquí. En una máquina virtual, " +
        "revisa que el iPod en modo DFU esté redirigido a Windows: al entrar en DFU cambia de " +
        "identificador USB y puede hacer falta autorizarlo de nuevo.";
    public static string InstallerDfuUnreadable =>
        "No se pudo leer el estado del iPod. Revisa abajo si falta el controlador de Apple.";

    public static string InstallerFlash => "Grabar el arranque";
    public static string InstallerFlashing => "Grabando el arranque en el iPod…";
    public static string InstallerFlashConfirm =>
        "Entiendo que esto reemplaza el arranque original de Apple y no se puede deshacer sin restaurarlo.";
    public static string InstallerFlashNeedsConfirmation =>
        "Falta tu confirmación para grabar el arranque. Aura Studio no graba nada sin que confirmes antes.";
    public static string InstallerFlashFailed => "No se pudo grabar el arranque.";
    public static string InstallerAwaitingReboot =>
        "Grabado. Esperando a que el iPod se reinicie y vuelva a aparecer…";
    public static string InstallerRebooted =>
        "El iPod salió de modo DFU. Ya puedes copiar el firmware.";
    public static string InstallerStuckInDfu =>
        "El iPod sigue en modo DFU y no se confirmó la instalación. No desconectes: vuelve a buscarlo.";

    // MARK: - Actualizar el arranque (ST-143, ST-168)
    //
    // La pantalla responde las cuatro preguntas que cualquiera se hace antes de
    // apretar un botón que pide modo DFU: qué es el arranque, por qué hace falta
    // DFU, qué NO se toca y —la que evita una llamada de soporte— que no es
    // obligatorio.

    public static string BootloaderUpdateOffer => "Actualizar el arranque de este iPod";

    public static string BootloaderUpdateOfferDifferent =>
        "Esta versión trae un arranque más nuevo que el que tiene tu iPod.";

    public static string BootloaderUpdateOfferUnknown =>
        "No sabemos qué arranque tiene tu iPod: lo instaló otra computadora, o una versión " +
        "anterior de la app.";

    public static string BootloaderUpdateTitle => "Actualizar el arranque";

    public static string BootloaderUpdateWhatItIs =>
        "El arranque es el programa que corre antes del firmware, en un chip aparte del disco. " +
        "Esta versión trae uno nuevo, con otra pantalla de encendido.";

    public static string BootloaderUpdateWhyDfu =>
        "Hace falta modo DFU porque ese chip no se puede escribir de ninguna otra forma.";

    public static string BootloaderUpdateNothingTouched =>
        "No se toca nada del disco. Tu música, tus fotos, tus listas y tus ajustes se quedan " +
        "exactamente como están.";

    public static string BootloaderUpdateNotRequired =>
        "No es obligatorio. El firmware nuevo funciona igual con el arranque que ya tienes; " +
        "lo único que cambia es la pantalla de encendido.";

    public static string BootloaderUpdateNoPassword =>
        "No te pide tu contraseña de administrador ni una sola vez.";

    public static string BootloaderUpdateContinue => "Continuar";

    public static string BootloaderUpdateEnterDfuWhen =>
        "El iPod tiene que estar conectado por USB mientras lo haces. No se toca su disco: " +
        "solo se regraba el arranque.";

    public static string BootloaderUpdateFlashConfirm =>
        "Entiendo que esto regraba el arranque del iPod. No borra su disco ni quita el arranque " +
        "de Apple.";

    /// <summary>
    /// El nombre de la familia va adentro: se está regrabando SU arranque, no
    /// uno genérico — a un iPod con Metro se le graba el de Metro.
    /// </summary>
    public static string BootloaderUpdateFlashing(string? family) =>
        string.IsNullOrWhiteSpace(family)
            ? "Actualizando el arranque del iPod…"
            : $"Actualizando el arranque de {family}…";

    public static string BootloaderUpdateAwaitingReboot =>
        "Arranque enviado. Esperando a que el iPod confirme y reinicie…";

    public static string BootloaderUpdateDoneTitle => "Listo: el arranque quedó actualizado";

    public static string BootloaderUpdateDoneDetail =>
        "Tu música y tus ajustes siguen intactos. La próxima vez que enciendas el iPod vas a ver " +
        "la pantalla de arranque nueva.";

    // MARK: - La salida cuando el DFU no aparece (ST-169)

    public static string ServicePauseTitle => "¿No aparece?";

    public static string ServicePauseDetail =>
        "Windows puede tener el servicio de Apple ocupando el iPod. Podemos detenerlo mientras dura " +
        "esto y lo volvemos a encender al terminar.";

    /// <summary>Se dice antes de apretar, no después: es el único permiso de este flujo.</summary>
    public static string ServicePauseAsksForPermission =>
        "Esto sí te va a pedir permiso de administrador.";

    public static string ServicePauseButton => "Pausar los servicios de Apple";

    public static string ServicePauseNotRunning =>
        "El servicio de Apple no está corriendo, así que no es lo que está estorbando.";

    public static string InstallerDoneTitle => "Listo";
    public static string InstallerDoneDetail =>
        "El firmware quedó instalado. Expulsa el iPod desde General antes de desconectarlo.";
    public static string InstallerFailedTitle => "No se pudo continuar";
    public static string InstallerRestart => "Empezar de nuevo";
    public static string InstallerCancelled => "Operación cancelada.";
    public static string InstallerAlreadyWriting =>
        "Ya hay una operación escribiendo en el iPod. Espera a que termine antes de empezar otra.";
    public static string InstallerArtifactsInvalid =>
        "Los archivos del firmware no se pudieron verificar, así que no se instala nada.";

    // MARK: - Controlador de DFU

    public static string DfuDriverHeading => "Controlador para el modo DFU";

    public static string DfuDriverReady(string device) =>
        $"Windows reconoce «{device}» y tiene su controlador funcionando.";
    public static string DfuDriverMissing =>
        "Windows ve el iPod pero no tiene controlador para él. Instala «Dispositivos Apple» desde la " +
        "Microsoft Store (o iTunes de Apple) y vuelve a conectarlo: Aura Studio necesita ese controlador " +
        "para hablarle al iPod en modo DFU.";
    public static string DfuDriverInstalledNoDevice =>
        "El controlador de Apple está instalado. Todavía no se ve ningún iPod en modo DFU.";
    public static string DfuDriverPackageMissing =>
        "No se encontró el controlador de dispositivos de Apple. Instala «Dispositivos Apple» desde la " +
        "Microsoft Store (o iTunes) antes de continuar: sin él, Windows no puede hablarle al iPod en " +
        "modo DFU.";
    public static string DfuDriverUnknown =>
        "No se pudo consultar el estado del controlador.";

    // MARK: - Licencias (contrato §B, GPL v2)

    public static string LicensesTitle => "Licencias";
    public static string LicensesSubtitle => "Software libre incluido en Aura Studio";
    public static string LicensesOpen => "Ver licencias";

    public static string LicensesIntro =>
        "mks5lboot, bootloader-ipod6g.ipod, rockbox.ipod y rockbox.zip son obras derivadas de " +
        "Rockbox y se distribuyen bajo la Licencia Pública General de GNU, versión 2. " +
        "Aura Studio los incluye como agregación y no los modifica de ninguna forma. " +
        "Para cada firmware incluido puedes obtener su código fuente completo en el repositorio " +
        "y la versión exacta que se listan abajo.";

    public static string LicensesFamiliesHeading => "Firmware incluido";
    public static string LicensesRepositoryLabel => "Código fuente";
    public static string LicensesTagLabel => "Versión incluida";

    public static string LicensesUnknownTag => "No se conoce";

    public static string LicensesUnknownTagDetail =>
        "Estos archivos se copiaron sin registrar de qué Release salieron. " +
        "Vuelve a poblarlos con scripts/FirmwareFetch.ps1 para que la versión quede anotada.";

    public static string LicensesDocumentPresent(string name) => $"{name}: incluido";
    public static string LicensesDocumentMissing(string name) => $"{name}: no incluido en estos archivos";

    public static string LicensesToolHeading => "Herramienta de grabado (mks5lboot.exe)";

    public static string LicensesToolFromRelease(string tag) =>
        $"Publicada en el Release {tag} y verificada contra su checksums.txt.";

    public static string LicensesToolLocalPin(string tag) =>
        "Compilada aparte para Windows: el Release publica la versión de Unix. " +
        $"Coincide con el hash fijado en el propio Aura Studio (origen declarado: {tag}). " +
        "Su código fuente es el del repositorio del firmware que se indica arriba.";

    public static string LicensesToolUnverified =>
        "No se pudo comprobar contra ningún hash. Aura Studio no la ejecutará hasta poder verificarla.";

    public static string LicensesToolMissing => "No está incluida en esta copia.";

    // MARK: - Licencias: bibliotecas de terceros

    /// <summary>
    /// ST-082 dejó esta deuda anotada: TagLib# es LGPL y hay que declararlo.
    /// Se enlaza dinámicamente (paquete NuGet, DLL aparte), que es lo que hace
    /// compatible su uso con una app cerrada — y esa forma de enlace es
    /// justamente lo que la licencia obliga a decir.
    /// </summary>
    public static string LicensesLibrariesHeading => "Bibliotecas incluidas";

    public static string LicensesLibrariesIntro =>
        "Aura Studio incluye bibliotecas de software libre. Se distribuyen como archivos " +
        "aparte junto al programa, sin modificar, y puedes reemplazarlas por otra versión " +
        "compatible.";

    public static string LicensesTagLibName => "TagLib# 2.3.0 — LGPL v2.1";

    public static string LicensesTagLibDetail =>
        "Lee las etiquetas y las carátulas de tus archivos de música (MP3, FLAC, M4A). " +
        "En Aura Studio para Mac ese trabajo lo hace AVFoundation, que no existe en Windows.";

    public static string LicensesTagLibSource => "https://github.com/mono/taglib-sharp";

    // MARK: - Secciones todavía no construidas

    /// <summary>
    /// Una sección que aún no existe lo dice de frente en vez de fingir una
    /// pantalla vacía (mismo criterio que `ExtrasView` de macOS: no mostrar
    /// filas que el producto no tiene).
    /// </summary>
    public static string SectionPendingTitle => "Todavía no está lista";

    public static string SectionPendingDetail(string phase) =>
        $"Esta sección llega en la {phase} del port a Windows. " +
        "La navegación ya está en su lugar para que nada cambie cuando el contenido aparezca.";
}
