namespace AuraStudio.Core.Library;

/// <summary>
/// Columnas de la tabla de Canciones (ST-030). Cada una sabe su rótulo, a qué
/// grupo pertenece en la ventana de opciones y con qué comparador ordena, así
/// la vista no repite el mismo <c>switch</c> en cada uso.
///
/// <para>"Título" <b>no</b> está acá: es la columna fija que siempre va primero,
/// como en Music.app.</para>
/// </summary>
public enum MusicTableColumn
{
    // Música
    Album, AlbumArtist, Artist, Composer, DiscNumber, Duration, Genre, TrackNumber, Year,
    // Personal
    Favorite, Rating,
    // Estadísticas
    DateAdded,
    // Archivo
    FileFormat, FileSize,
    // Otros
    Status
}

/// <summary>Los grupos de la ventana "Opciones de visualización".</summary>
public enum MusicColumnGroup { Music, Personal, Statistics, File, Other }

public static class MusicTableColumns
{
    public static readonly IReadOnlyList<MusicTableColumn> All =
        [.. Enum.GetValues<MusicTableColumn>()];

    /// <summary>
    /// Lo que muestra la tabla recién instalada: las mismas que tenía la tabla
    /// fija anterior (Título va aparte), más "Favorito", que es nueva y es el
    /// motivo del filtro "Solo favoritos".
    /// </summary>
    public static readonly IReadOnlyList<MusicTableColumn> DefaultVisible =
    [
        MusicTableColumn.Artist, MusicTableColumn.Album, MusicTableColumn.Genre,
        MusicTableColumn.Duration, MusicTableColumn.Favorite, MusicTableColumn.Status
    ];

    /// <summary>
    /// Los criterios que ofrece "Opciones para ordenar". Título se agrega
    /// aparte, porque no es una columna configurable.
    /// </summary>
    public static readonly IReadOnlyList<MusicTableColumn> SortMenuColumns =
    [
        MusicTableColumn.Album, MusicTableColumn.Artist, MusicTableColumn.Duration,
        MusicTableColumn.Favorite, MusicTableColumn.Genre, MusicTableColumn.Rating,
        MusicTableColumn.Year, MusicTableColumn.DateAdded
    ];

    /// <summary>El valor con el que se persiste. Estable: cambiarlo perdería la configuración.</summary>
    public static string RawValue(this MusicTableColumn column) => column switch
    {
        MusicTableColumn.Album => "album",
        MusicTableColumn.AlbumArtist => "albumArtist",
        MusicTableColumn.Artist => "artist",
        MusicTableColumn.Composer => "composer",
        MusicTableColumn.DiscNumber => "discNumber",
        MusicTableColumn.Duration => "duration",
        MusicTableColumn.Genre => "genre",
        MusicTableColumn.TrackNumber => "trackNumber",
        MusicTableColumn.Year => "year",
        MusicTableColumn.Favorite => "favorite",
        MusicTableColumn.Rating => "rating",
        MusicTableColumn.DateAdded => "dateAdded",
        MusicTableColumn.FileFormat => "fileFormat",
        MusicTableColumn.FileSize => "fileSize",
        _ => "status"
    };

    public static MusicTableColumn? Parse(string? raw) =>
        raw is null ? null : All.Cast<MusicTableColumn?>().FirstOrDefault(c => c!.Value.RawValue() == raw);

    public static MusicColumnGroup Group(this MusicTableColumn column) => column switch
    {
        MusicTableColumn.Album or MusicTableColumn.AlbumArtist or MusicTableColumn.Artist
            or MusicTableColumn.Composer or MusicTableColumn.DiscNumber or MusicTableColumn.Duration
            or MusicTableColumn.Genre or MusicTableColumn.TrackNumber or MusicTableColumn.Year
            => MusicColumnGroup.Music,
        MusicTableColumn.Favorite or MusicTableColumn.Rating => MusicColumnGroup.Personal,
        MusicTableColumn.DateAdded => MusicColumnGroup.Statistics,
        MusicTableColumn.FileFormat or MusicTableColumn.FileSize => MusicColumnGroup.File,
        _ => MusicColumnGroup.Other
    };

    public static string Title(this MusicColumnGroup group) => group switch
    {
        MusicColumnGroup.Music => "Música",
        MusicColumnGroup.Personal => "Personal",
        MusicColumnGroup.Statistics => "Estadísticas",
        MusicColumnGroup.File => "Archivo",
        _ => "Otros"
    };

    public static IReadOnlyList<MusicTableColumn> Columns(this MusicColumnGroup group) =>
        [.. All.Where(column => column.Group() == group)];

    public static string Title(this MusicTableColumn column) => column switch
    {
        MusicTableColumn.Album => "Álbum",
        MusicTableColumn.AlbumArtist => "Artista del álbum",
        MusicTableColumn.Artist => "Artista",
        MusicTableColumn.Composer => "Compositor",
        MusicTableColumn.DiscNumber => "Número de disco",
        MusicTableColumn.Duration => "Duración",
        MusicTableColumn.Genre => "Género",
        MusicTableColumn.TrackNumber => "Número de pista",
        MusicTableColumn.Year => "Año",
        MusicTableColumn.Favorite => "Favorito",
        MusicTableColumn.Rating => "Calificación",
        MusicTableColumn.DateAdded => "Fecha en que se agregó",
        MusicTableColumn.FileFormat => "Formato",
        MusicTableColumn.FileSize => "Tamaño",
        _ => "Estado"
    };

    /// <summary>Encabezado corto para la tabla; la ventana de opciones usa el título largo.</summary>
    public static string HeaderTitle(this MusicTableColumn column) => column switch
    {
        MusicTableColumn.DiscNumber => "Disco",
        MusicTableColumn.TrackNumber => "N.º",
        MusicTableColumn.DateAdded => "Agregado",
        _ => column.Title()
    };

    public static double MinWidth(this MusicTableColumn column) => column switch
    {
        MusicTableColumn.Album or MusicTableColumn.Artist or MusicTableColumn.AlbumArtist
            or MusicTableColumn.Composer => 90,
        MusicTableColumn.Genre => 60,
        MusicTableColumn.Duration => 50,
        MusicTableColumn.DiscNumber or MusicTableColumn.TrackNumber => 36,
        MusicTableColumn.Year => 44,
        MusicTableColumn.Favorite => 30,
        MusicTableColumn.Rating => 70,
        MusicTableColumn.DateAdded => 90,
        MusicTableColumn.FileFormat => 50,
        MusicTableColumn.FileSize => 60,
        _ => 90
    };

    public static double IdealWidth(this MusicTableColumn column) => column switch
    {
        MusicTableColumn.Album => 160,
        MusicTableColumn.Artist or MusicTableColumn.AlbumArtist or MusicTableColumn.Composer => 140,
        MusicTableColumn.Genre => 100,
        MusicTableColumn.Duration => 64,
        MusicTableColumn.DiscNumber or MusicTableColumn.TrackNumber => 44,
        MusicTableColumn.Year => 56,
        MusicTableColumn.Favorite => 34,
        MusicTableColumn.Rating => 90,
        MusicTableColumn.DateAdded => 110,
        MusicTableColumn.FileFormat => 60,
        MusicTableColumn.FileSize => 70,
        _ => 120
    };

    /// <summary>
    /// Migración desde el menú "+" viejo (D-199): lo que el usuario ya había
    /// activado ahí se conserva como columnas visibles, en vez de que la tabla
    /// aparezca de golpe con la configuración de fábrica.
    /// </summary>
    public static IReadOnlyList<MusicTableColumn> MigratingLegacyExtraColumns(string? raw)
    {
        List<MusicTableColumn> columns = [.. DefaultVisible];

        foreach (string token in raw?.Split(',') ?? [])
        {
            MusicTableColumn? column = token switch
            {
                "rating" => MusicTableColumn.Rating,
                "trackNumber" => MusicTableColumn.TrackNumber,
                "year" => MusicTableColumn.Year,
                _ => null
            };
            if (column is { } value && !columns.Contains(value)) columns.Add(value);
        }

        return columns;
    }
}

/// <summary>
/// Criterio de orden de la tabla: cualquier columna ordenable, o Título — que no
/// es una columna configurable, por eso no alcanza con <see cref="MusicTableColumn"/>.
/// </summary>
/// <param name="Column"><c>null</c> significa Título.</param>
public readonly record struct MusicSortField(MusicTableColumn? Column)
{
    public static MusicSortField ByTitle => new((MusicTableColumn?)null);

    public static MusicSortField By(MusicTableColumn column) => new(column);

    public string Title => Column?.Title() ?? "Título";

    public string RawValue => Column?.RawValue() ?? "title";

    public static MusicSortField? Parse(string? raw)
    {
        if (raw == "title") return ByTitle;
        return MusicTableColumns.Parse(raw) is { } column ? By(column) : null;
    }

    /// <summary>
    /// Los criterios del menú de orden, alfabéticos y con Título en su lugar —
    /// no al principio por ser especial, sino donde le toca por nombre.
    /// </summary>
    public static IReadOnlyList<MusicSortField> MenuFields { get; } =
        [.. MusicTableColumns.SortMenuColumns
            .Select(By)
            .Append(ByTitle)
            .OrderBy(field => field.Title, MediaTableRow.NaturalOrder)];
}
