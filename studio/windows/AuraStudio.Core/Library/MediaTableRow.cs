using System.Globalization;

namespace AuraStudio.Core.Library;

/// <summary>
/// Estado de un elemento frente al iPod conectado. El índice que lo calcula es
/// de la Fase 4; el enum vive acá porque la columna "Estado" de la tabla ordena
/// por él (ST-030) y su orden es parte del contrato de esa columna.
/// </summary>
public enum SyncItemState
{
    /// <summary>Copiado a este dispositivo y sin cambios de ninguno de los dos lados.</summary>
    Synced,

    /// <summary>Nunca se copió a ESTE dispositivo, o todavía no está listo.</summary>
    Pending,

    /// <summary>Se editó acá después de copiarlo: en el iPod sigue la versión vieja.</summary>
    ChangedLocally,

    /// <summary>Alguien lo tocó en el iPod fuera de Aura Studio.</summary>
    ModifiedOnDevice,

    /// <summary>
    /// Se borró a mano en el iPod. <b>Nunca se vuelve a copiar solo</b>: es una
    /// decisión del usuario y se respeta.
    /// </summary>
    RemovedFromDevice
}

/// <summary>
/// Un renglón de la tabla de Canciones: el elemento más lo que la tabla necesita
/// mostrar y ordenar, ya calculado. Port de <c>MediaTableRow</c>.
///
/// <para><b>El tamaño del archivo se pasa al construir</b>, no se lee en cada
/// acceso. En macOS es una propiedad calculada que consulta el disco, así que
/// ordenar por "Tamaño" lo consulta una vez por comparación; acá se lee una vez
/// por renglón. El resultado en pantalla es el mismo.</para>
/// </summary>
public sealed class MediaTableRow(LibraryItem item, long fileSizeBytes = 0, SyncItemState? syncState = null)
{
    /// <summary>
    /// Orden natural e insensible a mayúsculas, el equivalente de
    /// <c>localizedStandard</c>: "Pista 2" antes que "Pista 10".
    /// </summary>
    public static readonly StringComparer NaturalOrder = StringComparer.Create(
        CultureInfo.GetCultureInfo("es-MX"), CompareOptions.IgnoreCase | CompareOptions.NumericOrdering);

    /// <summary>
    /// Las fechas se muestran en español de México pase lo que pase, aunque
    /// Windows esté en otro idioma: es una regla del repo, no del sistema.
    /// </summary>
    private static readonly CultureInfo DisplayCulture = CultureInfo.GetCultureInfo("es-MX");

    public LibraryItem Item { get; } = item;
    public SyncItemState? SyncState { get; set; } = syncState;
    public Guid Id => Item.Id;

    /// <summary>
    /// Clave de orden de la columna "Estado": primero lo que ya está en el iPod,
    /// después lo que falta por hacer, y al final lo que necesita atención — así
    /// "ordenar por Estado" <b>agrupa</b> lo pendiente y lo problemático en vez
    /// de mezclarlo. El texto que se muestra sale aparte; esto es solo el rango.
    /// </summary>
    public int StatusRank => Item.Status.State switch
    {
        LibraryItemState.Ready => SyncState switch
        {
            SyncItemState.Synced => 0,
            null => 1,                              // "Listo", sin iPod conectado
            SyncItemState.Pending => 2,
            SyncItemState.ChangedLocally => 3,
            SyncItemState.ModifiedOnDevice => 4,
            _ => 5                                  // borrado en el iPod
        },
        LibraryItemState.Queued => 6,
        LibraryItemState.Enriching => 7,
        LibraryItemState.Transcoding => 8,
        LibraryItemState.NeedsReview => 9,
        _ => 10                                     // falló
    };

    public string Title => Item.DisplayTitle;
    public string Artist => Item.Metadata?.Artist ?? "";
    public string Album => Item.Metadata?.Album ?? "";
    public string AlbumArtist => Item.Metadata?.AlbumArtist ?? "";
    public string Composer => Item.Metadata?.Composer ?? "";
    public string Genre => Item.Metadata?.Genre ?? "";
    public string Category => Item.Category ?? "";
    public string Year => Item.Metadata?.Year ?? "";

    public double DurationSeconds => Item.Metadata?.DurationSeconds ?? 0;
    public string DurationText =>
        Item.Metadata?.DurationSeconds is > 0 and double seconds
            ? SimilarityText.Clock(seconds)
            : "--";

    public int DiscNumberSort => Item.Metadata?.DiscNumber ?? 0;
    public string DiscNumberText => Item.Metadata?.DiscNumber?.ToString(DisplayCulture) ?? "";

    public int TrackNumberSort => Item.Metadata?.TrackNumber ?? 0;
    public string TrackNumberText => Item.Metadata?.TrackNumber?.ToString(DisplayCulture) ?? "";

    public bool IsFavorite => Item.Metadata?.IsFavorite ?? false;

    /// <summary>Ascendente = favoritos primero (0 antes que 1).</summary>
    public int FavoriteRank => IsFavorite ? 0 : 1;

    public int RatingValue => Item.Metadata?.Rating ?? 0;
    public string RatingText => RatingValue > 0 ? new string('★', RatingValue) : "";

    /// <summary>Sin fecha va al final del orden ascendente, no al principio.</summary>
    public DateTimeOffset AddedAtSort => Item.AddedAt ?? DateTimeOffset.MinValue;

    public string AddedAtText => Item.AddedAt?.ToString("d 'de' MMMM 'de' yyyy", DisplayCulture) ?? "";

    public string FileFormat => Path.GetExtension(Item.SourcePath).TrimStart('.').ToUpperInvariant();

    public long FileSizeBytes { get; } = fileSizeBytes;

    public string FileSizeText => FileSizeBytes > 0 ? SimilarityText.FormatBytes(FileSizeBytes) : "--";

    /// <summary>
    /// Lo que se ve en la celda de una columna. Vive junto a la clave de orden a
    /// propósito: una columna que muestre una cosa y ordene por otra es el
    /// error clásico de las tablas (ordenar "10:00" antes que "3:24"), y tenerlas
    /// pegadas hace evidente cuándo no coinciden.
    ///
    /// <para>Favorito devuelve texto vacío: esa celda la dibuja la vista con un
    /// corazón, no con letras.</para>
    /// </summary>
    public string CellText(MusicTableColumn column) => column switch
    {
        MusicTableColumn.Album => Album,
        MusicTableColumn.AlbumArtist => AlbumArtist,
        MusicTableColumn.Artist => Artist,
        MusicTableColumn.Composer => Composer,
        MusicTableColumn.DiscNumber => DiscNumberText,
        MusicTableColumn.Duration => DurationText,
        MusicTableColumn.Genre => Genre,
        MusicTableColumn.TrackNumber => TrackNumberText,
        MusicTableColumn.Year => Year,
        MusicTableColumn.Favorite => "",
        MusicTableColumn.Rating => RatingText,
        MusicTableColumn.DateAdded => AddedAtText,
        MusicTableColumn.FileFormat => FileFormat,
        MusicTableColumn.FileSize => FileSizeText,
        _ => StatusText
    };

    /// <summary>
    /// El estado en una frase corta. Lo que está en el iPod y lo que le falta se
    /// dicen distinto: "Listo" a secas, sin dispositivo, no promete nada.
    /// </summary>
    public string StatusText => Item.Status.State switch
    {
        LibraryItemState.Ready => SyncState switch
        {
            SyncItemState.Synced => "En el iPod",
            null => "Listo",
            SyncItemState.Pending => "Falta copiar",
            SyncItemState.ChangedLocally => "Cambió aquí",
            SyncItemState.ModifiedOnDevice => "Cambió en el iPod",
            _ => "Se borró en el iPod"
        },
        LibraryItemState.Queued => "En cola",
        LibraryItemState.Enriching => "Buscando información",
        LibraryItemState.Transcoding => $"Convirtiendo… {Item.Status.Progress * 100:0}%",
        LibraryItemState.NeedsReview => "Necesita revisión",
        _ => Item.Status.Error is { Length: > 0 } error ? $"Error: {error}" : "Error"
    };

    /// <summary>El valor con el que ordena una columna dada.</summary>
    public IComparable SortKey(MusicTableColumn column) => column switch
    {
        MusicTableColumn.Album => Album,
        MusicTableColumn.AlbumArtist => AlbumArtist,
        MusicTableColumn.Artist => Artist,
        MusicTableColumn.Composer => Composer,
        MusicTableColumn.DiscNumber => DiscNumberSort,
        MusicTableColumn.Duration => DurationSeconds,
        MusicTableColumn.Genre => Genre,
        MusicTableColumn.TrackNumber => TrackNumberSort,
        MusicTableColumn.Year => Year,
        MusicTableColumn.Favorite => FavoriteRank,
        MusicTableColumn.Rating => RatingValue,
        MusicTableColumn.DateAdded => AddedAtSort,
        MusicTableColumn.FileFormat => FileFormat,
        MusicTableColumn.FileSize => FileSizeBytes,
        _ => StatusRank
    };
}

/// <summary>
/// El comparador de un criterio de orden. <b>Toda columna declara el suyo</b>
/// (regla del repo): una columna que no ordena es un bug, no una decisión.
/// </summary>
public sealed class MediaTableRowComparer(MusicSortField field, bool ascending) : IComparer<MediaTableRow>
{
    /// <summary>Las columnas de texto se comparan en orden natural, no por código de carácter.</summary>
    private static readonly IReadOnlySet<MusicTableColumn> TextColumns =
        new HashSet<MusicTableColumn>
        {
            MusicTableColumn.Album, MusicTableColumn.AlbumArtist, MusicTableColumn.Artist,
            MusicTableColumn.Composer, MusicTableColumn.Genre
        };

    public int Compare(MediaTableRow? a, MediaTableRow? b)
    {
        if (ReferenceEquals(a, b)) return 0;
        if (a is null) return -1;
        if (b is null) return 1;

        // Sin desempate artificial: dos renglones con el mismo valor quedan
        // empatados y conservan el orden en que venían, igual que en macOS. Lo
        // que hace que eso sea estable —y no un orden distinto en cada
        // reordenamiento— es que el ordenamiento de abajo sí lo es.
        int result = CompareAscending(a, b);
        return ascending ? result : -result;
    }

    private int CompareAscending(MediaTableRow a, MediaTableRow b)
    {
        if (field.Column is not { } column)
            return MediaTableRow.NaturalOrder.Compare(a.Title, b.Title);

        if (TextColumns.Contains(column) || column == MusicTableColumn.Year)
            return MediaTableRow.NaturalOrder.Compare((string)a.SortKey(column), (string)b.SortKey(column));

        return a.SortKey(column).CompareTo(b.SortKey(column));
    }
}

public static class MediaTableRowSorting
{
    /// <summary>
    /// Los renglones ordenados por el criterio dado. Devuelve una lista nueva:
    /// el orden es una vista, no una mutación del catálogo.
    ///
    /// <para><b>Ordenamiento estable</b> (<c>OrderBy</c>, no
    /// <c>List.Sort</c>): los renglones con el mismo valor conservan el orden en
    /// que venían, como hace la tabla de macOS. Con un ordenamiento inestable,
    /// las tres canciones de un mismo álbum cambiarían de lugar entre sí cada
    /// vez que se reordena la tabla.</para>
    /// </summary>
    public static IReadOnlyList<MediaTableRow> Sorted(
        this IEnumerable<MediaTableRow> rows, MusicSortField field, bool ascending)
        => [.. rows.OrderBy(row => row, new MediaTableRowComparer(field, ascending))];
}
