using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;
using AuraStudio.App.Resources;
using AuraStudio.App.ViewModels;
using AuraStudio.Core;
using AuraStudio.Core.Library;
using AuraStudio.Core.Networking;

namespace AuraStudio.App.Views;

/// <summary>
/// Lo que se le pasa a la tabla al abrirla desde una cuadrícula: qué mostrar y
/// cómo llamarlo.
/// </summary>
public sealed record SongsRequest(MusicScope Scope, string Title, string Subtitle);

/// <summary>
/// La tabla de Canciones (ST-030): columnas configurables, orden persistido y
/// filtro de favoritos.
///
/// <para><b>Por qué un <c>ListView</c> con encabezado propio y no el DataGrid
/// del Community Toolkit</b> (el plan pedía evaluarlo): el DataGrid traería una
/// dependencia nueva —con su propia licencia que declarar— para conseguir lo
/// que acá hace falta, que es un conjunto de columnas <b>dinámico</b>. Con el
/// encabezado y las celdas armados desde la lista de columnas visibles no hay
/// tope de columnas, que es justamente el punto de ST-030 frente a las 10 fijas
/// de antes. Lo que se cede es redimensionar columnas arrastrando: queda
/// anotado como pendiente, no como decisión.</para>
///
/// <para>El menú de columnas y el de orden se arman en código: sus opciones
/// salen de <c>MusicTableColumns</c>, así que declararlas a mano en XAML sería
/// una segunda lista que se desincroniza sola.</para>
/// </summary>
public sealed partial class SongsPage : Page
{
    public SongsViewModel ViewModel { get; }

    private readonly Services.IDeviceSessionService _session;
    private readonly Services.IAppPreferences _preferences;

    public SongsPage()
    {
        InitializeComponent();
        ViewModel = App.Services.GetRequiredService<SongsViewModel>();
        _session = App.Services.GetRequiredService<Services.IDeviceSessionService>();
        _preferences = App.Services.GetRequiredService<Services.IAppPreferences>();
        Loaded += SongsPage_Loaded;
    }

    private void SongsPage_Loaded(object sender, RoutedEventArgs e)
    {
        BuildColumnOptions();

        // Antes del refresco: rehacer la tabla suelta la selección del control,
        // y lo anotado acá tiene que soltarse con ella (ST-202).
        ViewModel.PropertyChanged -= OnViewModelChanged;
        ViewModel.PropertyChanged += OnViewModelChanged;

        ViewModel.Refresh();
    }

    protected override void OnNavigatedTo(Microsoft.UI.Xaml.Navigation.NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);

        if (e.Parameter is SongsRequest request)
            ViewModel.SetScope(request.Scope, request.Title, request.Subtitle);
        else
            ViewModel.SetScope(new MusicScope.All(), AppStrings.NavSongs, "Toda tu música.");
    }

    // MARK: - Menús que salen del modelo, no de XAML

    private void BuildColumnOptions()
    {
        ColumnOptions.Children.Clear();

        foreach (MusicColumnGroup group in Enum.GetValues<MusicColumnGroup>())
        {
            ColumnOptions.Children.Add(new TextBlock
            {
                Text = group.Title(),
                Style = (Style)Application.Current.Resources["AuraCaptionTextStyle"],
                Margin = new Thickness(0, 8, 0, 2)
            });

            foreach (MusicTableColumn column in group.Columns())
            {
                var check = new CheckBox
                {
                    Content = column.Title(),
                    IsChecked = ViewModel.IsVisible(column),
                    Tag = column
                };
                check.Checked += ColumnOption_Changed;
                check.Unchecked += ColumnOption_Changed;
                ColumnOptions.Children.Add(check);
            }
        }
    }

    private void ColumnOption_Changed(object sender, RoutedEventArgs e)
    {
        if (sender is not CheckBox { Tag: MusicTableColumn column } check) return;
        ViewModel.SetVisible(column, check.IsChecked == true);
    }

    // MARK: - §11: el menú de los encabezados

    /// <summary>
    /// El mismo menú desde las dos entradas que manda el documento: el botón de
    /// la barra y el clic derecho en el encabezado. <b>Una sola fuente</b>, en
    /// Core: dos listas armadas por separado se desincronizan en cuanto alguien
    /// agregue una opción a una sola.
    /// </summary>
    private IReadOnlyList<MenuEntry> HeaderMenuEntries() =>
        SongsHeaderMenu.Build(ViewModel.FavoritesOnly, ViewModel.Library.SortField,
            ViewModel.Library.SortAscending);

    private void HeaderMenu_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement anchor) return;

        ContextMenuBuilder.Build(HeaderMenuEntries(), InvokeHeaderMenu)?.ShowAt(anchor);
    }

    private void Header_ContextRequested(UIElement sender, ContextRequestedEventArgs args)
    {
        ContextMenuBuilder.Build(HeaderMenuEntries(), InvokeHeaderMenu)?.ShowAt(sender,
            new FlyoutShowOptions { Position = args.TryGetPosition(sender, out var point) ? point : null });

        args.Handled = true;
    }

    private void InvokeHeaderMenu(string id)
    {
        switch (id)
        {
            case "filter.all": ViewModel.FavoritesOnly = false; break;
            case "filter.favorites": ViewModel.FavoritesOnly = true; break;

            case "sort.ascending": SetAscending(true); break;
            case "sort.descending": SetAscending(false); break;

            case "view.options": ColumnsButton.Flyout?.ShowAt(ColumnsButton); break;

            default:
                if (id.StartsWith("sort:", StringComparison.Ordinal)
                    && MusicSortField.Parse(id["sort:".Length..]) is { } field)
                {
                    ViewModel.SortBy(field);
                }
                break;
        }
    }

    private void SetAscending(bool ascending)
    {
        ViewModel.Library.SortAscending = ascending;
        ViewModel.Refresh();
    }

    private void TitleHeader_Click(object sender, RoutedEventArgs e) =>
        ViewModel.SortBy(MusicSortField.ByTitle);

    private void ColumnHeader_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: MusicTableColumn column }) return;
        ViewModel.SortBy(MusicSortField.By(column));
    }

    private void Favorites_Toggled(object sender, RoutedEventArgs e) => ViewModel.Refresh();

    // MARK: - La rueda del mouse

    /// <summary>
    /// Red de seguridad: si la rueda llega hasta acá <b>sin que nadie la haya
    /// atendido</b>, se la pasa a la lista.
    ///
    /// <para>La tabla vive dentro de un contenedor que solo desplaza en
    /// horizontal —para que el encabezado y las filas se muevan juntos—, y en
    /// WinUI un contenedor así puede quedarse con el evento aunque no pueda
    /// desplazar vertical. Esto lo cubre <b>sin poder desplazar de más</b>: si
    /// la lista ya lo atendió, el evento no llega y no se hace nada.</para>
    ///
    /// <para>Se busca el desplazador de la lista una sola vez y se guarda: la
    /// rueda llega decenas de veces por segundo y recorrer el árbol visual en
    /// cada una no tiene sentido.</para>
    /// </summary>
    private void TableScroller_PointerWheelChanged(object sender, PointerRoutedEventArgs e)
    {
        _rowsScroller ??= FindScrollViewer(RowsList);
        if (_rowsScroller is null) return;

        int delta = e.GetCurrentPoint(RowsList).Properties.MouseWheelDelta;
        if (delta == 0) return;

        // Tres renglones por muesca, como cualquier lista del sistema.
        _rowsScroller.ChangeView(null, _rowsScroller.VerticalOffset - delta * 3.0 / 5, null, disableAnimation: true);

        e.Handled = true;
    }

    private ScrollViewer? _rowsScroller;

    private static ScrollViewer? FindScrollViewer(DependencyObject root)
    {
        for (int i = 0; i < Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChildrenCount(root); i++)
        {
            DependencyObject child = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChild(root, i);

            if (child is ScrollViewer found) return found;
            if (FindScrollViewer(child) is { } deeper) return deeper;
        }

        return null;
    }

    /// <summary>
    /// Completa lo seleccionado, o todo lo que esté incompleto si no hay
    /// selección: es lo que el usuario quiere arreglar cuando aprieta esto sin
    /// haber elegido nada.
    /// </summary>
    /// <summary>
    /// Publica la selección para «Solo la selección» de General (R3-4). La de
    /// la vista <b>activa</b> manda, y se limpia al salir: sin eso, el alcance
    /// seguiría apuntando a lo que había seleccionado dos pantallas atrás.
    /// </summary>
    private void Rows_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        // ST-202: por DELTA, no releyendo `SelectedItems`. Con 12 000 renglones
        // y la tabla entera marcada, cada Mayús+flecha recorría los 12 000
        // —cruzando la frontera del control por cada uno— para publicar una
        // selección que solo había cambiado en un elemento.
        foreach (SongRowViewModel row in e.RemovedItems.OfType<SongRowViewModel>()) _selectedIds.Remove(row.Id);
        foreach (SongRowViewModel row in e.AddedItems.OfType<SongRowViewModel>()) _selectedIds.Add(row.Id);

        ViewModel.Library.PublishSelectionForSync([.. _selectedIds]);
    }

    /// <summary>
    /// Lo marcado, que se lleva sumando y restando lo que avisa el control. Se
    /// vacía cuando la tabla se rehace: sus renglones son objetos nuevos, así
    /// que el control suelta la selección, y quedarse con la anterior sería
    /// publicar canciones que ya nadie ve marcadas.
    /// </summary>
    private readonly HashSet<Guid> _selectedIds = [];

    private void OnViewModelChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(SongsViewModel.Rows)) _selectedIds.Clear();
    }

    protected override void OnNavigatedFrom(Microsoft.UI.Xaml.Navigation.NavigationEventArgs e)
    {
        base.OnNavigatedFrom(e);
        ViewModel.PropertyChanged -= OnViewModelChanged;
        ViewModel.Library.ClearSelectionForSync();
    }

    /// <summary>
    /// Ctrl+A marca toda la tabla y Escape la desmarca. Ninguno de los dos viene
    /// de fábrica con <c>SelectionMode="Extended"</c>, que cubre clic,
    /// Ctrl+clic, Mayús+clic, flechas y Mayús+flechas, y nada más.
    ///
    /// <para>Van por las operaciones de RANGO: <c>SelectAll</c> y
    /// <c>DeselectRange</c> avisan <b>una sola vez</b> y no materializan lo que
    /// está virtualizado, mientras que agregar o quitar de <c>SelectedItems</c>
    /// uno por uno serían 12 000 avisos.</para>
    /// </summary>
    private void Page_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        switch (e.Key)
        {
            case Windows.System.VirtualKey.Escape:
                if (RowsList.SelectedItems.Count > 0)
                {
                    RowsList.DeselectRange(
                        new Microsoft.UI.Xaml.Data.ItemIndexRange(0, (uint)ViewModel.Rows.Count));
                }

                e.Handled = true;
                break;

            case Windows.System.VirtualKey.A when IsControlDown():
                RowsList.SelectAll();
                e.Handled = true;
                break;
        }
    }

    private static bool IsControlDown() =>
        Microsoft.UI.Input.InputKeyboardSource
            .GetKeyStateForCurrentThread(Windows.System.VirtualKey.Control)
            .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);

    private async void Enrich_Click(object sender, RoutedEventArgs e)
    {
        List<Guid> selected = [.. RowsList.SelectedItems.OfType<SongRowViewModel>().Select(row => row.Id)];
        await ViewModel.Library.EnrichAsync(selected);
    }

    private void Similar_Click(object sender, RoutedEventArgs e) =>
        Frame.Navigate(typeof(SimilarItemsPage), null,
            new Microsoft.UI.Xaml.Media.Animation.DrillInNavigationTransitionInfo());

    // MARK: - Agregar archivos

    private async void AddFiles_Click(object sender, RoutedEventArgs e)
    {
        IReadOnlyList<string> paths = await FilePickers.PickFilesAsync(
            CoverArtAssets.AudioExtensions);
        if (paths.Count > 0) Add(paths);
    }

    private async void AddFolder_Click(object sender, RoutedEventArgs e)
    {
        string? folder = await FilePickers.PickFolderAsync();
        if (folder is not null) Add([folder]);
    }

    private void Add(IEnumerable<string> paths)
    {
        ViewModel.Library.AddDroppedFiles(paths, LibraryItemKind.Music);
        ViewModel.Refresh();
    }

    // MARK: - Arrastrar y soltar

    private void Page_DragOver(object sender, DragEventArgs e)
    {
        if (!e.DataView.Contains(StandardDataFormats.StorageItems)) return;

        e.AcceptedOperation = DataPackageOperation.Copy;
        e.DragUIOverride.Caption = AppStrings.LibraryDropHint(LibraryItemKind.Music);
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

    // MARK: - Menú contextual del renglón

    /// <summary>
    /// El menú §4 del documento de paridad. Lo que se muestra lo decide Core
    /// (<see cref="MediaTableContextMenu"/>); acá se arma el alcance con el
    /// criterio de Finder y se ejecuta lo elegido.
    /// </summary>
    private void Rows_ContextRequested(UIElement sender, ContextRequestedEventArgs args)
    {
        if (RowFrom(args.OriginalSource) is not { } row) return;

        // Regla 0.1: clic derecho sobre algo seleccionado alcanza a toda la
        // selección; sobre algo que no lo está, solo a eso — y la selección
        // anterior no se pierde.
        IReadOnlyList<Guid> reached = GridSelection.EffectiveIds(
            row.Id, [.. RowsList.SelectedItems.OfType<SongRowViewModel>().Select(selected => selected.Id)]);

        List<LibraryItem> items = [.. ViewModel.Library.Items.Where(item => reached.Contains(item.Id))];
        if (items.Count == 0) return;

        MenuFlyout? menu = ContextMenuBuilder.Build(
            MediaTableContextMenu.Build(items[0].Kind, ScopeOf(items), CategoriesFor(items[0].Kind))
                // Editar metadata en lote todavía no tiene pantalla (queda
                // anotado en ESTADO-PORT): mostrar el ítem sería ofrecer algo
                // que no hace nada.
                .Where(entry => entry.Id != "info.batch").ToList(),
            id => Invoke(id, row, items));

        menu?.ShowAt(sender, new FlyoutShowOptions
        {
            Position = args.TryGetPosition(sender, out var point) ? point : null
        });

        args.Handled = true;
    }

    /// <summary>
    /// El renglón al que pertenece lo que se clickeó.
    ///
    /// <para>No alcanza con mirar el <c>DataContext</c> del origen: dentro de
    /// cada renglón, las celdas tienen el suyo propio (<c>SongCell</c>), así que
    /// un clic derecho sobre cualquier columna que no sea el título no
    /// encontraba nada y el menú <b>no aparecía</b>. Hay que subir por el árbol
    /// hasta el renglón.</para>
    /// </summary>
    private static SongRowViewModel? RowFrom(object? source)
    {
        for (var element = source as FrameworkElement; element is not null; element = element.Parent as FrameworkElement)
        {
            if (element.DataContext is SongRowViewModel row) return row;
        }

        return null;
    }

    /// <summary>Lo que Core necesita saber de lo alcanzado para decidir el menú.</summary>
    private MenuScope ScopeOf(IReadOnlyList<LibraryItem> items)
    {
        LibraryItem first = items[0];

        return new MenuScope(
            items.Count,
            AllFavorite: items.All(item => item.Metadata?.IsFavorite == true),
            HasCover: items.Any(item => item.Metadata?.CoverArtData is { Length: > 0 }),
            HasPoster: items.Any(item => item.Kind == LibraryItemKind.Video
                                         && item.Metadata?.CoverArtData is { Length: > 0 }),
            SingleAlbumWithTitle: items.All(item => item.Kind == LibraryItemKind.Music)
                                  && items.Select(item => LibraryGrouping.AlbumKeyOf(item, _preferences.ArtistGrouping)).Distinct().Count() == 1
                                  && first.Metadata?.Album is { Length: > 0 },
            HasAlbum: first.Metadata?.Album is { Length: > 0 },
            HasArtist: first.Metadata?.Artist is { Length: > 0 },
            AnyReady: items.Any(item => item.Status.State == LibraryItemState.Ready),
            DeviceConnected: _session.Device is { SupportsAuraContract: true });
    }

    private IReadOnlyList<string>? CategoriesFor(LibraryItemKind kind) => kind switch
    {
        LibraryItemKind.Video => [.. MediaCategoryNames.VideoCategories],
        LibraryItemKind.Photo => _preferences.PhotoCollections,
        _ => null
    };

    private async void Invoke(string id, SongRowViewModel row, IReadOnlyList<LibraryItem> items)
    {
        IReadOnlyList<Guid> ids = [.. items.Select(item => item.Id)];

        switch (id)
        {
            case "enrich": await ViewModel.Library.EnrichAsync(ids); break;
            case "lyrics": await ViewModel.Library.FetchLyricsAsync(ids); break;
            case "retag": ViewModel.Library.RetagFromFile(ids); break;
            case "cover.remove": ViewModel.Library.RemoveCover(ids); break;
            case "poster": await ViewModel.Library.FetchVideoPostersAsync(); break;
            case "poster.remove": ViewModel.Library.RemovePoster(ids); break;
            case "album.covers": await ShowAlbumCoverPickerAsync(items); break;

            case "favorite.add": ViewModel.Library.SetFavorite(ids, true); break;
            case "favorite.remove": ViewModel.Library.SetFavorite(ids, false); break;

            case "select.album": Select(ViewModel.Library.SameAlbumAs(row.Id)); break;
            case "select.artist": Select(ViewModel.Library.SameArtistAs(row.Id)); break;

            case "rename": await RenameAsync(items[0]); break;
            case "info": ShowInfo(row); break;

            // R3-2: la sincronización vive en General, así que el ítem lleva
            // ahí. **Todavía no acota a la selección**: `SyncViewModel` sabe
            // filtrar por tipo, no por elemento, y prometer un alcance que no
            // se aplica sería peor que llevar al lugar donde se decide. Anotado
            // en ESTADO-PORT.
            case "sync.selection": Frame.Navigate(typeof(DeviceListPage)); break;

            case "reveal": foreach (LibraryItem item in items) FilePickers.RevealInExplorer(item.SourcePath); break;
            case "similar": Frame.Navigate(typeof(SimilarItemsPage)); break;

            case "delete":
                ViewModel.Library.Remove(ids);
                ViewModel.Refresh();
                break;

            default:
                if (id.StartsWith("category:", StringComparison.Ordinal))
                {
                    foreach (Guid itemId in ids) ViewModel.Library.ApplyCategory(itemId, id["category:".Length..]);
                    ViewModel.Refresh();
                }
                break;
        }
    }

    private void Select(IReadOnlyList<Guid> ids)
    {
        RowsList.SelectedItems.Clear();

        foreach (SongRowViewModel candidate in ViewModel.Rows.Where(candidate => ids.Contains(candidate.Id)))
            RowsList.SelectedItems.Add(candidate);
    }

    /// <summary>
    /// Cambiar el nombre visible del elemento. Es el título de la metadata, no
    /// el archivo en disco: <b>Studio nunca renombra los archivos del
    /// usuario</b>.
    /// </summary>
    private async Task RenameAsync(LibraryItem item)
    {
        var box = new TextBox
        {
            Text = item.DisplayTitle,
            SelectionStart = 0,
            SelectionLength = item.DisplayTitle.Length
        };

        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "Cambiar nombre",
            Content = new StackPanel
            {
                Spacing = 8,
                Children =
                {
                    box,
                    new TextBlock
                    {
                        Text = "Cambia cómo se ve en tu biblioteca y en el iPod. El archivo en disco no se toca.",
                        TextWrapping = TextWrapping.Wrap,
                        Style = (Style)Application.Current.Resources["AuraCaptionTextStyle"]
                    }
                }
            },
            PrimaryButtonText = "Guardar",
            CloseButtonText = "Cancelar",
            DefaultButton = ContentDialogButton.Primary
        };

        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        if (box.Text.Trim() is not { Length: > 0 } name) return;

        TrackMetadata metadata = item.Metadata ?? new TrackMetadata();
        metadata.Title = name;

        ViewModel.Library.ApplyMetadataEdit(item.Id, metadata);
        ViewModel.Refresh();
    }

    /// <summary>
    /// La hoja de tapas del álbum (ST-104): <b>ofrece, no aplica</b>. Ni
    /// siquiera cuando encuentra una sola — dos ediciones de un disco tienen
    /// tapas distintas y las dos son correctas.
    /// </summary>
    private async Task ShowAlbumCoverPickerAsync(IReadOnlyList<LibraryItem> items)
    {
        LibraryItem first = items[0];
        string album = first.Metadata?.Album ?? "";
        string albumKey = LibraryGrouping.AlbumKeyOf(first, _preferences.ArtistGrouping);

        // El número de pistas que se puntúa es el del ÁLBUM en la biblioteca,
        // no el de lo que esté seleccionado: si no, elegir tres canciones de un
        // disco de doce haría fallar el criterio contra todas las ediciones.
        var facts = new AlbumFacts(album, first.Metadata?.Year,
            ViewModel.Library.SameAlbumAs(first.Id).Count);

        AlbumCoverCandidate? chosen = await AlbumCoverPicker.ShowAsync(
            XamlRoot, album, first.Metadata?.Artist, facts, _preferences.DeezerEnabled);

        if (chosen is null) return;

        // La eligió el usuario a mano, así que sí queda marcada como editada.
        ViewModel.Library.ApplyAlbumCover(albumKey, chosen.Data);
        ViewModel.Refresh();
    }

    /// <summary>
    /// Abre "Más información" y aplica lo que el usuario haya cambiado. La hoja
    /// devuelve <c>null</c> si canceló: entonces no se toca nada, ni siquiera la
    /// marca de "editado a mano".
    /// </summary>
    private async void ShowInfo(SongRowViewModel row)
    {
        MediaInfoResult? result = await MediaInfoDialog.ShowAsync(
            XamlRoot, row.Row.Item, availableCategories: null, row.Row.FileSizeBytes);

        if (result?.Metadata is null) return;

        ViewModel.Library.ApplyMetadataEdit(row.Id, result.Metadata);
        ViewModel.Refresh();
    }
}
