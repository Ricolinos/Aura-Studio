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
/// Una tarjeta de la cuadrícula. Deliberadamente plana: la cuadrícula no sabe si
/// atrás hay un álbum, una serie o una carpeta de fotos, solo dibuja tarjetas.
/// </summary>
/// <param name="CoverData">Carátula o póster embebido; <c>null</c> si no hay.</param>
/// <param name="ImagePath">Imagen de archivo, para las tarjetas de fotos.</param>
public sealed partial class MediaCard(
    string id, string title, string subtitle, byte[]? coverData, string? imagePath) : ObservableObject
{
    public string Id { get; } = id;
    public string Title { get; } = title;
    public string Subtitle { get; } = subtitle;
    public byte[]? CoverData { get; } = coverData;
    public string? ImagePath { get; } = imagePath;

    public bool HasCover => CoverData is { Length: > 0 } || ImagePath is { Length: > 0 };

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

    [ObservableProperty]
    public partial IReadOnlyList<MediaCard> Cards { get; private set; }

    [ObservableProperty]
    public partial string Title { get; private set; }

    [ObservableProperty]
    public partial string Subtitle { get; private set; }

    public MediaGridViewModel(LibraryViewModel library)
    {
        _library = library;
        _library.PropertyChanged += (_, _) => Refresh();
        Cards = [];
        Title = "";
        Subtitle = "";
    }

    public LibraryViewModel Library => _library;

    public MediaGridKind Kind { get; private set; } = MediaGridKind.Albums;

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

    public void Refresh()
    {
        Cards = Kind switch
        {
            MediaGridKind.Albums =>
            [
                .. _library.Albums().Select(album => new MediaCard(
                    album.Id,
                    album.Title,
                    album.IsUnknownArtist ? album.SubtitleDetail : $"{album.Artist} · {album.SubtitleDetail}",
                    album.CoverArtData, null))
            ],

            MediaGridKind.Movies =>
            [
                .. _library.VideoCollections()
                    .Where(collection => !collection.IsSeries)
                    .Select(movie => new MediaCard(
                        movie.Id, movie.Title, movie.Year ?? "", movie.PosterData, null))
            ],

            MediaGridKind.Series =>
            [
                .. _library.VideoCollections()
                    .Where(collection => collection.IsSeries)
                    .Select(series => new MediaCard(
                        series.Id, series.Title,
                        $"{SeasonsText(series)} · {AppStrings.LibraryEpisodes(series.EpisodeCount)}",
                        series.PosterData, null))
            ],

            MediaGridKind.PhotoCollection =>
            [
                .. _library.PhotoAlbums(PhotoCategory).Select(album => new MediaCard(
                    album.Id, album.Title, AppStrings.LibraryPhotos(album.Count),
                    null, album.PreviewPaths.FirstOrDefault()))
            ],

            MediaGridKind.AllPhotos =>
            [
                .. _library.OfKind(LibraryItemKind.Photo).Select(photo => new MediaCard(
                    photo.Id.ToString("D"), photo.DisplayTitle, photo.Category ?? "",
                    null, photo.PreparedPath ?? photo.SourcePath))
            ],

            MediaGridKind.Clips =>
            [
                .. _library.Clips().Select(clip => new MediaCard(
                    clip.Id.ToString("D"), clip.DisplayTitle, clip.Category ?? "",
                    clip.Metadata?.CoverArtData, null))
            ],

            _ =>
            [
                .. _library.OfKind(LibraryItemKind.Video).Select(video => new MediaCard(
                    video.Id.ToString("D"), video.DisplayTitle, video.Category ?? "",
                    video.Metadata?.CoverArtData, null))
            ]
        };

        // La casilla escribe directo en la tarjeta —así también funciona con el
        // teclado y con un lector de pantalla—, así que los conteos se enteran
        // escuchándola, no interceptando el clic.
        foreach (MediaCard card in Cards)
            card.PropertyChanged += OnCardChanged;

        OnPropertyChanged(nameof(IsEmpty));
        OnPropertyChanged(nameof(CountText));
        NotifySelectionChanged();
    }

    private void OnCardChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(MediaCard.IsSelected)) NotifySelectionChanged();
    }

    private static string SeasonsText(VideoCollectionGroup series)
    {
        int real = series.Seasons.Count(season => season.Number != VideoCollectionGroup.NoSeasonNumber);
        return real == 1 ? "1 temporada" : $"{real} temporadas";
    }

    /// <summary>El ámbito de la tabla al abrir una tarjeta; <c>null</c> si la tarjeta no abre nada.</summary>
    // MARK: - Selección (ST-103)

    /// <summary>Lo que está marcado ahora. Vacío casi siempre, y eso está bien.</summary>
    public IReadOnlyList<MediaCard> SelectedCards => [.. Cards.Where(card => card.IsSelected)];

    public int SelectedCount => Cards.Count(card => card.IsSelected);

    /// <summary>
    /// La casilla <b>alterna</b> ese elemento sin tocar el resto. Es
    /// acumulativa a propósito: para eso existe, y es lo que la distingue del
    /// clic en la tarjeta.
    /// </summary>
    public void ToggleSelection(MediaCard card)
    {
        card.IsSelected = !card.IsSelected;
        NotifySelectionChanged();
    }

    /// <summary>
    /// El clic en la tarjeta <b>reemplaza</b> la selección, como en macOS y como
    /// en cualquier cuadrícula del sistema.
    /// </summary>
    public void SelectOnly(MediaCard card)
    {
        foreach (MediaCard other in Cards) other.IsSelected = ReferenceEquals(other, card);
        NotifySelectionChanged();
    }

    public void ClearSelection()
    {
        foreach (MediaCard card in Cards) card.IsSelected = false;
        NotifySelectionChanged();
    }

    private void NotifySelectionChanged()
    {
        // R2-1: en cuanto hay algo seleccionado, TODAS las tarjetas muestran su
        // casilla. Cada tarjeta necesita saberlo, así que el dato se empuja en
        // vez de que cada una consulte a la cuadrícula.
        bool any = SelectedCount > 0;
        foreach (MediaCard card in Cards) card.AnySelection = any;

        // R3-4: lo seleccionado acá es lo que puede alcanzar «Solo la
        // selección» de General. Una tarjeta es un álbum o un artista, así que
        // lo que viaja son sus CANCIONES, no la tarjeta.
        _library.PublishSelectionForSync(SongIdsOf(SelectedCards));

        OnPropertyChanged(nameof(SelectedCards));
        OnPropertyChanged(nameof(SelectedCount));
        OnPropertyChanged(nameof(HasSelection));
        OnPropertyChanged(nameof(SelectionText));
    }

    public bool HasSelection => SelectedCount > 0;

    /// <summary>Cuántos hay marcados, dicho en la barra de estado.</summary>
    public string SelectionText => SelectedCount switch
    {
        0 => "",
        1 => "1 seleccionado",
        int count => $"{count} seleccionados"
    };

    // MARK: - Lo que necesitan los menús contextuales

    /// <summary>Las canciones/videos/fotos que hay detrás de las tarjetas alcanzadas.</summary>
    public IReadOnlyList<LibraryItem> ItemsOf(IReadOnlyList<MediaCard> cards)
    {
        var ids = cards.Select(card => card.Id).ToHashSet(StringComparer.Ordinal);

        return Kind switch
        {
            MediaGridKind.Albums =>
                [.. _library.AvailableItems.Where(item => item.Kind == LibraryItemKind.Music
                                                          && ids.Contains(LibraryGrouping.AlbumKeyOf(item, _library.ArtistGrouping)))],

            MediaGridKind.Movies or MediaGridKind.Series =>
                [.. _library.AvailableItems.Where(item => item.Kind == LibraryItemKind.Video
                                                          && ids.Contains(LibraryGrouping.VideoCollectionKeyOf(item)))],

            // Fotos y los listados planos: la tarjeta ES el elemento.
            _ => [.. _library.AvailableItems.Where(item => ids.Contains(item.Id.ToString("D")))]
        };
    }

    public IReadOnlyList<Guid> SongIdsOf(IReadOnlyList<MediaCard> cards) =>
        [.. ItemsOf(cards).Select(item => item.Id)];

    /// <summary>El alcance, contado en <b>tarjetas</b> —álbumes, artistas— y no en canciones.</summary>
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
            ApplyingRecommendedCover: IsApplyingRecommendedCover);
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

    // MARK: - Carátula recomendada (R2-3)

    /// <summary>
    /// Mientras dura la operación el ítem del menú se ve <b>deshabilitado</b>:
    /// que desaparezca a mitad de camino deja al usuario pensando que se rompió.
    /// </summary>
    [ObservableProperty] public partial bool IsApplyingRecommendedCover { get; private set; }

    /// <summary>Un álbum al que se le puede recomendar tapa, con los hechos que se puntúan.</summary>
    public sealed record AlbumCoverTarget(
        MediaCard Card, string AlbumKey, string Title, string? Artist, AlbumFacts Facts);

    /// <summary>
    /// Los álbumes alcanzados que tienen <b>título propio</b>. "Sin álbum" no es
    /// un disco sino el cajón de lo que no tiene uno: no hay tapa que buscarle.
    /// </summary>
    public IReadOnlyList<AlbumCoverTarget> AlbumCoverTargets(IReadOnlyList<MediaCard> cards)
    {
        if (Kind != MediaGridKind.Albums) return [];

        List<AlbumCoverTarget> targets = [];

        foreach (MediaCard card in cards)
        {
            IReadOnlyList<LibraryItem> tracks = ItemsOf([card]);
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

        var search = new AlbumCoverSearch();
        List<AlbumCoverTarget> pending = [];
        int applied = 0;

        IsApplyingRecommendedCover = true;

        try
        {
            foreach (AlbumCoverTarget target in targets)
            {
                ct.ThrowIfCancellationRequested();

                AlbumCoverCandidate? best;

                try
                {
                    IReadOnlyList<AlbumCoverCandidate> candidates = await search.CandidatesAsync(
                        target.Title, target.Artist, deezerEnabled, ct, target.Facts);

                    best = candidates.FirstOrDefault();
                }
                catch (Exception ex) when (ex is not OperationCanceledException)
                {
                    // Que un álbum falle no puede tumbar el lote: el usuario
                    // pidió las tapas de su selección, no la de uno.
                    best = null;
                }

                if (best is { CanApplyWithoutAsking: true })
                {
                    _library.ApplyAlbumCover(target.AlbumKey, best.Data, markEditedByUser: false);
                    applied++;
                }
                else
                {
                    pending.Add(target);
                }
            }
        }
        finally
        {
            IsApplyingRecommendedCover = false;
        }

        Refresh();
        return (applied, pending);
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
