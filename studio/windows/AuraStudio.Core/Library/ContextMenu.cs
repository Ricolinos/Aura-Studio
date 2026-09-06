namespace AuraStudio.Core.Library;

public enum MenuRole
{
    Normal,

    /// <summary>Se pinta como acción destructiva. Nunca confirma en el propio menú.</summary>
    Destructive
}

/// <summary>
/// Un renglón de menú contextual. <c>Id</c> es lo que ejecuta la app;
/// <c>Text</c> es lo que lee el usuario.
/// </summary>
/// <param name="Enabled">
/// Un ítem que no aplica se <b>deshabilita</b> en vez de esconderse cuando el
/// documento de paridad lo dice así: que desaparezca deja al usuario buscando
/// una opción que ayer estaba.
/// </param>
public sealed record MenuEntry(
    string Id,
    string Text,
    bool Enabled = true,
    MenuRole Role = MenuRole.Normal,
    bool Checked = false,
    IReadOnlyList<MenuEntry>? Submenu = null)
{
    public bool IsSeparator => Id.Length == 0;

    public static MenuEntry Separator { get; } = new("", "");

    public static MenuEntry Sub(string id, string text, IReadOnlyList<MenuEntry> items) =>
        new(id, text, Submenu: items);
}

/// <summary>
/// El criterio de Finder para qué alcanza una acción del menú contextual.
///
/// <para>Clic derecho sobre algo que <b>ya está seleccionado</b>: la acción
/// alcanza a toda la selección. Sobre algo que <b>no lo está</b>: alcanza solo
/// a eso, y la selección anterior no se pierde. Es lo que hace el Finder, lo
/// que hace el Explorador, y lo que el usuario espera sin saber que lo
/// espera.</para>
/// </summary>
public static class GridSelection
{
    public static IReadOnlyList<T> EffectiveIds<T>(T clicked, IReadOnlyCollection<T> selection)
        where T : notnull =>
        selection.Contains(clicked) ? [.. selection] : [clicked];
}

/// <summary>
/// Lo que hace falta saber de lo alcanzado para decidir el menú. Se arma en la
/// app a partir de los elementos reales; acá se razona solo con esto.
/// </summary>
/// <param name="Count">Cuántos elementos de la colección alcanza (álbumes, artistas, fotos…).</param>
/// <param name="AllFavorite">Si TODAS las canciones alcanzadas ya son favoritas.</param>
/// <param name="HasArtistPhoto">Si <b>algún</b> artista alcanzado ya tiene foto guardada (R2-2).</param>
/// <param name="ArtistsWithPhotoCount">
/// Cuántos de los alcanzados la tienen — es lo que decide el plural del ítem
/// para quitarla, que no es lo mismo que cuántos artistas se alcanzaron.
/// </param>
/// <param name="AlbumCount">
/// Cuántos álbumes CON TÍTULO PROPIO alcanza la selección (ST-206). Con más de
/// uno, "Buscar carátulas del álbum..." pasa a su forma plural en vez de
/// desaparecer: era el caso que el dueño reportó como "en Canciones con todo
/// seleccionado no aparece Buscar carátulas".
/// </param>
/// <param name="ApplyingRecommendedCover">
/// Si ya se está aplicando la carátula recomendada: el ítem se deshabilita
/// mientras dura, en vez de desaparecer.
/// </param>
public readonly record struct MenuScope(
    int Count,
    bool AllFavorite = false,
    bool HasCover = false,
    bool HasPoster = false,
    bool HasArtistPhoto = false,
    bool SingleAlbumWithTitle = false,
    bool HasAlbum = false,
    bool HasArtist = false,
    bool AnyReady = false,
    bool DeviceConnected = false,
    bool AnyNamedAlbum = false,
    bool IsDefaultTheme = false,
    int ArtistsWithPhotoCount = 0,
    bool ApplyingRecommendedCover = false,
    int AlbumCount = 0)
{
    public bool IsEmpty => Count == 0;

    public bool IsSingle => Count == 1;
}

/// <summary>
/// Los menús contextuales, ítem por ítem, con su orden, sus separadores y sus
/// condiciones — port de <c>docs/paridad-menus-contextuales.md</c>, que es
/// <b>vinculante</b> (ST-105).
///
/// <para>Vive en Core y no en las pantallas a propósito: lo que más fácil se
/// pierde al portar un menú no son los textos sino las condiciones —qué alcanza
/// la acción, cuándo va en plural, qué se deshabilita en vez de esconderse,
/// dónde va cada separador— y nada de eso da error al perderse: da un menú
/// parecido. Acá se puede comparar contra el documento, renglón por
/// renglón.</para>
/// </summary>
public static class LibraryContextMenus
{
    // Windows dice "Explorador" donde macOS dice "Finder". Es la ÚNICA
    // excepción de texto del documento (§13.1), y está acá sola para que no se
    // convierta en licencia para reescribir el resto.
    public const string Reveal = "Mostrar en el Explorador";

    private const string SearchOnline = "Buscar información en línea";
    private const string SearchAlbumCovers = "Buscar carátulas del álbum...";
    private const string SearchPoster = "Buscar póster en línea";
    private const string ChangeCategory = "Cambiar categoría";

    private static MenuEntry Favorite(bool allFavorite, string removeText = "Quitar favorito") =>
        new(allFavorite ? "favorite.remove" : "favorite.add",
            allFavorite ? removeText : "Marcar como favorito");

    /// <summary>
    /// El ítem de buscar tapas, en singular o en plural según a cuántos álbumes
    /// alcance la selección (ST-206; hermano de ST-182 en la Mac).
    ///
    /// <para>Antes, con la selección tocando varios discos, el ítem
    /// <b>desaparecía</b> — "¿la tapa de cuál?" —, y eso es lo que el dueño
    /// reportó: en Canciones con todo seleccionado no aparecía. La respuesta no
    /// es esconderlo sino buscar la de cada uno: aplica sola la que supere el
    /// umbral y las dudosas se revisan de a una.</para>
    /// </summary>
    /// <param name="batch">
    /// Si esta vista ofrece la forma en lote. En <b>Álbumes</b> no: ahí el lote
    /// ya se ofrece como "Aplicar carátula recomendada a N álbumes" (R2-3), y
    /// dos ítems que hacen lo mismo en el mismo menú son peor que uno.
    /// </param>
    internal static MenuEntry? AlbumCovers(MenuScope scope, bool batch = true)
    {
        if (scope.SingleAlbumWithTitle) return new MenuEntry("album.covers", SearchAlbumCovers);

        // "Sin álbum" no cuenta: no es un disco sino el cajón de lo que no tiene
        // uno, y no hay tapa que buscarle.
        if (batch && scope.AlbumCount > 1)
            return new MenuEntry("album.covers", $"Buscar carátulas de {scope.AlbumCount} álbumes...");

        return null;
    }

    // MARK: - 1. Álbum de música

    public static IReadOnlyList<MenuEntry> ForAlbums(MenuScope scope)
    {
        List<MenuEntry> items = [];

        if (scope.IsSingle)
        {
            items.Add(new MenuEntry("open", "Abrir"));
            items.Add(MenuEntry.Separator);
        }

        items.Add(Favorite(scope.AllFavorite));
        items.Add(new MenuEntry("enrich", SearchOnline));

        // ST-104: uno solo abre su selector. En plural NO va acá: este menú ya
        // ofrece el lote como "Aplicar carátula recomendada a N álbumes" (R2-3),
        // que es la misma operación. "Sin álbum" no cuenta en ningún caso — no
        // es un disco sino el cajón de lo que no tiene uno.
        if (AlbumCovers(scope, batch: false) is { } covers) items.Add(covers);

        // R2-3: aplica SIN preguntar solo lo que supere el umbral de
        // `docs/caratula-recomendada.md`. Lo que no lo supere no se toca y se
        // cuenta en el resumen — aplicar a ciegas una tapa dudosa a veinte
        // álbumes es exactamente el daño que el umbral evita.
        if (scope.AnyNamedAlbum)
        {
            items.Add(new MenuEntry("album.cover.recommended",
                scope.IsSingle
                    ? "Aplicar carátula recomendada"
                    : $"Aplicar carátula recomendada a {scope.Count} álbumes",
                Enabled: !scope.ApplyingRecommendedCover));
        }

        items.Add(MenuEntry.Separator);
        items.Add(new MenuEntry("reveal", Reveal));
        items.Add(new MenuEntry("delete", scope.IsSingle ? "Eliminar álbum" : "Eliminar álbumes",
            Role: MenuRole.Destructive));

        return items;
    }

    // MARK: - 2. Artista

    public static IReadOnlyList<MenuEntry> ForArtists(MenuScope scope, bool canFetchPhotos = true)
    {
        List<MenuEntry> items =
        [
            Favorite(scope.AllFavorite),
            new MenuEntry("enrich", SearchOnline)
        ];

        if (canFetchPhotos)
        {
            items.Add(new MenuEntry("artist.photo",
                scope.IsSingle ? "Buscar foto del artista" : "Buscar fotos de los artistas"));
        }

        // R2-2: si ALGUNO de los alcanzados tiene foto. Antes se ofrecía solo
        // con un artista seleccionado, así que quitar cinco fotos obligaba a
        // cinco pasadas — y la acción tiene todo el sentido en plural.
        if (scope.HasArtistPhoto)
        {
            items.Add(new MenuEntry("artist.photo.remove",
                scope.ArtistsWithPhotoCount > 1 ? "Quitar fotos de los artistas" : "Quitar foto del artista"));
        }

        items.Add(MenuEntry.Separator);
        items.Add(new MenuEntry("reveal", Reveal));
        items.Add(new MenuEntry("delete", scope.IsSingle ? "Eliminar artista" : "Eliminar artistas",
            Role: MenuRole.Destructive));

        return items;
    }

    // MARK: - 3. Canción dentro de Artistas

    /// <summary>Alcance: siempre esa sola canción — esta lista no tiene selección múltiple.</summary>
    public static IReadOnlyList<MenuEntry> ForArtistSong(bool isFavorite) =>
    [
        new MenuEntry("info", "Más información..."),
        new MenuEntry(isFavorite ? "favorite.remove" : "favorite.add",
            isFavorite ? "Quitar de favoritos" : "Marcar como favorito"),
        MenuEntry.Separator,
        new MenuEntry("reveal", Reveal)
    ];

    // MARK: - 5 y 6. Películas y series

    public static IReadOnlyList<MenuEntry> ForMovies(MenuScope scope, IReadOnlyList<string> categories) =>
        ForVideoCollection(scope, categories, "Eliminar película", "Eliminar películas");

    public static IReadOnlyList<MenuEntry> ForSeries(MenuScope scope, IReadOnlyList<string> categories) =>
        ForVideoCollection(scope, categories, "Eliminar serie", "Eliminar series");

    private static IReadOnlyList<MenuEntry> ForVideoCollection(
        MenuScope scope, IReadOnlyList<string> categories, string deleteOne, string deleteMany)
    {
        List<MenuEntry> items = [];

        if (scope.IsSingle)
        {
            items.Add(new MenuEntry("open", "Abrir"));
            items.Add(MenuEntry.Separator);
        }

        items.Add(Favorite(scope.AllFavorite));
        items.Add(new MenuEntry("poster", SearchPoster));
        items.Add(CategorySubmenu(categories));
        items.Add(MenuEntry.Separator);
        items.Add(new MenuEntry("reveal", Reveal));
        items.Add(new MenuEntry("delete", scope.IsSingle ? deleteOne : deleteMany, Role: MenuRole.Destructive));

        return items;
    }

    // MARK: - 7. Episodio

    public static IReadOnlyList<MenuEntry> ForEpisodes(MenuScope scope, IReadOnlyList<string> categories)
    {
        List<MenuEntry> items = [];

        if (scope.IsSingle)
        {
            items.Add(new MenuEntry("info", "Más información..."));
            items.Add(MenuEntry.Separator);
        }

        items.Add(Favorite(scope.AllFavorite));
        items.Add(CategorySubmenu(categories));
        items.Add(MenuEntry.Separator);
        items.Add(new MenuEntry("reveal", Reveal));
        items.Add(new MenuEntry("delete", scope.IsSingle ? "Eliminar episodio" : "Eliminar episodios",
            Role: MenuRole.Destructive));

        return items;
    }

    // MARK: - 8. Álbum de fotos

    public static IReadOnlyList<MenuEntry> ForPhotoAlbums(
        MenuScope scope, IReadOnlyList<string> collections, bool hasPhotos = true)
    {
        List<MenuEntry> items = [];

        if (scope.IsSingle)
        {
            items.Add(new MenuEntry("open", "Abrir"));
            items.Add(MenuEntry.Separator);
        }

        // Visible siempre, deshabilitado sin fotos: esconderlo dejaría al
        // usuario buscando una opción que ayer estaba.
        items.Add(CategorySubmenu(collections) with { Enabled = hasPhotos });

        if (scope.AnyNamedAlbum)
        {
            items.Add(MenuEntry.Separator);

            if (scope.IsSingle) items.Add(new MenuEntry("album.rename", "Renombrar álbum..."));

            items.Add(new MenuEntry("album.dissolve", scope.IsSingle ? "Disolver álbum" : "Disolver álbumes",
                Role: MenuRole.Destructive));
        }

        items.Add(MenuEntry.Separator);
        items.Add(new MenuEntry("reveal", Reveal));

        // Sin variante en plural, a propósito: es la misma frase con una foto o
        // con doscientas.
        items.Add(new MenuEntry("delete", "Eliminar fotos de la biblioteca", Role: MenuRole.Destructive));

        return items;
    }

    // MARK: - 9. Foto

    public static IReadOnlyList<MenuEntry> ForPhotos(MenuScope scope, IReadOnlyList<string> collections)
    {
        List<MenuEntry> items = [];

        if (scope.IsSingle)
        {
            items.Add(new MenuEntry("preview", "Vista previa"));
            items.Add(MenuEntry.Separator);
        }

        items.Add(CategorySubmenu(collections));
        items.Add(new MenuEntry("photo.removeFromAlbum", "Quitar del álbum"));
        items.Add(new MenuEntry("reveal", Reveal));
        items.Add(MenuEntry.Separator);
        items.Add(new MenuEntry("delete", "Eliminar de la biblioteca", Role: MenuRole.Destructive));

        return items;
    }

    // MARK: - 10. Tema

    /// <summary>
    /// Con el tema por omisión el menú queda <b>vacío</b>: macOS no muestra
    /// ninguno, y un menú con un solo ítem deshabilitado no es lo mismo.
    /// </summary>
    public static IReadOnlyList<MenuEntry> ForTheme(bool isDefaultTheme) =>
        isDefaultTheme ? [] : [new MenuEntry("delete", "Eliminar", Role: MenuRole.Destructive)];

    private static MenuEntry CategorySubmenu(IReadOnlyList<string> categories) =>
        MenuEntry.Sub("category", ChangeCategory,
            [.. categories.Select(category => new MenuEntry("category:" + category, category))]);
}

/// <summary>
/// El menú de las tablas de Canciones, Video y Fotos, y el de la tabla del
/// detalle de un álbum (§4 del documento de paridad).
///
/// <para>Se arma <b>por bloques</b>, y un bloque que no aplica desaparece
/// entero, con su separador. Ese detalle es la mitad del menú: sin él quedan
/// separadores sueltos o, peor, un bloque de música colgando de una foto.</para>
/// </summary>
public static class MediaTableContextMenu
{
    /// <param name="categories">
    /// Las categorías de la sección, si tiene. Solo Fotos y Video tienen: la
    /// música se organiza por artista y álbum, y eso se elige en Ajustes, no
    /// elemento por elemento.
    /// </param>
    public static IReadOnlyList<MenuEntry> Build(
        LibraryItemKind kind, MenuScope scope, IReadOnlyList<string>? categories = null)
    {
        // Cada bloque se arma entero y aparte, y los vacíos desaparecen con su
        // separador. Ir agregando separadores sobre la marcha deja uno suelto
        // arriba, o dos seguidos, en cuanto un bloque no aplica — que es
        // justamente lo más frecuente.
        List<List<MenuEntry>> blocks =
        [
            kind == LibraryItemKind.Music && !scope.IsEmpty ? MusicBlock(scope) : [],
            kind == LibraryItemKind.Video && !scope.IsEmpty ? VideoBlock(scope) : [],
            CategoryBlock(kind, scope, categories),
            InfoBlock(kind, scope),
            SyncBlock(scope),
            FinalBlock(scope)
        ];

        List<MenuEntry> items = [];

        foreach (List<MenuEntry> block in blocks.Where(block => block.Count > 0))
        {
            if (items.Count > 0) items.Add(MenuEntry.Separator);
            items.AddRange(block);
        }

        return items;
    }

    /// <summary>
    /// El bloque de música lleva sus dos separadores <b>adentro</b>: son parte
    /// del bloque, no uniones entre bloques.
    /// </summary>
    private static List<MenuEntry> MusicBlock(MenuScope scope)
    {
        List<MenuEntry> items = [new MenuEntry("enrich", "Buscar información en línea")];

        // ST-104: si TODAS las alcanzadas son del MISMO álbum con título; desde
        // ST-206, también en plural cuando la selección toca varios discos.
        if (LibraryContextMenus.AlbumCovers(scope) is { } covers) items.Add(covers);

        items.Add(new MenuEntry("lyrics", "Buscar letra"));
        items.Add(new MenuEntry("retag", "Volver a leer etiquetas del archivo"));

        // Visible siempre; deshabilitado si no hay ninguna carátula que quitar.
        items.Add(new MenuEntry("cover.remove", "Eliminar carátula", Enabled: scope.HasCover));

        items.Add(MenuEntry.Separator);
        items.Add(new MenuEntry(scope.AllFavorite ? "favorite.remove" : "favorite.add",
            scope.AllFavorite ? "Quitar de favoritos" : "Marcar como favorito"));

        if (!scope.HasAlbum && !scope.HasArtist) return items;

        items.Add(MenuEntry.Separator);

        if (scope.HasAlbum) items.Add(new MenuEntry("select.album", "Seleccionar canciones del mismo álbum"));
        if (scope.HasArtist) items.Add(new MenuEntry("select.artist", "Seleccionar canciones del mismo artista"));

        return items;
    }

    private static List<MenuEntry> VideoBlock(MenuScope scope) =>
    [
        new MenuEntry("poster", "Buscar póster en línea"),
        new MenuEntry("poster.remove", "Quitar póster", Enabled: scope.HasPoster)
    ];

    /// <summary>
    /// Solo Fotos y Video tienen categorías: la música se organiza por artista y
    /// álbum, y eso se elige en Ajustes, no elemento por elemento.
    /// </summary>
    private static List<MenuEntry> CategoryBlock(
        LibraryItemKind kind, MenuScope scope, IReadOnlyList<string>? categories)
    {
        if (kind == LibraryItemKind.Music || scope.IsEmpty || categories is not { Count: > 0 }) return [];

        return
        [
            MenuEntry.Sub("category", "Cambiar categoría",
                [.. categories.Select(category => new MenuEntry("category:" + category, category))])
        ];
    }

    private static List<MenuEntry> InfoBlock(LibraryItemKind kind, MenuScope scope)
    {
        if (scope.IsSingle)
        {
            return
            [
                new MenuEntry("rename", "Cambiar nombre..."),
                new MenuEntry("info", "Más información...")
            ];
        }

        // Edición en lote (D-218): solo tiene sentido con música y con más de un
        // elemento.
        return kind == LibraryItemKind.Music && scope.Count > 1
            ? [new MenuEntry("info.batch", "Obtener información...")]
            : [];
    }

    /// <summary>Sin un iPod con Aura no hay a dónde sincronizar: el ítem no aparece.</summary>
    private static List<MenuEntry> SyncBlock(MenuScope scope) =>
        scope.DeviceConnected
            ? [new MenuEntry("sync.selection", "Sincronizar la selección", Enabled: scope.AnyReady)]
            : [];

    private static List<MenuEntry> FinalBlock(MenuScope scope)
    {
        // "Eliminar" es visible siempre, deshabilitado con alcance vacío; el
        // resto del bloque necesita algo alcanzado.
        if (scope.IsEmpty) return [new MenuEntry("delete", "Eliminar", Enabled: false, Role: MenuRole.Destructive)];

        return
        [
            new MenuEntry("reveal", LibraryContextMenus.Reveal),
            new MenuEntry("similar", "Buscar elementos similares..."),
            MenuEntry.Separator,
            new MenuEntry("delete", "Eliminar", Role: MenuRole.Destructive)
        ];
    }
}

/// <summary>
/// El menú de los encabezados de la tabla de Canciones (§11 del documento de
/// paridad).
///
/// <para><b>El mismo contenido sale del clic derecho en el encabezado y del
/// botón de la barra superior.</b> En macOS es literalmente el mismo menú
/// instalado en dos lados, y acá también: dos listas armadas por separado se
/// desincronizan en cuanto alguien agregue una opción a una sola.</para>
/// </summary>
public static class SongsHeaderMenu
{
    public static IReadOnlyList<MenuEntry> Build(
        bool favoritesOnly, MusicSortField sortField, bool ascending) =>
    [
        new MenuEntry("filter.all", "Todas las canciones", Checked: !favoritesOnly),
        new MenuEntry("filter.favorites", "Solo favoritos", Checked: favoritesOnly),
        MenuEntry.Separator,
        MenuEntry.Sub("sort", "Opciones para ordenar", SortItems(sortField, ascending)),
        MenuEntry.Separator,
        new MenuEntry("view.options", "Mostrar opciones de visualización")
    ];

    private static IReadOnlyList<MenuEntry> SortItems(MusicSortField sortField, bool ascending)
    {
        List<MenuEntry> items =
        [
            .. MusicSortField.MenuFields.Select(field =>
                new MenuEntry("sort:" + field.RawValue, field.Title, Checked: field == sortField))
        ];

        items.Add(MenuEntry.Separator);
        items.Add(new MenuEntry("sort.ascending", "Ascendente", Checked: ascending));
        items.Add(new MenuEntry("sort.descending", "Descendente", Checked: !ascending));

        return items;
    }
}
