using CommunityToolkit.Mvvm.ComponentModel;
using AuraStudio.Core.Library;

namespace AuraStudio.App.ViewModels;

/// <summary>Una fila de la lista de artistas: avatar y nombre, nada más.</summary>
public sealed partial class ArtistRow(ArtistGroup group, byte[]? photo, LibraryItem? fallbackCover) : ObservableObject
{
    public ArtistGroup Group { get; } = group;

    public string Id => Group.Id;

    public string Name => Group.Name;

    /// <summary>
    /// La foto del artista si la hay (ST-032); si no, la portada de alguno de
    /// sus álbumes. Sin ninguna de las dos, la vista dibuja la inicial: nunca
    /// un cuadro vacío.
    /// </summary>
    /// <summary>La foto del artista (ST-032), si la hay. Es chica y se lee al armar la lista.</summary>
    public byte[]? PhotoData { get; } = photo;

    /// <summary>
    /// A falta de foto, de dónde sacar la portada de alguno de sus álbumes
    /// (ST-208): una REFERENCIA, no la imagen — la pide la vista al dibujar.
    /// </summary>
    public LibraryItem? FallbackCoverItem { get; } = fallbackCover;

    public bool HasAvatar => PhotoData is { Length: > 0 } || FallbackCoverItem is not null;

    public string Initial => Name.Length > 0 ? Name[..1].ToUpperInvariant() : "?";
}

/// <summary>Una canción dentro de la ficha del artista.</summary>
public sealed partial class ArtistTrackRow(LibraryItem item, int position, string artistKey) : ObservableObject
{
    public LibraryItem Item { get; } = item;

    public Guid Id => Item.Id;

    /// <summary>El número de pista real; a falta de él, la posición en el álbum.</summary>
    public string Position { get; } =
        item.Metadata?.TrackNumber?.ToString(System.Globalization.CultureInfo.CurrentCulture)
        ?? position.ToString(System.Globalization.CultureInfo.CurrentCulture);

    public string Title => Item.DisplayTitle;

    public string DurationText => new MediaTableRow(Item).DurationText;

    /// <summary>
    /// El artista de la pista se muestra <b>solo cuando difiere</b> del artista
    /// del grupo. Es lo que hace legible la homologación de R2-4: dentro de
    /// "Gorillaz", la canción acreditada a "Gorillaz feat. De La Soul" dice a
    /// quién más tiene, y las demás no repiten el nombre en cada renglón.
    /// </summary>
    public bool ShowsArtist =>
        Item.Metadata?.Artist is { Length: > 0 } artist
        && LibraryGrouping.Normalize(artist) != artistKey;

    public string TrackArtist => Item.Metadata?.Artist ?? "";

    [ObservableProperty] public partial bool IsFavorite { get; set; } = item.Metadata?.IsFavorite == true;

    /// <summary>Estrella llena o vacía, según el estado.</summary>
    public string FavoriteGlyph => IsFavorite ? "" : "";

    /// <summary>
    /// Lo que anuncia un lector de pantalla en el botón de la estrella. Lleva
    /// el título adentro a propósito: veinte botones que dicen "Favorito" no le
    /// sirven a nadie que no vea la fila.
    /// </summary>
    public string FavoriteLabel =>
        (IsFavorite ? "Quitar de favoritos: " : "Marcar como favorito: ") + Title;

    partial void OnIsFavoriteChanged(bool value)
    {
        OnPropertyChanged(nameof(FavoriteGlyph));
        OnPropertyChanged(nameof(FavoriteLabel));
    }
}

/// <summary>Un álbum dentro de la ficha del artista, con sus canciones.</summary>
public sealed partial class ArtistAlbumRow(AlbumGroup album, string artistKey) : ObservableObject
{
    public AlbumGroup Album { get; } = album;

    public string Title => Album.Title;

    /// <summary>"Rock · 2005" — las dos partes son opcionales.</summary>
    public string Detail { get; } =
        string.Join(" · ", new[] { album.Genre, album.Year }.Where(part => part is { Length: > 0 }));

    public string CountText => Album.TrackCount == 1 ? "1 canción" : $"{Album.TrackCount} canciones";

    public bool IsFavorite => Album.IsFavorite;

    /// <summary>De dónde sale la tapa del álbum (ST-208); la imagen se pide al dibujar.</summary>
    public LibraryItem? CoverItem => Album.CoverItem;

    public bool HasCover => CoverItem is not null;

    public IReadOnlyList<ArtistTrackRow> Tracks { get; } =
        [.. album.Items.Select((item, index) => new ArtistTrackRow(item, index + 1, artistKey))];
}

/// <summary>
/// La sección «Artistas» (R2-6, ST-121): <b>maestro-detalle</b>, como la de
/// macOS. A la izquierda la lista de artistas con su avatar; a la derecha la
/// ficha del seleccionado, con sus álbumes uno debajo del otro y las canciones
/// de cada uno.
///
/// <para>Antes esta vista era la misma cuadrícula de tarjetas que Álbumes, con
/// casillas de selección (ST-108). El dueño la vio y dictaminó que no se parece
/// en nada a la de macOS, así que <b>aquella divergencia queda revocada</b>. La
/// selección vuelve a ser la nativa de una lista —Ctrl y Mayús, como en el
/// Explorador—, que es el equivalente exacto de lo que hace macOS acá y, de
/// paso, deja esta vista fuera de la regla de casillas de R2-1.</para>
///
/// <para>Es también la vista donde se ve la homologación de R2-4: los tres
/// "Gorillaz" de una biblioteca real tienen que ser <b>una sola fila</b>.</para>
/// </summary>
public sealed partial class ArtistsViewModel : ViewModelBase
{
    private readonly LibraryViewModel _library;

    public ArtistsViewModel(LibraryViewModel library)
    {
        _library = library;
        _library.PropertyChanged += OnLibraryChanged;
        Artists = [];
        VisibleArtists = [];
        SelectedAlbums = [];
        SearchText = "";
    }

    /// <summary>
    /// Igual que la cuadrícula (ST-161): la lista se rehace ante cambios de
    /// <b>contenido</b> de la biblioteca, no ante cualquier aviso suyo.
    /// <see cref="Refresh"/> termina en <see cref="SetSelection"/>, que publica
    /// la selección; escuchar ese aviso cerraba el mismo ciclo sin fin que
    /// colgaba la app en Álbumes.
    /// </summary>
    private void OnLibraryChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (ChangesLibraryContent(e.PropertyName))
        {
            Refresh();
            return;
        }

        // ST-203: mientras carga la lista está vacía, y eso no es "no hay
        // música en la biblioteca".
        if (e.PropertyName == nameof(LibraryViewModel.IsLoading))
            OnPropertyChanged(nameof(ShowsEmptyState));
    }

    /// <summary>Nombre vacío o <c>null</c> es "cambió todo": eso sí obliga a rehacer.</summary>
    private static bool ChangesLibraryContent(string? propertyName) =>
        string.IsNullOrEmpty(propertyName)
        || propertyName == nameof(LibraryViewModel.Items)
        || propertyName == nameof(LibraryViewModel.AvailableItems);

    public LibraryViewModel Library => _library;

    [ObservableProperty] public partial IReadOnlyList<ArtistRow> Artists { get; private set; }

    [ObservableProperty] public partial IReadOnlyList<ArtistRow> VisibleArtists { get; private set; }

    [ObservableProperty] public partial IReadOnlyList<ArtistAlbumRow> SelectedAlbums { get; private set; }

    [ObservableProperty] public partial string SearchText { get; set; }

    partial void OnSearchTextChanged(string value) => ApplyFilter();

    /// <summary>
    /// Lo que está seleccionado en la lista. Lo empuja la pantalla desde el
    /// control: la selección múltiple la lleva el <c>ListView</c>, no el modelo
    /// — al revés que en las cuadrículas, y a propósito.
    /// </summary>
    public IReadOnlyList<ArtistRow> Selection { get; private set; } = [];

    public void SetSelection(IReadOnlyList<ArtistRow> rows)
    {
        Selection = rows;

        SelectedAlbums = rows is [{ } single]
            ? [.. single.Group.Albums.Select(album => new ArtistAlbumRow(album, single.Id))]
            : [];

        // R3-4: alimenta «Solo la selección» de General con las canciones de
        // los artistas elegidos.
        _library.PublishSelectionForSync(SongIdsOf(rows));

        OnPropertyChanged(nameof(Selection));
        OnPropertyChanged(nameof(SelectedArtist));
        OnPropertyChanged(nameof(HasSingleSelection));
        OnPropertyChanged(nameof(HasMultipleSelection));
        OnPropertyChanged(nameof(ShowsEmptyDetail));
        OnPropertyChanged(nameof(SelectionSummary));
        OnPropertyChanged(nameof(StatusText));
        OnPropertyChanged(nameof(SelectionAllFavorite));
        OnPropertyChanged(nameof(FavoriteButtonText));
    }

    /// <summary>El artista de la ficha; <c>null</c> con 0 o más de 1 seleccionados.</summary>
    public ArtistRow? SelectedArtist => Selection is [{ } only] ? only : null;

    public bool HasSingleSelection => SelectedArtist is not null;

    public bool HasMultipleSelection => Selection.Count > 1;

    public bool ShowsEmptyDetail => Selection.Count == 0;

    public string SelectionSummary => $"{Selection.Count} artistas seleccionados";

    public bool SelectionAllFavorite
    {
        get
        {
            IReadOnlyList<LibraryItem> items = SelectedItems;
            return items.Count > 0 && items.All(item => item.Metadata?.IsFavorite == true);
        }
    }

    public string FavoriteButtonText => SelectionAllFavorite ? "Quitar favorito" : "Marcar como favorito";

    public IReadOnlyList<LibraryItem> SelectedItems => [.. Selection.SelectMany(row => row.Group.Items)];

    public bool IsEmpty => Artists.Count == 0;

    /// <summary>
    /// Cuándo sale el cartel de "todavía no hay música" (ST-203): <b>no mientras
    /// carga</b>. El avance se ve en la franja de estado, que es lo que de verdad
    /// está pasando.
    /// </summary>
    public bool ShowsEmptyState => Artists.Count == 0 && !_library.IsLoading;

    /// <summary>
    /// Artistas, álbumes y canciones de lo que se está viendo, más la selección
    /// (ST-063). Cuenta lo <b>visible</b>: con un filtro escrito, decir el total
    /// de la biblioteca sería mentir sobre lo que hay en pantalla.
    /// </summary>
    public string StatusText
    {
        get
        {
            int artists = VisibleArtists.Count;
            int albums = VisibleArtists.Sum(row => row.Group.Albums.Count);
            int songs = VisibleArtists.Sum(row => row.Group.TrackCount);

            string counts = $"{artists} {(artists == 1 ? "artista" : "artistas")} · " +
                            $"{albums} {(albums == 1 ? "álbum" : "álbumes")} · " +
                            $"{songs} {(songs == 1 ? "canción" : "canciones")}";

            return Selection.Count > 1 ? $"{counts} · {Selection.Count} seleccionados" : counts;
        }
    }

    public void Refresh()
    {
        var store = new ArtistImageStore(_library.LibraryPath);

        Artists =
        [
            .. _library.Artists().Select(group =>
                new ArtistRow(group, store.Image(group.Id), group.FallbackCoverItem))
        ];

        ApplyFilter();

        // La selección se rehace por id: tras recargar la biblioteca los grupos
        // son objetos nuevos, y quedarse con los viejos dejaría la ficha
        // mostrando canciones que ya no están.
        var ids = Selection.Select(row => row.Id).ToHashSet(StringComparer.Ordinal);
        IReadOnlyList<ArtistRow> restored = [.. Artists.Where(row => ids.Contains(row.Id))];

        SetSelection(restored.Count > 0 ? restored : Artists.Count > 0 ? [Artists[0]] : []);

        OnPropertyChanged(nameof(IsEmpty));
        OnPropertyChanged(nameof(ShowsEmptyState));
    }

    /// <summary>
    /// Filtra por nombre, sin distinguir mayúsculas ni acentos — la misma
    /// normalización con la que se agrupa, para que buscar "cafe" encuentre
    /// "Café Tacvba".
    /// </summary>
    private void ApplyFilter()
    {
        string needle = LibraryGrouping.Normalize(SearchText);

        VisibleArtists = needle.Length == 0
            ? Artists
            : [.. Artists.Where(row => LibraryGrouping.Normalize(row.Name).Contains(needle, StringComparison.Ordinal))];

        OnPropertyChanged(nameof(StatusText));
    }

    /// <summary>
    /// El criterio Finder, con la selección que lleva el propio control: clic
    /// derecho sobre algo ya seleccionado alcanza a toda la selección; sobre
    /// algo que no lo está, solo a eso.
    /// </summary>
    public IReadOnlyList<ArtistRow> EffectiveArtists(ArtistRow clicked) =>
        Selection.Any(row => row.Id == clicked.Id) ? Selection : [clicked];

    public MenuScope ScopeOf(IReadOnlyList<ArtistRow> rows)
    {
        IReadOnlyList<LibraryItem> items = [.. rows.SelectMany(row => row.Group.Items)];
        var store = new ArtistImageStore(_library.LibraryPath);
        int withPhoto = rows.Count(row => store.Image(row.Id) is not null);

        return new MenuScope(
            rows.Count,
            AllFavorite: items.Count > 0 && items.All(item => item.Metadata?.IsFavorite == true),
            HasArtistPhoto: withPhoto > 0,
            ArtistsWithPhotoCount: withPhoto);
    }

    public IReadOnlyList<Guid> SongIdsOf(IReadOnlyList<ArtistRow> rows) =>
        [.. rows.SelectMany(row => row.Group.Items).Select(item => item.Id)];

    public void RemoveArtistPhoto(IReadOnlyList<ArtistRow> rows)
    {
        var store = new ArtistImageStore(_library.LibraryPath);

        foreach (ArtistRow row in rows) store.Remove(row.Id);

        Refresh();
    }

    public void ToggleFavorite(ArtistTrackRow track)
    {
        bool next = !track.IsFavorite;
        _library.SetFavorite([track.Id], next);
        track.IsFavorite = next;
    }
}
