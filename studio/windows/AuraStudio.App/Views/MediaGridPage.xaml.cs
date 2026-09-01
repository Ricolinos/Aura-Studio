using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml.Navigation;
using Microsoft.UI.Xaml.Input;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;
using Windows.Storage.Streams;
using AuraStudio.App.Resources;
using AuraStudio.App.ViewModels;
using AuraStudio.Core;
using AuraStudio.Core.Library;
using AuraStudio.Core.Networking;

namespace AuraStudio.App.Views;

/// <summary>Lo que se le pasa a la página al navegar.</summary>
/// <param name="PhotoCategory">Solo para una colección de fotos.</param>
public sealed record MediaGridRequest(MediaGridKind Kind, string? PhotoCategory = null);

/// <summary>
/// Las cuadrículas de la biblioteca: Álbumes, Artistas, Películas, Series,
/// colecciones de fotos, y los listados sin agrupar.
///
/// <para>Una sola página para todas a propósito: lo único que cambia es de dónde
/// salen las tarjetas y qué tipo acepta al soltar. Seis páginas casi idénticas
/// terminan desincronizándose entre sí.</para>
/// </summary>
public sealed partial class MediaGridPage : Page
{
    public MediaGridViewModel ViewModel { get; }

    private readonly Services.IAppPreferences _preferences;

    public MediaGridPage()
    {
        InitializeComponent();
        ViewModel = App.Services.GetRequiredService<MediaGridViewModel>();
        _preferences = App.Services.GetRequiredService<Services.IAppPreferences>();
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);

        if (e.Parameter is MediaGridRequest request)
            ViewModel.Show(request.Kind, request.PhotoCategory);
        else
            ViewModel.Refresh();
    }

    /// <summary>
    /// R3-4: la selección de la vista activa es la que alimenta «Solo la
    /// selección»; al salir se limpia, para que el alcance no siga apuntando a
    /// lo que había seleccionado dos pantallas atrás.
    /// </summary>
    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        base.OnNavigatedFrom(e);
        ViewModel.Library.ClearSelectionForSync();
    }

    // MARK: - Portadas

    /// <summary>
    /// La imagen se carga al aparecer la tarjeta y no al armar la lista: en una
    /// biblioteca de cientos de álbumes, decodificarlas todas de golpe bloquea
    /// la interfaz aunque solo se vean doce.
    ///
    /// <para><c>DecodePixelWidth</c> va solo en el ancho, nunca en los dos
    /// lados: fijar ambos deforma una portada que no sea cuadrada — el mismo
    /// bug que se corrigió en las miniaturas de macOS.</para>
    /// </summary>
    private async void Cover_Loaded(object sender, RoutedEventArgs e)
    {
        if (sender is not Image image) return;
        if (image.Tag is not string id) return;

        MediaCard? card = ViewModel.Cards.FirstOrDefault(candidate => candidate.Id == id);
        if (card is null) return;

        try
        {
            var bitmap = new BitmapImage { DecodePixelWidth = 304 };   // 152 pt a 2×

            if (card.CoverData is { Length: > 0 } data)
            {
                using var stream = new InMemoryRandomAccessStream();
                using (var writer = new DataWriter(stream.GetOutputStreamAt(0)))
                {
                    writer.WriteBytes(data);
                    await writer.StoreAsync();
                }
                await bitmap.SetSourceAsync(stream);
            }
            else if (card.ImagePath is { Length: > 0 } path && File.Exists(path))
            {
                var file = await StorageFile.GetFileFromPathAsync(path);
                using IRandomAccessStream stream = await file.OpenReadAsync();
                await bitmap.SetSourceAsync(stream);
            }
            else
            {
                return;
            }

            image.Source = bitmap;
        }
        catch (Exception)
        {
            // Una portada ilegible deja la tarjeta con su inicial, que es
            // exactamente lo que se ve cuando no hay portada.
        }
    }

    // MARK: - Abrir una tarjeta

    /// <summary>Un clic <b>reemplaza</b> la selección (ST-103). Abrir son dos.</summary>
    private void Cards_ItemClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is MediaCard card) ViewModel.SelectOnly(card);
    }

    private void Card_DoubleTapped(object sender, DoubleTappedRoutedEventArgs e)
    {
        if (sender is not FrameworkElement { DataContext: MediaCard card }) return;
        if (ViewModel.Open(card) is not { } target) return;

        Frame.Navigate(typeof(SongsPage), new SongsRequest(target.Scope, target.Title, target.Subtitle));
    }

    /// <summary>
    /// La casilla ya alterna sola —está enlazada en dos sentidos, así que
    /// también funciona con el teclado y con un lector de pantalla—; lo único
    /// que hace falta acá es <b>comerse el toque</b> para que no llegue a la
    /// tarjeta, que reemplazaría justo lo que se acaba de sumar.
    /// </summary>
    private void SelectionBox_Tapped(object sender, TappedRoutedEventArgs e) => e.Handled = true;

    /// <summary>
    /// Un clic en el espacio vacío de la cuadrícula <b>vacía la selección</b>,
    /// como en el Explorador y como en el Finder.
    ///
    /// <para>Hace falta desde R2-1: el clic en una tarjeta <i>reemplaza</i>, así
    /// que nunca deja cero seleccionados, y sin esto no había ningún gesto para
    /// volver al estado limpio —el que la regla nueva describe como el normal—
    /// una vez que se seleccionó algo.</para>
    /// </summary>
    private void Cards_Tapped(object sender, TappedRoutedEventArgs e)
    {
        if (CardFrom(e.OriginalSource) is null) ViewModel.ClearSelection();
    }

    /// <summary>Escape hace lo mismo, para quien no usa el mouse.</summary>
    private void Page_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key != Windows.System.VirtualKey.Escape) return;

        ViewModel.ClearSelection();
        e.Handled = true;
    }

    /// <summary>
    /// R2-1: el cursor sobre una tarjeta muestra <b>su</b> casilla. Es lo único
    /// que hace descubrible la selección múltiple ahora que la cuadrícula ya no
    /// las muestra todas.
    /// </summary>
    private void Card_PointerEntered(object sender, PointerRoutedEventArgs e) =>
        SetHovered(sender, true);

    private void Card_PointerExited(object sender, PointerRoutedEventArgs e) =>
        SetHovered(sender, false);

    private static void SetHovered(object sender, bool hovered)
    {
        if (sender is FrameworkElement { DataContext: MediaCard card }) card.IsHovered = hovered;
    }

    // MARK: - Menú contextual (§1, §2, §5, §6, §8 del documento de paridad)

    /// <summary>
    /// El menú de la cuadrícula. Cuál es depende de qué se está mostrando; lo
    /// que tiene cada uno lo decide Core.
    /// </summary>
    private void Cards_ContextRequested(UIElement sender, ContextRequestedEventArgs args)
    {
        if (CardFrom(args.OriginalSource) is not { } card) return;

        // Regla 0.1: clic derecho sobre algo ya marcado alcanza a toda la
        // selección; sobre algo que no lo está, solo a eso.
        IReadOnlyList<MediaCard> reached = GridSelection.EffectiveIds(card, ViewModel.SelectedCards);
        MenuScope scope = ViewModel.ScopeOf(reached);

        IReadOnlyList<MenuEntry> entries = ViewModel.Kind switch
        {
            MediaGridKind.Albums => LibraryContextMenus.ForAlbums(scope),
            MediaGridKind.Movies => LibraryContextMenus.ForMovies(scope, MediaCategoryNames.VideoCategories),
            MediaGridKind.Series => LibraryContextMenus.ForSeries(scope, MediaCategoryNames.VideoCategories),

            // Una colección muestra ÁLBUMES de fotos (§8); "Todas las fotos"
            // muestra las fotos sueltas (§9). Son dos menús distintos y
            // confundirlos ofrece "Disolver álbum" sobre una foto.
            MediaGridKind.PhotoCollection =>
                LibraryContextMenus.ForPhotoAlbums(scope, _preferences.PhotoCollections),
            MediaGridKind.AllPhotos => LibraryContextMenus.ForPhotos(scope, _preferences.PhotoCollections),

            // Los listados planos de video son elementos sueltos, como los de
            // una tabla: les toca el menú de tabla (§4) con su bloque de video.
            MediaGridKind.AllVideos or MediaGridKind.Clips =>
                MediaTableContextMenu.Build(LibraryItemKind.Video, scope, MediaCategoryNames.VideoCategories),

            _ => []
        };

        MenuFlyout? menu = ContextMenuBuilder.Build(entries, id => Invoke(id, card, reached));

        menu?.ShowAt(sender, new FlyoutShowOptions
        {
            Position = args.TryGetPosition(sender, out var point) ? point : null
        });

        args.Handled = true;
    }

    /// <summary>
    /// La tarjeta a la que pertenece lo que se clickeó: dentro de una tarjeta
    /// hay varios elementos, y solo el de más afuera lleva su
    /// <c>DataContext</c>.
    /// </summary>
    private static MediaCard? CardFrom(object? source)
    {
        for (var element = source as FrameworkElement; element is not null; element = element.Parent as FrameworkElement)
        {
            if (element.DataContext is MediaCard card) return card;
        }

        return null;
    }

    // MARK: - Carátulas del álbum (§1 ítems 4 y 5)

    /// <summary>
    /// La hoja de tapas desde la cuadrícula de Álbumes. El ítem se ofrece solo
    /// cuando el alcance resuelve a UN álbum con título, así que acá hay uno.
    /// </summary>
    private async Task ShowAlbumCoverPickerAsync(IReadOnlyList<MediaCard> reached)
    {
        if (ViewModel.AlbumCoverTargets(reached) is not [{ } target, ..]) return;

        AlbumCoverCandidate? chosen = await AlbumCoverPicker.ShowAsync(
            XamlRoot, target.Title, target.Artist, target.Facts, _preferences.DeezerEnabled);

        if (chosen is null) return;

        // La eligió a mano: esta sí queda marcada como editada por el usuario.
        ViewModel.Library.ApplyAlbumCover(target.AlbumKey, chosen.Data);
        ViewModel.Refresh();
    }

    /// <summary>
    /// La acción automática de R2-3. Aplica solo lo seguro y <b>dice qué quedó
    /// pendiente</b>: un resumen que no cuenta lo que no se hizo es peor que no
    /// tener resumen.
    ///
    /// <para>Si queda <b>exactamente un</b> álbum sin opción segura, se abre su
    /// hoja. Con varios no se abre ninguna: una fila de hojas encadenadas no se
    /// puede usar, y el resumen ya dice cuántos quedaron.</para>
    /// </summary>
    private async Task ApplyRecommendedCoversAsync(IReadOnlyList<MediaCard> reached)
    {
        (int applied, IReadOnlyList<MediaGridViewModel.AlbumCoverTarget> pending) =
            await ViewModel.ApplyRecommendedCoversAsync(reached, _preferences.DeezerEnabled);

        ViewModel.Library.StatusMessage = Summary(applied, pending.Count);

        if (pending is [{ } only])
        {
            AlbumCoverCandidate? chosen = await AlbumCoverPicker.ShowAsync(
                XamlRoot, only.Title, only.Artist, only.Facts, _preferences.DeezerEnabled);

            if (chosen is null) return;

            ViewModel.Library.ApplyAlbumCover(only.AlbumKey, chosen.Data);
            ViewModel.Refresh();
        }
    }

    private static string Summary(int applied, int pending) => (applied, pending) switch
    {
        (0, 0) => "No había ningún álbum con título al que aplicarle una tapa.",
        (0, 1) => "No se encontró una tapa segura para ese álbum.",
        (0, _) => $"No se encontró una tapa segura para {pending} álbumes.",
        (1, 0) => "Se aplicó la tapa recomendada a 1 álbum.",
        (_, 0) => $"Se aplicó la tapa recomendada a {applied} álbumes.",
        (1, _) => $"Se aplicó la tapa recomendada a 1 álbum; {pending} quedaron sin una opción segura.",
        _ => $"Se aplicó la tapa recomendada a {applied} álbumes; {pending} quedaron sin una opción segura."
    };

    /// <summary>
    /// Renombrar un álbum de fotos. Es una etiqueta de la biblioteca: en el
    /// iPod las fotos viajan sin carpetas, así que no hay nada que renombrar
    /// del otro lado.
    /// </summary>
    private async Task RenameAlbumAsync(MediaCard card)
    {
        var box = new TextBox { Text = card.Title, SelectionStart = 0, SelectionLength = card.Title.Length };

        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "Renombrar álbum",
            Content = box,
            PrimaryButtonText = "Guardar",
            CloseButtonText = "Cancelar",
            DefaultButton = ContentDialogButton.Primary
        };

        if (await dialog.ShowAsync() == ContentDialogResult.Primary) ViewModel.RenameAlbum(card, box.Text);
    }

    private async Task ShowInfoAsync(LibraryItem item)
    {
        long size = 0;
        try { size = new FileInfo(item.SourcePath).Length; } catch (IOException) { }

        MediaInfoResult? result = await MediaInfoDialog.ShowAsync(
            XamlRoot, item, _preferences.PhotoCollections, size);

        if (result is null) return;

        if (result.Metadata is { } metadata) ViewModel.Library.ApplyMetadataEdit(item.Id, metadata);
        if (result.Category is { Length: > 0 } category) ViewModel.Library.ApplyCategory(item.Id, category);

        ViewModel.Refresh();
    }

    private async void Invoke(string id, MediaCard card, IReadOnlyList<MediaCard> reached)
    {
        IReadOnlyList<Guid> songIds = ViewModel.SongIdsOf(reached);

        switch (id)
        {
            case "open":
                if (ViewModel.Open(card) is { } target)
                {
                    Frame.Navigate(typeof(SongsPage),
                        new SongsRequest(target.Scope, target.Title, target.Subtitle));
                }
                break;

            case "favorite.add": ViewModel.Library.SetFavorite(songIds, true); break;
            case "favorite.remove": ViewModel.Library.SetFavorite(songIds, false); break;

            case "enrich": await ViewModel.Library.EnrichAsync(songIds); break;
            case "poster": await ViewModel.Library.FetchVideoPostersAsync(); break;

            // §13.2: la misma hoja que la tabla de Canciones. Estaba en el menú
            // y no tenía caso acá, así que el ítem no hacía nada.
            case "album.covers": await ShowAlbumCoverPickerAsync(reached); break;

            // R2-3: aplica la recomendada SIN preguntar solo donde el puntaje
            // supera el umbral; lo que no lo supera no se toca.
            case "album.cover.recommended": await ApplyRecommendedCoversAsync(reached); break;

            case "reveal": ViewModel.RevealInExplorer(reached); break;

            // §9: abre la foto con el visor del sistema. No hay visor propio, y
            // no hace falta: el de Windows ya sabe hacer zoom y girar.
            case "preview": ViewModel.OpenWithSystemViewer(reached); break;

            case "photo.removeFromAlbum": ViewModel.RemoveFromAlbum(reached); break;

            case "album.rename": await RenameAlbumAsync(card); break;
            case "album.dissolve": ViewModel.DissolveAlbums(reached); break;

            case "poster.remove": ViewModel.Library.RemovePoster(songIds); break;
            case "info": if (ViewModel.ItemsOf(reached) is [{ } only]) await ShowInfoAsync(only); break;

            case "delete":
                ViewModel.Library.Remove(songIds);
                ViewModel.Refresh();
                break;

            default:
                if (id.StartsWith("category:", StringComparison.Ordinal))
                {
                    foreach (Guid songId in songIds)
                        ViewModel.Library.ApplyCategory(songId, id["category:".Length..]);

                    ViewModel.Refresh();
                }
                break;
        }
    }

    // MARK: - Agregar archivos

    /// <summary>Descarga los pósters que falten. Los que ya están no se vuelven a pedir.</summary>
    private async void VideoPosters_Click(object sender, RoutedEventArgs e) =>
        await ViewModel.Library.FetchVideoPostersAsync();

    private async void AddFiles_Click(object sender, RoutedEventArgs e)
    {
        IReadOnlyList<string> paths = await FilePickers.PickFilesAsync(ExtensionsFor(ViewModel.DropKind));
        if (paths.Count > 0) Add(paths);
    }

    private async void AddFolder_Click(object sender, RoutedEventArgs e)
    {
        string? folder = await FilePickers.PickFolderAsync();
        if (folder is not null) Add([folder]);
    }

    private static IEnumerable<string> ExtensionsFor(LibraryItemKind kind) => kind switch
    {
        LibraryItemKind.Music => CoverArtAssets.AudioExtensions,
        LibraryItemKind.Video => CoverArtAssets.VideoExtensions,
        _ => CoverArtAssets.ImageExtensions
    };

    private void Add(IEnumerable<string> paths)
    {
        ViewModel.Library.AddDroppedFiles(paths, ViewModel.DropKind);
        ViewModel.Refresh();
    }

    // MARK: - Arrastrar y soltar

    private void Page_DragOver(object sender, DragEventArgs e)
    {
        if (!e.DataView.Contains(StandardDataFormats.StorageItems)) return;

        e.AcceptedOperation = DataPackageOperation.Copy;
        e.DragUIOverride.Caption = ViewModel.DropHint;
        e.DragUIOverride.IsGlyphVisible = true;
    }

    private async void Page_Drop(object sender, DragEventArgs e)
    {
        if (!e.DataView.Contains(StandardDataFormats.StorageItems)) return;

        DragOperationDeferral deferral = e.GetDeferral();
        try
        {
            IReadOnlyList<IStorageItem> dropped = await e.DataView.GetStorageItemsAsync();
            Add(dropped.Select(item => item.Path).Where(path => path.Length > 0));
        }
        finally
        {
            deferral.Complete();
        }
    }
}
