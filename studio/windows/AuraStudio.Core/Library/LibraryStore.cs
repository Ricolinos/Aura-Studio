namespace AuraStudio.Core.Library;

/// <summary>
/// La biblioteca en disco: traduce entre los <see cref="LibraryItem"/> vivos y
/// el catálogo persistido, y guarda las portadas como archivos aparte.
///
/// <para>Es el <b>único</b> punto que sabe dónde vive cada cosa dentro de la
/// carpeta de biblioteca. Nadie más arma esas rutas a mano.</para>
/// </summary>
public sealed class LibraryStore(string root)
{
    public string Root { get; } = root;

    /// <summary>
    /// Si se puede trabajar con esta biblioteca ahora mismo (ST-171). Se lee
    /// <b>cada vez</b> y no se guarda: un disco externo se conecta y se
    /// desconecta mientras la app está abierta, así que la respuesta de hace un
    /// minuto no sirve.
    /// </summary>
    public LibraryAvailability Availability => LibraryAvailability.For(Root);

    public static string DefaultRoot => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "Aura Studio");

    public string CoversDirectory => Path.Combine(Root, PersistedLibrary.CoversDirName);

    /// <summary>
    /// ST-141: la versión de <c>coversNormalized</c> que trae el catálogo en
    /// disco (<c>null</c> = biblioteca anterior al recorte cuadrado). Se lee al
    /// cargar y se vuelve a escribir en cada guardado: perderla haría que la
    /// migración se repitiera en cada apertura.
    /// </summary>
    public int? CoversNormalized { get; set; }

    public string PreparedDirectory => Path.Combine(Root, PersistedLibrary.PreparedDirName);

    /// <summary>
    /// Las carpetas de la biblioteca que <b>ninguna rutina puede borrar</b>:
    /// ni una limpieza, ni un "liberar espacio", ni un mantenimiento.
    ///
    /// <para>Instrucción del dueño tras ST-087. Cuando se perdieron 2408
    /// entradas del catálogo, lo único que quedó de ellas fueron estos archivos
    /// —audios ya convertidos con sus etiquetas, y sus letras al lado—: son la
    /// reconstrucción latente si algún día decide intentarla.</para>
    ///
    /// <para>Cualquier código que vaya a borrar dentro de la biblioteca
    /// <b>consulta esta lista primero</b>, o usa <see cref="IsProtected"/>.</para>
    /// </summary>
    public IReadOnlyList<string> NeverCleaned => [PreparedDirectory, CoversDirectory];

    /// <summary>
    /// <c>true</c> si la ruta cae dentro de una carpeta protegida. Se compara
    /// por ruta completa, no por nombre: una carpeta que se llame igual en otro
    /// lado no queda protegida por accidente, y una subcarpeta de las
    /// protegidas sí lo está.
    /// </summary>
    public bool IsProtected(string path)
    {
        string full;
        try { full = Path.GetFullPath(path); }
        catch (ArgumentException) { return false; }

        return NeverCleaned.Any(protectedDirectory =>
        {
            string root = Path.GetFullPath(protectedDirectory);
            return full.Equals(root, StringComparison.OrdinalIgnoreCase)
                   || full.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
        });
    }

    /// <summary>
    /// <c>.portadas/&lt;ID&gt;.jpg</c> con el identificador <b>en mayúsculas y con
    /// guiones</b>, que es como lo escribe macOS. La biblioteca se comparte
    /// entre las dos apps: con otro formato, cada una escribiría su propia
    /// carátula para la misma canción y ninguna vería la de la otra.
    /// </summary>
    public string CoverPath(Guid id) => Path.Combine(CoversDirectory, CatalogPath.CoverFileName(id));

    /// <summary>
    /// Relativa si el archivo está dentro de la biblioteca; absoluta si no.
    /// Con "copiar medios a la biblioteca" apagado los archivos siguen viviendo
    /// donde el usuario los tiene, y ahí una ruta relativa no significa nada.
    /// </summary>
    public string ToStoredPath(string absolutePath) => CatalogPath.Store(Root, absolutePath);

    public string ToAbsolutePath(string storedPath) => CatalogPath.Resolve(Root, storedPath);

    /// <summary>
    /// Los items del catálogo, con sus rutas ya resueltas y su portada leída de
    /// <c>.portadas/</c>. Nunca lanza: un catálogo ilegible da biblioteca vacía.
    /// </summary>
    public IReadOnlyList<LibraryItem> LoadItems() => LoadItems(out _);

    /// <summary>
    /// Igual, pero devuelve por qué no se pudo leer el catálogo, si es que no se
    /// pudo. <b>Una biblioteca vacía y un catálogo ilegible no son lo mismo</b>,
    /// y en pantalla se veían idénticos.
    /// </summary>
    public IReadOnlyList<LibraryItem> LoadItems(out string? error)
    {
        LibraryCatalogStore.CatalogLoad load = LibraryCatalogStore.TryLoad(Root);
        error = load.Error;

        PersistedLibrary catalog = load.Catalog;
        CoversNormalized = catalog.CoversNormalized;
        var items = new List<LibraryItem>(catalog.Items.Count);

        foreach (PersistedLibraryItem persisted in catalog.Items)
        {
            items.Add(new LibraryItem
            {
                Id = persisted.Id,
                SourcePath = ToAbsolutePath(persisted.SourceRelativePath),
                Kind = LibraryPersistenceMapper.LiveKind(persisted.Kind),
                Status = LibraryPersistenceMapper.LiveStatus(persisted.Status),
                Metadata = LibraryPersistenceMapper.ToLive(
                    persisted.Metadata, ReadCover(persisted.Id)),
                PreparedPath = persisted.PreparedRelativePath is null
                    ? null : ToAbsolutePath(persisted.PreparedRelativePath),
                Category = LibraryPersistenceMapper.LiveCategory(persisted.Category),
                SeriesName = persisted.SeriesName,
                Season = persisted.Season,
                Episode = persisted.Episode,
                PhotoAlbum = persisted.PhotoAlbum,
                MetadataEditedByUser = persisted.MetadataEditedByUser ?? false,
                AddedAt = persisted.AddedAt
            });
        }

        return items;
    }

    /// <summary>Las listas del catálogo, como objetos vivos.</summary>
    public IReadOnlyList<Playlist> LoadPlaylists() =>
    [
        .. LibraryCatalogStore.TryLoad(Root).Catalog.Playlists.Select(persisted => new Playlist
        {
            Id = persisted.Id,
            Name = persisted.Name,
            TrackItemIds = [.. persisted.TrackItemIds],
            ImageRelativePath = persisted.ImageRelativePath
        })
    ];

    /// <summary>
    /// Guarda las listas <b>sin tocar los elementos</b>: se releen del catálogo
    /// y se vuelven a escribir. Guardar una parte de la biblioteca nunca puede
    /// borrar la otra (ST-087).
    /// </summary>
    public void SavePlaylists(IEnumerable<Playlist> playlists)
    {
        PersistedLibrary catalog = LibraryCatalogStore.TryLoad(Root).Catalog;

        catalog.Playlists =
        [
            .. playlists.Select(playlist => new PersistedPlaylist
            {
                Id = playlist.Id,
                Name = playlist.Name,
                TrackItemIds = [.. playlist.TrackItemIds],
                ImageRelativePath = playlist.ImageRelativePath is null
                    ? null
                    : CatalogPath.Canonical(playlist.ImageRelativePath)
            })
        ];

        LibraryCatalogStore.Save(Root, catalog);
    }

    /// <summary>
    /// Guarda los items. Las playlists que ya estaban en el catálogo se
    /// conservan tal cual: guardar la biblioteca no puede borrar lo que otra
    /// parte de la app escribió.
    /// </summary>
    public void SaveItems(IEnumerable<LibraryItem> items, IReadOnlyList<PersistedPlaylist>? playlists = null)
    {
        List<PersistedPlaylist> keptPlaylists =
            playlists?.ToList() ?? LibraryCatalogStore.Load(Root).Playlists;

        var catalog = new PersistedLibrary { Playlists = keptPlaylists, CoversNormalized = CoversNormalized };

        foreach (LibraryItem item in items)
        {
            // La portada solo se toca cuando el elemento la trae cargada. Un
            // elemento que se guarda sin haberla leído —porque su archivo no
            // estaba accesible, por ejemplo— NO puede borrar la carátula que ya
            // había en disco.
            if (item.Metadata is not null) WriteCover(item);

            catalog.Items.Add(new PersistedLibraryItem
            {
                Id = item.Id,
                SourceRelativePath = ToStoredPath(item.SourcePath),
                Kind = LibraryPersistenceMapper.PersistedKind(item.Kind),
                Status = LibraryPersistenceMapper.PersistedStatus(item.Status),
                Metadata = LibraryPersistenceMapper.ToPersisted(item.Metadata),
                PreparedRelativePath = item.PreparedPath is null ? null : ToStoredPath(item.PreparedPath),
                CoverRelativePath = item.Metadata?.CoverArtData is null ? null : CatalogPath.CoverRelative(item.Id),
                Category = item.Category,
                SeriesName = item.SeriesName,
                Season = item.Season,
                Episode = item.Episode,
                PhotoAlbum = item.PhotoAlbum,
                MetadataEditedByUser = item.MetadataEditedByUser ? true : null,
                AddedAt = item.AddedAt
            });
        }

        LibraryCatalogStore.Save(Root, catalog);
    }

    /// <summary>
    /// La carátula de un elemento, por su nombre canónico y —si no está— por el
    /// que esta app usaba antes de ST-087: el hexadecimal pelado, en minúsculas.
    ///
    /// <para>Sin esta segunda vuelta, una carátula guardada por una versión
    /// anterior de Aura Studio para Windows queda <b>invisible para las dos
    /// apps</b> con el archivo ahí al lado, y la siguiente pasada la daría por
    /// inexistente. Leerla acá la recupera, y el próximo guardado la deja con el
    /// nombre canónico sola.</para>
    /// </summary>
    private byte[]? ReadCover(Guid id)
    {
        try
        {
            string path = CoverPath(id);
            if (File.Exists(path)) return File.ReadAllBytes(path);

            string legacy = Path.Combine(CoversDirectory, id.ToString("N") + ".jpg");
            return File.Exists(legacy) ? File.ReadAllBytes(legacy) : null;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Una portada ilegible no puede impedir que el item cargue.
            return null;
        }
    }

    private void WriteCover(LibraryItem item)
    {
        byte[]? data = item.Metadata?.CoverArtData;
        string path = CoverPath(item.Id);
        try
        {
            if (data is null or { Length: 0 })
            {
                if (File.Exists(path)) File.Delete(path);
                return;
            }
            Directory.CreateDirectory(CoversDirectory);
            File.WriteAllBytes(path, data);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Sin portada en disco el item sigue siendo válido; se vuelve a
            // leer de la etiqueta la próxima vez.
        }
    }
}
