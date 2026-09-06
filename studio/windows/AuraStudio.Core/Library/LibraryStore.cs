namespace AuraStudio.Core.Library;

/// <summary>
/// Lo que salió de leer el catálogo (ST-203).
/// </summary>
/// <param name="Items">Lo que se pudo leer; vacío si no se pudo.</param>
/// <param name="Error">
/// Por qué no se pudo, o <c>null</c> si todo salió bien. <b>Una biblioteca
/// vacía y un catálogo ilegible no son lo mismo</b>, y en pantalla se veían
/// idénticos hasta que esto existió.
/// </param>
public readonly record struct LibraryLoad(IReadOnlyList<LibraryItem> Items, string? Error);

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
        LibraryLoad load = Load();
        error = load.Error;
        return load.Items;
    }

    /// <summary>
    /// La carga con <b>avance y cancelación</b> (ST-203): se llama desde una
    /// tarea de fondo, así que hace falta poder decir por dónde va y poder
    /// pararla si el usuario cambia de carpeta de biblioteca a mitad.
    /// </summary>
    /// <param name="onProgress">Cuántos van y cuántos son.</param>
    public LibraryLoad Load(Action<int, int>? onProgress = null, CancellationToken ct = default)
    {
        LibraryCatalogStore.CatalogLoad load = LibraryCatalogStore.TryLoad(Root);

        PersistedLibrary catalog = load.Catalog;
        CoversNormalized = catalog.CoversNormalized;
        var items = new List<LibraryItem>(catalog.Items.Count);

        foreach (PersistedLibraryItem persisted in catalog.Items)
        {
            ct.ThrowIfCancellationRequested();

            items.Add(new LibraryItem
            {
                Id = persisted.Id,
                SourcePath = ToAbsolutePath(persisted.SourceRelativePath),
                Kind = LibraryPersistenceMapper.LiveKind(persisted.Kind),
                Status = LibraryPersistenceMapper.LiveStatus(persisted.Status),

                // ST-208: **sin la carátula**. Antes se leían acá los 87 MB de
                // `.portadas\`, uno por uno, y quedaban en memoria para siempre.
                // Ahora viaja la referencia; los bytes los pide quien de verdad
                // los necesita, cuando los necesita.
                Metadata = LibraryPersistenceMapper.ToLive(persisted.Metadata, null),
                CoverRelativePath = persisted.CoverRelativePath,
                CoverHash = persisted.CoverHash,

                PreparedPath = persisted.PreparedRelativePath is null
                    ? null : ToAbsolutePath(persisted.PreparedRelativePath),
                Category = LibraryPersistenceMapper.LiveCategory(persisted.Category),
                SeriesName = persisted.SeriesName,
                Season = persisted.Season,
                Episode = persisted.Episode,
                PhotoAlbum = persisted.PhotoAlbum,
                MetadataEditedByUser = persisted.MetadataEditedByUser ?? false,
                AddedAt = persisted.AddedAt,
                // Después de SourcePath a propósito: asignar la ruta olvida el
                // tamaño (ST-201), así que ponerlo antes lo borraría.
                FileSizeBytes = persisted.FileSizeBytes
            });

            if (items.Count % ProgressEvery == 0) onProgress?.Invoke(items.Count, catalog.Items.Count);
        }

        ResolveMissingCoverPaths(items);

        onProgress?.Invoke(items.Count, catalog.Items.Count);
        return new LibraryLoad(items, load.Error);
    }

    /// <summary>
    /// Recupera las carátulas que están en disco pero que el catálogo no anota
    /// (ST-087, sostenido en ST-208).
    ///
    /// <para>Pasa con lo que escribió una versión de esta app anterior a ST-087,
    /// que usaba el hexadecimal pelado en minúsculas. Sin esto, esa imagen queda
    /// ahí al lado e <b>invisible para las dos apps</b>, y desde ST-208 —que ya
    /// no abre archivo por archivo— quedaría invisible para siempre.</para>
    ///
    /// <para>Se resuelve con <b>un solo listado del directorio</b>, no con dos
    /// consultas por elemento: son 12 000 elementos y mil carátulas, y por red la
    /// diferencia entre un viaje y veinticuatro mil es la diferencia entre
    /// abrir la biblioteca y no abrirla.</para>
    ///
    /// <para>Y la que aparece con el nombre viejo se <b>renombra</b> al canónico
    /// ahí mismo: así queda bien para las dos apps sin esperar a que alguien
    /// guarde. Si el renombrado falla, se anota igual con su nombre viejo — verla
    /// importa más que verla ordenada.</para>
    /// </summary>
    private void ResolveMissingCoverPaths(List<LibraryItem> items)
    {
        if (!items.Any(item => item.CoverRelativePath is null)) return;

        HashSet<string> onDisk;

        try
        {
            if (!Directory.Exists(CoversDirectory)) return;

            onDisk = [.. Directory.EnumerateFiles(CoversDirectory)
                .Select(Path.GetFileName)
                .OfType<string>()];
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return;
        }

        if (onDisk.Count == 0) return;

        foreach (LibraryItem item in items)
        {
            if (item.CoverRelativePath is not null) continue;

            string canonical = CatalogPath.CoverFileName(item.Id);

            if (onDisk.Contains(canonical))
            {
                item.CoverRelativePath = CatalogPath.CoverRelative(item.Id);
                continue;
            }

            string legacy = item.Id.ToString("N") + ".jpg";
            if (!onDisk.Contains(legacy)) continue;

            item.CoverRelativePath = TryRenameToCanonical(legacy, canonical)
                ? CatalogPath.CoverRelative(item.Id)
                : PersistedLibrary.CoversDirName + "/" + legacy;
        }
    }

    private bool TryRenameToCanonical(string legacy, string canonical)
    {
        try
        {
            File.Move(Path.Combine(CoversDirectory, legacy), Path.Combine(CoversDirectory, canonical));
            return true;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    /// <summary>
    /// Cada cuántos elementos se avisa del avance. Avisar por elemento sería un
    /// salto al hilo de interfaz por canción.
    /// </summary>
    private const int ProgressEvery = 250;

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
            // ST-208: **los bytes que trae el elemento son una carátula PENDIENTE
            // DE ESCRIBIR**, no "la carátula que tiene".
            //
            // Antes eran lo mismo, porque cargar la biblioteca los traía. Desde
            // que no los trae, confundirlos sería catastrófico: cargar y guardar
            // sin tocar nada dejaría a los 12 000 elementos sin ruta en el
            // catálogo y borraría las mil carátulas del disco — y como el
            // catálogo es compartido, la app de macOS abriría la biblioteca sin
            // tapas. Quién tiene carátula lo dice `CoverRelativePath`, y quitarla
            // es una acción explícita (`RemoveCover`).
            if (item.Metadata?.CoverArtData is { Length: > 0 } pending) WriteCover(item, pending);

            catalog.Items.Add(new PersistedLibraryItem
            {
                Id = item.Id,
                SourceRelativePath = ToStoredPath(item.SourcePath),
                Kind = LibraryPersistenceMapper.PersistedKind(item.Kind),
                Status = LibraryPersistenceMapper.PersistedStatus(item.Status),
                Metadata = LibraryPersistenceMapper.ToPersisted(item.Metadata),
                PreparedRelativePath = item.PreparedPath is null ? null : ToStoredPath(item.PreparedPath),
                CoverRelativePath = item.CoverRelativePath,

                // La invariante que fijó la maestra: sin ruta tampoco hay hash.
                CoverHash = item.CoverRelativePath is { Length: > 0 } ? item.CoverHash : null,
                Category = item.Category,
                SeriesName = item.SeriesName,
                Season = item.Season,
                Episode = item.Episode,
                PhotoAlbum = item.PhotoAlbum,
                MetadataEditedByUser = item.MetadataEditedByUser ? true : null,
                AddedAt = item.AddedAt,
                FileSizeBytes = item.FileSizeBytes
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
    public byte[]? ReadCover(LibraryItem item)
    {
        // Los que todavía no se guardaron ya están en la mano: no hay nada que
        // ir a buscar, y buscarlo daría el archivo VIEJO.
        if (item.Metadata?.CoverArtData is { Length: > 0 } pending) return pending;

        if (!item.HasCover) return null;

        byte[]? data = ReadCoverBytes(item.CoverRelativePath, item.Id);
        if (data is null) return null;

        // Si el catálogo no traía el hash —uno anterior a ST-208, o escrito por
        // la app de macOS antes de que adopte el campo—, este es el momento
        // barato de calcularlo: los bytes ya están en la mano. Queda anotado y
        // el próximo guardado lo escribe.
        item.CoverHash ??= CoverArtHash.Of(data);

        return data;
    }

    private byte[]? ReadCoverBytes(string? recorded, Guid id)
    {
        try
        {
            // ST-203: primero LA RUTA ANOTADA, como ya hace la app de macOS
            // (`SharedCatalogPath.coverURL(recorded:itemID:)`). Windows la
            // escribía y la ignoraba al leer, derivándola siempre del
            // identificador; con la biblioteca compartida eso significa que una
            // carátula anotada en otra forma —otra normalización Unicode, otro
            // separador— quedaba invisible acá aunque el archivo estuviera ahí.
            if (recorded is { Length: > 0 })
            {
                string fromCatalog = ToAbsolutePath(recorded);
                if (File.Exists(fromCatalog)) return File.ReadAllBytes(fromCatalog);
            }

            string path = CoverPath(id);
            if (File.Exists(path)) return File.ReadAllBytes(path);

            string legacy = Path.Combine(CoversDirectory, id.ToString("N") + ".jpg");
            return File.Exists(legacy) ? File.ReadAllBytes(legacy) : null;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            // Una portada ilegible no puede impedir que el item cargue.
            return null;
        }
    }

    /// <summary>
    /// Le pone esta carátula al elemento: la escribe en <c>.portadas\</c> y
    /// anota su ruta y su hash. <b>Es la única forma de darle una tapa</b> — el
    /// hash sale de los mismos bytes que se escriben, así que no puede quedar
    /// describiendo otra imagen.
    /// </summary>
    public void WriteCover(LibraryItem item, byte[] data)
    {
        if (data.Length == 0)
        {
            RemoveCover(item);
            return;
        }

        try
        {
            Directory.CreateDirectory(CoversDirectory);
            File.WriteAllBytes(CoverPath(item.Id), data);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Sin portada en disco el item sigue siendo válido; se vuelve a leer
            // de la etiqueta la próxima vez. Y no se anota nada: decir que tiene
            // una tapa que no se pudo escribir sería mentirle al catálogo.
            return;
        }

        item.CoverRelativePath = CatalogPath.CoverRelative(item.Id);
        item.CoverHash = CoverArtHash.Of(data);

        // Los bytes ya están en disco: dejarlos colgando del elemento es
        // exactamente el megabyte por canción que ST-208 vino a sacar.
        if (item.Metadata is not null) item.Metadata.CoverArtData = null;
    }

    /// <summary>
    /// Le quita la carátula: borra el archivo y deja el elemento sin ruta ni
    /// hash. <b>Explícito a propósito</b> (ST-208): guardar un elemento sin
    /// bytes cargados no quiere decir que haya que quitarle nada.
    /// </summary>
    public void RemoveCover(LibraryItem item)
    {
        foreach (string path in CoverFilesOf(item))
        {
            try
            {
                if (File.Exists(path)) File.Delete(path);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // No poder borrarla no puede tumbar nada; el catálogo ya dice
                // que no la tiene.
            }
        }

        item.CoverRelativePath = null;
        item.CoverHash = null;
        if (item.Metadata is not null) item.Metadata.CoverArtData = null;
    }

    /// <summary>
    /// Todos los archivos que podrían ser la carátula de ese elemento: el
    /// anotado, el canónico y el del nombre anterior a ST-087. Se borran los
    /// tres, porque dejar uno haría que la siguiente carga la "encontrara" otra
    /// vez.
    /// </summary>
    private IEnumerable<string> CoverFilesOf(LibraryItem item)
    {
        if (item.CoverRelativePath is { Length: > 0 } recorded)
        {
            string? resolved = null;
            try { resolved = ToAbsolutePath(recorded); } catch (ArgumentException) { }
            if (resolved is not null) yield return resolved;
        }

        yield return CoverPath(item.Id);
        yield return Path.Combine(CoversDirectory, item.Id.ToString("N") + ".jpg");
    }
}
