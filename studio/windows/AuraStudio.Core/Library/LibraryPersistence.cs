using System.Text.Json;
using System.Text.Json.Serialization;

namespace AuraStudio.Core.Library;

/// <summary>
/// Catálogo persistido de la biblioteca (`biblioteca.json` en la raíz de la
/// carpeta de biblioteca, D-180). Port de `LibraryPersistence.swift`.
///
/// <para><b>Todas las rutas son RELATIVAS</b> a esa carpeta: mover la carpeta
/// entera a otro disco y apuntar ahí la preferencia conserva la biblioteca
/// intacta.</para>
///
/// <para><b>La portada no se serializa dentro del JSON</b>: una imagen por
/// pista inflaría el catálogo a decenas de megabytes y cada guardado sería una
/// reescritura completa. Vive como archivo en `.portadas/&lt;id&gt;.jpg` y acá
/// solo viaja su ruta.</para>
/// </summary>
public sealed class PersistedLibrary
{
    public const string CatalogFileName = "biblioteca.json";

    /// <summary>
    /// Las tres raíces que el usuario ve en el Explorador. `.preparados` y
    /// `.portadas` llevan punto adelante porque son técnicas, no de cara al
    /// usuario (D-228: ya no hay una única carpeta plana; el destino de cada
    /// item depende de su tipo, artista, álbum y categoría).
    /// </summary>
    public const string MusicDirName = "Música";
    public const string ImagesDirName = "Imágenes";
    public const string VideosDirName = "Videos";

    /// <summary>
    /// Lo ya convertido y listo para copiar al iPod.
    ///
    /// <para><b>NUNCA se limpia</b> — instrucción del dueño tras ST-087. Cuando
    /// se perdieron 2408 entradas del catálogo, lo que quedó de ellas fueron
    /// justamente estos archivos: audios con sus etiquetas y sus letras al lado.
    /// Es la única reconstrucción posible si algún día decide intentarla, así
    /// que ninguna rutina de mantenimiento, de "liberar espacio" ni de limpieza
    /// puede borrarlos. Ver <see cref="LibraryStore.NeverCleaned"/>.</para>
    /// </summary>
    public const string PreparedDirName = ".preparados";

    /// <summary>Las carátulas, una por elemento. Tampoco se limpia sola.</summary>
    public const string CoversDirName = ".portadas";

    public List<PersistedLibraryItem> Items { get; set; } = [];
    public List<PersistedPlaylist> Playlists { get; set; } = [];

    /// <summary>
    /// ST-141: versión del formato de las imágenes de <c>.portadas\</c>.
    /// Ausente = biblioteca anterior al recorte cuadrado (hay que migrarla);
    /// <c>2</c> = todas las carátulas de música y todas las fotos de artista son
    /// cuadradas y de lado ≤ 1000. Anulable por la misma razón que el resto de
    /// los campos nuevos: un catálogo viejo no lo trae.
    /// </summary>
    public int? CoversNormalized { get; set; }
}

public sealed class PersistedLibraryItem
{
    public Guid Id { get; set; }

    /// <summary>Relativa a la carpeta de biblioteca.</summary>
    public string SourceRelativePath { get; set; } = "";

    public string Kind { get; set; } = "unsupported";

    /// <summary>
    /// Solo estados estables. Los transitorios y los fallidos se guardan como
    /// `queued`: al reabrir la app se reintentan en vez de quedar congelados en
    /// un estado que ya no corre.
    /// </summary>
    public string Status { get; set; } = "queued";

    public PersistedTrackMetadata? Metadata { get; set; }
    public string? PreparedRelativePath { get; set; }
    public string? CoverRelativePath { get; set; }
    public string? Category { get; set; }
    public string? SeriesName { get; set; }
    public int? Season { get; set; }
    public int? Episode { get; set; }
    public string? PhotoAlbum { get; set; }

    /// <summary>
    /// Anulable a propósito, no `bool` a secas: un catálogo guardado antes de
    /// este campo no lo trae, y exigirlo tiraría el catálogo **entero** en vez
    /// de solo este campo.
    /// </summary>
    public bool? MetadataEditedByUser { get; set; }

    public DateTimeOffset? AddedAt { get; set; }
}

public sealed class PersistedTrackMetadata
{
    public string? Title { get; set; }
    public string? Artist { get; set; }
    public string? Album { get; set; }
    public string? AlbumArtist { get; set; }
    public string? Year { get; set; }
    public string? Genre { get; set; }
    public string? Composer { get; set; }
    public int? TrackNumber { get; set; }
    public string? SyncedLyrics { get; set; }
    // Swift los declara con "ID" en mayúsculas y su decodificador SÍ distingue
    // mayúsculas: escritos como "…Id", la app de macOS no los encontraría y
    // perdería el enlace con MusicBrainz sin decir nada.
    [JsonPropertyName("musicBrainzRecordingID")]
    public string? MusicBrainzRecordingId { get; set; }

    [JsonPropertyName("musicBrainzReleaseID")]
    public string? MusicBrainzReleaseId { get; set; }
    public double? DurationSeconds { get; set; }
    public int? Rating { get; set; }
    public bool? IsFavorite { get; set; }
    public int? DiscNumber { get; set; }
}

/// <summary>
/// Una playlist del catálogo. Se conserva su forma completa aunque el módulo de
/// playlists llegue después: cargar y volver a guardar el catálogo **no puede
/// perder** lo que otra parte de la app escribió.
/// </summary>
public sealed class PersistedPlaylist
{
    public Guid Id { get; set; }
    public string Name { get; set; } = "";
    [JsonPropertyName("trackItemIDs")]
    public List<Guid> TrackItemIds { get; set; } = [];

    /// <summary>Archivo en `.portadas/`, no imagen embebida.</summary>
    public string? ImageRelativePath { get; set; }
}

/// <summary>
/// Mapeo entre el modelo vivo y el persistido, como funciones puras para poder
/// probarlas sin tocar disco. Port de `LibraryPersistenceMapper`.
/// </summary>
public static class LibraryPersistenceMapper
{
    public static string PersistedStatus(LibraryItemStatus status) => status.State switch
    {
        LibraryItemState.Ready => "ready",
        LibraryItemState.NeedsReview => "needsReview",
        // Transitorios y fallidos vuelven a la cola: se reintentan al reabrir.
        _ => "queued"
    };

    public static LibraryItemStatus LiveStatus(string? raw) => raw switch
    {
        "ready" => LibraryItemStatus.Ready,
        "needsReview" => LibraryItemStatus.NeedsReview,
        _ => LibraryItemStatus.Queued
    };

    public static string PersistedKind(LibraryItemKind kind) => kind switch
    {
        LibraryItemKind.Music => "music",
        LibraryItemKind.Video => "video",
        LibraryItemKind.Photo => "photo",
        _ => "unsupported"
    };

    public static LibraryItemKind LiveKind(string? raw) => raw switch
    {
        "music" => LibraryItemKind.Music,
        "video" => LibraryItemKind.Video,
        "photo" => LibraryItemKind.Photo,
        _ => LibraryItemKind.Unsupported
    };

    /// <summary>
    /// D-228: los catálogos guardados antes de ese cambio persistían el valor
    /// interno de la categoría; ahora es un nombre de display libre. Los valores
    /// viejos conocidos se traducen; cualquier otro pasa tal cual — puede ser un
    /// nombre nuevo o una colección que el usuario creó.
    /// </summary>
    public static readonly IReadOnlyDictionary<string, string> LegacyCategoryDisplayNames =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["images"] = "Imágenes",
            ["photos"] = "Fotos",
            ["aiGenerated"] = "IA",
            ["homeVideos"] = "Series",
            ["videos"] = "Videos",
            ["movies"] = "Películas"
        };

    public static string? LiveCategory(string? raw)
    {
        if (raw is null) return null;
        return LegacyCategoryDisplayNames.TryGetValue(raw, out string? display) ? display : raw;
    }

    public static PersistedTrackMetadata? ToPersisted(TrackMetadata? metadata)
    {
        if (metadata is null) return null;
        return new PersistedTrackMetadata
        {
            Title = metadata.Title,
            Artist = metadata.Artist,
            Album = metadata.Album,
            AlbumArtist = metadata.AlbumArtist,
            Year = metadata.Year,
            Genre = metadata.Genre,
            Composer = metadata.Composer,
            TrackNumber = metadata.TrackNumber,
            SyncedLyrics = metadata.SyncedLyrics,
            MusicBrainzRecordingId = metadata.MusicBrainzRecordingId,
            MusicBrainzReleaseId = metadata.MusicBrainzReleaseId,
            DurationSeconds = metadata.DurationSeconds,
            Rating = metadata.Rating,
            // Solo se escribe cuando es verdadero: un catálogo lleno de
            // `false` explícitos no aporta nada y engorda el archivo.
            IsFavorite = metadata.IsFavorite ? true : null,
            DiscNumber = metadata.DiscNumber
        };
    }

    /// <summary>
    /// La portada llega aparte: no vive en el JSON sino en `.portadas/`.
    /// </summary>
    public static TrackMetadata? ToLive(PersistedTrackMetadata? persisted, byte[]? coverArtData)
    {
        if (persisted is null) return null;
        return new TrackMetadata
        {
            Title = persisted.Title,
            Artist = persisted.Artist,
            Album = persisted.Album,
            AlbumArtist = persisted.AlbumArtist,
            Year = persisted.Year,
            Genre = persisted.Genre,
            Composer = persisted.Composer,
            TrackNumber = persisted.TrackNumber,
            CoverArtData = coverArtData,
            SyncedLyrics = persisted.SyncedLyrics,
            MusicBrainzRecordingId = persisted.MusicBrainzRecordingId,
            MusicBrainzReleaseId = persisted.MusicBrainzReleaseId,
            DurationSeconds = persisted.DurationSeconds,
            Rating = persisted.Rating,
            IsFavorite = persisted.IsFavorite ?? false,
            DiscNumber = persisted.DiscNumber
        };
    }
}

/// <summary>
/// Lee y escribe el catálogo en disco. El guardado es **atómico**: se escribe a
/// un archivo temporal y se reemplaza, para que un corte de luz a mitad no deje
/// `biblioteca.json` truncado — perder el catálogo obliga al usuario a rearmar
/// su biblioteca entera.
/// </summary>
public static class LibraryCatalogStore
{
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        // Los conversores existen para que este archivo sea el MISMO para las
        // dos apps: el dueño usa la misma carpeta de biblioteca desde la Mac y
        // desde Windows.
        //
        // Al leer, toleran lo que escribe Swift y lo que escriben etiquetas
        // rotas —un solo campo raro no puede costar el catálogo entero—. Al
        // escribir, producen exactamente la forma que decodifica un
        // `JSONDecoder()` por omisión de macOS: fecha como número de segundos
        // desde 2001 e identificadores en mayúsculas. Es más importante de lo
        // que parece, porque **allá el decodificador se usa con `try?`**: lo que
        // no puede leer no da error, deja la biblioteca vacía en silencio.
        Converters =
        {
            new AppleEpochDateConverter(),
            new TolerantInt32Converter(),
            new SwiftUuidConverter()
        }
    };

    public static string CatalogPath(string libraryRoot)
        => Path.Combine(libraryRoot, PersistedLibrary.CatalogFileName);

    /// <param name="Catalog">Lo que se pudo leer; vacío si no se pudo.</param>
    /// <param name="Error">
    /// Por qué no se pudo, o <c>null</c> si todo salió bien. <b>Que no haya
    /// catálogo no es un error</b>: una biblioteca nueva simplemente está vacía.
    /// </param>
    public readonly record struct CatalogLoad(PersistedLibrary Catalog, string? Error)
    {
        public bool Failed => Error is not null;
    }

    /// <summary>
    /// El catálogo, o uno vacío si no existe o no se puede leer. **Nunca
    /// lanza**: ante un archivo ilegible es mejor arrancar con la biblioteca
    /// vacía y que el usuario reimporte, que no abrir.
    /// </summary>
    public static PersistedLibrary Load(string libraryRoot) => TryLoad(libraryRoot).Catalog;

    /// <summary>
    /// Igual que <see cref="Load"/>, pero <b>dice si falló</b>. Existe por un
    /// caso real: un catálogo de 2809 elementos hecho en la Mac se mostraba como
    /// biblioteca vacía, y "vacía" y "no la pude leer" se veían idénticas en
    /// pantalla. Quien tenga cómo decírselo al usuario, que use esta.
    /// </summary>
    public static CatalogLoad TryLoad(string libraryRoot)
    {
        string path;

        // ST-171: "el disco de la biblioteca no está" NO es "la biblioteca está
        // vacía". Sin esta distinción las dos se veían idénticas —catálogo
        // vacío y sin error—, y de ahí salía el bug: con el disco desmontado la
        // app concluía que no había carátulas que normalizar, se daba por
        // normalizada y trataba de GUARDAR esa conclusión en una unidad que no
        // existe.
        //
        // Se pregunta por el VOLUMEN y no por la carpeta: una carpeta que aún
        // no existe en un disco montado es una biblioteca nueva, y ésa sí se
        // lee como vacía y sin error, que es lo correcto.
        if (!LibraryRoot.VolumeIsMounted(libraryRoot))
        {
            return new CatalogLoad(new PersistedLibrary(),
                $"La biblioteca no está disponible: {libraryRoot}");
        }

        try
        {
            path = CatalogPath(libraryRoot);
            if (!File.Exists(path)) return new CatalogLoad(new PersistedLibrary(), null);
        }
        catch (ArgumentException ex)
        {
            return new CatalogLoad(new PersistedLibrary(), $"La ruta de la biblioteca no es válida: {ex.Message}");
        }

        try
        {
            PersistedLibrary? catalog =
                JsonSerializer.Deserialize<PersistedLibrary>(File.ReadAllText(path), Options);

            return catalog is null
                ? new CatalogLoad(new PersistedLibrary(), "El catálogo de la biblioteca está vacío o dañado.")
                : new CatalogLoad(catalog, null);
        }
        catch (JsonException ex)
        {
            return new CatalogLoad(new PersistedLibrary(),
                $"No se pudo leer el catálogo de la biblioteca: {ex.Message}");
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return new CatalogLoad(new PersistedLibrary(),
                $"No se pudo abrir el catálogo de la biblioteca: {ex.Message}");
        }
    }

    /// <summary>
    /// Escribe el catálogo entero, creando la carpeta si hace falta.
    ///
    /// <para>ST-171: <b>no si el volumen no está montado.</b> Crear la carpeta
    /// de una biblioteca nueva es legítimo —es lo que pasa en el primer
    /// arranque—, pero crearla en una unidad que no está es inventar un disco:
    /// eso es lo que reventaba con una <c>DirectoryNotFoundException</c> en la
    /// cara del usuario cuando abría la app con su disco externo desmontado. Y
    /// si la unidad hubiera existido con la carpeta borrada, habría sido peor:
    /// habría escrito un catálogo vacío encima, en silencio.</para>
    /// </summary>
    /// <exception cref="LibraryRootUnavailableException">El volumen de esa ruta no está montado.</exception>
    public static void Save(string libraryRoot, PersistedLibrary catalog)
    {
        if (!LibraryRoot.VolumeIsMounted(libraryRoot))
            throw new LibraryRootUnavailableException(libraryRoot);

        Directory.CreateDirectory(libraryRoot);
        string path = CatalogPath(libraryRoot);
        string temporary = path + ".tmp";

        File.WriteAllText(temporary, JsonSerializer.Serialize(catalog, Options));
        // Move con overwrite es atómico dentro del mismo volumen: o queda el
        // catálogo viejo entero, o el nuevo entero. Nunca uno a medias.
        File.Move(temporary, path, overwrite: true);
    }
}
