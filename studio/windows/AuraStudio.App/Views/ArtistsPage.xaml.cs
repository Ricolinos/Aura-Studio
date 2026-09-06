using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml.Navigation;
using Windows.Storage.Streams;
using AuraStudio.App.ViewModels;
using AuraStudio.Core.Library;

namespace AuraStudio.App.Views;

/// <summary>
/// La sección «Artistas» (R2-6, ST-121). El diseño es el de macOS
/// (`ArtistsView.swift`), no el de las cuadrículas: maestro-detalle, con la
/// selección nativa del <c>ListView</c>.
///
/// <para>La página se ocupa solo de lo que es de la vista —decodificar
/// imágenes, abrir menús, empujar la selección al modelo—; qué se muestra y
/// qué alcanza cada acción lo decide <see cref="ArtistsViewModel"/>, y el
/// contenido de los menús lo decide Core.</para>
/// </summary>
public sealed partial class ArtistsPage : Page
{
    public ArtistsViewModel ViewModel { get; }

    public ArtistsPage()
    {
        InitializeComponent();
        ViewModel = App.Services.GetRequiredService<ArtistsViewModel>();
        ViewModel.PropertyChanged += OnViewModelChanged;
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        ViewModel.Refresh();
        SyncListSelection();
        UpdateHeader();
    }

    /// <summary>R3-4: lo seleccionado acá no puede sobrevivir a esta vista.</summary>
    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        base.OnNavigatedFrom(e);
        ViewModel.Library.ClearSelectionForSync();
    }

    private void OnViewModelChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(ArtistsViewModel.SelectedArtist)) UpdateHeader();
    }

    // MARK: - Selección

    /// <summary>
    /// La selección la lleva el control, no el modelo: al modelo se le empuja
    /// lo que el control decidió. Es lo que hace que Ctrl y Mayús funcionen sin
    /// escribir una línea de lógica de selección — el equivalente de la
    /// <c>List(selection:)</c> de macOS.
    /// </summary>
    private void ArtistList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        ViewModel.SetSelection([.. ArtistList.SelectedItems.OfType<ArtistRow>()]);
        UpdateHeader();
    }

    /// <summary>
    /// Devuelve al control la selección que el modelo restauró tras recargar la
    /// biblioteca (los grupos son objetos nuevos, así que los de antes ya no
    /// están en la lista).
    /// </summary>
    private void SyncListSelection()
    {
        ArtistList.SelectionChanged -= ArtistList_SelectionChanged;

        ArtistList.SelectedItems.Clear();
        foreach (ArtistRow row in ViewModel.Selection) ArtistList.SelectedItems.Add(row);

        ArtistList.SelectionChanged += ArtistList_SelectionChanged;
    }

    /// <summary>
    /// Ctrl+A marca todos los artistas y Escape los desmarca (ST-202). Con
    /// <c>SelectionMode="Extended"</c> el control ya traía clic, Ctrl+clic,
    /// Mayús+clic, flechas y Mayús+flechas; estos dos no vienen.
    ///
    /// <para>El buscador de arriba es un <c>TextBox</c>, que atiende Ctrl+A por
    /// su cuenta —seleccionar SU texto— y marca el evento como atendido. Este
    /// manejador está en la página, así que solo ve lo que el control dejó
    /// pasar: escribiendo en el buscador, Ctrl+A sigue siendo "todo el
    /// texto".</para>
    ///
    /// <para>Van por rango (<c>SelectAll</c>/<c>DeselectRange</c>): avisan una
    /// sola vez, en vez de una por artista.</para>
    /// </summary>
    private void Page_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        switch (e.Key)
        {
            case Windows.System.VirtualKey.Escape:
                if (ArtistList.SelectedItems.Count > 0)
                {
                    ArtistList.DeselectRange(
                        new Microsoft.UI.Xaml.Data.ItemIndexRange(0, (uint)ViewModel.VisibleArtists.Count));
                }

                e.Handled = true;
                break;

            case Windows.System.VirtualKey.A when IsControlDown():
                ArtistList.SelectAll();
                e.Handled = true;
                break;
        }
    }

    private static bool IsControlDown() =>
        Microsoft.UI.Input.InputKeyboardSource
            .GetKeyStateForCurrentThread(Windows.System.VirtualKey.Control)
            .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);

    // MARK: - Cabecera de la ficha

    /// <summary>
    /// La cabecera se arma en código y no con <c>x:Bind</c> porque su avatar es
    /// un arreglo de bytes que hay que decodificar, y porque cambia con la
    /// selección, no con la lista.
    /// </summary>
    private async void UpdateHeader()
    {
        if (ViewModel.SelectedArtist is not { } artist) return;

        HeaderName.Text = artist.Name;
        HeaderSummary.Text = artist.Group.Summary;
        HeaderInitial.Text = artist.Initial;
        HeaderInitial.Visibility = artist.HasAvatar ? Visibility.Collapsed : Visibility.Visible;
        HeaderAvatar.Source = artist.HasAvatar ? await DecodeAsync(artist.AvatarData!, 192) : null;
    }

    // MARK: - Imágenes

    private async void Avatar_Loaded(object sender, RoutedEventArgs e)
    {
        if (sender is not Image image) return;
        if (image.Tag is not string id) return;

        ArtistRow? row = ViewModel.Artists.FirstOrDefault(candidate => candidate.Id == id);
        if (row?.AvatarData is not { Length: > 0 } data) return;

        image.Source = await DecodeAsync(data, 80);   // 40 px a 2×
    }

    private async void AlbumCover_Loaded(object sender, RoutedEventArgs e)
    {
        if (sender is not Image image) return;
        if (image.Tag is not string id) return;

        ArtistAlbumRow? row = ViewModel.SelectedAlbums.FirstOrDefault(candidate => candidate.Album.Id == id);
        if (row?.CoverData is not { Length: > 0 } data) return;

        image.Source = await DecodeAsync(data, 256);  // 128 px a 2×
    }

    /// <summary>
    /// <c>DecodePixelWidth</c> va solo en el ancho, nunca en los dos lados:
    /// fijar ambos deforma una portada que no sea cuadrada.
    /// </summary>
    private static async Task<BitmapImage?> DecodeAsync(byte[] data, int width)
    {
        try
        {
            var bitmap = new BitmapImage { DecodePixelWidth = width };
            using var stream = new InMemoryRandomAccessStream();

            using (var writer = new DataWriter(stream.GetOutputStreamAt(0)))
            {
                writer.WriteBytes(data);
                await writer.StoreAsync();
            }

            await bitmap.SetSourceAsync(stream);
            return bitmap;
        }
        catch (Exception)
        {
            // Una imagen ilegible deja la inicial, que es lo mismo que se ve
            // cuando no hay ninguna.
            return null;
        }
    }

    // MARK: - Menú del artista (§2 del documento de paridad)

    private void ArtistList_ContextRequested(UIElement sender, ContextRequestedEventArgs args)
    {
        if (RowFrom(args.OriginalSource) is not { } row) return;

        IReadOnlyList<ArtistRow> reached = ViewModel.EffectiveArtists(row);

        ContextMenuBuilder
            .Build(LibraryContextMenus.ForArtists(ViewModel.ScopeOf(reached)), id => InvokeArtist(id, reached))?
            .ShowAt(sender, new FlyoutShowOptions
            {
                Position = args.TryGetPosition(sender, out var point) ? point : null
            });

        args.Handled = true;
    }

    /// <summary>El botón de la cabecera: completa en línea solo ese artista.</summary>
    private async void ArtistEnrich_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel.SelectedArtist is not { } artist) return;

        await ViewModel.Library.EnrichAsync(ViewModel.SongIdsOf([artist]));
    }

    private void ArtistMenu_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement anchor) return;
        if (ViewModel.SelectedArtist is not { } artist) return;

        IReadOnlyList<ArtistRow> reached = [artist];

        ContextMenuBuilder
            .Build(LibraryContextMenus.ForArtists(ViewModel.ScopeOf(reached)), id => InvokeArtist(id, reached))?
            .ShowAt(anchor);
    }

    private async void InvokeArtist(string id, IReadOnlyList<ArtistRow> reached)
    {
        IReadOnlyList<Guid> songIds = ViewModel.SongIdsOf(reached);

        switch (id)
        {
            case "favorite.add": ViewModel.Library.SetFavorite(songIds, true); break;
            case "favorite.remove": ViewModel.Library.SetFavorite(songIds, false); break;

            case "enrich": await ViewModel.Library.EnrichAsync(songIds); break;

            case "artist.photo": await ViewModel.Library.FetchArtistImagesAsync(); break;
            case "artist.photo.remove": ViewModel.RemoveArtistPhoto(reached); break;

            case "reveal": Reveal(reached); break;

            case "delete":
                ViewModel.Library.Remove(songIds);
                ViewModel.Refresh();
                SyncListSelection();
                break;
        }
    }

    /// <summary>
    /// Con un solo artista alcanza con revelar una canción; con varios, todas
    /// — el mismo criterio que macOS.
    /// </summary>
    private void Reveal(IReadOnlyList<ArtistRow> reached)
    {
        IEnumerable<LibraryItem> items = reached.SelectMany(row => row.Group.Items);
        if (reached.Count == 1) items = items.Take(1);

        foreach (LibraryItem item in items) FilePickers.RevealInExplorer(item.SourcePath);
    }

    // MARK: - Menú del álbum dentro de la ficha

    private void AlbumMenu_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { Tag: string albumId } anchor) return;

        ArtistAlbumRow? album = ViewModel.SelectedAlbums.FirstOrDefault(row => row.Album.Id == albumId);
        if (album is null) return;

        IReadOnlyList<Guid> songIds = [.. album.Album.Items.Select(item => item.Id)];

        var menu = new MenuFlyout();

        var favorite = new MenuFlyoutItem
        {
            Text = album.IsFavorite ? "Quitar favorito del álbum" : "Marcar álbum como favorito"
        };
        favorite.Click += (_, _) =>
        {
            ViewModel.Library.SetFavorite(songIds, !album.IsFavorite);
            ViewModel.Refresh();
        };

        var enrich = new MenuFlyoutItem { Text = "Buscar información en línea" };
        enrich.Click += async (_, _) => await ViewModel.Library.EnrichAsync(songIds);

        var reveal = new MenuFlyoutItem { Text = LibraryContextMenus.Reveal };
        reveal.Click += (_, _) =>
        {
            foreach (LibraryItem item in album.Album.Items) FilePickers.RevealInExplorer(item.SourcePath);
        };

        menu.Items.Add(favorite);
        menu.Items.Add(enrich);
        menu.Items.Add(new MenuFlyoutSeparator());
        menu.Items.Add(reveal);

        menu.ShowAt(anchor);
    }

    // MARK: - Canciones (§3 del documento de paridad)

    private void Track_ContextRequested(UIElement sender, ContextRequestedEventArgs args)
    {
        if (TrackFrom(args.OriginalSource) is not { } track) return;

        ContextMenuBuilder
            .Build(LibraryContextMenus.ForArtistSong(track.IsFavorite), id => InvokeTrack(id, track))?
            .ShowAt(sender, new FlyoutShowOptions
            {
                Position = args.TryGetPosition(sender, out var point) ? point : null
            });

        args.Handled = true;
    }

    private async void InvokeTrack(string id, ArtistTrackRow track)
    {
        switch (id)
        {
            case "info": await ShowInfoAsync(track); break;

            case "favorite.add":
            case "favorite.remove":
                ViewModel.ToggleFavorite(track);
                break;

            case "reveal": FilePickers.RevealInExplorer(track.Item.SourcePath); break;
        }
    }

    private async Task ShowInfoAsync(ArtistTrackRow track)
    {
        long size = 0;
        try { size = new FileInfo(track.Item.SourcePath).Length; } catch (IOException) { }

        MediaInfoResult? result = await MediaInfoDialog.ShowAsync(
            XamlRoot, track.Item, availableCategories: null, size);

        if (result?.Metadata is null) return;

        ViewModel.Library.ApplyMetadataEdit(track.Id, result.Metadata);
        ViewModel.Refresh();
    }

    private void TrackFavorite_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: ArtistTrackRow track }) ViewModel.ToggleFavorite(track);
    }

    // MARK: - Acciones con varios artistas seleccionados

    private void FetchPhotos_Click(object sender, RoutedEventArgs e) =>
        _ = ViewModel.Library.FetchArtistImagesAsync();

    private void BulkFavorite_Click(object sender, RoutedEventArgs e)
    {
        ViewModel.Library.SetFavorite(ViewModel.SongIdsOf(ViewModel.Selection), !ViewModel.SelectionAllFavorite);
        ViewModel.Refresh();
    }

    private async void BulkEnrich_Click(object sender, RoutedEventArgs e) =>
        await ViewModel.Library.EnrichAsync(ViewModel.SongIdsOf(ViewModel.Selection));

    private void BulkReveal_Click(object sender, RoutedEventArgs e) => Reveal(ViewModel.Selection);

    private void BulkDelete_Click(object sender, RoutedEventArgs e)
    {
        ViewModel.Library.Remove(ViewModel.SongIdsOf(ViewModel.Selection));
        ViewModel.Refresh();
        SyncListSelection();
    }

    // MARK: - De dónde salió el clic

    private static ArtistRow? RowFrom(object? source) => AncestorContext<ArtistRow>(source);

    private static ArtistTrackRow? TrackFrom(object? source) => AncestorContext<ArtistTrackRow>(source);

    /// <summary>
    /// Sube por el árbol buscando el <c>DataContext</c> del tipo pedido: dentro
    /// de una fila hay varios elementos y solo algunos lo llevan.
    /// </summary>
    private static T? AncestorContext<T>(object? source) where T : class
    {
        for (var element = source as FrameworkElement; element is not null; element = element.Parent as FrameworkElement)
        {
            if (element.DataContext is T match) return match;
        }

        return null;
    }
}
