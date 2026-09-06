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

        if (_statusSummaryTimer is { } timer)
        {
            timer.Interval = StatusSummaryDelay;
            timer.IsRepeating = false;
            timer.Tick += (_, _) => UpdateStatusSummary();
        }
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);

        // La suscripción va por navegación, no por constructor: el modelo es
        // único y la página se crea de nuevo cada vez que se entra. Suscribirse
        // en el constructor dejaría a las páginas anteriores escuchando y
        // tocando su propio control, que ya no está en pantalla.
        ViewModel.SelectionSyncRequested += OnSelectionSyncRequested;

        if (e.Parameter is MediaGridRequest request)
            ViewModel.Show(request.Kind, request.PhotoCategory);
        else
            ViewModel.Refresh();

        // Al entrar se escribe de una vez, sin rebote: el rebote es para las
        // ráfagas de selección, no para el primer dibujo.
        UpdateStatusSummary();
    }

    /// <summary>
    /// R3-4: la selección de la vista activa es la que alimenta «Solo la
    /// selección»; al salir se limpia, para que el alcance no siga apuntando a
    /// lo que había seleccionado dos pantallas atrás.
    /// </summary>
    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        base.OnNavigatedFrom(e);
        ViewModel.SelectionSyncRequested -= OnSelectionSyncRequested;
        ViewModel.Library.ClearSelectionForSync();
    }

    // MARK: - Selección (ST-202)

    /// <summary>
    /// Lo que el control decidió, al modelo. Llega el <b>delta</b>: con 1 000
    /// álbumes marcados, releer <c>SelectedItems</c> entero en cada cambio sería
    /// volver a pagar por tecla lo que ST-201 sacó del camino.
    /// </summary>
    private void Cards_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        ViewModel.SyncFromControl(
            [.. e.AddedItems.OfType<MediaCard>()],
            [.. e.RemovedItems.OfType<MediaCard>()]);

        ScheduleStatusSummary();
    }

    // MARK: - Barra de estado (ST-202)

    /// <summary>
    /// El resumen se reescribe <b>con rebote</b>: mantener apretada Mayús+flecha
    /// manda un aviso por tecla, y la parte del texto que depende de la selección
    /// cuesta proporcional a lo marcado. Con 1 000 álbumes eso es trabajo real
    /// que nadie alcanza a leer mientras la selección todavía se mueve.
    ///
    /// <para>El total no entra en esa cuenta: lo tiene guardado
    /// <c>StatusSummaryModel</c> por versión del catálogo.</para>
    /// </summary>
    private readonly Microsoft.UI.Dispatching.DispatcherQueueTimer? _statusSummaryTimer =
        Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread()?.CreateTimer();

    /// <summary>Cuánto se espera a que la selección se quede quieta.</summary>
    private static readonly TimeSpan StatusSummaryDelay = TimeSpan.FromMilliseconds(120);

    private void ScheduleStatusSummary()
    {
        if (!ViewModel.ShowsStatusSummary) return;

        // Sin despachador —no debería pasar en la app— se escribe al instante:
        // degradar es mejor que no mostrar nada.
        if (_statusSummaryTimer is null)
        {
            UpdateStatusSummary();
            return;
        }

        // Reiniciar el temporizador en cada aviso es el rebote: mientras las
        // teclas sigan llegando, el texto no se rearma.
        _statusSummaryTimer.Stop();
        _statusSummaryTimer.Start();
    }

    private void UpdateStatusSummary()
    {
        if (!ViewModel.ShowsStatusSummary)
        {
            StatusTotal.Text = "";
            StatusSelection.Text = "";
            return;
        }

        LibraryStatusSummary summary = ViewModel.StatusSummary;
        StatusTotal.Text = summary.Total;
        StatusSelection.Text = summary.Selection;
    }

    /// <summary>
    /// Después de un refresco, el control vuelve a marcar lo que dice el modelo:
    /// las tarjetas que cambiaron de contenido son instancias nuevas, y para él
    /// son otras.
    ///
    /// <para>Se hace con el aviso desconectado —el mismo patrón que
    /// <c>ArtistsPage</c>—: si no, restaurar la selección se leería como si el
    /// usuario la hubiera cambiado.</para>
    /// </summary>
    private void OnSelectionSyncRequested(object? sender, IReadOnlyList<MediaCard> selected)
    {
        // El catálogo pudo haber cambiado: el resumen tiene que enterarse aunque
        // la selección haya quedado igual.
        ScheduleStatusSummary();

        if (selected.Count == 0 && CardsView.SelectedItems.Count == 0) return;

        CardsView.SelectionChanged -= Cards_SelectionChanged;

        try
        {
            CardsView.SelectedItems.Clear();
            foreach (MediaCard card in selected) CardsView.SelectedItems.Add(card);
        }
        finally
        {
            CardsView.SelectionChanged += Cards_SelectionChanged;
        }
    }

    /// <summary>
    /// Vaciar la selección <b>sin</b> quitar los elementos uno por uno: cada
    /// quite suelto dispara su propio aviso, y con 1 000 marcados eso son 1 000
    /// vueltas por el modelo. <c>DeselectRange</c> avisa una sola vez y no
    /// necesita materializar los elementos virtualizados.
    /// </summary>
    private void DeselectAll()
    {
        if (CardsView.SelectedItems.Count == 0) return;

        CardsView.DeselectRange(new Microsoft.UI.Xaml.Data.ItemIndexRange(0, (uint)ViewModel.Cards.Count));
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
    private void Cover_Loaded(object sender, RoutedEventArgs e) => LoadCover(sender as Image);

    /// <summary>
    /// Desde ST-201 la cuadrícula se actualiza <b>en su lugar</b>: un contenedor
    /// que ya existía puede pasar a mostrar otra tarjeta sin volver a cargarse.
    /// Cargar la portada por el dato de la celda —y no solo por <c>Loaded</c>— es
    /// lo que evita que quede la portada de la anterior; es el mismo reciclaje
    /// que ya se veía al desplazarse.
    /// </summary>
    private void Cover_DataContextChanged(FrameworkElement sender, DataContextChangedEventArgs args) =>
        LoadCover(sender as Image);

    private async void LoadCover(Image? image)
    {
        if (image?.DataContext is not MediaCard card) return;

        try
        {
            var bitmap = new BitmapImage { DecodePixelWidth = 304 };   // 152 pt a 2×

            if (card.CoverItem is { } coverItem)
            {
                // ST-208: la carátula ya no viene en la tarjeta — se lee del
                // disco, fuera del hilo de interfaz, y solo la de las celdas que
                // de verdad se ven.
                byte[]? data = await ViewModel.Library.ReadCoverAsync(coverItem);
                if (data is not { Length: > 0 }) return;

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

            // La celda pudo haber cambiado de tarjeta mientras se decodificaba:
            // pintar acá sería poner la portada de una en el lugar de otra.
            if (!ReferenceEquals(image.DataContext, card)) return;

            image.Source = bitmap;
        }
        catch (Exception)
        {
            // Una portada ilegible deja la tarjeta con su inicial, que es
            // exactamente lo que se ve cuando no hay portada.
        }
    }

    // MARK: - Abrir una tarjeta

    /// <summary>Un clic selecciona —eso lo hace el control—; abrir son dos.</summary>
    private void Card_DoubleTapped(object sender, DoubleTappedRoutedEventArgs e)
    {
        if (sender is not FrameworkElement { DataContext: MediaCard card }) return;
        if (ViewModel.Open(card) is not { } target) return;

        Frame.Navigate(typeof(SongsPage), new SongsRequest(target.Scope, target.Title, target.Subtitle));
    }

    /// <summary>
    /// La casilla <b>alterna esa tarjeta</b> dentro de la selección del control,
    /// sin tocar el resto (ST-103): es acumulativa a propósito, y es lo que la
    /// distingue del clic en la tarjeta, que reemplaza.
    ///
    /// <para><c>Click</c> y no <c>Tapped</c> porque también sale con la barra
    /// espaciadora: la casilla tiene que servir con el teclado y con un lector de
    /// pantalla, que es de donde salió ST-103.</para>
    /// </summary>
    private void SelectionBox_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { DataContext: MediaCard card }) return;

        if (CardsView.SelectedItems.Contains(card)) CardsView.SelectedItems.Remove(card);
        else CardsView.SelectedItems.Add(card);
    }

    /// <summary>
    /// El toque en la casilla no llega a la tarjeta: si llegara, el control
    /// reemplazaría la selección entera justo con lo que se acaba de sumar.
    /// </summary>
    private void SelectionBox_Tapped(object sender, TappedRoutedEventArgs e) => e.Handled = true;

    /// <summary>
    /// Un clic en el espacio vacío de la cuadrícula <b>vacía la selección</b>,
    /// como en el Explorador y como en el Finder. El control no lo trae: para él
    /// un clic fuera de un elemento no es nada.
    /// </summary>
    private void Cards_Tapped(object sender, TappedRoutedEventArgs e)
    {
        if (CardFrom(e.OriginalSource) is null) DeselectAll();
    }

    /// <summary>
    /// Escape vacía la selección y Ctrl+A la llena. Ninguno de los dos viene de
    /// fábrica: la tabla de gestos de <c>Extended</c> cubre clic, Ctrl+clic,
    /// Mayús+clic, flechas y Mayús+flechas, y nada más.
    ///
    /// <para>Este manejador está en la <b>página</b>, así que solo ve lo que el
    /// control dejó pasar: si alguna versión del control llegara a atender
    /// Ctrl+A por su cuenta, el resultado sería el mismo y esto no correría.</para>
    ///
    /// <para>Los dos usan las operaciones por RANGO
    /// (<c>SelectAll</c>/<c>DeselectRange</c>) y no <c>SelectedItems</c> elemento
    /// por elemento: cada quite o agregado suelto dispara su propio
    /// <c>SelectionChanged</c>, y con 1 000 álbumes eso son 1 000 vueltas por el
    /// modelo en vez de una.</para>
    /// </summary>
    private void Page_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        switch (e.Key)
        {
            case Windows.System.VirtualKey.Escape:
                DeselectAll();
                e.Handled = true;
                break;

            case Windows.System.VirtualKey.A when IsControlDown():
                CardsView.SelectAll();
                e.Handled = true;
                break;
        }
    }

    private static bool IsControlDown() =>
        Microsoft.UI.Input.InputKeyboardSource
            .GetKeyStateForCurrentThread(Windows.System.VirtualKey.Control)
            .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);

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
