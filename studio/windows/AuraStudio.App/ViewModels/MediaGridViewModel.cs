using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using AuraStudio.App.Resources;
using AuraStudio.Core;
using AuraStudio.Core.Library;
using AuraStudio.Core.Networking;

namespace AuraStudio.App.ViewModels;

/// <summary>Qué muestra la cuadrícula. Es lo que llega como parámetro de navegación.</summary>
public enum MediaGridKind
{
    Albums,
    Movies,
    Series,
    /// <summary>Los álbumes de fotos de una colección (Fotos, Imágenes o IA).</summary>
    PhotoCollection,
    /// <summary>Todas las fotos, sin agrupar.</summary>
    AllPhotos,
    /// <summary>Todos los videos, sin agrupar.</summary>
    AllVideos,
    /// <summary>Los videos que no son película ni serie.</summary>
    Clips
}

/// <summary>
/// Lo que una tarjeta muestra, sin la tarjeta. Es lo que se compara para decidir
/// si la instancia que ya está en pantalla sirve o hay que hacer una nueva
/// (ST-201): reconstruir las 1 091 tarjetas en cada refresco obligaba al control
/// a rehacer todos sus contenedores y a decodificar todas las portadas otra vez.
/// </summary>
public readonly record struct MediaCardSpec(
    string Id, string Title, string Subtitle, LibraryItem? CoverItem, string? ImagePath)
{
    /// <summary>
    /// Si la tarjeta que ya existe muestra exactamente esto. La portada se
    /// compara <b>por referencia</b> a propósito: comparar 15 KB por álbum en
    /// cada refresco costaría más que lo que se está ahorrando, y cuando la tapa
    /// cambia de verdad llega en un arreglo nuevo —lo escribe
    /// <c>ApplyAlbumCover</c>—, así que la referencia alcanza.
    /// </summary>
    public bool Matches(MediaCard card) =>
        string.Equals(card.Title, Title, StringComparison.Ordinal)
        && string.Equals(card.Subtitle, Subtitle, StringComparison.Ordinal)
        && string.Equals(card.ImagePath, ImagePath, StringComparison.Ordinal)
        && ReferenceEquals(card.CoverItem, CoverItem)
        && string.Equals(card.CoverItem?.CoverHash, CoverItem?.CoverHash, StringComparison.Ordinal)

        // ST-204: y la tapa que TODAVÍA no se guardó. Desde que el guardado se
        // difiere, el hash de una tapa recién elegida sigue siendo el viejo
        // hasta que el persistidor escriba —medio segundo después—, así que
        // mirar solo el hash dejaría la tarjeta con la tapa anterior justo
        // después de cambiarla.
        && ReferenceEquals(card.CoverItem?.Metadata?.CoverArtData, CoverItem?.Metadata?.CoverArtData);

    public MediaCard ToCard() => new(Id, Title, Subtitle, CoverItem, ImagePath);
}

/// <summary>
/// Una tarjeta de la cuadrícula. Deliberadamente plana: la cuadrícula no sabe si
/// atrás hay un álbum, una serie o una carpeta de fotos, solo dibuja tarjetas.
/// </summary>
/// <param name="coverItem">De dónde sale la tapa (ST-208); <c>null</c> si no hay.</param>
/// <param name="imagePath">Imagen de archivo, para las tarjetas de fotos.</param>
public sealed partial class MediaCard(
    string id, string title, string subtitle, LibraryItem? coverItem, string? imagePath) : ObservableObject
{
    public string Id { get; } = id;
    public string Title { get; } = title;
    public string Subtitle { get; } = subtitle;
    public LibraryItem? CoverItem { get; } = coverItem;
    public string? ImagePath { get; } = imagePath;

    public bool HasCover => CoverItem is not null || ImagePath is { Length: > 0 };

    /// <summary>La inicial que se dibuja cuando no hay imagen; nunca un cuadro vacío.</summary>
    public string Initial => Title.Length > 0 ? Title[..1].ToUpperInvariant() : "?";

    /// <summary>
    /// Si está en la selección. Vive en la tarjeta —y no solo en una lista del
    /// modelo— porque la casilla tiene que <b>verse</b> marcada: ST-103 nació
    /// justo de que el gesto que no se ve no existe.
    /// </summary>
    [ObservableProperty] public partial bool IsSelected { get; set; }

    /// <summary>Si el cursor está encima de ESTA tarjeta.</summary>
    [ObservableProperty] public partial bool IsHovered { get; set; }

    /// <summary>Si hay algo seleccionado en la cuadrícula, sea esta tarjeta o no.</summary>
    [ObservableProperty] public partial bool AnySelection { get; set; }

    /// <summary>
    /// Cuándo se ve la casilla (R2-1, ST-120). La regla es idéntica en las dos
    /// apps:
    ///
    /// <list type="bullet">
    /// <item>Sin nada seleccionado, <b>ninguna</b>: la cuadrícula se ve limpia.</item>
    /// <item>Al pasar el cursor por una tarjeta, <b>solo la de ella</b>: es lo
    /// que hace descubrible la selección múltiple sin ensuciar la vista.</item>
    /// <item>Con uno o más seleccionados, <b>todas</b>: el usuario ya está en
    /// modo selección y necesita ver dónde sumar o quitar.</item>
    /// <item>Una tarjeta seleccionada muestra la suya siempre.</item>
    /// </list>
    ///
    /// <para>Revierte parte de ST-103 por orden del dueño: aquella decisión las
    /// dejaba siempre visibles, y con una biblioteca real eso es una cuadrícula
    /// sembrada de casillas que nadie pidió.</para>
    /// </summary>
    public bool ShowsSelectionBox => IsSelected || IsHovered || AnySelection;

    partial void OnIsSelectedChanged(bool value) => OnPropertyChanged(nameof(ShowsSelectionBox));

    partial void OnIsHoveredChanged(bool value) => OnPropertyChanged(nameof(ShowsSelectionBox));

    partial void OnAnySelectionChanged(bool value) => OnPropertyChanged(nameof(ShowsSelectionBox));
}

/// <summary>
/// Las cuadrículas de la biblioteca. Una sola pantalla para Álbumes, Artistas,
/// Películas, Series y colecciones de fotos: cambian el título, de dónde salen
/// las tarjetas y qué tipo de archivo aceptan al soltar — el resto es igual, y
/// cinco páginas casi idénticas se desincronizan solas.
/// </summary>
public sealed partial class MediaGridViewModel : ViewModelBase
{
    private readonly LibraryViewModel _library;

    /// <summary>Lo marcado, como lógica pura y compartible con la Mac (ST-201).</summary>
    private readonly GridSelectionModel _selection = new();

    /// <summary>Tarjeta por identificador: la selección toca por id, no por posición.</summary>
    private readonly Dictionary<string, MediaCard> _byId = new(StringComparer.Ordinal);

    /// <summary>
    /// Mientras es <c>true</c>, lo que avise el control sobre su selección no se
    /// le hace caso: la colección se está reacomodando y esos avisos son su
    /// contabilidad interna, no una decisión del usuario (ST-202).
    /// </summary>
    private bool _refreshing;

    /// <summary>Lo último que se les empujó a las tarjetas como <c>AnySelection</c>.</summary>
    private bool _anySelectionPushed;

    private IReadOnlyList<MediaCard>? _selectedCards;

    /// <summary>
    /// Las tarjetas. Es <b>la misma instancia siempre</b>: los refrescos la
    /// actualizan en su lugar (ST-201). Reemplazarla obligaría al control a
    /// rehacer todos sus contenedores, que es de donde salía el trabón.
    /// </summary>
    public ObservableCollection<MediaCard> Cards { get; } = [];

    [ObservableProperty]
    public partial string Title { get; private set; }

    [ObservableProperty]
    public partial string Subtitle { get; private set; }

    public MediaGridViewModel(LibraryViewModel library)
    {
        _library = library;
        _library.PropertyChanged += OnLibraryChanged;
        Title = "";
        Subtitle = "";
    }

    /// <summary>
    /// La cuadrícula se rehace cuando cambia el <b>contenido</b> de la
    /// biblioteca, no ante cualquier aviso suyo (ST-161).
    ///
    /// <para>Escucharlos todos costaba dos cosas. Una, trabajo: cada renglón de
    /// avance de la normalización de carátulas —que escribe
    /// <c>StatusMessage</c> decenas de veces— reagrupaba la biblioteca entera.
    /// La otra, un ciclo: refrescar publica la selección, publicar avisaba, y
    /// ese aviso volvía a refrescar, sin fin.</para>
    /// </summary>
    private void OnLibraryChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (ChangesLibraryContent(e.PropertyName))
        {
            Refresh();
            return;
        }

        // ST-203: mientras carga no hay tarjetas, pero eso no es "no tienes
        // música".
        if (e.PropertyName == nameof(LibraryViewModel.IsLoading))
            OnPropertyChanged(nameof(ShowsEmptyState));
    }

    /// <summary>
    /// Nombre vacío o <c>null</c> significa "cambió todo" en
    /// <c>INotifyPropertyChanged</c>: eso sí obliga a rehacer. Y no reabre el
    /// ciclo, porque publicar lo mismo ya no avisa
    /// (<see cref="LibraryViewModel.PublishSelectionForSync"/>).
    /// </summary>
    private static bool ChangesLibraryContent(string? propertyName) =>
        string.IsNullOrEmpty(propertyName)
        || propertyName == nameof(LibraryViewModel.Items)
        || propertyName == nameof(LibraryViewModel.AvailableItems);

    public LibraryViewModel Library => _library;

    public MediaGridKind Kind { get; private set; } = MediaGridKind.Albums;

    /// <summary>
    /// Cómo pregunta esta cuadrícula por lo que hay detrás de una tarjeta
    /// (ST-201). Es la traducción de <see cref="MediaGridKind"/> —que es de la
    /// app— a lo que entiende el índice de Core, y es lo que reutilizan el menú
    /// contextual y el alcance de sincronización.
    /// </summary>
    public LibraryGroupKind GroupKind => Kind switch
    {
        MediaGridKind.Albums => LibraryGroupKind.Album,
        MediaGridKind.Movies or MediaGridKind.Series => LibraryGroupKind.VideoCollection,
        MediaGridKind.PhotoCollection => LibraryGroupKind.PhotoAlbum,

        // Fotos sueltas y los listados planos: la tarjeta ES el elemento.
        _ => LibraryGroupKind.Item
    };

    /// <summary>
    /// Los pósters solo tienen sentido donde se ven videos. En Fotos o en
    /// Álbumes el botón no diría nada.
    /// </summary>
    public bool ShowsVideoPosterAction => Kind
        is MediaGridKind.Movies or MediaGridKind.Series or MediaGridKind.Clips or MediaGridKind.AllVideos;

    /// <summary>Solo para <see cref="MediaGridKind.PhotoCollection"/>.</summary>
    public string PhotoCategory { get; private set; } = "";

    /// <summary>Qué tipo acepta esta sección al soltar (ST-012).</summary>
    public LibraryItemKind DropKind => Kind switch
    {
        MediaGridKind.Albums => LibraryItemKind.Music,
        MediaGridKind.PhotoCollection or MediaGridKind.AllPhotos => LibraryItemKind.Photo,
        _ => LibraryItemKind.Video
    };

    public string DropHint => AppStrings.LibraryDropHint(DropKind);

    public string SectionRule => AppStrings.LibrarySectionOnlyItsType(DropKind);

    public bool IsEmpty => Cards.Count == 0;

    /// <summary>
    /// Cuándo sale el cartel de "arrastra tu música aquí" (ST-203).
    ///
    /// <para><b>No mientras carga.</b> Desde que la biblioteca se lee en segundo
    /// plano, la cuadrícula está vacía durante el primer segundo por una razón
    /// que no es la que ese cartel dice: decirle a alguien que no tiene música
    /// mientras se le está leyendo su música es la peor forma de contestar.
    /// Durante la carga se ve el avance en la franja de estado, que es lo que de
    /// verdad está pasando.</para>
    /// </summary>
    public bool ShowsEmptyState => Cards.Count == 0 && !_library.IsLoading;

    /// <summary>
    /// El resumen de la barra de estado (ST-202 y su addendum). Lo tienen las
    /// cuadrículas donde el resumen dice algo que <b>no está ya en la
    /// pantalla</b>: cuántos artistas hay detrás de los álbumes marcados, cuánto
    /// dura lo seleccionado, cuánto ocupa.
    ///
    /// <para>Lo llevan TODAS, decisión de la maestra: la Mac lo tiene en cada
    /// sección de <c>MediaSectionView</c>. En los listados planos de video la
    /// tarjeta ES el elemento, y aun así el resumen agrega lo que la lista no
    /// muestra: el desglose por tipo, cuánto dura y cuánto ocupa.</para>
    /// </summary>
    public bool ShowsStatusSummary => true;

    private readonly StatusSummaryModel _statusSummary = new();

    /// <summary>
    /// Qué sección se le pide al modelo de resumen, con lo que esa sección
    /// necesita saber de más: la colección abierta en los álbumes de fotos, y el
    /// orden configurado de las colecciones en "Todas las fotos".
    /// </summary>
    private LibraryStatusScope StatusScope => Kind switch
    {
        MediaGridKind.Movies => LibraryStatusSection.Movies,
        MediaGridKind.Series => LibraryStatusSection.Series,
        MediaGridKind.PhotoCollection =>
            new LibraryStatusScope(LibraryStatusSection.PhotoAlbums, PhotoCategory),
        MediaGridKind.AllPhotos =>
            new LibraryStatusScope(LibraryStatusSection.Photos, Collections: _library.PhotoCollections),
        MediaGridKind.AllVideos => LibraryStatusSection.Videos,
        MediaGridKind.Clips =>
            new LibraryStatusScope(LibraryStatusSection.Videos, ClipsOnly: true),
        _ => LibraryStatusSection.Albums
    };

    /// <summary>
    /// El resumen de ahora. El total se recalcula solo cuando cambia el catálogo;
    /// la parte de la selección cuesta lo que mide la selección. Quien lo pide
    /// con rebote es la página: mantener apretada Mayús+flecha no tiene por qué
    /// rearmar el texto en cada tecla.
    /// </summary>
    public LibraryStatusSummary StatusSummary => _statusSummary.Summary(
        _library.Index, StatusScope, _library.CatalogVersion,
        ItemsOf(SelectedCards), _selection.Count);

    public string CountText => Kind switch
    {
        MediaGridKind.Albums => Cards.Count == 1 ? "1 álbum" : $"{Cards.Count} álbumes",
        MediaGridKind.Movies => Cards.Count == 1 ? "1 película" : $"{Cards.Count} películas",
        MediaGridKind.Series => Cards.Count == 1 ? "1 serie" : $"{Cards.Count} series",
        MediaGridKind.PhotoCollection => Cards.Count == 1 ? "1 álbum" : $"{Cards.Count} álbumes",
        MediaGridKind.AllPhotos => AppStrings.LibraryPhotos(Cards.Count),
        _ => Cards.Count == 1 ? "1 video" : $"{Cards.Count} videos"
    };

    public void Show(MediaGridKind kind, string? photoCategory = null)
    {
        // Entrar a una sección la muestra limpia, como antes de ST-201: el
        // modelo es único para las cinco cuadrículas, y lo marcado en Álbumes no
        // significa nada en Fotos —las claves ni siquiera son de la misma clase—.
        //
        // Lo que sí sobrevive ahora es un <see cref="Refresh"/>: aplicar tapas en
        // lote ya no deja al usuario sin la selección con la que las pidió.
        ClearSelection();

        Kind = kind;
        PhotoCategory = photoCategory ?? "";
        Title = TitleFor(kind, PhotoCategory);
        Subtitle = SubtitleFor(kind);
        Refresh();
    }

    private static string TitleFor(MediaGridKind kind, string photoCategory) => kind switch
    {
        MediaGridKind.Albums => AppStrings.NavAlbums,
        MediaGridKind.Movies => AppStrings.NavMovies,
        MediaGridKind.Series => AppStrings.NavSeries,
        MediaGridKind.PhotoCollection => photoCategory,
        MediaGridKind.AllPhotos => AppStrings.NavAllPhotos,
        MediaGridKind.Clips => AppStrings.NavClips,
        _ => AppStrings.NavAllVideos
    };

    private static string SubtitleFor(MediaGridKind kind) => kind switch
    {
        MediaGridKind.Albums => "Los álbumes de tu biblioteca, armados con la metadata de cada canción.",
        MediaGridKind.Movies => "Tus películas.",
        MediaGridKind.Series => "Tus series, con sus temporadas.",
        MediaGridKind.PhotoCollection => "Álbumes de esta colección. Los álbumes son locales: al iPod las fotos viajan sin carpetas.",
        MediaGridKind.AllPhotos => "Todas tus imágenes.",
        MediaGridKind.Clips => "Videos que no son película ni serie.",
        _ => "Todos tus videos."
    };

    /// <summary>
    /// Rehace la cuadrícula <b>por diferencias</b> (ST-201): las tarjetas que
    /// siguen mostrando lo mismo se quedan tal cual —con su contenedor, su
    /// portada ya decodificada y su suscripción—, y la colección solo se entera
    /// de lo que de verdad cambió.
    ///
    /// <para>Antes se tiraban las 1 091 tarjetas y se construían 1 091 nuevas en
    /// cada refresco, aunque no hubiera cambiado nada.</para>
    /// </summary>
    public void Refresh()
    {
        IReadOnlyList<MediaCard> desired = Reconcile(SpecsFor(Kind));

        // Mientras la colección se reacomoda, el control avisa por su cuenta que
        // dejó de tener seleccionado lo que sacó (ST-202). Esos avisos no son
        // una decisión del usuario: si se le hiciera caso, reemplazar la tarjeta
        // de un álbum al que se le acaba de aplicar una tapa lo sacaría de la
        // selección con la que el usuario la pidió.
        _refreshing = true;

        try
        {
            ObservableListSync.Apply(Cards, desired, Subscribe, Unsubscribe);
        }
        finally
        {
            _refreshing = false;
        }

        // Lo que se había seleccionado y ya no está deja de estar seleccionado:
        // si no, seguiría alcanzado por «Solo la selección» sin que nadie lo vea.
        _selection.Retain(_byId.Keys);

        OnPropertyChanged(nameof(IsEmpty));
        OnPropertyChanged(nameof(ShowsEmptyState));
        OnPropertyChanged(nameof(CountText));
        NotifySelectionChanged();

        // Y ahora sí, que el control vuelva a marcar lo que corresponde: las
        // tarjetas que se reemplazaron son instancias nuevas, y para él son
        // otras.
        SelectionSyncRequested?.Invoke(this, SelectedCards);
    }

    /// <summary>
    /// Lo que la cuadrícula debería mostrar, como datos y sin tarjetas. Separar
    /// las dos cosas es lo que permite reusar las que ya existen.
    /// </summary>
    private IEnumerable<MediaCardSpec> SpecsFor(MediaGridKind kind) => kind switch
    {
        MediaGridKind.Albums => _library.Albums().Select(album => new MediaCardSpec(
            album.Id,
            album.Title,
            album.IsUnknownArtist ? album.SubtitleDetail : $"{album.Artist} · {album.SubtitleDetail}",
            album.CoverItem, null)),

        MediaGridKind.Movies => _library.VideoCollections()
            .Where(collection => !collection.IsSeries)
            .Select(movie => new MediaCardSpec(
                movie.Id, movie.Title, movie.Year ?? "", movie.PosterItem, null)),

        MediaGridKind.Series => _library.VideoCollections()
            .Where(collection => collection.IsSeries)
            .Select(series => new MediaCardSpec(
                series.Id, series.Title,
                $"{SeasonsText(series)} · {AppStrings.LibraryEpisodes(series.EpisodeCount)}",
                series.PosterItem, null)),

        MediaGridKind.PhotoCollection => _library.PhotoAlbums(PhotoCategory).Select(album => new MediaCardSpec(
            album.Id, album.Title, AppStrings.LibraryPhotos(album.Count),
            null, album.PreviewPaths.FirstOrDefault())),

        MediaGridKind.AllPhotos => _library.OfKind(LibraryItemKind.Photo).Select(photo => new MediaCardSpec(
            photo.Id.ToString("D"), photo.DisplayTitle, photo.Category ?? "",
            null, photo.PreparedPath ?? photo.SourcePath)),

        MediaGridKind.Clips => _library.Clips().Select(clip => new MediaCardSpec(
            clip.Id.ToString("D"), clip.DisplayTitle, clip.Category ?? "",
            clip.HasCover ? clip : null, null)),

        _ => _library.OfKind(LibraryItemKind.Video).Select(video => new MediaCardSpec(
            video.Id.ToString("D"), video.DisplayTitle, video.Category ?? "",
            video.HasCover ? video : null, null))
    };

    /// <summary>
    /// La lista de tarjetas que corresponde: la que ya existía cuando muestra lo
    /// mismo, una nueva cuando no. Una tarjeta nueva nace con el estado de
    /// selección que le toca — si no, entraría desmarcada aunque su álbum siga
    /// seleccionado.
    /// </summary>
    private IReadOnlyList<MediaCard> Reconcile(IEnumerable<MediaCardSpec> specs)
    {
        List<MediaCard> cards = [];

        foreach (MediaCardSpec spec in specs)
        {
            if (_byId.TryGetValue(spec.Id, out MediaCard? existing) && spec.Matches(existing))
            {
                cards.Add(existing);
                continue;
            }

            MediaCard card = spec.ToCard();
            card.IsSelected = _selection.Contains(spec.Id);
            card.AnySelection = _anySelectionPushed;
            cards.Add(card);
        }

        return cards;
    }

    private void Subscribe(MediaCard card) => _byId[card.Id] = card;

    private void Unsubscribe(MediaCard card)
    {
        // Solo si sigue siendo la que está en el índice: al reemplazar una
        // tarjeta por otra con el mismo id, la nueva entra antes de que salga la
        // vieja, y borrar acá dejaría el índice sin la que sí está en pantalla.
        if (_byId.TryGetValue(card.Id, out MediaCard? current) && ReferenceEquals(current, card))
            _byId.Remove(card.Id);
    }

    private static string SeasonsText(VideoCollectionGroup series)
    {
        int real = series.Seasons.Count(season => season.Number != VideoCollectionGroup.NoSeasonNumber);
        return real == 1 ? "1 temporada" : $"{real} temporadas";
    }

    // MARK: - Selección (ST-103)

    /// <summary>
    /// Lo que está marcado ahora, <b>en el orden de la cuadrícula</b> y calculado
    /// recién cuando alguien pregunta (ST-201): lo consulta el menú contextual,
    /// que se abre una vez, no en cada clic.
    /// </summary>
    public IReadOnlyList<MediaCard> SelectedCards =>
        _selectedCards ??= _selection.Count == 0
            ? []
            : [.. Cards.Where(card => _selection.Contains(card.Id))];

    /// <summary>Cuántos hay marcados. O(1): lo sabe el modelo de selección.</summary>
    public int SelectedCount => _selection.Count;

    /// <summary>
    /// Pide que el control vuelva a marcar lo que dice el modelo. Sale después
    /// de cada <see cref="Refresh"/>, con las tarjetas que tienen que quedar
    /// seleccionadas (ST-202).
    /// </summary>
    public event EventHandler<IReadOnlyList<MediaCard>>? SelectionSyncRequested;

    /// <summary>
    /// <b>La selección la lleva el control</b> (ST-202): acá solo se anota lo
    /// que decidió. Es lo que hace que un clic, Ctrl+clic, Mayús+clic,
    /// Mayús+flechas y Ctrl+A funcionen sin una línea de lógica de selección
    /// propia — antes estaban reimplementados a mano, y solo el clic simple.
    ///
    /// <para>Llega el <b>delta</b>, no la selección entera: con 1 000 álbumes
    /// marcados, releer la lista completa del control en cada cambio sería
    /// volver a pagar por tecla lo que ST-201 sacó del camino.</para>
    /// </summary>
    public void SyncFromControl(IReadOnlyList<MediaCard> added, IReadOnlyList<MediaCard> removed)
    {
        // Durante un refresco, el control avisa que soltó lo que se le sacó de
        // la colección. Eso no es una decisión del usuario.
        if (_refreshing) return;

        bool changed = false;

        foreach (MediaCard card in removed)
        {
            if (!_selection.Set(card.Id, false).IsEmpty) changed = true;
            card.IsSelected = false;
        }

        foreach (MediaCard card in added)
        {
            if (!_selection.Set(card.Id, true).IsEmpty) changed = true;
            card.IsSelected = true;
        }

        if (!changed) return;

        // El alcance de sincronización se corrige con lo que cambió, no
        // rearmándolo entero: sumar el álbum 1 000 tiene que costar lo que ese
        // álbum trae, no los 12 000 identificadores de toda la selección.
        LibraryCatalogIndex index = _library.Index;

        _library.Selection.Apply(
            index.ItemIdsForKeys(GroupKind, added.Select(card => card.Id)),
            index.ItemIdsForKeys(GroupKind, removed.Select(card => card.Id)));

        NotifySelectionChanged(publishSelection: false);
    }

    /// <summary>
    /// Deja el modelo sin selección. Al control se lo dice la página, que es la
    /// que lo tiene.
    /// </summary>
    public void ClearSelection()
    {
        SelectionDelta delta = _selection.Clear();
        if (delta.IsEmpty) return;

        foreach (string id in delta.Deselected)
            if (_byId.TryGetValue(id, out MediaCard? card)) card.IsSelected = false;

        NotifySelectionChanged();
    }

    /// <param name="publishSelection">
    /// <c>false</c> cuando quien llama ya corrigió el alcance de sincronización
    /// con el delta, que es más barato que rearmarlo entero (ST-202).
    /// </param>
    private void NotifySelectionChanged(bool publishSelection = true)
    {
        // R2-1: en cuanto hay algo seleccionado, TODAS las tarjetas muestran su
        // casilla. Cada tarjeta necesita saberlo, así que el dato se empuja —
        // pero solo cuando la respuesta CAMBIA (ST-201). Antes se escribía en
        // las 1 091 en cada clic para decirles lo que ya sabían; ahora ese
        // recorrido ocurre a lo sumo dos veces por gesto de selección: al marcar
        // el primero y al quedarse sin ninguno.
        bool any = _selection.Any;

        if (any != _anySelectionPushed)
        {
            _anySelectionPushed = any;
            foreach (MediaCard card in Cards) card.AnySelection = any;
        }

        _selectedCards = null;

        // R3-4: lo seleccionado acá es lo que puede alcanzar «Solo la
        // selección» de General. Una tarjeta es un álbum o una serie, así que lo
        // que viaja son sus CANCIONES, no la tarjeta. Con el índice cuesta lo
        // que suman los grupos marcados, no lo que mide la biblioteca.
        if (publishSelection)
        {
            _library.PublishSelectionForSync(
                _library.Index.ItemIdsForKeys(GroupKind, _selection.Ids));
        }

        OnPropertyChanged(nameof(SelectedCards));
        OnPropertyChanged(nameof(SelectedCount));
        OnPropertyChanged(nameof(HasSelection));
        OnPropertyChanged(nameof(SelectionText));
    }

    public bool HasSelection => _selection.Any;

    /// <summary>Cuántos hay marcados, dicho en la barra de estado.</summary>
    public string SelectionText => SelectedCount switch
    {
        0 => "",
        1 => "1 seleccionado",
        int count => $"{count} seleccionados"
    };

    // MARK: - Lo que necesitan los menús contextuales

    /// <summary>
    /// Las canciones/videos/fotos que hay detrás de las tarjetas alcanzadas.
    ///
    /// <para>Cuesta lo que suman los grupos alcanzados, no lo que mide el
    /// catálogo (ST-201). Antes recorría los 12 000 elementos normalizando dos
    /// cadenas por elemento, una vez por pregunta.</para>
    /// </summary>
    public IReadOnlyList<LibraryItem> ItemsOf(IReadOnlyList<MediaCard> cards) =>
        _library.Index.ItemsForKeys(GroupKind, cards.Select(card => card.Id));

    public IReadOnlyList<Guid> SongIdsOf(IReadOnlyList<MediaCard> cards) =>
        _library.Index.ItemIdsForKeys(GroupKind, cards.Select(card => card.Id));

    /// <summary>El alcance, contado en <b>tarjetas</b> —álbumes, series— y no en canciones.</summary>
    public MenuScope ScopeOf(IReadOnlyList<MediaCard> cards)
    {
        IReadOnlyList<LibraryItem> items = ItemsOf(cards);

        // Artistas ya no es una cuadrícula (R2-6): las fotos de artista y su
        // menú viven en `ArtistsPage`, que arma su propio alcance.
        return new MenuScope(
            cards.Count,
            AllFavorite: items.Count > 0 && items.All(item => item.Metadata?.IsFavorite == true),
            SingleAlbumWithTitle: Kind == MediaGridKind.Albums && cards.Count == 1
                                  && items.FirstOrDefault()?.Metadata?.Album is { Length: > 0 },
            AnyNamedAlbum: AnyNamedAlbumIn(cards, items),
            ApplyingRecommendedCover: IsApplyingRecommendedCover,
            AlbumCount: NamedAlbumCount(cards));
    }

    /// <summary>
    /// Qué cuenta como "álbum con nombre propio" según lo que la cuadrícula
    /// esté mostrando. Son dos preguntas distintas con el mismo nombre:
    ///
    /// <list type="bullet">
    /// <item>En <b>Álbumes</b> (§1) decide si hay algo a lo que recomendarle
    /// tapa. "Sin álbum" no es un disco sino el cajón de lo que no tiene uno:
    /// no hay tapa que buscarle.</item>
    /// <item>En <b>álbumes de fotos</b> (§8) decide si se puede renombrar o
    /// disolver. Ahí "Sin álbum" tampoco es un álbum de verdad.</item>
    /// </list>
    /// </summary>
    private bool AnyNamedAlbumIn(IReadOnlyList<MediaCard> cards, IReadOnlyList<LibraryItem> items) =>
        Kind == MediaGridKind.Albums
            ? items.Any(item => item.Metadata?.Album is { Length: > 0 })
            : cards.Any(card => card.Id.Length > 0);

    /// <summary>
    /// Cuántos de los álbumes alcanzados tienen <b>título propio</b> (ST-206).
    /// Es lo que decide si "Buscar carátulas..." aparece en plural.
    ///
    /// <para>Fuera de Álbumes es cero: en Películas o en Fotos no hay discos que
    /// contar, y devolver otra cosa haría aparecer el ítem donde no va.</para>
    /// </summary>
    private int NamedAlbumCount(IReadOnlyList<MediaCard> cards)
    {
        if (Kind != MediaGridKind.Albums) return 0;

        LibraryCatalogIndex index = _library.Index;

        return cards.Count(
            card => index.ByAlbumKey(card.Id).FirstOrDefault()?.Metadata?.Album is { Length: > 0 });
    }

    // MARK: - Carátula recomendada (R2-3)

    /// <summary>
    /// Mientras dura la operación el ítem del menú se ve <b>deshabilitado</b>:
    /// que desaparezca a mitad de camino deja al usuario pensando que se rompió.
    ///
    /// <para>Lo lleva la biblioteca desde ST-206, no la cuadrícula: el mismo
    /// lote se puede haber pedido desde la tabla de Canciones, y el ítem tiene
    /// que verse deshabilitado igual.</para>
    /// </summary>
    public bool IsApplyingRecommendedCover => _library.IsApplyingRecommendedCover;

    /// <summary>Un álbum al que se le puede recomendar tapa, con los hechos que se puntúan.</summary>
    public sealed record AlbumCoverTarget(
        MediaCard Card, string AlbumKey, string Title, string? Artist, AlbumFacts Facts);

    /// <summary>
    /// Los álbumes alcanzados que tienen <b>título propio</b>. "Sin álbum" no es
    /// un disco sino el cajón de lo que no tiene uno: no hay tapa que buscarle.
    ///
    /// <para>Una consulta al índice por álbum, en O(1) cada una (ST-201). Antes
    /// filtraba los 12 000 elementos <b>por cada tarjeta alcanzada</b>: con
    /// 1 000 álbumes marcados, doce millones de claves normalizadas para armar
    /// un menú.</para>
    /// </summary>
    public IReadOnlyList<AlbumCoverTarget> AlbumCoverTargets(IReadOnlyList<MediaCard> cards)
    {
        if (Kind != MediaGridKind.Albums) return [];

        LibraryCatalogIndex index = _library.Index;
        List<AlbumCoverTarget> targets = [];

        foreach (MediaCard card in cards)
        {
            IReadOnlyList<LibraryItem> tracks = index.ByAlbumKey(card.Id);
            if (tracks.Count == 0) continue;

            LibraryItem first = tracks[0];
            if (first.Metadata?.Album is not { Length: > 0 } title) continue;

            targets.Add(new AlbumCoverTarget(
                card, card.Id, title, first.Metadata?.Artist,
                new AlbumFacts(title, first.Metadata?.Year, tracks.Count)));
        }

        return targets;
    }

    /// <summary>
    /// Aplica la recomendada a cada álbum alcanzado, <b>sin preguntar y solo
    /// donde el puntaje supera el umbral</b> de <c>docs/caratula-recomendada.md</c>.
    ///
    /// <para>Lo que no lo supera no se toca y vuelve en <c>Pending</c>: aplicar
    /// a ciegas una tapa dudosa a veinte álbumes es exactamente el daño que el
    /// umbral evita. Y no marca <c>MetadataEditedByUser</c> — eso significa "el
    /// usuario lo decidió", y acá no lo decidió nadie.</para>
    /// </summary>
    public async Task<(int Applied, IReadOnlyList<AlbumCoverTarget> Pending)> ApplyRecommendedCoversAsync(
        IReadOnlyList<MediaCard> cards, bool deezerEnabled, CancellationToken ct = default)
    {
        IReadOnlyList<AlbumCoverTarget> targets = AlbumCoverTargets(cards);
        if (targets.Count == 0) return (0, []);

        // ST-206: el lote lo corre la biblioteca, que es de donde también lo
        // pide la tabla de Canciones. Tenerlo dos veces sería tener dos
        // criterios de "tapa segura" esperando a divergir — y solo uno de los
        // dos aparecería en el centro de tareas.
        AlbumCoverBatchResult result = await _library.ApplyRecommendedCoversAsync(
            [.. targets.Select(target =>
                new AlbumCoverJob(target.AlbumKey, target.Title, target.Artist, target.Facts))],
            deezerEnabled, ct);

        // De vuelta a tarjetas: quien abre el selector las necesita para
        // refrescar la cuadrícula.
        Dictionary<string, AlbumCoverTarget> byKey = [];
        foreach (AlbumCoverTarget target in targets) byKey.TryAdd(target.AlbumKey, target);

        List<AlbumCoverTarget> pending = [];
        foreach (AlbumCoverJob job in result.Pending)
        {
            if (byKey.TryGetValue(job.AlbumKey, out AlbumCoverTarget? target)) pending.Add(target);
        }

        // Con algo aplicado, el aviso de la biblioteca ya rehace esta cuadrícula
        // (OnLibraryChanged); sin nada aplicado, nadie avisó.
        if (result.Applied == 0) Refresh();

        return (result.Applied, pending);
    }

    /// <summary>Abre con el visor del sistema. No hay uno propio, y no hace falta.</summary>
    public void OpenWithSystemViewer(IReadOnlyList<MediaCard> cards)
    {
        foreach (LibraryItem item in ItemsOf(cards))
        {
            string path = item.PreparedPath is { Length: > 0 } prepared && File.Exists(prepared)
                ? prepared
                : item.SourcePath;

            if (!File.Exists(path)) continue;

            try
            {
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(path)
                {
                    UseShellExecute = true
                });
            }
            catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or IOException)
            {
                // Sin aplicación asociada no se puede abrir, y no es un error
                // que valga interrumpir nada.
            }
        }
    }

    /// <summary>
    /// Saca las fotos de su álbum. <b>No borra nada</b>: quedan en la
    /// biblioteca, sin álbum.
    /// </summary>
    public void RemoveFromAlbum(IReadOnlyList<MediaCard> cards)
    {
        int moved = 0;

        foreach (LibraryItem item in ItemsOf(cards).Where(item => item.PhotoAlbum is { Length: > 0 }))
        {
            item.PhotoAlbum = null;
            moved++;
        }

        if (moved == 0) return;

        _library.SaveAndRefresh();
        Refresh();
        _library.StatusMessage = moved == 1 ? "Se quitó 1 foto de su álbum." : $"Se quitaron {moved} fotos de su álbum.";
    }

    /// <summary>
    /// Deshace los álbumes alcanzados: las fotos se quedan, sin álbum. Es lo
    /// mismo que quitarlas una por una, dicho de otra forma.
    /// </summary>
    public void DissolveAlbums(IReadOnlyList<MediaCard> cards)
    {
        RemoveFromAlbum(cards);
        Refresh();
    }

    public void RenameAlbum(MediaCard card, string name)
    {
        string trimmed = name.Trim();
        if (trimmed.Length == 0) return;

        foreach (LibraryItem item in ItemsOf([card])) item.PhotoAlbum = trimmed;

        _library.SaveAndRefresh();
        Refresh();
    }

    public void RevealInExplorer(IReadOnlyList<MediaCard> cards)
    {
        // Con una sola tarjeta alcanza con revelar una canción; con varias, se
        // revelan todas — mismo criterio que macOS.
        foreach (LibraryItem item in cards.Count == 1 ? ItemsOf(cards).Take(1) : ItemsOf(cards))
            Views.FilePickers.RevealInExplorer(item.SourcePath);
    }

    public (MusicScope Scope, string Title, string Subtitle)? Open(MediaCard card) => Kind switch
    {
        MediaGridKind.Albums => (new MusicScope.Album(card.Id), card.Title, card.Subtitle),
        MediaGridKind.Movies or MediaGridKind.Series =>
            (new MusicScope.VideoCollection(card.Id), card.Title, card.Subtitle),
        MediaGridKind.PhotoCollection => (new MusicScope.PhotoAlbum(card.Id), card.Title, card.Subtitle),
        _ => null
    };
}
