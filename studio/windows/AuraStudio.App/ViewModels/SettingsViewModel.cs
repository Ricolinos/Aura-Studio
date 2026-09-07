using System.Reflection;
using CommunityToolkit.Mvvm.ComponentModel;
using AuraStudio.App.Platform;
using AuraStudio.App.Resources;
using AuraStudio.App.Services;
using AuraStudio.Core.Library;
using AuraStudio.Core.Resources;

namespace AuraStudio.App.ViewModels;

/// <summary>Una opción del selector de tema, con su etiqueta ya en español.</summary>
public sealed record ThemeOption(AppTheme Theme, string Label);

/// <summary>
/// Una opción del selector de idioma (ST-247, B7b).
///
/// <para>El nombre va <b>en su propio idioma</b> y no traducido: quien abre la
/// app en un idioma que no lee busca "Español" o "Русский" en la lista, y no lo
/// encontraría si dijera "Spanish" o "Russian". Es la misma regla que con el
/// nombre de una colección de fotos — hay texto que es dato, no interfaz.</para>
/// </summary>
public sealed record LanguageOption(string Culture, string Label, bool ReviewedByHumans)
{
    /// <summary>La marca "(beta)" de un idioma que todavía nadie revisó.</summary>
    public string Mark => ReviewedByHumans ? "" : AppStrings.LanguageBetaMark;

    public bool ShowsMark => !ReviewedByHumans;
}

/// <summary>
/// Una entrada del orden de búsqueda de carátula: el proveedor, si hoy se puede
/// usar y —cuando no— por qué.
/// </summary>
public sealed record CoverProviderRow(
    int Position, CoverArtProvider Provider, string Name, bool Usable, string Reason,
    bool CanMoveUp, bool CanMoveDown)
{
    public string PositionText => Position.ToString();
    public bool HasReason => Reason.Length > 0;
}

/// <summary>
/// Ajustes de la app. **Ojo con la distinción**: los ajustes del firmware
/// (tema del iPod, animaciones, ecualizador) viven en el iPod y se cambian ahí
/// — acá está solo lo que le toca decidir a Studio.
///
/// <para>Paridad con las seis pestañas de macOS. Lo que no aplica en Windows se
/// dice en pantalla; nada se omite en silencio.</para>
/// </summary>
public sealed partial class SettingsViewModel : ViewModelBase
{
    private readonly IAppPreferences _preferences;
    private readonly CredentialStore _credentials;
    private readonly BackgroundTaskCenter _tasks;
    private readonly LibraryViewModel _library;

    public SettingsViewModel(
        IAppPreferences preferences, LibraryViewModel library, AppUpdateService updates,
        BackgroundTaskCenter tasks)
    {
        _preferences = preferences;
        _library = library;
        Updates = updates;
        _tasks = tasks;
        _credentials = new CredentialStore();
        SelectedTheme = ThemeOptions.First(option => option.Theme == preferences.Theme);
        SelectedLanguage = LanguageOptions.FirstOrDefault(option => option.Culture == preferences.Language)
                           ?? LanguageOptions[0];
        RefreshCoverProviders();
    }

    // MARK: - General

    public IReadOnlyList<ThemeOption> ThemeOptions { get; } =
    [
        new(AppTheme.System, AppStrings.ThemeSystem),
        new(AppTheme.Light, AppStrings.ThemeLight),
        new(AppTheme.Dark, AppStrings.ThemeDark)
    ];

    [ObservableProperty]
    public partial ThemeOption SelectedTheme { get; set; }

    partial void OnSelectedThemeChanged(ThemeOption value)
    {
        // La ventana escucha el cambio de preferencia y vuelve a aplicar el
        // tema (incluida la barra de título, que no es parte del árbol XAML).
        _preferences.Theme = value.Theme;
    }

    /// <summary>
    /// Los idiomas que se pueden elegir hoy, más "igual que el sistema".
    ///
    /// <para>Solo aparecen los que de verdad existen: ofrecer un idioma cuyo
    /// archivo no está sería prometer algo que al elegirlo no pasa —la app
    /// caería al español sin decir nada— y ese es el modo de falla que este
    /// bloque entero viene a evitar.</para>
    /// </summary>
    public IReadOnlyList<LanguageOption> LanguageOptions { get; } =
    [
        new("", AppStrings.LanguageFollowSystem, ReviewedByHumans: true),
        .. AppLanguages.Available.Select(
            language => new LanguageOption(language.Culture, language.Endonym, language.ReviewedByHumans))
    ];

    [ObservableProperty]
    public partial LanguageOption SelectedLanguage { get; set; }

    /// <summary>
    /// Si hay que decirle al usuario que cierre y vuelva a abrir. Se enciende al
    /// cambiar de idioma y ya no se apaga: el aviso tiene que seguir ahí si
    /// vuelve a Ajustes más tarde y no se acuerda.
    /// </summary>
    [ObservableProperty]
    public partial bool LanguageNeedsRestart { get; set; }

    /// <summary>
    /// Si el idioma elegido todavía no lo revisó una persona. Hoy nunca es
    /// verdadero —solo se ofrecen español e inglés— y el aviso existe igual,
    /// listo para B7c: cuando lleguen los cuatro traducidos por una máquina, la
    /// app tiene que decirlo, no descubrirse.
    /// </summary>
    public bool LanguageIsUnreviewed => !SelectedLanguage.ReviewedByHumans;

    /// <summary>
    /// Qué ofrecer después de cambiar el idioma. La decisión vive en Core
    /// (<see cref="LanguageChangePrompt"/>) para poder probarla sin abrir una
    /// ventana; acá solo se le pregunta cuántas tareas hay en curso.
    /// </summary>
    private LanguageChangeAdvice LanguageAdvice => LanguageChangePrompt.For(_tasks.Count);

    /// <summary>
    /// Si se puede ofrecer cerrar. Con una sincronización, una conversión, una
    /// migración o una instalación de firmware en curso, <b>no</b>: cerrar
    /// dejaría eso a medias en el disco de alguien, y por un cambio de idioma,
    /// que es lo más prescindible que hay.
    /// </summary>
    public bool LanguageCanCloseNow => LanguageAdvice.CanCloseNow;

    /// <summary>El texto del aviso, que no es el mismo en los dos casos.</summary>
    public string LanguageRestartDetail => Strings.Get(LanguageAdvice.DetailKey);

    partial void OnSelectedLanguageChanged(LanguageOption value)
    {
        // El aviso de "sin revisar" depende del idioma elegido, así que se
        // refresca aunque no haya cambiado nada más.
        OnPropertyChanged(nameof(LanguageIsUnreviewed));
        OnPropertyChanged(nameof(LanguageCanCloseNow));
        OnPropertyChanged(nameof(LanguageRestartDetail));

        if (_preferences.Language == value.Culture) return;

        _preferences.Language = value.Culture;

        // No se recarga la interfaz en caliente. `x:Bind` resuelve el texto una
        // sola vez, al construir cada página, así que cambiar la cultura ahora
        // dejaría media app en un idioma y media en otro — peor que no hacer
        // nada, porque parece que funcionó. Se dice y se deja al usuario
        // decidir cuándo.
        LanguageNeedsRestart = true;
    }

    /// <summary>Versión del ensamblado, para "Acerca de".</summary>
    public string AppVersion =>
        Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "—";

    /// <summary>
    /// El estado de "¿hay una versión nueva de Aura Studio?" (ST-211). Vive en
    /// un servicio y no acá porque el aviso también sale en el armazón, y el
    /// mismo estado tiene que valer en los dos lugares.
    /// </summary>
    public AppUpdateService Updates { get; }

    // MARK: - Video

    public bool HasManualFfmpegPath => _preferences.FfmpegPath.Length > 0;

    /// <summary>
    /// Dónde está ffmpeg, o cómo instalarlo. Se dice la ruta encontrada y no
    /// solo "listo": si hay dos instalaciones, el usuario necesita saber cuál
    /// se está usando.
    /// </summary>
    public string FfmpegStatus => Core.Media.FfmpegLocator.Locate(_preferences.FfmpegPath) is { } path
        ? $"Encontrado en {path}"
        : Core.Media.FfmpegLocator.NotFoundMessage;

    public void SetFfmpegPath(string path)
    {
        _preferences.FfmpegPath = path;
        OnPropertyChanged(nameof(FfmpegStatus));
        OnPropertyChanged(nameof(HasManualFfmpegPath));
    }

    // MARK: - Biblioteca

    public string LibraryPath => _preferences.LibraryPath;

    /// <summary>
    /// Cambia la carpeta de la biblioteca. <b>No mueve ni copia nada</b>, igual
    /// que macOS: se apunta a la carpeta nueva y se lee su catálogo, o se
    /// empieza vacía si no tiene uno. La biblioteca anterior queda intacta donde
    /// estaba y vuelve al elegirla de nuevo — por eso la pantalla lo dice antes
    /// de que el usuario cambie.
    /// </summary>
    public void SetLibraryPath(string path)
    {
        if (path == _preferences.LibraryPath) return;

        _preferences.LibraryPath = path;
        _library.Reload();
        OnPropertyChanged(nameof(LibraryPath));
        OnPropertyChanged(nameof(LibraryChangedNotice));
    }

    /// <summary>
    /// Lo que se le dice al usuario sobre la carpeta actual. Las tres
    /// situaciones se distinguen a propósito: <b>vacía</b>, <b>ilegible</b> y
    /// <b>con el catálogo bien pero sin los archivos</b> se veían todas igual, y
    /// eso escondió que un catálogo real de 2809 elementos no se estaba
    /// leyendo.
    /// </summary>
    public string LibraryChangedNotice
    {
        get
        {
            if (_library.LoadError is { Length: > 0 } error) return error;

            if (_library.Items.Count == 0)
                return _library.MissingFileCount > 0
                    ? $"El catálogo de esta carpeta tiene {_library.MissingFileCount} elementos, pero no se encontró ninguno de sus archivos. Suele pasar al apuntar a la biblioteca de otra computadora."
                    : "Esta carpeta todavía no tiene una biblioteca de Aura Studio: empieza vacía.";

            string summary = LibraryViewModel.SummaryOf(_library.Items);

            return _library.MissingFileCount > 0
                ? $"{summary}. Faltan los archivos de otros {_library.MissingFileCount} elementos del catálogo."
                : summary;
        }
    }

    public bool CopyMediaIntoLibrary
    {
        get => _preferences.CopyMediaIntoLibrary;
        set
        {
            _preferences.CopyMediaIntoLibrary = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(CopyMediaDetail));
        }
    }

    public string CopyMediaDetail => CopyMediaIntoLibrary
        ? "Cada canción, foto o video que sueltas en Aura Studio se copia dentro de la carpeta de arriba; el original queda intacto donde estaba. Usa más espacio en disco, pero la biblioteca queda completa en un solo lugar."
        : "No se copia nada: la biblioteca referencia tus archivos donde ya están, y aquí solo se guarda lo que los liga a Aura (metadata, letras, portadas). Al sincronizar, Aura Studio arma el archivo para el iPod leyendo el original en ese momento — un poco más lento la primera vez, pero tu disco nunca termina con una copia duplicada de toda tu biblioteca.";

    /// <summary>
    /// ST-243, corregido en ST-244: la conversión se avisa <b>antes</b>, no
    /// después de que el usuario encuentre un <c>.m4a</c> donde había dejado un
    /// <c>.wav</c>. Y se dice por qué, que es lo que convierte una sorpresa en
    /// una decisión entendida.
    ///
    /// <para>Depende de la calidad elegida, porque el resultado depende de ella:
    /// decir "se convierten a MP3" con "Original sin pérdida" puesto sería
    /// mentir.</para>
    /// </summary>
    public string AudioConversionDetail =>
        "Un WAV o un AIFF ocupa diez veces lo que la misma canción comprimida, y el disco del iPod no "
        + "da abasto: al copiarlos a la biblioteca se convierten, con el codificador que ya trae "
        + "Windows, a " + (AudioOriginal ? "ALAC, que es sin pérdida" : "MP3 de 256 kbps")
        + " — lo que hayas elegido en \"Cómo guardar tu música\". Tu archivo original queda intacto "
        + "donde estaba.";

    // MARK: - Cómo guardar tu música (ST-245, plan §2 — texto compartido con la Mac)

    public string StorageSectionTitle => AppStrings.StorageSectionTitle;
    public string StorageCopyExplainer => AppStrings.StorageCopyExplainer;
    public string StorageReferenceExplainer => AppStrings.StorageReferenceExplainer;
    public string StorageChangeOnlyAffectsFuture => AppStrings.StorageChangeOnlyAffectsFuture;

    // MARK: - Huérfanos (ST-245)

    public string OrphansDetail => AppStrings.OrphansDetail;
    public string OrphansScanButton => AppStrings.OrphansButton;
    public string OrphansCleanButton => AppStrings.OrphansCleanButton;

    /// <summary>
    /// Lo último que encontró <see cref="ScanForOrphans"/>. <c>null</c> antes
    /// de la primera búsqueda de esta sesión de Ajustes — la pantalla no
    /// afirma nada sobre huérfanos hasta que de verdad los buscó.
    /// </summary>
    private OrphanScanResult? _orphanScan;

    public bool HasScannedForOrphans => _orphanScan is not null;

    public string OrphanScanSummary => _orphanScan is { } scan
        ? (scan.Count == 0 ? AppStrings.OrphansNoneFound : AppStrings.OrphansFound(scan))
        : "";

    public bool HasOrphansToClean => _orphanScan is { Count: > 0 };

    public void ScanForOrphans()
    {
        _orphanScan = _library.FindOrphans();
        NotifyOrphanScanChanged();
    }

    /// <summary>El mensaje del diálogo de confirmación, o <c>null</c> si no hay nada que limpiar.</summary>
    public string? OrphanCleanupConfirmMessage => _orphanScan is { Count: > 0 } scan
        ? AppStrings.OrphansConfirmMessage(scan)
        : null;

    public int PendingOrphanCount => _orphanScan?.Count ?? 0;

    private string _orphanCleanupResult = "";

    /// <summary>Lo último que dijo una limpieza. Vacío hasta que corre la primera.</summary>
    public string OrphanCleanupResult => _orphanCleanupResult;

    /// <summary>
    /// Borra lo que encontró la última búsqueda. El llamador ya mostró la
    /// confirmación —acá no se vuelve a preguntar—.
    ///
    /// <para>Vuelve a buscar después de borrar, en vez de limpiar el estado a
    /// ciegas: es la misma prueba que se le pediría a cualquier otra acción de
    /// "limpiar" —que ya no encuentre lo que se acaba de borrar—, y si algo
    /// quedó (un archivo en uso en ese instante, un permiso), se ve.</para>
    /// </summary>
    public void ConfirmOrphanCleanup()
    {
        if (_orphanScan is not { Count: > 0 } scan) return;

        int cleaned = scan.Count;
        _library.CleanOrphans(scan);
        _orphanScan = _library.FindOrphans();
        _orphanCleanupResult = AppStrings.OrphansCleaned(cleaned);

        NotifyOrphanScanChanged();
        OnPropertyChanged(nameof(OrphanCleanupResult));
    }

    private void NotifyOrphanScanChanged()
    {
        OnPropertyChanged(nameof(HasScannedForOrphans));
        OnPropertyChanged(nameof(OrphanScanSummary));
        OnPropertyChanged(nameof(HasOrphansToClean));
        OnPropertyChanged(nameof(OrphanCleanupConfirmMessage));
        OnPropertyChanged(nameof(PendingOrphanCount));
    }

    // MARK: - Migración de una versión anterior (ST-246)

    /// <summary>La biblioteca, para el botón de migrar.</summary>
    public LibraryViewModel Library => _library;

    /// <summary>
    /// Qué dice la sección de migración. Cuando hay algo detectado se dice qué
    /// es; cuando no, se explica igual para qué sirve — porque hay un caso que
    /// <b>no se puede detectar al abrir sin leer archivo por archivo</b>
    /// (copias de <c>Música/</c> a las que les faltan las etiquetas del
    /// catálogo), y ST-203 prohíbe hacer eso en el arranque. Ese caso se
    /// arregla desde acá.
    /// </summary>
    public string MigrationDetail => _library.MigrationNeed.Needed
        ? _library.MigrationMessage
        : "Si esta biblioteca la armó una versión anterior de Aura Studio, migrarla deja las "
          + "etiquetas del catálogo escritas en las copias de Música, ordena lo preparado y borra "
          + "lo que ya no usa nadie. Tus archivos originales no se tocan, y correrla de nuevo "
          + "cuando ya está al día no cambia nada.";

    public IReadOnlyList<string> LinkedFolders => _preferences.LinkedLibraryFolders;

    public bool HasLinkedFolders => LinkedFolders.Count > 0;

    /// <summary>
    /// Quita una carpeta de la lista. <b>No borra ni desvincula</b> lo que ya se
    /// importó desde ella: es pura higiene de la lista.
    /// </summary>
    public void RemoveLinkedFolder(string path)
    {
        _preferences.LinkedLibraryFolders = [.. LinkedFolders.Where(folder => folder != path)];
        OnPropertyChanged(nameof(LinkedFolders));
        OnPropertyChanged(nameof(HasLinkedFolders));
    }

    // MARK: - Colaboraciones (R2-4)

    /// <summary>
    /// «Agrupar las colaboraciones bajo el artista principal». Encendido por
    /// omisión; apagarlo devuelve la agrupación de antes sin migrar nada,
    /// porque la homologación nunca escribió nada en la biblioteca.
    /// </summary>
    public bool GroupCollaborations
    {
        get => _preferences.GroupCollaborations;
        set
        {
            if (_preferences.GroupCollaborations == value) return;
            _preferences.GroupCollaborations = value;
            OnPropertyChanged();
        }
    }

    public string GroupCollaborationsDetail =>
        "«Gorillaz feat. De La Soul» se muestra dentro de «Gorillaz»: una sola fila en Artistas y una sola foto de artista. " +
        "Los separadores son «feat.», «feat», «ft.», «ft», «featuring», «+», «with» y «con», siempre como palabra suelta. " +
        "«vs.» y «versus» NO agrupan: «Spacemonkeyz vs. Gorillaz» es un proyecto con nombre propio. " +
        "Esto solo cambia cómo se AGRUPA lo que ves; nunca reescribe el artista de la canción ni mueve carpetas en el iPod.";

    public IReadOnlyList<string> ArtistGroupingExceptions => _preferences.ArtistGroupingExceptions;

    public bool HasArtistGroupingExceptions => ArtistGroupingExceptions.Count > 0;

    public void AddArtistGroupingException(string name)
    {
        string trimmed = (name ?? "").Trim();
        if (trimmed.Length == 0) return;

        // Sin duplicados, comparando como compara la homologación.
        if (ArtistGroupingExceptions.Any(existing =>
                LibraryGrouping.Normalize(existing) == LibraryGrouping.Normalize(trimmed)))
        {
            return;
        }

        _preferences.ArtistGroupingExceptions = [.. ArtistGroupingExceptions, trimmed];
        NotifyExceptionsChanged();
    }

    public void RemoveArtistGroupingException(string name)
    {
        _preferences.ArtistGroupingExceptions =
            [.. ArtistGroupingExceptions.Where(existing => existing != name)];

        NotifyExceptionsChanged();
    }

    private void NotifyExceptionsChanged()
    {
        OnPropertyChanged(nameof(ArtistGroupingExceptions));
        OnPropertyChanged(nameof(HasArtistGroupingExceptions));
    }

    public bool CoverArtAlbumOnly
    {
        get => _preferences.CoverArtPolicy == CoverArtPolicy.AlbumOnly;
        set
        {
            _preferences.CoverArtPolicy = value ? CoverArtPolicy.AlbumOnly : CoverArtPolicy.PerTrack;
            OnPropertyChanged();
            OnPropertyChanged(nameof(CoverArtPerTrack));
            OnPropertyChanged(nameof(CoverArtDetail));
        }
    }

    public bool CoverArtPerTrack
    {
        get => !CoverArtAlbumOnly;
        set => CoverArtAlbumOnly = !value;
    }

    public string CoverArtDetail => CoverArtAlbumOnly
        ? "Una sola imagen por álbum, compartida por todas sus canciones. Es lo que el firmware busca primero y ocupa mucho menos espacio en el iPod."
        : "Cada canción lleva su propia carátula. Sirve para sencillos y recopilaciones, donde una sola portada por álbum sería incorrecta.";

    public bool EnrichOnline
    {
        get => _preferences.EnrichOnline;
        set
        {
            _preferences.EnrichOnline = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(CanFetchLyrics));
        }
    }

    /// <summary>Sin conexión a servicios no hay de dónde sacar la letra.</summary>
    public bool CanFetchLyrics => EnrichOnline;

    public bool FetchSyncedLyrics
    {
        get => _preferences.FetchSyncedLyrics;
        set { _preferences.FetchSyncedLyrics = value; OnPropertyChanged(); }
    }

    // MARK: - Música

    public bool MusicByArtistAlbum
    {
        get => _preferences.MusicOrganization == MusicOrganization.ArtistAlbum;
        set { if (value) SetMusicOrganization(MusicOrganization.ArtistAlbum); }
    }

    public bool MusicByAlbum
    {
        get => _preferences.MusicOrganization == MusicOrganization.Album;
        set { if (value) SetMusicOrganization(MusicOrganization.Album); }
    }

    public bool MusicByArtist
    {
        get => _preferences.MusicOrganization == MusicOrganization.Artist;
        set { if (value) SetMusicOrganization(MusicOrganization.Artist); }
    }

    private void SetMusicOrganization(MusicOrganization value)
    {
        _preferences.MusicOrganization = value;
        OnPropertyChanged(nameof(MusicByArtistAlbum));
        OnPropertyChanged(nameof(MusicByAlbum));
        OnPropertyChanged(nameof(MusicByArtist));
        OnPropertyChanged(nameof(MusicOrganizationDetail));
    }

    public string MusicOrganizationDetail => _preferences.MusicOrganization switch
    {
        MusicOrganization.Album => "Music/Álbum/ — todas las canciones agrupadas solo por álbum, sin carpeta de artista.",
        MusicOrganization.Artist => "Music/Artista/ — todas las canciones del artista juntas, sin carpeta de álbum.",
        _ => "Music/Artista/Álbum/ — una carpeta por álbum dentro de cada artista."
    };

    public bool FilenameTitleOnly
    {
        get => _preferences.MusicFilenameFormat == MusicFilenameFormat.TitleOnly;
        set { if (value) SetFilenameFormat(MusicFilenameFormat.TitleOnly); }
    }

    public bool FilenameTrackTitle
    {
        get => _preferences.MusicFilenameFormat == MusicFilenameFormat.TrackNumberTitle;
        set { if (value) SetFilenameFormat(MusicFilenameFormat.TrackNumberTitle); }
    }

    public bool FilenameTitleArtist
    {
        get => _preferences.MusicFilenameFormat == MusicFilenameFormat.TitleArtist;
        set { if (value) SetFilenameFormat(MusicFilenameFormat.TitleArtist); }
    }

    public bool FilenameTitleAlbum
    {
        get => _preferences.MusicFilenameFormat == MusicFilenameFormat.TitleAlbum;
        set { if (value) SetFilenameFormat(MusicFilenameFormat.TitleAlbum); }
    }

    private void SetFilenameFormat(MusicFilenameFormat value)
    {
        _preferences.MusicFilenameFormat = value;
        OnPropertyChanged(nameof(FilenameTitleOnly));
        OnPropertyChanged(nameof(FilenameTrackTitle));
        OnPropertyChanged(nameof(FilenameTitleArtist));
        OnPropertyChanged(nameof(FilenameTitleAlbum));
        OnPropertyChanged(nameof(FilenamePreview));
    }

    /// <summary>Un ejemplo concreto vale más que la descripción del formato.</summary>
    public string FilenamePreview => _preferences.MusicFilenameFormat switch
    {
        MusicFilenameFormat.TrackNumberTitle => "Ejemplo: 03 Persiana americana.mp3",
        MusicFilenameFormat.TitleArtist => "Ejemplo: Persiana americana - Soda Stereo.mp3",
        MusicFilenameFormat.TitleAlbum => "Ejemplo: Persiana americana - Signos.mp3",
        _ => "Ejemplo: Persiana americana.mp3"
    };

    public bool AudioOriginal
    {
        get => _preferences.AudioQuality == AudioQuality.OriginalLossless;
        set
        {
            if (!value) return;
            _preferences.AudioQuality = AudioQuality.OriginalLossless;
            NotifyAudioQuality();
        }
    }

    public bool AudioCompressed
    {
        get => _preferences.AudioQuality == AudioQuality.Compressed;
        set
        {
            if (!value) return;
            _preferences.AudioQuality = AudioQuality.Compressed;
            NotifyAudioQuality();
        }
    }

    private void NotifyAudioQuality()
    {
        OnPropertyChanged(nameof(AudioOriginal));
        OnPropertyChanged(nameof(AudioCompressed));
        OnPropertyChanged(nameof(AudioQualityDetail));

        // ST-244: el aviso de conversión también depende de la calidad, y si no
        // se refresca queda diciendo lo contrario de lo que va a pasar.
        OnPropertyChanged(nameof(AudioConversionDetail));
    }

    /// <summary>
    /// ST-244: dice lo que de verdad pasa con cada formato. El texto anterior
    /// prometía que WAV y AIFF "se copian tal cual", y desde ST-243 no es cierto
    /// — se convierten siempre, porque en el disco del iPod no caben.
    /// </summary>
    public string AudioQualityDetail => AudioOriginal
        ? "FLAC, ALAC, M4A y MP3 se copian tal cual: el iPod con Aura los reproduce sin perder calidad. "
          + "WAV y AIFF sí se convierten, a ALAC, que también es sin pérdida y ocupa la mitad. Tu "
          + "archivo original nunca se modifica."
        : "Cada canción se convierte a MP3 de 256 kbps antes de copiarla: buena calidad, mucho menos "
          + "espacio. Si sueltas un FLAC, tu biblioteca de Aura guarda el MP3 y no el FLAC; el archivo "
          + "original se queda intacto en su carpeta.";

    // MARK: - Fotos

    public bool PhotoOptimized
    {
        get => _preferences.PhotoQuality == PhotoQuality.Optimized;
        set
        {
            if (!value) return;
            _preferences.PhotoQuality = PhotoQuality.Optimized;
            NotifyPhotoQuality();
        }
    }

    public bool PhotoHd
    {
        get => _preferences.PhotoQuality == PhotoQuality.Hd;
        set
        {
            if (!value) return;
            _preferences.PhotoQuality = PhotoQuality.Hd;
            NotifyPhotoQuality();
        }
    }

    private void NotifyPhotoQuality()
    {
        OnPropertyChanged(nameof(PhotoOptimized));
        OnPropertyChanged(nameof(PhotoHd));
    }

    public bool OrganizePhotosByCategory
    {
        get => _preferences.OrganizePhotosByCategory;
        set { _preferences.OrganizePhotosByCategory = value; OnPropertyChanged(); }
    }

    public IReadOnlyList<string> PhotoCollections => _preferences.PhotoCollections;

    public void AddPhotoCollection(string name)
    {
        _preferences.PhotoCollections = LibraryOptions.AddPhotoCollection(PhotoCollections, name);
        OnPropertyChanged(nameof(PhotoCollections));
    }

    public void RemovePhotoCollection(string name)
    {
        _preferences.PhotoCollections = LibraryOptions.RemovePhotoCollection(PhotoCollections, name);
        OnPropertyChanged(nameof(PhotoCollections));
    }

    // MARK: - Video

    public bool OrganizeVideosByCategory
    {
        get => _preferences.OrganizeVideosByCategory;
        set { _preferences.OrganizeVideosByCategory = value; OnPropertyChanged(); }
    }

    // MARK: - Servicios (D-203)

    [ObservableProperty]
    public partial IReadOnlyList<CoverProviderRow> CoverProviders { get; private set; } = [];

    public bool DeezerEnabled
    {
        get => _preferences.DeezerEnabled;
        set
        {
            _preferences.DeezerEnabled = value;
            OnPropertyChanged();
            RefreshCoverProviders();
        }
    }

    public void MoveCoverProvider(CoverArtProvider provider, int offset)
    {
        _preferences.CoverArtProviderOrder =
            LibraryOptions.Move(_preferences.CoverArtProviderOrder, provider, offset);
        RefreshCoverProviders();
    }

    /// <summary>
    /// Vuelve a armar la lista con quién puede usarse ahora. Un proveedor sin
    /// clave sigue en la lista, marcado y explicado: esconderlo dejaría al
    /// usuario sin saber que existe.
    /// </summary>
    public void RefreshCoverProviders()
    {
        IReadOnlyList<CoverArtProvider> order = _preferences.CoverArtProviderOrder;

        CoverProviders =
        [
            .. order.Select((provider, index) => new CoverProviderRow(
                Position: index + 1,
                Provider: provider,
                Name: provider.DisplayName(),
                Usable: IsUsable(provider),
                Reason: UnusableReason(provider),
                CanMoveUp: index > 0,
                CanMoveDown: index < order.Count - 1))
        ];
    }

    private bool IsUsable(CoverArtProvider provider) => provider switch
    {
        CoverArtProvider.FanartTV => _credentials.HasKey(ApiKeyService.FanartTV.Key),
        CoverArtProvider.Deezer => _preferences.DeezerEnabled,
        _ => true
    };

    private string UnusableReason(CoverArtProvider provider)
    {
        if (IsUsable(provider)) return "";

        return provider == CoverArtProvider.Deezer
            ? "apagado abajo"
            : "sin clave configurada abajo";
    }

    // MARK: - Claves

    public IReadOnlyList<ApiKeyService> KeyServices { get; } =
        [.. ApiKeyService.MetadataServices, ApiKeyService.GitHub];

    public bool HasKey(ApiKeyService service) => _credentials.HasKey(service.Key);

    public string? LoadKey(ApiKeyService service) => _credentials.Load(service.Key);

    /// <summary>
    /// Guarda la clave en el Administrador de credenciales de Windows. Devuelve
    /// lo que hay que mostrarle al usuario: **ningún botón queda gris sin
    /// explicación** (ST-053).
    /// </summary>
    public string SaveKey(ApiKeyService service, string value)
    {
        string trimmed = value.Trim();

        if (trimmed.Length == 0)
        {
            _credentials.Delete(service.Key);
            RefreshCoverProviders();
            return "Se quitó la clave del Administrador de credenciales.";
        }

        bool saved = _credentials.Save(service.Key, trimmed);
        RefreshCoverProviders();

        return saved
            ? "Clave guardada en el Administrador de credenciales de Windows."
            : "No se pudo guardar la clave. Revisa que tu cuenta de Windows permita guardar credenciales.";
    }

    public string DeleteKey(ApiKeyService service)
    {
        _credentials.Delete(service.Key);
        RefreshCoverProviders();
        return "Se quitó la clave del Administrador de credenciales.";
    }
}
