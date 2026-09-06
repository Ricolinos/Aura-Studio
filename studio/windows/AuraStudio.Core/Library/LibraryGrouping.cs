using System.Globalization;
using System.Text;

namespace AuraStudio.Core.Library;

/// <summary>
/// Un álbum tal como lo ve la vista "Álbumes" (ST-031): un grupo de canciones,
/// <b>no</b> un directorio. Nada de esto crea carpetas — la organización en
/// disco la sigue decidiendo la preferencia del usuario.
/// </summary>
/// <param name="Id">
/// Clave estable (álbum + artista del álbum, normalizados): permite seleccionar
/// el mismo grupo después de un cambio de metadata que no toque esos dos campos.
/// </param>
/// <param name="CoverItem">
/// La primera canción del grupo que tenga carátula, o <c>null</c> si ninguna la
/// tiene. <b>Es de dónde sale la tapa, no la tapa</b> (ST-208): desde que las
/// carátulas no viven en memoria, lo que viaja es la referencia y la vista pide
/// la miniatura por el hash.
/// </param>
/// <param name="IsUnknown"><c>true</c> para el grupo especial "Sin álbum".</param>
public sealed record AlbumGroup(
    string Id, string Title, string Artist, IReadOnlyList<LibraryItem> Items,
    LibraryItem? CoverItem, string? Year, string? Genre, bool IsUnknown)
{
    public bool HasCover => CoverItem is not null;

    public int TrackCount => Items.Count;

    public bool IsFavorite => Items.Any(item => item.Metadata?.IsFavorite == true);

    public double TotalDurationSeconds => Items.Sum(item => item.Metadata?.DurationSeconds ?? 0);

    public bool IsUnknownArtist => Artist == LibraryGrouping.UnknownArtistName;

    /// <summary>"3 canciones · 2019" para la tarjeta.</summary>
    public string SubtitleDetail
    {
        get
        {
            var parts = new List<string> { $"{TrackCount} {(TrackCount == 1 ? "canción" : "canciones")}" };
            if (!string.IsNullOrEmpty(Year)) parts.Add(Year);
            return string.Join(" · ", parts);
        }
    }
}

/// <summary>
/// Un artista para la vista "Artistas": sus álbumes —agrupados por artista del
/// álbum, no por artista de la pista— y el total de canciones.
/// </summary>
public sealed record ArtistGroup(string Id, string Name, IReadOnlyList<AlbumGroup> Albums, bool IsUnknown)
{
    public int TrackCount => Albums.Sum(album => album.TrackCount);

    public IReadOnlyList<LibraryItem> Items => [.. Albums.SelectMany(album => album.Items)];

    /// <summary>Cuando no hay foto de artista: la portada del primer álbum que tenga.</summary>
    public LibraryItem? FallbackCoverItem =>
        Albums.Select(album => album.CoverItem).FirstOrDefault(cover => cover is not null);

    /// <summary>"31 álbumes, 321 canciones", como la cabecera de Music.app.</summary>
    public string Summary
    {
        get
        {
            int albumCount = Albums.Count(album => !album.IsUnknown);
            string songs = TrackCount == 1 ? "1 canción" : $"{TrackCount} canciones";
            if (albumCount == 0) return songs;
            string albums = albumCount == 1 ? "1 álbum" : $"{albumCount} álbumes";
            return $"{albums}, {songs}";
        }
    }
}

/// <summary>
/// Un álbum de fotos <b>dentro</b> de una colección (Fotos/Imágenes/IA), como
/// los álbumes del iPod Classic original. Solo local: nunca llega al iPod
/// (D-192, <c>/Photos</c> sigue plano) ni crea carpetas por sí solo.
/// </summary>
public sealed record PhotoAlbumGroup(
    string Id, string Title, string Category, IReadOnlyList<LibraryItem> Items, bool IsUnknown)
{
    public int Count => Items.Count;

    /// <summary>
    /// Hasta cuatro rutas para el mosaico 2×2 de la tarjeta. Se devuelven
    /// <b>rutas</b>, no bytes: leer cuatro imágenes en una propiedad calculada
    /// haría que cada redibujado de la cuadrícula golpeara el disco.
    ///
    /// <para>Se prefiere el archivo preparado —una foto nunca completa su
    /// metadata, la imagen misma es el contenido— y si todavía no se procesó, el
    /// original.</para>
    /// </summary>
    public IReadOnlyList<string> PreviewPaths =>
        [.. Items.Take(4).Select(item => item.PreparedPath ?? item.SourcePath)];
}

/// <summary>
/// Una temporada dentro de una serie: sus episodios ordenados por número, los
/// que no lo tienen al final.
/// </summary>
public sealed record SeasonGroup(int Number, IReadOnlyList<LibraryItem> Items)
{
    public int Id => Number;
}

/// <summary>
/// Una película o serie para las vistas "Películas"/"Series": grupo en memoria,
/// igual que <see cref="AlbumGroup"/> — nada de esto cambia la organización en
/// disco.
/// </summary>
/// <param name="Seasons">
/// Vacío para una película. Para una serie, una entrada por temporada presente
/// (incluida "Sin temporada", siempre al final).
/// </param>
public sealed record VideoCollectionGroup(
    string Id, string Title, string? Year, LibraryItem? PosterItem, bool IsSeries,
    IReadOnlyList<LibraryItem> Items, IReadOnlyList<SeasonGroup> Seasons)
{
    public const int NoSeasonNumber = -1;

    public int EpisodeCount => Items.Count;
}

/// <summary>
/// Ámbito de la tabla cuando se embebe dentro de Álbumes, Artistas, Películas,
/// Series o un álbum de fotos (ST-031).
/// </summary>
public abstract record MusicScope
{
    public sealed record All : MusicScope;
    public sealed record Album(string Key) : MusicScope;
    public sealed record Artist(string Key) : MusicScope;
    public sealed record VideoCollection(string Key) : MusicScope;

    /// <summary>Solo los episodios de una temporada dentro de esa serie.</summary>
    public sealed record Season(string CollectionKey, int Number) : MusicScope;

    /// <summary>
    /// Todas las fotos de un álbum dentro de una colección. La clave incluye la
    /// categoría: dos colecciones distintas pueden tener un álbum con el mismo
    /// nombre.
    /// </summary>
    public sealed record PhotoAlbum(string Key) : MusicScope;
}

/// <summary>
/// Agrupa la biblioteca en lo que muestran las cuadrículas. Port de
/// <c>LibraryGrouping.swift</c>. Todo es puro: entra una lista de elementos,
/// salen grupos en memoria.
/// </summary>
public static class LibraryGrouping
{
    public const string UnknownAlbumTitle = "Sin álbum";
    public const string UnknownArtistName = "Artista desconocido";
    public const string UnknownPhotoAlbumTitle = "Sin álbum";
    /// <summary>
    /// Separador de las claves compuestas. Se escribe con su código y no como el
    /// carácter suelto: un byte de control invisible dentro del fuente es lo que
    /// después nadie sabe explicar. Es el mismo que usa macOS, así que las
    /// claves de agrupación coinciden entre las dos apps.
    /// </summary>
    private const char KeySeparator = (char)0x1F;

    private static readonly StringComparer NaturalOrder = MediaTableRow.NaturalOrder;

    /// <summary>
    /// Normalización para agrupar: sin espacios sobrantes, sin distinguir
    /// mayúsculas ni acentos — "Álbum" y "album " son el mismo álbum.
    /// </summary>
    public static string Normalize(string? value)
    {
        string trimmed = (value ?? "").Trim();
        if (trimmed.Length == 0) return "";

        string decomposed = trimmed.Normalize(NormalizationForm.FormD);
        var builder = new StringBuilder(decomposed.Length);

        foreach (char c in decomposed)
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark)
                builder.Append(c);

        return builder.ToString().ToLowerInvariant();
    }

    /// <summary>
    /// El artista con el que se agrupa un álbum: <b>la misma precedencia que la
    /// ruta de sincronización</b> (artista del álbum, y si no, artista), para
    /// que lo que se ve acá coincida con las carpetas del iPod.
    /// </summary>
    public static string? AlbumArtistOf(LibraryItem item)
    {
        string candidate = (item.Metadata?.AlbumArtist ?? item.Metadata?.Artist ?? "").Trim();
        return candidate.Length == 0 ? null : candidate;
    }

    /// <summary>
    /// El artista con el que se AGRUPA: el principal del crédito (R2-4).
    ///
    /// <para>Es distinto de <see cref="AlbumArtistOf"/> a propósito. Ese
    /// devuelve el crédito crudo y es el que arma las carpetas en disco y en el
    /// iPod; este agrupa. R2-4 pidió agrupación, no reorganización: mover
    /// carpetas ya sincronizadas es una operación destructiva sobre archivos
    /// del usuario. <b>Consecuencia conocida y aceptada</b>: un álbum que se
    /// muestra bajo "Gorillaz" puede vivir en el iPod en una carpeta
    /// "Gorillaz feat. De La Soul".</para>
    /// </summary>
    public static string? GroupingArtistOf(LibraryItem item, ArtistGroupingOptions? options = null)
    {
        string? raw = AlbumArtistOf(item);
        if (raw is null) return null;

        string principal = ArtistNameNormalizer.PrincipalArtist(raw, options);
        return principal.Length == 0 ? null : principal;
    }

    public static string AlbumKeyOf(LibraryItem item, ArtistGroupingOptions? options = null) =>
        $"{Normalize(item.Metadata?.Album)}{KeySeparator}{Normalize(GroupingArtistOf(item, options))}";

    public static string ArtistKeyOf(LibraryItem item, ArtistGroupingOptions? options = null) =>
        Normalize(GroupingArtistOf(item, options));

    /// <summary>
    /// Agrupa conservando el orden en que aparece cada clave por primera vez —
    /// eso es lo que hace que la grafía mostrada sea la de la primera pista que
    /// entró al grupo, y no la de una que llegue después.
    /// </summary>
    private static List<(string Key, List<T> Items)> Bucket<T>(
        IEnumerable<T> source, Func<T, string> keyOf)
    {
        var order = new List<string>();
        var buckets = new Dictionary<string, List<T>>(StringComparer.Ordinal);

        foreach (T item in source)
        {
            string key = keyOf(item);
            if (!buckets.TryGetValue(key, out List<T>? bucket))
            {
                buckets[key] = bucket = [];
                order.Add(key);
            }
            bucket.Add(item);
        }

        return [.. order.Select(key => (key, buckets[key]))];
    }

    /// <summary>
    /// Álbumes: los conocidos por título (orden natural, ignorando el artículo
    /// inicial) y después por año; dentro, por disco, pista y título. "Sin
    /// álbum" —uno por artista— siempre al final.
    /// </summary>
    public static IReadOnlyList<AlbumGroup> Albums(
        IReadOnlyList<LibraryItem> items, ArtistGroupingOptions? options = null)
    {
        var groups = new List<AlbumGroup>();

        foreach ((string key, List<LibraryItem> bucket) in
                 Bucket(items.Where(item => item.Kind == LibraryItemKind.Music),
                        item => AlbumKeyOf(item, options)))
        {
            LibraryItem first = bucket[0];
            IReadOnlyList<LibraryItem> tracks = SortedTracks(bucket);
            string albumTitle = (first.Metadata?.Album ?? "").Trim();
            bool isUnknown = albumTitle.Length == 0;

            groups.Add(new AlbumGroup(
                Id: key,
                Title: isUnknown ? UnknownAlbumTitle : albumTitle,
                Artist: GroupingArtistOf(first, options) ?? UnknownArtistName,
                Items: tracks,
                CoverItem: tracks.FirstOrDefault(track => track.HasCover),
                Year: tracks.Select(t => t.Metadata?.Year).FirstOrDefault(y => !string.IsNullOrEmpty(y)),
                Genre: tracks.Select(t => t.Metadata?.Genre).FirstOrDefault(g => !string.IsNullOrEmpty(g)),
                IsUnknown: isUnknown));
        }

        return [.. groups
            .OrderBy(album => album.IsUnknown)                      // lo conocido primero
            .ThenBy(album => album.IsUnknown ? SortName(album.Artist) : SortName(album.Title), NaturalOrder)
            .ThenBy(album => album.Year ?? "", StringComparer.Ordinal)];
    }

    /// <summary>
    /// Artistas por nombre, con "Artista desconocido" al final. Cada uno con sus
    /// álbumes en el mismo orden que los devuelve <see cref="Albums"/>.
    /// </summary>
    public static IReadOnlyList<ArtistGroup> Artists(
        IReadOnlyList<LibraryItem> items, ArtistGroupingOptions? options = null)
    {
        IReadOnlyList<AlbumGroup> albums = Albums(items, options);
        var groups = new List<ArtistGroup>();

        foreach ((string key, List<AlbumGroup> bucket) in
                 Bucket(albums, album => Normalize(album.IsUnknownArtist ? null : album.Artist)))
        {
            bool isUnknown = key.Length == 0;
            groups.Add(new ArtistGroup(
                Id: key,
                Name: isUnknown ? UnknownArtistName : bucket[0].Artist,
                Albums: bucket,
                IsUnknown: isUnknown));
        }

        return [.. groups
            .OrderBy(artist => artist.IsUnknown)
            .ThenBy(artist => SortName(artist.Name), NaturalOrder)];
    }

    /// <summary>
    /// Las pistas de un álbum en el orden en que se escuchan: disco, pista y —a
    /// falta de número— título.
    ///
    /// <para><b>Sin número de disco cuenta como disco 1</b>, igual que Music.app:
    /// una pista sin ese dato no puede quedar antes de todo el disco 1. Sin
    /// número de <i>pista</i>, en cambio, va al final: ahí no hay un valor
    /// razonable que suponer.</para>
    /// </summary>
    public static IReadOnlyList<LibraryItem> SortedTracks(IEnumerable<LibraryItem> items) =>
        [.. items
            .OrderBy(item => item.Metadata?.DiscNumber ?? 1)
            .ThenBy(item => item.Metadata?.TrackNumber ?? int.MaxValue)
            .ThenBy(item => item.DisplayTitle, NaturalOrder)];

    /// <summary>
    /// El nombre por el que se ordena: sin el artículo inicial y sin la
    /// puntuación de adelante, como hace Music.app — "Los Fabulosos Cadillacs"
    /// va en la F, y "…Little Broken Hearts" en la L.
    /// </summary>
    public static string SortName(string name)
    {
        string trimmed = new([.. name.SkipWhile(c => !char.IsLetterOrDigit(c))]);
        if (trimmed.Length == 0) trimmed = name;

        string lower = trimmed.ToLowerInvariant();

        foreach (string article in (string[])["the ", "los ", "las ", "el ", "la ", "una ", "un ", "an ", "a "])
        {
            if (!lower.StartsWith(article, StringComparison.Ordinal)) continue;

            string rest = trimmed[article.Length..].Trim();
            return rest.Length == 0 ? trimmed : rest;
        }

        return trimmed;
    }

    // MARK: - Video

    /// <summary>
    /// Clave de agrupación de un video: por nombre de serie si es un episodio
    /// (varios archivos, un solo grupo); por título si es película (agrupa una
    /// reimportación con el original) o, sin título, por su propio id — así
    /// nunca se agrupa con nada más por accidente.
    /// </summary>
    public static string VideoCollectionKeyOf(LibraryItem item)
    {
        if (MediaCategoryNames.IsSeriesCategory(item.Category)
            && (item.SeriesName ?? "").Trim() is { Length: > 0 } seriesName)
            return $"series{KeySeparator}{Normalize(seriesName)}";

        if ((item.Metadata?.Title ?? "").Trim() is { Length: > 0 } title)
            return $"movie{KeySeparator}{Normalize(title)}";

        return $"movie{KeySeparator}{item.Id:D}";
    }

    /// <summary>
    /// Películas y series agrupadas. El artículo inicial se ignora al ordenar,
    /// mismo criterio que álbumes y artistas.
    /// </summary>
    public static IReadOnlyList<VideoCollectionGroup> VideoCollections(IReadOnlyList<LibraryItem> items)
    {
        IEnumerable<LibraryItem> videos = items.Where(item =>
            item.Kind == LibraryItemKind.Video
            && (MediaCategoryNames.IsMoviesCategory(item.Category)
                || MediaCategoryNames.IsSeriesCategory(item.Category)));

        var groups = new List<VideoCollectionGroup>();

        foreach ((string key, List<LibraryItem> bucket) in Bucket(videos, VideoCollectionKeyOf))
        {
            LibraryItem first = bucket[0];
            bool isSeries = MediaCategoryNames.IsSeriesCategory(first.Category);

            string title = isSeries && (first.SeriesName ?? "").Trim() is { Length: > 0 } seriesName
                ? seriesName
                : (first.Metadata?.Title ?? "").Trim() is { Length: > 0 } metaTitle
                    ? metaTitle
                    : first.DisplayTitle;

            groups.Add(new VideoCollectionGroup(
                Id: key,
                Title: title,
                Year: bucket.Select(v => v.Metadata?.Year).FirstOrDefault(y => !string.IsNullOrEmpty(y)),
                PosterItem: bucket.FirstOrDefault(video => video.HasCover),
                IsSeries: isSeries,
                Items: bucket,
                Seasons: isSeries ? Seasons(bucket) : []));
        }

        return [.. groups.OrderBy(group => SortName(group.Title), NaturalOrder)];
    }

    private static IReadOnlyList<SeasonGroup> Seasons(IEnumerable<LibraryItem> episodes) =>
        [.. Bucket(episodes, episode =>
                (episode.Season ?? VideoCollectionGroup.NoSeasonNumber).ToString(CultureInfo.InvariantCulture))
            .Select(bucket => (
                Number: bucket.Items[0].Season ?? VideoCollectionGroup.NoSeasonNumber,
                bucket.Items))
            // "Sin temporada" siempre al final, no antes de la temporada 1.
            .OrderBy(season => season.Number == VideoCollectionGroup.NoSeasonNumber)
            .ThenBy(season => season.Number)
            .Select(season => new SeasonGroup(season.Number,
                [.. season.Items
                    .OrderBy(episode => episode.Episode ?? int.MaxValue)
                    .ThenBy(episode => episode.DisplayTitle, NaturalOrder)]))];

    // MARK: - Fotos

    /// <summary>
    /// Clave de un álbum de fotos: categoría más nombre de álbum. La categoría
    /// entra a propósito — "Fotos" e "Imágenes" pueden tener cada una un álbum
    /// llamado igual sin que se mezclen.
    /// </summary>
    public static string PhotoAlbumKeyOf(LibraryItem item, string category) =>
        $"{Normalize(category)}{KeySeparator}{Normalize(item.PhotoAlbum)}";

    /// <summary>
    /// Los álbumes de fotos dentro de <b>una</b> colección. "Sin álbum" —las
    /// fotos de esa colección sin álbum asignado— siempre al final.
    /// </summary>
    public static IReadOnlyList<PhotoAlbumGroup> PhotoAlbums(
        IReadOnlyList<LibraryItem> items, string category)
    {
        IEnumerable<LibraryItem> photos = items.Where(item =>
            item.Kind == LibraryItemKind.Photo && item.Category == category);

        var groups = new List<PhotoAlbumGroup>();

        foreach ((string key, List<LibraryItem> bucket) in
                 Bucket(photos, item => PhotoAlbumKeyOf(item, category)))
        {
            string albumName = (bucket[0].PhotoAlbum ?? "").Trim();
            bool isUnknown = albumName.Length == 0;

            groups.Add(new PhotoAlbumGroup(
                Id: key,
                Title: isUnknown ? UnknownPhotoAlbumTitle : albumName,
                Category: category,
                Items: bucket,
                IsUnknown: isUnknown));
        }

        return [.. groups
            .OrderBy(album => album.IsUnknown)
            .ThenBy(album => SortName(album.Title), NaturalOrder)];
    }
}
