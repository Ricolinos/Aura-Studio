using System.Globalization;

namespace AuraStudio.Core.Library;

/// <summary>
/// Lo que muestra la barra de estado al pie de una sección de la biblioteca
/// (ST-063, encargo del dueño: "al estilo de la barra de estado del Finder").
/// Port de <c>LibraryStatusSummary.swift</c>.
/// </summary>
/// <param name="Total">"12 000 canciones · 40 artistas · 1 000 álbumes".</param>
/// <param name="Selection">"5 de 12 000 seleccionadas · 2 álbumes"; vacío sin selección.</param>
/// <param name="Trailing">El dato de la derecha: "8 h 12 min · 1.2 GB".</param>
public sealed record LibraryStatusSummary(string Total, string Selection = "", string Trailing = "")
{
    public static LibraryStatusSummary Empty { get; } = new("");

    public bool HasSelection => Selection.Length > 0;

    public bool HasTrailing => Trailing.Length > 0;
}

/// <summary>Qué sección se está resumiendo.</summary>
public enum LibraryStatusSection
{
    /// <summary>La tabla de Canciones.</summary>
    Songs,

    /// <summary>La cuadrícula de Álbumes.</summary>
    Albums,

    /// <summary>La lista de Artistas.</summary>
    Artists,

    /// <summary>La cuadrícula de Películas.</summary>
    Movies,

    /// <summary>La cuadrícula de Series.</summary>
    Series,

    /// <summary>Todas las fotos, sin agrupar.</summary>
    Photos,

    /// <summary>Los álbumes de fotos de UNA colección (Fotos, Imágenes o IA).</summary>
    PhotoAlbums
}

/// <summary>
/// Los cálculos de la barra de estado, puros y probados. Port de
/// <c>LibraryStats</c> de macOS, con la misma pluralización en español.
///
/// <para><b>El tamaño no toca el disco</b> (ST-201): sale de
/// <see cref="LibraryItem.FileSizeBytes"/>, que ya vive en el catálogo. En macOS
/// esto necesita una caché de <c>stat</c> por ruta justamente porque allá la
/// barra se recalcula en cada cambio de selección y una biblioteca grande no
/// puede pagar miles de consultas al disco cada vez; acá el dato ya está.</para>
/// </summary>
public static class LibraryStats
{
    /// <summary>
    /// Los números se escriben en español de México pase lo que pase, aunque
    /// Windows esté en otro idioma: es una regla del repo, no del sistema.
    /// </summary>
    private static readonly CultureInfo DisplayCulture = CultureInfo.GetCultureInfo("es-MX");

    public static string Formatted(int value) => value.ToString("N0", DisplayCulture);

    /// <summary>"1 canción" / "3 canciones".</summary>
    public static string Count(int value, string singular, string plural) =>
        $"{Formatted(value)} {(value == 1 ? singular : plural)}";

    /// <summary>Une con el separador de la barra, saltando lo vacío.</summary>
    public static string Join(params string?[] parts) =>
        string.Join(" · ", parts.Where(part => part is { Length: > 0 }));

    /// <summary>"3 h 12 min", "12 min", "45 s"; vacío si no hay duración conocida.</summary>
    public static string DurationText(double seconds)
    {
        if (seconds <= 0) return "";

        int total = (int)Math.Round(seconds);
        int hours = total / 3600;
        int minutes = total % 3600 / 60;

        if (hours >= 24)
        {
            int days = hours / 24;
            return $"{days} {(days == 1 ? "día" : "días")} {hours % 24} h";
        }

        if (hours > 0) return $"{hours} h {minutes} min";
        if (minutes > 0) return $"{minutes} min";
        return $"{total} s";
    }

    /// <summary>
    /// Tamaño legible, con las mismas unidades que el Explorador. Vacío si no se
    /// sabe cuánto pesa — <b>no "0 bytes"</b>: no saberlo y pesar cero no son lo
    /// mismo, y la barra no puede afirmar lo segundo cuando pasa lo primero.
    /// </summary>
    public static string SizeText(long bytes)
    {
        if (bytes <= 0) return "";

        string[] units = ["bytes", "KB", "MB", "GB", "TB"];
        double value = bytes;
        int unit = 0;

        while (value >= 1024 && unit < units.Length - 1)
        {
            value /= 1024;
            unit++;
        }

        return unit == 0
            ? $"{(long)value} {units[unit]}"
            : $"{value.ToString(value >= 100 ? "0" : "0.0", DisplayCulture)} {units[unit]}";
    }

    public static double TotalDuration(IEnumerable<LibraryItem> items) =>
        items.Sum(item => item.Metadata?.DurationSeconds ?? 0);

    /// <summary>
    /// Lo que suman los archivos, según el catálogo. Lo que todavía no se midió
    /// (ST-201) suma cero y se irá sumando cuando el relleno de fondo lo mida.
    /// </summary>
    public static long TotalSize(IEnumerable<LibraryItem> items) =>
        items.Sum(item => item.FileSizeBytes ?? 0);

    /// <summary>
    /// R2-4: los conteos de la barra usan la MISMA homologación que las vistas.
    /// Si no, la barra diría "3 artistas" debajo de una lista con dos filas.
    /// </summary>
    public static int ArtistCount(IEnumerable<LibraryItem> items, ArtistGroupingOptions? options = null) =>
        items.Select(item => LibraryGrouping.ArtistKeyOf(item, options))
             .Where(key => key.Length > 0)
             .Distinct(StringComparer.Ordinal)
             .Count();

    public static int AlbumCount(IEnumerable<LibraryItem> items, ArtistGroupingOptions? options = null) =>
        items.Where(item => (item.Metadata?.Album ?? "").Trim().Length > 0)
             .Select(item => LibraryGrouping.AlbumKeyOf(item, options))
             .Distinct(StringComparer.Ordinal)
             .Count();

    /// <summary>
    /// Cuántas temporadas hay entre esos episodios (addendum de ST-202). Se
    /// cuentan pares serie+temporada distintos: la temporada 1 de dos series son
    /// dos, no una.
    ///
    /// <para>"Sin temporada" cuenta como una: es lo que la vista muestra, y la
    /// barra no puede decir un número que no esté en pantalla.</para>
    /// </summary>
    public static int SeasonCount(IEnumerable<LibraryItem> episodes) =>
        episodes.Where(item => item.Kind == LibraryItemKind.Video
                               && MediaCategoryNames.IsSeriesCategory(item.Category))
                .Select(item => (LibraryGrouping.VideoCollectionKeyOf(item),
                                 item.Season ?? VideoCollectionGroup.NoSeasonNumber))
                .Distinct()
                .Count();

    /// <summary>
    /// Cuántos álbumes de fotos <b>con nombre</b> hay entre esas fotos. Las
    /// sueltas no forman un álbum: "Sin álbum" es el cajón de lo que no tiene
    /// uno, y contarlo diría un álbum de más.
    /// </summary>
    public static int PhotoAlbumCount(IEnumerable<LibraryItem> photos) =>
        photos.Where(item => item.Kind == LibraryItemKind.Photo
                             && (item.PhotoAlbum ?? "").Trim().Length > 0)
              .Select(item => LibraryGrouping.PhotoAlbumKeyOf(item, item.Category ?? ""))
              .Distinct(StringComparer.Ordinal)
              .Count();
}
