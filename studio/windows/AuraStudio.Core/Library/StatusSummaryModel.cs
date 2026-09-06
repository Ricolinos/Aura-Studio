namespace AuraStudio.Core.Library;

/// <summary>
/// Qué se está resumiendo, con lo que la sección necesita saber además de su
/// nombre (addendum de ST-202).
///
/// <para>Dos secciones no se resuelven solo con el enum: los álbumes de fotos
/// son los de <b>una</b> colección, y el desglose de "Todas las fotos" nombra
/// las colecciones <b>en el orden que el usuario configuró</b>, que la
/// biblioteca no sabe.</para>
/// </summary>
/// <param name="Category">La colección de fotos abierta. Solo para <c>PhotoAlbums</c>.</param>
/// <param name="Collections">
/// Las colecciones de fotos, en su orden. Solo para <c>Photos</c>; sin ellas el
/// total no desglosa, que es peor pero nunca incorrecto.
/// </param>
public readonly record struct LibraryStatusScope(
    LibraryStatusSection Section,
    string Category = "",
    IReadOnlyList<string>? Collections = null)
{
    /// <summary>
    /// Una sección sola es un ámbito válido: es el caso de Canciones, Álbumes,
    /// Artistas, Películas y Series, que no necesitan nada más.
    /// </summary>
    public static implicit operator LibraryStatusScope(LibraryStatusSection section) => new(section);

    /// <summary>
    /// Con qué comparar para saber si lo memoizado sigue sirviendo. Se arma una
    /// vez por pedido de resumen —que ya viene con rebote desde la vista—, no
    /// una por elemento.
    /// </summary>
    internal string MemoKey =>
        $"{Section}\u0001{Category}\u0001{string.Join('\u0001', Collections ?? [])}";
}

/// <summary>
/// La barra de estado de una sección, partida en dos por costo (ST-202;
/// paridad con <c>StatusSummaryModel.swift</c> de ST-153):
///
/// <list type="bullet">
/// <item>Lo que <b>no</b> depende de la selección —cuántos álbumes, cuántos
/// artistas, cuánto dura todo— se calcula una vez por versión del catálogo y se
/// guarda. Es lo caro: recorre la biblioteca entera.</item>
/// <item>Lo que <b>sí</b> depende de la selección se calcula en el momento, y es
/// barato: proporcional a lo seleccionado, no al catálogo.</item>
/// </list>
///
/// <para>Antes de partirlo, macOS recalculaba las dos mitades en cada clic
/// —normalizando cadenas de los 12 000 elementos para poder decir "5
/// seleccionadas"—, y era una de las dos causas del congelamiento que midió
/// ST-152. Acá el total se apoya además en <see cref="LibraryCatalogIndex"/>, que
/// ya tiene los grupos contados: pedirle cuántos álbumes hay es O(1).</para>
///
/// <para>Es puro y no sabe de hilos ni de temporizadores: el rebote —para que
/// mantener apretada Mayús+flecha no recalcule el texto en cada tecla— lo pone
/// la app, que es la que tiene el despachador.</para>
/// </summary>
public sealed class StatusSummaryModel
{
    private int _version = -1;
    private string _scope = "";
    private LibraryStatusSummary _total = LibraryStatusSummary.Empty;

    /// <summary>
    /// Contra cuántos se compara lo seleccionado: canciones en Canciones,
    /// películas en Películas, álbumes de fotos en una colección. Se guarda con
    /// el total porque el texto de la selección lo necesita ("5 de 12 000"), y
    /// contarlo ahí sería recorrer el catálogo en cada cambio de selección —
    /// justo lo que este modelo existe para evitar.
    /// </summary>
    private int _denominator;

    /// <summary>
    /// La parte que no depende de la selección. Se recalcula solo cuando cambia
    /// la versión del catálogo o el ámbito.
    /// </summary>
    public LibraryStatusSummary Total(
        LibraryCatalogIndex index, LibraryStatusScope scope, int catalogVersion)
    {
        string key = scope.MemoKey;
        if (_version == catalogVersion && _scope == key) return _total;

        _version = catalogVersion;
        _scope = key;
        _total = ComputeTotal(index, scope, out _denominator);
        return _total;
    }

    /// <summary>
    /// El resumen completo: el total guardado más lo que dice la selección.
    /// <paramref name="selected"/> son los ELEMENTOS alcanzados, no las tarjetas
    /// — una tarjeta de Álbumes son sus canciones.
    /// </summary>
    /// <param name="selectedGroupCount">
    /// Cuántas tarjetas/filas hay marcadas, que no es lo mismo que cuántos
    /// elementos alcanzan: en Álbumes se dice "3 de 1 000 seleccionados" con
    /// álbumes, y las canciones van aparte.
    /// </param>
    public LibraryStatusSummary Summary(
        LibraryCatalogIndex index,
        LibraryStatusScope scope,
        int catalogVersion,
        IReadOnlyList<LibraryItem> selected,
        int selectedGroupCount)
    {
        LibraryStatusSummary total = Total(index, scope, catalogVersion);

        return selected.Count == 0
            ? total
            : total with { Selection = SelectionText(index, scope, selected, selectedGroupCount, _denominator) };
    }

    // MARK: - El total

    private static LibraryStatusSummary ComputeTotal(
        LibraryCatalogIndex index, LibraryStatusScope scope, out int denominator) =>
        scope.Section switch
        {
            LibraryStatusSection.Movies => VideoTotal(index, series: false, out denominator),
            LibraryStatusSection.Series => VideoTotal(index, series: true, out denominator),
            LibraryStatusSection.Photos => PhotosTotal(index, scope.Collections, out denominator),
            LibraryStatusSection.PhotoAlbums => PhotoAlbumsTotal(index, scope.Category, out denominator),
            _ => MusicTotal(index, scope.Section, out denominator)
        };

    private static LibraryStatusSummary MusicTotal(
        LibraryCatalogIndex index, LibraryStatusSection section, out int denominator)
    {
        IReadOnlyList<LibraryItem> music = [.. index.Items.Where(item => item.Kind == LibraryItemKind.Music)];

        // Del índice, que ya los tiene contados: preguntarle cuántos álbumes hay
        // es O(1), y volver a agrupar la biblioteca para saberlo era justamente
        // lo que la barra hacía en cada clic.
        int albums = index.GroupCount(LibraryGroupKind.Album);
        int artists = index.GroupCount(LibraryGroupKind.Artist);

        string trailing = LibraryStats.Join(
            LibraryStats.DurationText(LibraryStats.TotalDuration(music)),
            LibraryStats.SizeText(LibraryStats.TotalSize(music)));

        string total = section switch
        {
            LibraryStatusSection.Albums => LibraryStats.Join(
                LibraryStats.Count(albums, "álbum", "álbumes"),
                LibraryStats.Count(artists, "artista", "artistas"),
                LibraryStats.Count(music.Count, "canción", "canciones")),

            LibraryStatusSection.Artists => LibraryStats.Join(
                LibraryStats.Count(artists, "artista", "artistas"),
                LibraryStats.Count(albums, "álbum", "álbumes"),
                LibraryStats.Count(music.Count, "canción", "canciones")),

            _ => LibraryStats.Join(
                LibraryStats.Count(music.Count, "canción", "canciones"),
                LibraryStats.Count(artists, "artista", "artistas"),
                LibraryStats.Count(albums, "álbum", "álbumes"))
        };

        denominator = section switch
        {
            LibraryStatusSection.Albums => albums,
            LibraryStatusSection.Artists => artists,
            _ => music.Count
        };

        return new LibraryStatusSummary(total, "", trailing);
    }

    /// <summary>
    /// Películas y series salen del mismo índice y se separan por la categoría
    /// de su primer elemento, no leyendo la forma de la clave: cómo se arma esa
    /// clave es asunto de <see cref="LibraryGrouping"/>, y mirarla acá sería
    /// copiarla.
    /// </summary>
    private static LibraryStatusSummary VideoTotal(
        LibraryCatalogIndex index, bool series, out int denominator)
    {
        List<LibraryItem> items = [];
        int groups = 0;

        foreach (string key in index.Keys(LibraryGroupKind.VideoCollection))
        {
            IReadOnlyList<LibraryItem> bucket = index.ByVideoCollectionKey(key);
            if (bucket.Count == 0) continue;
            if (MediaCategoryNames.IsSeriesCategory(bucket[0].Category) != series) continue;

            groups++;
            items.AddRange(bucket);
        }

        denominator = groups;

        if (!series)
        {
            return new LibraryStatusSummary(
                LibraryStats.Count(groups, "película", "películas"),
                "",
                LibraryStats.Join(
                    LibraryStats.DurationText(LibraryStats.TotalDuration(items)),
                    LibraryStats.SizeText(LibraryStats.TotalSize(items))));
        }

        return new LibraryStatusSummary(
            LibraryStats.Join(
                LibraryStats.Count(groups, "serie", "series"),
                LibraryStats.Count(LibraryStats.SeasonCount(items), "temporada", "temporadas"),
                LibraryStats.Count(items.Count, "episodio", "episodios")),
            "",
            LibraryStats.DurationText(LibraryStats.TotalDuration(items)));
    }

    private static LibraryStatusSummary PhotosTotal(
        LibraryCatalogIndex index, IReadOnlyList<string>? collections, out int denominator)
    {
        IReadOnlyList<LibraryItem> photos = [.. index.Items.Where(item => item.Kind == LibraryItemKind.Photo)];
        denominator = photos.Count;

        List<string?> parts = [LibraryStats.Count(photos.Count, "foto", "fotos")];

        // El desglose va en el orden que el usuario configuró, y solo nombra las
        // colecciones que tienen algo: "0 en IA" no le dice nada a nadie.
        if (collections is { Count: > 0 } && photos.Count > 0)
        {
            foreach (string collection in collections)
            {
                int inCollection = photos.Count(photo => photo.Category == collection);
                if (inCollection > 0) parts.Add($"{LibraryStats.Formatted(inCollection)} en {collection}");
            }
        }

        int albums = LibraryStats.PhotoAlbumCount(photos);
        if (albums > 0) parts.Add(LibraryStats.Count(albums, "álbum", "álbumes"));

        return new LibraryStatusSummary(
            LibraryStats.Join([.. parts]),
            "",
            LibraryStats.SizeText(LibraryStats.TotalSize(photos)));
    }

    private static LibraryStatusSummary PhotoAlbumsTotal(
        LibraryCatalogIndex index, string category, out int denominator)
    {
        List<LibraryItem> photos = [];
        int named = 0;
        int loose = 0;
        int groups = 0;

        foreach (string key in index.Keys(LibraryGroupKind.PhotoAlbum))
        {
            IReadOnlyList<LibraryItem> bucket = index.ByPhotoAlbumKey(key);
            if (bucket.Count == 0 || (bucket[0].Category ?? "") != category) continue;

            groups++;
            photos.AddRange(bucket);

            // "Sin álbum" es una tarjeta más en la cuadrícula —por eso cuenta en
            // el denominador— pero NO es un álbum: contarlo diría uno de más.
            if ((bucket[0].PhotoAlbum ?? "").Trim().Length > 0) named++;
            else loose += bucket.Count;
        }

        denominator = groups;

        return new LibraryStatusSummary(
            LibraryStats.Join(
                LibraryStats.Count(named, "álbum", "álbumes"),
                LibraryStats.Count(photos.Count, "foto", "fotos"),
                loose > 0 ? $"{LibraryStats.Formatted(loose)} sin álbum" : null),
            "",
            LibraryStats.SizeText(LibraryStats.TotalSize(photos)));
    }

    // MARK: - La selección

    private static string SelectionText(
        LibraryCatalogIndex index,
        LibraryStatusScope scope,
        IReadOnlyList<LibraryItem> selected,
        int selectedGroupCount,
        int denominator)
    {
        ArtistGroupingOptions? options = index.Grouping;
        string duration = LibraryStats.DurationText(LibraryStats.TotalDuration(selected));
        string size = LibraryStats.SizeText(LibraryStats.TotalSize(selected));

        string OfTotal(int count, string word) =>
            $"{LibraryStats.Formatted(count)} de {LibraryStats.Formatted(denominator)} {word}";

        return scope.Section switch
        {
            LibraryStatusSection.Albums => LibraryStats.Join(
                OfTotal(selectedGroupCount, "seleccionados"),
                LibraryStats.Count(LibraryStats.ArtistCount(selected, options), "artista", "artistas"),
                LibraryStats.Count(selected.Count, "canción", "canciones"),
                duration),

            LibraryStatusSection.Artists => LibraryStats.Join(
                OfTotal(selectedGroupCount, "seleccionados"),
                LibraryStats.Count(LibraryStats.AlbumCount(selected, options), "álbum", "álbumes"),
                LibraryStats.Count(selected.Count, "canción", "canciones"),
                duration),

            LibraryStatusSection.Movies => LibraryStats.Join(
                OfTotal(selectedGroupCount, "seleccionadas"), duration, size),

            LibraryStatusSection.Series => LibraryStats.Join(
                OfTotal(selectedGroupCount, "seleccionadas"),
                LibraryStats.Count(LibraryStats.SeasonCount(selected), "temporada", "temporadas"),
                LibraryStats.Count(selected.Count, "episodio", "episodios"),
                duration),

            // En "Todas las fotos" la tarjeta ES la foto: se cuentan elementos y
            // no grupos, porque son lo mismo.
            LibraryStatusSection.Photos => LibraryStats.Join(
                OfTotal(selected.Count, "seleccionadas"), size),

            LibraryStatusSection.PhotoAlbums => LibraryStats.Join(
                OfTotal(selectedGroupCount, "seleccionados"),
                LibraryStats.Count(selected.Count, "foto", "fotos"),
                size),

            _ => LibraryStats.Join(
                OfTotal(selected.Count, "seleccionadas"),
                LibraryStats.Count(LibraryStats.ArtistCount(selected, options), "artista", "artistas"),
                LibraryStats.Count(LibraryStats.AlbumCount(selected, options), "álbum", "álbumes"),
                duration)
        };
    }
}
