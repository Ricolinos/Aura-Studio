namespace AuraStudio.Core.Library;

/// <summary>
/// Por qué clave se está preguntando. Existe para que <see cref="LibraryCatalogIndex"/>
/// se pueda usar desde Core sin conocer <c>MediaGridKind</c>, que es de la app:
/// la cuadrícula traduce su tipo a uno de estos y el índice responde igual para
/// las dos plataformas.
/// </summary>
public enum LibraryGroupKind
{
    /// <summary>Clave de <see cref="LibraryGrouping.AlbumKeyOf"/>.</summary>
    Album,

    /// <summary>Clave de <see cref="LibraryGrouping.ArtistKeyOf"/>.</summary>
    Artist,

    /// <summary>Clave de <see cref="LibraryGrouping.VideoCollectionKeyOf"/>.</summary>
    VideoCollection,

    /// <summary>Clave de <see cref="LibraryGrouping.PhotoAlbumKeyOf"/>.</summary>
    PhotoAlbum,

    /// <summary>El identificador del elemento mismo, en formato <c>D</c>.</summary>
    Item
}

/// <summary>
/// Las claves de agrupación de la biblioteca, calculadas <b>una sola vez por
/// versión del catálogo</b> (ST-201).
///
/// <para>Antes, cada pregunta del tipo "qué canciones hay detrás de estas
/// tarjetas" recorría los 12 000 elementos normalizando dos cadenas por
/// elemento — y esa pregunta se hace en cada clic, para publicar la selección, y
/// una vez <b>por álbum</b> al armar el menú contextual. Con 1 000 álbumes
/// seleccionados son 12 millones de normalizaciones para responder algo que ya
/// estaba calculado.</para>
///
/// <para>Es inmutable y puro: entra una lista de elementos, sale un índice. Si
/// el catálogo cambia se construye otro — nunca se parchea este, porque un
/// índice a medio actualizar es peor que no tenerlo. Quien lo cachea es
/// responsable de tirarlo cuando cambian los elementos <b>o el criterio de
/// agrupación de artistas</b> (R2-4): las claves de álbum y de artista dependen
/// de ese ajuste.</para>
///
/// <para>Lo comparten la cuadrícula, el resumen de estado y el menú contextual:
/// dos índices distintos darían dos respuestas distintas a la misma
/// pregunta.</para>
/// </summary>
public sealed class LibraryCatalogIndex
{
    private static readonly IReadOnlyList<LibraryItem> NoItems = [];

    private readonly Dictionary<string, List<LibraryItem>> _albums;
    private readonly Dictionary<string, List<LibraryItem>> _artists;
    private readonly Dictionary<string, List<LibraryItem>> _videoCollections;
    private readonly Dictionary<string, List<LibraryItem>> _photoAlbums;
    private readonly Dictionary<Guid, LibraryItem> _byId;

    /// <summary>
    /// La dirección contraria (ST-206, hermana de ST-182 en la Mac): de una
    /// canción a la clave de su álbum. No es un lujo — responder "de qué
    /// álbumes es esta selección" con 12 000 canciones marcadas es la
    /// diferencia entre 24 000 normalizaciones de cadena y 12 000 búsquedas en
    /// una tabla hash.
    /// </summary>
    private readonly Dictionary<Guid, string> _albumKeyById;

    private LibraryCatalogIndex(
        IReadOnlyList<LibraryItem> items,
        ArtistGroupingOptions? grouping,
        Dictionary<string, List<LibraryItem>> albums,
        Dictionary<string, List<LibraryItem>> artists,
        Dictionary<string, List<LibraryItem>> videoCollections,
        Dictionary<string, List<LibraryItem>> photoAlbums,
        Dictionary<Guid, LibraryItem> byId,
        Dictionary<Guid, string> albumKeyById)
    {
        Items = items;
        Grouping = grouping;
        _albums = albums;
        _artists = artists;
        _videoCollections = videoCollections;
        _photoAlbums = photoAlbums;
        _byId = byId;
        _albumKeyById = albumKeyById;
    }

    /// <summary>Los elementos que se indexaron, en el orden en que venían.</summary>
    public IReadOnlyList<LibraryItem> Items { get; }

    /// <summary>Con qué criterio de artista se armaron las claves (R2-4).</summary>
    public ArtistGroupingOptions? Grouping { get; }

    public static LibraryCatalogIndex Empty { get; } = Build([], null);

    /// <summary>
    /// Una sola pasada por el catálogo. Las claves salen de
    /// <see cref="LibraryGrouping"/>, nunca de una copia de esa lógica: dos
    /// formas de armar la misma clave son dos agrupaciones distintas esperando
    /// a divergir.
    /// </summary>
    public static LibraryCatalogIndex Build(
        IReadOnlyList<LibraryItem> items, ArtistGroupingOptions? grouping = null)
    {
        var albums = new Dictionary<string, List<LibraryItem>>(StringComparer.Ordinal);
        var artists = new Dictionary<string, List<LibraryItem>>(StringComparer.Ordinal);
        var videoCollections = new Dictionary<string, List<LibraryItem>>(StringComparer.Ordinal);
        var photoAlbums = new Dictionary<string, List<LibraryItem>>(StringComparer.Ordinal);
        var byId = new Dictionary<Guid, LibraryItem>(items.Count);
        var albumKeyById = new Dictionary<Guid, string>(items.Count);

        foreach (LibraryItem item in items)
        {
            // Un identificador repetido no puede tirar la carga entera: se queda
            // el primero, igual que hace la agrupación.
            byId.TryAdd(item.Id, item);

            switch (item.Kind)
            {
                case LibraryItemKind.Music:
                    string albumKey = LibraryGrouping.AlbumKeyOf(item, grouping);

                    Add(albums, albumKey, item);
                    Add(artists, LibraryGrouping.ArtistKeyOf(item, grouping), item);

                    // La misma clave que se acaba de calcular, guardada al
                    // revés: calcularla dos veces sería el gasto que este
                    // índice existe para no pagar.
                    albumKeyById.TryAdd(item.Id, albumKey);
                    break;

                // TODO el video, no solo películas y series: es lo que responde
                // hoy la cuadrícula, y recortar ese alcance acá sería cambiar en
                // silencio a qué llega el menú contextual de un clip suelto.
                case LibraryItemKind.Video:
                    Add(videoCollections, LibraryGrouping.VideoCollectionKeyOf(item), item);
                    break;

                case LibraryItemKind.Photo:
                    Add(photoAlbums, LibraryGrouping.PhotoAlbumKeyOf(item, item.Category ?? ""), item);
                    break;
            }
        }

        return new LibraryCatalogIndex(
            items, grouping, albums, artists, videoCollections, photoAlbums, byId, albumKeyById);
    }

    private static void Add(Dictionary<string, List<LibraryItem>> buckets, string key, LibraryItem item)
    {
        if (!buckets.TryGetValue(key, out List<LibraryItem>? bucket)) buckets[key] = bucket = [];
        bucket.Add(item);
    }

    /// <summary>Cuántos grupos hay de ese tipo. O(1).</summary>
    public int GroupCount(LibraryGroupKind kind) => kind switch
    {
        LibraryGroupKind.Album => _albums.Count,
        LibraryGroupKind.Artist => _artists.Count,
        LibraryGroupKind.VideoCollection => _videoCollections.Count,
        LibraryGroupKind.PhotoAlbum => _photoAlbums.Count,
        _ => _byId.Count
    };

    public IReadOnlyList<LibraryItem> ByAlbumKey(string key) => Bucket(_albums, key);

    public IReadOnlyList<LibraryItem> ByArtistKey(string key) => Bucket(_artists, key);

    public IReadOnlyList<LibraryItem> ByVideoCollectionKey(string key) => Bucket(_videoCollections, key);

    public IReadOnlyList<LibraryItem> ByPhotoAlbumKey(string key) => Bucket(_photoAlbums, key);

    public LibraryItem? ById(Guid id) => _byId.GetValueOrDefault(id);

    /// <summary>
    /// Por identificador en texto, que es como viaja en la tarjeta de una
    /// cuadrícula plana. Lo que no es un identificador válido no está: no se
    /// intenta interpretarlo de otra forma.
    /// </summary>
    public LibraryItem? ById(string id) => Guid.TryParse(id, out Guid parsed) ? ById(parsed) : null;

    /// <summary>
    /// La clave del álbum de <b>una</b> canción, en O(1) (ST-206). <c>null</c>
    /// para lo que no es música: un video no tiene álbum, y devolver "" lo
    /// metería en el mismo cajón que las canciones sin disco.
    /// </summary>
    public string? AlbumKeyOf(Guid id) => _albumKeyById.GetValueOrDefault(id);

    /// <summary>
    /// De qué álbumes es esta selección, sin repetir y <b>en el orden en que
    /// aparecen</b> — que es el orden en que el usuario los ve.
    ///
    /// <para>Es la pregunta del menú contextual de Canciones con toda la
    /// biblioteca marcada. Antes había que normalizar dos cadenas por canción
    /// para responderla; acá son 12 000 búsquedas en una tabla hash.</para>
    /// </summary>
    public IReadOnlyList<string> AlbumKeysOf(IEnumerable<Guid> ids)
    {
        List<string> keys = [];
        HashSet<string> seen = new(StringComparer.Ordinal);

        foreach (Guid id in ids)
        {
            if (AlbumKeyOf(id) is { } key && seen.Add(key)) keys.Add(key);
        }

        return keys;
    }

    /// <summary>
    /// Igual, pero desde los elementos. Se resuelve por identificador y no
    /// recalculando la clave: dos formas de armarla son dos agrupaciones
    /// esperando a divergir.
    /// </summary>
    public IReadOnlyList<string> AlbumKeysOf(IEnumerable<LibraryItem> items) =>
        AlbumKeysOf(items.Select(item => item.Id));

    /// <summary>Lo que hay detrás de <b>una</b> clave, en O(1).</summary>
    public IReadOnlyList<LibraryItem> ItemsForKey(LibraryGroupKind kind, string key) => kind switch
    {
        LibraryGroupKind.Album => ByAlbumKey(key),
        LibraryGroupKind.Artist => ByArtistKey(key),
        LibraryGroupKind.VideoCollection => ByVideoCollectionKey(key),
        LibraryGroupKind.PhotoAlbum => ByPhotoAlbumKey(key),
        _ => ById(key) is { } item ? [item] : NoItems
    };

    /// <summary>
    /// Lo que hay detrás de varias claves, en el orden en que llegan las claves
    /// y sin repetir un elemento aunque dos claves lo alcancen.
    ///
    /// <para>Es la operación del menú contextual (regla 0.1: el clic derecho
    /// sobre algo marcado alcanza a toda la selección) y la de publicar la
    /// selección. Cuesta lo que suman los grupos alcanzados, no lo que mide el
    /// catálogo.</para>
    /// </summary>
    public IReadOnlyList<LibraryItem> ItemsForKeys(LibraryGroupKind kind, IEnumerable<string> keys)
    {
        List<LibraryItem> reached = [];
        HashSet<Guid> seen = [];

        foreach (string key in keys)
        {
            foreach (LibraryItem item in ItemsForKey(kind, key))
                if (seen.Add(item.Id)) reached.Add(item);
        }

        return reached;
    }

    /// <summary>
    /// Los identificadores de lo alcanzado, que es lo que viaja como alcance de
    /// sincronización.
    /// </summary>
    public IReadOnlyList<Guid> ItemIdsForKeys(LibraryGroupKind kind, IEnumerable<string> keys) =>
        [.. ItemsForKeys(kind, keys).Select(item => item.Id)];

    private static IReadOnlyList<LibraryItem> Bucket(
        Dictionary<string, List<LibraryItem>> buckets, string key) =>
        buckets.TryGetValue(key, out List<LibraryItem>? bucket) ? bucket : NoItems;
}
