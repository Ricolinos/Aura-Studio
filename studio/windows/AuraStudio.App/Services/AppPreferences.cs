using System.Text.Json;
using System.Text.Json.Serialization;
using AuraStudio.Core;
using AuraStudio.Core.Library;

namespace AuraStudio.App.Services;

/// <summary>
/// <see cref="IAppPreferences"/> sobre un JSON en
/// `%LOCALAPPDATA%\Aura Studio\preferences.json`.
///
/// Escribe en cada cambio (el archivo es diminuto) y **nunca deja caer una
/// excepción de disco a la UI**: si el perfil del usuario es de solo lectura o
/// el JSON quedó corrupto, la app arranca con los valores por omisión en vez
/// de no arrancar. Perder una preferencia es recuperable; no abrir, no.
///
/// <para>Los valores de opción se guardan **como texto**, con las mismas
/// cadenas que escribe la app de macOS: así el valor sobrevive a que se agregue
/// una opción en medio de un enum, y un criterio significa lo mismo en las dos
/// apps.</para>
/// </summary>
public sealed class AppPreferences : IAppPreferences
{
    private const string FolderName = "Aura Studio";
    private const string FileName = "preferences.json";

    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() }
    };

    private readonly string _path;
    private PreferencesFile _values;

    public event EventHandler<string>? Changed;

    public AppPreferences() : this(DefaultPath()) { }

    /// <summary>Constructor para pruebas: permite apuntar a un archivo temporal.</summary>
    public AppPreferences(string path)
    {
        _path = path;
        _values = Load(path);

        if (string.IsNullOrEmpty(_values.InstallationId))
        {
            _values = _values with { InstallationId = Guid.NewGuid().ToString("D") };
            Save();
        }
    }

    private static string DefaultPath() => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        FolderName, FileName);

    public AppTheme Theme
    {
        get => _values.Theme;
        set => Set(value, _values.Theme, v => _values = _values with { Theme = v });
    }

    public WindowPlacement? WindowPlacement
    {
        get => _values.WindowPlacement;
        set
        {
            if (Nullable.Equals(_values.WindowPlacement, value)) return;
            _values = _values with { WindowPlacement = value };
            Persist(nameof(WindowPlacement));
        }
    }

    public string InstallationId => _values.InstallationId ?? "";

    // MARK: - Biblioteca

    public string LibraryPath
    {
        get => _values.LibraryPath ?? LibraryStore.DefaultRoot;
        set => Set(value, LibraryPath, v => _values = _values with { LibraryPath = v });
    }

    public bool CopyMediaIntoLibrary
    {
        get => _values.CopyMediaIntoLibrary;
        set => Set(value, _values.CopyMediaIntoLibrary,
            v => _values = _values with { CopyMediaIntoLibrary = v });
    }

    /// <summary>ST-093: vacío = se busca solo en los lugares habituales y en el PATH.</summary>
    public string FfmpegPath
    {
        get => _values.FfmpegPath ?? "";
        set => Set(value, FfmpegPath, v => _values = _values with { FfmpegPath = v });
    }

    public IReadOnlyList<string> LinkedLibraryFolders
    {
        get => _values.LinkedLibraryFolders ?? [];
        set
        {
            string[] folders = [.. value];
            if (LinkedLibraryFolders.SequenceEqual(folders, StringComparer.Ordinal)) return;
            _values = _values with { LinkedLibraryFolders = folders };
            Persist(nameof(LinkedLibraryFolders));
        }
    }

    public CoverArtPolicy CoverArtPolicy
    {
        get => LibraryOptions.ParseCoverArtPolicy(_values.CoverArtPolicy);
        set => SetRaw(value.RawValue(), _values.CoverArtPolicy,
            v => _values = _values with { CoverArtPolicy = v }, nameof(CoverArtPolicy));
    }

    public bool EnrichOnline
    {
        get => _values.EnrichOnline;
        set => Set(value, _values.EnrichOnline, v => _values = _values with { EnrichOnline = v });
    }

    public bool FetchSyncedLyrics
    {
        get => _values.FetchSyncedLyrics;
        set => Set(value, _values.FetchSyncedLyrics, v => _values = _values with { FetchSyncedLyrics = v });
    }

    // MARK: - Música

    public MusicOrganization MusicOrganization
    {
        get => LibraryOptions.ParseMusicOrganization(_values.MusicOrganization);
        set => SetRaw(value.RawValue(), _values.MusicOrganization,
            v => _values = _values with { MusicOrganization = v }, nameof(MusicOrganization));
    }

    public MusicFilenameFormat MusicFilenameFormat
    {
        get => LibraryOptions.ParseMusicFilenameFormat(_values.MusicFilenameFormat);
        set => SetRaw(value.RawValue(), _values.MusicFilenameFormat,
            v => _values = _values with { MusicFilenameFormat = v }, nameof(MusicFilenameFormat));
    }

    public AudioQuality AudioQuality
    {
        get => LibraryOptions.ParseAudioQuality(_values.AudioQuality);
        set => SetRaw(value.RawValue(), _values.AudioQuality,
            v => _values = _values with { AudioQuality = v }, nameof(AudioQuality));
    }

    // MARK: - Fotos y video

    public PhotoQuality PhotoQuality
    {
        get => LibraryOptions.ParsePhotoQuality(_values.PhotoQuality);
        set => SetRaw(value.RawValue(), _values.PhotoQuality,
            v => _values = _values with { PhotoQuality = v }, nameof(PhotoQuality));
    }

    public bool OrganizePhotosByCategory
    {
        get => _values.OrganizePhotosByCategory;
        set => Set(value, _values.OrganizePhotosByCategory,
            v => _values = _values with { OrganizePhotosByCategory = v });
    }

    public bool OrganizeVideosByCategory
    {
        get => _values.OrganizeVideosByCategory;
        set => Set(value, _values.OrganizeVideosByCategory,
            v => _values = _values with { OrganizeVideosByCategory = v });
    }

    /// <summary>
    /// Lista separada por comas, igual que macOS. Una lista guardada vacía cae a
    /// las tres de fábrica: quedarse sin ninguna colección dejaría el selector
    /// de categoría sin opciones.
    /// </summary>
    public IReadOnlyList<string> PhotoCollections
    {
        get
        {
            string[] stored = (_values.PhotoCollections ?? "")
                .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            return stored.Length == 0 ? LibraryOptions.DefaultPhotoCollections : stored;
        }
        set
        {
            string raw = string.Join(",", value);
            if (_values.PhotoCollections == raw) return;
            _values = _values with { PhotoCollections = raw };
            Persist(nameof(PhotoCollections));
        }
    }

    // MARK: - Servicios

    public IReadOnlyList<CoverArtProvider> CoverArtProviderOrder
    {
        get => LibraryOptions.ParseCoverArtProviderOrder(_values.CoverArtProviderOrder);
        set
        {
            string raw = string.Join(",", value.Select(provider => provider.RawValue()));
            if (_values.CoverArtProviderOrder == raw) return;
            _values = _values with { CoverArtProviderOrder = raw };
            Persist(nameof(CoverArtProviderOrder));
        }
    }

    public bool DeezerEnabled
    {
        get => _values.DeezerEnabled;
        set => Set(value, _values.DeezerEnabled, v => _values = _values with { DeezerEnabled = v });
    }

    // MARK: - Tabla de Canciones (ST-030)

    /// <summary>
    /// Se guardan y se leen como texto, no como números: el valor persistido
    /// tiene que sobrevivir a que se agregue una columna en medio del enum.
    ///
    /// <para>Una columna que esta versión no conoce se descarta al leer, en vez
    /// de tirar la configuración entera.</para>
    /// </summary>
    public IReadOnlyList<MusicTableColumn> MusicVisibleColumns
    {
        get
        {
            if (_values.MusicVisibleColumns is not { } raw)
                // Nunca configurada: se hereda lo que el usuario tuviera en el
                // menú "+" viejo (D-199) antes de caer en lo de fábrica.
                return MusicTableColumns.MigratingLegacyExtraColumns(_values.LegacyExtraColumns);

            return [.. raw.Select(MusicTableColumns.Parse).OfType<MusicTableColumn>()];
        }
        set
        {
            string[] raw = [.. value.Select(column => column.RawValue())];
            if (_values.MusicVisibleColumns is { } current && current.SequenceEqual(raw)) return;

            _values = _values with { MusicVisibleColumns = raw };
            Persist(nameof(MusicVisibleColumns));
        }
    }

    public MusicSortField MusicSortField
    {
        get => MusicSortField.Parse(_values.MusicSortField) ?? MusicSortField.ByTitle;
        set => SetRaw(value.RawValue, _values.MusicSortField,
            v => _values = _values with { MusicSortField = v }, nameof(MusicSortField));
    }

    public bool MusicSortAscending
    {
        get => _values.MusicSortAscending;
        set => Set(value, _values.MusicSortAscending, v => _values = _values with { MusicSortAscending = v });
    }

    public bool MusicFavoritesOnly
    {
        get => _values.MusicFavoritesOnly;
        set => Set(value, _values.MusicFavoritesOnly, v => _values = _values with { MusicFavoritesOnly = v });
    }

    public bool ShowStatusBar
    {
        get => _values.ShowStatusBar;
        set => Set(value, _values.ShowStatusBar, v => _values = _values with { ShowStatusBar = v });
    }

    /// <summary>
    /// «Agrupar las colaboraciones bajo el artista principal» (R2-4).
    /// <b>Encendido por omisión.</b> Apagarlo devuelve la agrupación exacta de
    /// antes — sin migrar nada, porque la homologación nunca escribió nada.
    /// </summary>
    public bool GroupCollaborations
    {
        get => _values.GroupCollaborations;
        set => Set(value, _values.GroupCollaborations,
            v => _values = _values with { GroupCollaborations = v });
    }

    /// <summary>
    /// Nombres que no se recortan aunque traigan un separador ("Simon +
    /// Garfunkel", "Café con Leche").
    ///
    /// <para>Se guardan como arreglo nativo y <b>no</b> como lista separada por
    /// comas: un nombre real puede traer una coma, como "Earth, Wind &amp;
    /// Fire". Es la misma razón por la que macOS lo guarda así.</para>
    /// </summary>
    public IReadOnlyList<string> ArtistGroupingExceptions
    {
        get => _values.ArtistGroupingExceptions ?? [];
        set
        {
            string[] names = [.. value.Select(name => name.Trim()).Where(name => name.Length > 0)];
            if (ArtistGroupingExceptions.SequenceEqual(names, StringComparer.Ordinal)) return;
            _values = _values with { ArtistGroupingExceptions = names };
            Persist(nameof(ArtistGroupingExceptions));
        }
    }

    /// <summary>
    /// Cuál de los firmwares instalables usa el Instalador la próxima vez
    /// (ST-047, R4). Es una <b>preferencia, no una acción</b>: elegir en Extras
    /// no toca el iPod.
    ///
    /// <para>Se guarda por su <c>ConfigValue</c> —la misma cadena que escribe
    /// macOS en <c>aura.firmwareFamilyToInstall</c>—, no por su posición en un
    /// enum: agregar una familia en medio no puede cambiar lo que el usuario
    /// eligió. Una cadena que ya no corresponde a ninguna familia cae a Aura,
    /// que es la que siempre existe.</para>
    /// </summary>
    public FirmwareFamily FirmwareFamilyToInstall
    {
        get
        {
            // Una familia guardada que esta versión ya no sabe instalar cae a
            // Aura: el selector solo ofrece las instalables, y dejar elegida una
            // que no está sería un estado sin salida.
            FirmwareFamily stored = FirmwareFamily.Parse(_values.FirmwareFamilyToInstall);
            return stored.IsInstallable ? stored : FirmwareFamily.Aura;
        }
        set
        {
            string? raw = value?.ConfigValue;
            if (_values.FirmwareFamilyToInstall == raw) return;

            _values = _values with { FirmwareFamilyToInstall = raw };
            Persist(nameof(FirmwareFamilyToInstall));
        }
    }

    /// <summary>Lo que la agrupación necesita saber, en una sola pieza.</summary>
    public ArtistGroupingOptions ArtistGrouping =>
        new(GroupCollaborations, ArtistGroupingExceptions);

    public IReadOnlyList<string> IgnoredSimilarGroups
    {
        get => _values.IgnoredSimilarGroups ?? [];
        set
        {
            string[] groups = [.. value];
            if (IgnoredSimilarGroups.SequenceEqual(groups, StringComparer.Ordinal)) return;
            _values = _values with { IgnoredSimilarGroups = groups };
            Persist(nameof(IgnoredSimilarGroups));
        }
    }

    // MARK: - Arranques verificados (ST-166)

    /// <summary>
    /// Lo que hay anotado, ya normalizado. Se recalcula al leerlo en vez de
    /// guardarse aparte: el mapa tiene una entrada por iPod que pasó por esta
    /// computadora —dos o tres, no dos mil— y así no hay dos copias del mismo
    /// dato que puedan desincronizarse.
    /// </summary>
    private IReadOnlyDictionary<string, string> BootloaderRegistryMap =>
        BootloaderRegistry.Normalize(_values.BootloaderVerifiedDisks);

    public string? BootloaderHash(string? diskKey) =>
        BootloaderRegistry.HashFor(BootloaderRegistryMap, diskKey);

    /// <summary>
    /// Anota qué arranque quedó grabado. Quién decide qué se guarda —y qué pasa
    /// sin clave o sin hash— vive en <c>BootloaderRegistry</c> y está probado
    /// ahí; acá solo queda escribirlo.
    /// </summary>
    public void RecordBootloaderVerified(string? diskKey, string? hash) =>
        StoreBootloaderRegistry(
            BootloaderRegistry.WithRecord(BootloaderRegistryMap, diskKey, hash));

    public void ForgetBootloaderVerified(string? diskKey) =>
        StoreBootloaderRegistry(BootloaderRegistry.Without(BootloaderRegistryMap, diskKey));

    private void StoreBootloaderRegistry(IReadOnlyDictionary<string, string> updated)
    {
        // Anotar el mismo arranque en el mismo iPod pasa en cada reconexión:
        // sin esto se reescribiría el archivo de preferencias cada vez, para
        // dejarlo igual.
        if (BootloaderRegistry.SameRegistry(BootloaderRegistryMap, updated)) return;

        _values = _values with
        {
            BootloaderVerifiedDisks = updated.ToDictionary(
                entry => entry.Key, entry => (string?)entry.Value, StringComparer.Ordinal)
        };
        Persist(nameof(BootloaderHash));
    }

    // MARK: - Plomería

    private void Set<T>(T value, T current, Action<T> assign,
        [System.Runtime.CompilerServices.CallerMemberName] string propertyName = "")
    {
        if (EqualityComparer<T>.Default.Equals(value, current)) return;
        assign(value);
        Persist(propertyName);
    }

    private void SetRaw(string value, string? current, Action<string> assign, string propertyName)
    {
        if (current == value) return;
        assign(value);
        Persist(propertyName);
    }

    private void Persist(string propertyName)
    {
        Save();
        Changed?.Invoke(this, propertyName);
    }

    private void Save()
    {
        try
        {
            string? dir = Path.GetDirectoryName(_path);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            File.WriteAllText(_path, JsonSerializer.Serialize(_values, SerializerOptions));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or NotSupportedException)
        {
            // Preferencia perdida, app viva. Ver comentario de la clase.
        }
    }

    private static PreferencesFile Load(string path)
    {
        try
        {
            if (!File.Exists(path)) return new PreferencesFile();
            return JsonSerializer.Deserialize<PreferencesFile>(File.ReadAllText(path), SerializerOptions)
                   ?? new PreferencesFile();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException)
        {
            return new PreferencesFile();
        }
    }

    /// <summary>
    /// Forma serializada. Un campo nuevo se agrega acá con su valor por omisión;
    /// los de opción son <c>string?</c> para que un valor desconocido caiga al
    /// predeterminado en vez de romper la lectura del archivo entero.
    /// </summary>
    private sealed record PreferencesFile
    {
        public AppTheme Theme { get; init; } = AppTheme.System;
        public WindowPlacement? WindowPlacement { get; init; }
        public string? InstallationId { get; init; }

        public string? LibraryPath { get; init; }
        public string? FfmpegPath { get; init; }
        public bool CopyMediaIntoLibrary { get; init; } = true;
        public string[]? LinkedLibraryFolders { get; init; }
        public string? CoverArtPolicy { get; init; }
        public bool EnrichOnline { get; init; } = true;
        public bool FetchSyncedLyrics { get; init; } = true;

        public string? MusicOrganization { get; init; }
        public string? MusicFilenameFormat { get; init; }
        public string? AudioQuality { get; init; }

        public string? PhotoQuality { get; init; }
        public bool OrganizePhotosByCategory { get; init; } = true;
        public bool OrganizeVideosByCategory { get; init; } = true;
        public string? PhotoCollections { get; init; }

        public string? CoverArtProviderOrder { get; init; }
        public bool DeezerEnabled { get; init; } = true;

        /// <summary>
        /// `null` significa "el usuario nunca configuró las columnas", que no es
        /// lo mismo que "las dejó todas apagadas" — un arreglo vacío sí.
        /// </summary>
        public string[]? MusicVisibleColumns { get; init; }

        /// <summary>Lo que había en el menú "+" de la versión anterior (D-199).</summary>
        public string? LegacyExtraColumns { get; init; }

        public string? MusicSortField { get; init; }
        public bool MusicSortAscending { get; init; } = true;
        public bool MusicFavoritesOnly { get; init; }
        public bool ShowStatusBar { get; init; } = true;
        public string[]? IgnoredSimilarGroups { get; init; }
        public string? FirmwareFamilyToInstall { get; init; }
        public bool GroupCollaborations { get; init; } = true;
        public string[]? ArtistGroupingExceptions { get; init; }

        /// <summary>
        /// ST-166: qué arranque tiene grabado cada iPod que pasó por esta
        /// computadora — clave, el serial USB; valor, el SHA-256 del
        /// <c>bootloader-ipod6g.ipod</c> que se le grabó, o <c>"unknown"</c>.
        /// La NOR no se puede leer, así que este mapa es lo único que la app
        /// sabe. Lo interpreta <c>BootloaderRegistry.Normalize</c>: un valor que
        /// no sea un hash se lee como <c>"unknown"</c>, nunca como ausente.
        /// </summary>
        public Dictionary<string, string?>? BootloaderVerifiedDisks { get; init; }
    }
}
