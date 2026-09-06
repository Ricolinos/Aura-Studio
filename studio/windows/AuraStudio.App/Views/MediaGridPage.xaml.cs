using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Data;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Navigation;
using Microsoft.UI.Xaml.Input;
using Windows.ApplicationModel.DataTransfer;
using Windows.Foundation;
using Windows.Storage;
using AuraStudio.App.Platform;
using Windows.Graphics.Imaging;
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

        // Addendum de ST-209: el arrastre se escucha TAMBIÉN sobre la propia
        // cuadrícula, y con `handledEventsToo` — es la parte que faltaba para que
        // el recuadro existiera de verdad.
        //
        // La capa de captura sigue DETRÁS de las tarjetas y sigue siendo la que
        // expresa el diseño (solo le llega lo que empezó en un hueco). Lo que se
        // descubrió al probarlo con la ventana (W7) es que a esa capa **no le
        // llega nada**: el `ScrollViewer` del `GridView` se queda con el puntero
        // en toda su superficie, huecos incluidos, y marca el evento como
        // manejado. Escuchar acá, sin depender de fondos ni de orden en el
        // árbol, es lo que tiene que garantizar que el gesto llegue.
        AttachMarqueeHandlers(CardsView);

        // Y sobre el `ScrollViewer` de adentro, en cuanto exista: si el evento
        // se atendiera ahí y no llegara a burbujear hasta la cuadrícula, este es
        // el único lugar donde se lo puede ver. Es enganche de más a propósito
        // —los manejadores se defienden solos de que el mismo gesto llegue dos
        // veces— y la traza dice por qué ruta entró cada uno.
        CardsView.Loaded += (_, _) =>
        {
            if (FindScrollViewer(CardsView) is not { } scroll) return;
            if (_marqueeScroll is not null) return;

            _marqueeScroll = scroll;
            AttachMarqueeHandlers(scroll);

            MarqueeTrace.Write("Attach   scroll=sí");
        };

        MarqueeTrace.Session($"MediaGridPage {DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss}");
        MarqueeTrace.Write("Attach   grid=sí capa=sí");
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

    // MARK: - Arrastre de selección (ST-209)

    /// <summary>
    /// El arrastre en curso, o <c>null</c> si no hay ninguno. Toda la decisión
    /// —qué toca el recuadro, qué selección resulta— vive en Core; acá solo se
    /// traduce pulsar/mover/soltar a puntos y modificadores.
    /// </summary>
    private GridMarqueeDrag? _marquee;

    /// <summary>
    /// El <c>ScrollViewer</c> al que se le engancharon los manejadores, si se
    /// encontró. Se guarda solo para no engancharlo dos veces.
    /// </summary>
    private ScrollViewer? _marqueeScroll;

    /// <summary>
    /// Los cuatro manejadores del arrastre sobre un elemento, con
    /// <c>handledEventsToo</c>: es la forma de ver un evento que otro control ya
    /// marcó como atendido, que es exactamente lo que hace el
    /// <c>ScrollViewer</c> de la cuadrícula con el puntero.
    /// </summary>
    private void AttachMarqueeHandlers(UIElement element)
    {
        element.AddHandler(UIElement.PointerPressedEvent,
            new PointerEventHandler(Marquee_PointerPressed), handledEventsToo: true);
        element.AddHandler(UIElement.PointerMovedEvent,
            new PointerEventHandler(Marquee_PointerMoved), handledEventsToo: true);
        element.AddHandler(UIElement.PointerReleasedEvent,
            new PointerEventHandler(Marquee_PointerReleased), handledEventsToo: true);
        element.AddHandler(UIElement.PointerCaptureLostEvent,
            new PointerEventHandler(Marquee_PointerCaptureLost), handledEventsToo: true);
    }

    private ScrollViewer? _cardsScroll;

    /// <summary>
    /// El desplazamiento del contenido, para el autoscroll de los bordes. Se
    /// busca una vez: está adentro de la plantilla del control y no cambia.
    /// </summary>
    private ScrollViewer? CardsScroll => _cardsScroll ??= FindScrollViewer(CardsView);

    private static ScrollViewer? FindScrollViewer(DependencyObject root)
    {
        int children = VisualTreeHelper.GetChildrenCount(root);

        for (int index = 0; index < children; index++)
        {
            DependencyObject child = VisualTreeHelper.GetChild(root, index);

            if (child is ScrollViewer found) return found;
            if (FindScrollViewer(child) is { } deeper) return deeper;
        }

        return null;
    }

    private static GridSelectionModifiers ModifiersNow()
    {
        GridSelectionModifiers modifiers = GridSelectionModifiers.None;

        if (IsDown(Windows.System.VirtualKey.Shift)) modifiers |= GridSelectionModifiers.Extend;
        if (IsDown(Windows.System.VirtualKey.Control)) modifiers |= GridSelectionModifiers.Toggle;

        return modifiers;

        static bool IsDown(Windows.System.VirtualKey key) =>
            Microsoft.UI.Input.InputKeyboardSource
                .GetKeyStateForCurrentThread(key)
                .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);
    }

    /// <summary>
    /// La cadena de padres desde el origen del evento, para la traza. Es lo que
    /// permite ver <b>por qué</b> se decidió "tarjeta" o "hueco" sin tener la
    /// ventana delante.
    /// </summary>
    private static string ParentChain(object? source)
    {
        List<string> chain = [];

        for (var element = source as DependencyObject; element is not null && chain.Count < 12;
             element = VisualTreeHelper.GetParent(element))
        {
            chain.Add(element.GetType().Name);
            if (element is GridView) break;
        }

        return chain.Count == 0 ? "(sin árbol)" : string.Join(" > ", chain);
    }

    /// <summary>
    /// Si ese punto de partida es una tarjeta. Arrastrar DESDE una tarjeta es su
    /// propio gesto —seleccionarla, moverla—; el recuadro es solo lo que empieza
    /// en un hueco.
    ///
    /// <para>Se mira el árbol visual desde el origen del evento hacia arriba
    /// hasta el contenedor: es lo mismo que hace el menú contextual para saber a
    /// qué fila pertenece un clic, y no depende de fondos ni de qué elemento
    /// quedó encima.</para>
    /// </summary>
    private static bool StartedOnACard(object? source)
    {
        for (var element = source as DependencyObject; element is not null;
             element = VisualTreeHelper.GetParent(element))
        {
            // `SelectorItem` además de `GridViewItem`: es la clase base, y una
            // plantilla que devolviera otro contenedor seguiría siendo una
            // tarjeta.
            if (element is SelectorItem) return true;
            if (element is GridView) return false;
        }

        return false;
    }

    private void Marquee_PointerPressed(object sender, PointerRoutedEventArgs e)
    {
        string route = ReferenceEquals(sender, CardsView) ? "grid"
            : ReferenceEquals(sender, MarqueeCapture) ? "capa"
            : sender is ScrollViewer ? "scroll" : sender?.GetType().Name ?? "?";

        // Solo el mouse y el lápiz: con el dedo, arrastrar es desplazar.
        if (e.Pointer.PointerDeviceType == Microsoft.UI.Input.PointerDeviceType.Touch) return;

        bool onCard = StartedOnACard(e.OriginalSource);

        if (MarqueeTrace.Enabled)
        {
            Point where = CardsView.ItemsPanelRoot is { } p
                ? e.GetCurrentPoint(p).Position
                : e.GetCurrentPoint(CardsView).Position;

            MarqueeTrace.Write(
                $"Pressed  ruta={route} handled={e.Handled} yaArrastrando={_marquee is not null} " +
                $"decision={(onCard ? "tarjeta" : "hueco")} pos=({where.X:0},{where.Y:0}) " +
                $"origen={e.OriginalSource?.GetType().Name ?? "null"} cadena={ParentChain(e.OriginalSource)}");
        }

        // El mismo gesto puede llegar por varios caminos (la capa de atrás, el
        // ScrollViewer y la cuadrícula): el segundo no puede volver a empezarlo.
        if (_marquee is not null) return;

        if (onCard) return;
        if (CardsView.ItemsPanelRoot is not { } panel) return;

        Point origin = e.GetCurrentPoint(panel).Position;

        // La selección de partida se congela ACÁ: cada posición del puntero se
        // resuelve contra ESA. Si no, agrandar y achicar el recuadro no sería
        // reversible — lo que entró no volvería a salir.
        _marquee = new GridMarqueeDrag(
            new GridPoint(origin.X, origin.Y),
            [.. CardsView.SelectedItems.OfType<MediaCard>().Select(card => card.Id)],
            ModifiersNow());

        // Se captura sobre la cuadrícula y no sobre la capa de atrás: es la que
        // recibe el gesto, y así los movimientos siguen llegando aunque el
        // puntero salga de la ventana.
        bool captured = CardsView.CapturePointer(e.Pointer);
        _marqueeMoves = 0;

        MarqueeTrace.Write(
            $"Start    captura={captured} origen=({origin.X:0},{origin.Y:0}) " +
            $"seleccionDePartida={CardsView.SelectedItems.Count} mods={ModifiersNow()}");

        e.Handled = true;
    }

    /// <summary>Cuántos movimientos llegaron en el arrastre en curso, para la traza.</summary>
    private int _marqueeMoves;

    private void Marquee_PointerMoved(object sender, PointerRoutedEventArgs e)
    {
        if (_marquee is not { } drag) return;
        if (CardsView.ItemsPanelRoot is not { } panel) return;

        Point point = e.GetCurrentPoint(panel).Position;
        Dictionary<string, GridRect> frames = RealizedFrames(panel);
        SelectionDelta delta = drag.MoveTo(new GridPoint(point.X, point.Y), frames);

        _marqueeMoves++;

        if (MarqueeTrace.Enabled)
        {
            MarqueeTrace.Write(
                $"Moved  #{_marqueeMoves} pos=({point.X:0},{point.Y:0}) " +
                $"rect=({drag.Rect.X:0},{drag.Rect.Y:0},{drag.Rect.Width:0}x{drag.Rect.Height:0}) " +
                $"marcos={frames.Count} entran={delta.Selected.Count} salen={delta.Deselected.Count} " +
                $"marcados={drag.Current.Count}");
        }

        ApplyToControl(delta);
        DrawMarquee(drag.Rect, panel);
        AutoScroll(e.GetCurrentPoint(CardsView).Position.Y);

        e.Handled = true;
    }

    /// <summary>
    /// El puntero se fue a otro lado —lo tomó el <c>ScrollViewer</c>, se cerró la
    /// ventana— en medio del arrastre. Se anota aparte de soltar: si el gesto
    /// muere por acá, la traza lo dice y no parece que el usuario haya soltado.
    /// </summary>
    private void Marquee_PointerCaptureLost(object sender, PointerRoutedEventArgs e)
    {
        if (_marquee is null) return;

        MarqueeTrace.Write($"CaptureLost  tras {_marqueeMoves} movimientos");
        EndMarquee(applyEmptyClick: false);
    }

    private void Marquee_PointerReleased(object sender, PointerRoutedEventArgs e)
    {
        if (_marquee is null) return;

        MarqueeTrace.Write($"Released  tras {_marqueeMoves} movimientos");
        EndMarquee(applyEmptyClick: true);

        e.Handled = true;
    }

    private void EndMarquee(bool applyEmptyClick)
    {
        if (_marquee is not { } drag) return;

        _marquee = null;
        MarqueeBox.Visibility = Visibility.Collapsed;
        CardsView.ReleasePointerCaptures();

        // Un clic en un hueco, sin arrastre, limpia la selección — como en el
        // Explorador. Con Mayús o Control apretados no toca nada: ahí el usuario
        // está construyendo una selección, no descartándola.
        //
        // Solo al SOLTAR: si el puntero se perdió a mitad de camino, el usuario
        // no hizo clic en ningún hueco.
        if (applyEmptyClick && drag.Rect.IsEmpty && drag.Modifiers == GridSelectionModifiers.None)
            DeselectAll();
    }

    /// <summary>
    /// Los marcos de las tarjetas <b>realizadas</b>, en coordenadas del
    /// contenido. Se arman en cada movimiento y no se van anotando: con la
    /// virtualización son las decenas que se ven —no las mil que hay—, y
    /// recalcularlas es más barato que mantener al día un mapa que se desactualiza
    /// justo cuando la cuadrícula se desplaza sola.
    /// </summary>
    private static Dictionary<string, GridRect> RealizedFrames(Panel panel)
    {
        var frames = new Dictionary<string, GridRect>(StringComparer.Ordinal);

        foreach (UIElement child in panel.Children)
        {
            if (child is not GridViewItem { Content: MediaCard card } container) continue;

            Point origin = container.TransformToVisual(panel).TransformPoint(new Point(0, 0));

            frames[card.Id] = new GridRect(
                origin.X, origin.Y, container.ActualWidth, container.ActualHeight);
        }

        return frames;
    }

    /// <summary>
    /// Lo que cambió, aplicado <b>por rangos</b>: <c>SelectRange</c> y
    /// <c>DeselectRange</c> no desvirtualizan la cuadrícula, y son un aviso de
    /// selección en vez de uno por tarjeta (ST-202).
    /// </summary>
    private void ApplyToControl(SelectionDelta delta)
    {
        if (delta.IsEmpty) return;

        var indexOf = new Dictionary<string, int>(ViewModel.Cards.Count, StringComparer.Ordinal);
        for (int index = 0; index < ViewModel.Cards.Count; index++) indexOf[ViewModel.Cards[index].Id] = index;

        foreach (ItemIndexRange range in RangesOf(delta.Selected, indexOf)) CardsView.SelectRange(range);
        foreach (ItemIndexRange range in RangesOf(delta.Deselected, indexOf)) CardsView.DeselectRange(range);
    }

    /// <summary>
    /// Los índices de esas tarjetas, agrupados en tramos contiguos: una tarjeta
    /// suelta es un rango de uno, y una fila entera es un rango de cinco.
    /// </summary>
    private static IEnumerable<ItemIndexRange> RangesOf(
        IReadOnlyList<string> ids, Dictionary<string, int> indexOf)
    {
        List<int> indexes = [];
        foreach (string id in ids)
        {
            if (indexOf.TryGetValue(id, out int index)) indexes.Add(index);
        }

        if (indexes.Count == 0) yield break;

        indexes.Sort();

        int start = indexes[0];
        int length = 1;

        for (int position = 1; position < indexes.Count; position++)
        {
            if (indexes[position] == start + length)
            {
                length++;
                continue;
            }

            yield return new ItemIndexRange(start, (uint)length);
            start = indexes[position];
            length = 1;
        }

        yield return new ItemIndexRange(start, (uint)length);
    }

    /// <summary>
    /// El recuadro se dibuja en coordenadas de la ventana, así que se traduce
    /// desde las del contenido en cada movimiento: durante el autoscroll el
    /// contenido se mueve debajo del puntero.
    /// </summary>
    private void DrawMarquee(GridRect rect, Panel panel)
    {
        if (rect.IsEmpty)
        {
            MarqueeBox.Visibility = Visibility.Collapsed;
            return;
        }

        Point corner = panel.TransformToVisual(MarqueeLayer)
            .TransformPoint(new Point(rect.X, rect.Y));

        Canvas.SetLeft(MarqueeBox, corner.X);
        Canvas.SetTop(MarqueeBox, corner.Y);
        MarqueeBox.Width = rect.Width;
        MarqueeBox.Height = rect.Height;
        MarqueeBox.Visibility = Visibility.Visible;
    }

    /// <summary>
    /// Cerca de los bordes la cuadrícula se desplaza sola: sin esto no se puede
    /// seleccionar más de lo que entra en pantalla. Cuánto, lo decide Core.
    /// </summary>
    private void AutoScroll(double pointerY)
    {
        if (CardsScroll is not { } scroll) return;

        double speed = GridAutoScroll.SpeedFor(pointerY, CardsView.ActualHeight);
        if (speed == 0) return;

        scroll.ChangeView(null, scroll.VerticalOffset + speed, null, disableAnimation: true);
    }

    // MARK: - Portadas

    /// <summary>
    /// El lado al que se decodifica la miniatura: 152 pt de tarjeta a 2×. Va en
    /// el <b>lado mayor</b>, nunca en los dos: fijar ambos deforma una portada
    /// que no sea cuadrada — el mismo bug que se corrigió en las miniaturas de
    /// macOS.
    /// </summary>
    private const int CoverSide = 304;

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

    /// <summary>
    /// El contenedor se fue de pantalla: lo que estuviera cargando ya no le
    /// sirve a nadie (ST-205).
    /// </summary>
    private void Cover_Unloaded(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement element) CoverThumbnails.Cancel(element);
    }

    /// <summary>
    /// La imagen se carga al aparecer la tarjeta y no al armar la lista: en una
    /// biblioteca de cientos de álbumes, decodificarlas todas de golpe bloquea
    /// la interfaz aunque solo se vean doce.
    ///
    /// <para>Desde ST-205 pasa por <see cref="CoverThumbnailCache"/>: la primera
    /// vez se lee el archivo y se decodifica <b>ya reducido</b>, fuera del hilo
    /// de interfaz; las siguientes —desplazarse y volver— se responden desde
    /// memoria sin tocar el disco.</para>
    /// </summary>
    private async void LoadCover(Image? image)
    {
        if (image is null) return;

        // Lo primero, antes de cualquier espera: cortar lo que este contenedor
        // estuviera cargando y borrar lo que muestre. Si no, mientras llega la
        // nueva se sigue viendo la portada del álbum anterior.
        CancellationToken ct = CoverThumbnails.Restart(image);
        image.Source = null;

        if (image.DataContext is not MediaCard card) return;

        try
        {
            SoftwareBitmap? thumbnail = card.CoverItem is { } coverItem
                ? await CoverThumbnails.ForItemAsync(ViewModel.Library, coverItem, CoverSide, ct)
                : card.ImagePath is { Length: > 0 } path
                    ? await CoverThumbnails.ForPathAsync(path, CoverSide, ct)
                    : null;

            if (thumbnail is null || ct.IsCancellationRequested) return;

            // La celda pudo haber cambiado de tarjeta mientras se decodificaba:
            // pintar acá sería poner la portada de una en el lugar de otra.
            if (!ReferenceEquals(image.DataContext, card)) return;

            ImageSource? source = await CoverThumbnails.SourceAsync(thumbnail);
            if (source is null || ct.IsCancellationRequested) return;
            if (!ReferenceEquals(image.DataContext, card)) return;

            image.Source = source;
        }
        catch (OperationCanceledException)
        {
            // El contenedor se recicló mientras se leía. No es un error.
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
    /// "Buscar carátulas del álbum..." con uno solo, "Buscar carátulas de N
    /// álbumes..." con varios (ST-104, ST-206 y su addendum).
    ///
    /// <para>Con un álbum se abre su hoja y <b>no se aplica nada solo</b>: dos
    /// ediciones de un disco tienen tapas distintas y las dos son correctas. Con
    /// varios eso no se puede preguntar mil veces, así que corre el lote de
    /// R2-3 —que aplica sola la que supere el umbral— y los dudosos se revisan
    /// de a uno en la cola.</para>
    ///
    /// <para>No es lo mismo que "Aplicar carátula recomendada a N álbumes", que
    /// no pregunta nunca: esta sí.</para>
    /// </summary>
    private async Task SearchAlbumCoversAsync(IReadOnlyList<MediaCard> reached)
    {
        LibraryViewModel library = ViewModel.Library;

        IReadOnlyList<AlbumCoverJob> jobs = library.AlbumCoverJobsFor(
            ViewModel.AlbumCoverTargets(reached).Select(target => target.AlbumKey));

        if (jobs.Count == 0) return;

        if (jobs is [{ } only])
        {
            await ShowAlbumCoverPickerAsync(only);
            return;
        }

        AlbumCoverBatchResult result =
            await library.ApplyRecommendedCoversAsync(jobs, _preferences.DeezerEnabled);

        library.StatusMessage = result.Summary();
        ViewModel.Refresh();

        await ReviewPendingCoversAsync(result.Pending);
    }

    /// <summary>La hoja de tapas de un álbum: <b>ofrece, no aplica</b>.</summary>
    private async Task ShowAlbumCoverPickerAsync(AlbumCoverJob job)
    {
        AlbumCoverCandidate? chosen = await AlbumCoverPicker.ShowAsync(
            XamlRoot, job.Title, job.Artist, job.Facts, _preferences.DeezerEnabled);

        if (chosen is null) return;

        // La eligió a mano: esta sí queda marcada como editada por el usuario.
        ViewModel.Library.ApplyAlbumCover(job.AlbumKey, chosen.Data);
        ViewModel.Refresh();
    }

    /// <summary>
    /// La acción automática de R2-3. Aplica solo lo seguro y <b>dice qué quedó
    /// pendiente</b>: un resumen que no cuenta lo que no se hizo es peor que no
    /// tener resumen.
    ///
    /// <para>Los que quedaron sin una opción segura se revisan de a uno, en la
    /// cola de ST-205: antes, con más de uno, no se abría ninguna hoja.</para>
    /// </summary>
    private async Task ApplyRecommendedCoversAsync(IReadOnlyList<MediaCard> reached)
    {
        LibraryViewModel library = ViewModel.Library;

        IReadOnlyList<AlbumCoverJob> jobs = library.AlbumCoverJobsFor(
            ViewModel.AlbumCoverTargets(reached).Select(target => target.AlbumKey));

        if (jobs.Count == 0)
        {
            library.StatusMessage = new AlbumCoverBatchResult(0, [], false).Summary();
            return;
        }

        AlbumCoverBatchResult result =
            await library.ApplyRecommendedCoversAsync(jobs, _preferences.DeezerEnabled);

        library.StatusMessage = result.Summary();
        ViewModel.Refresh();

        await ReviewPendingCoversAsync(result.Pending);
    }

    /// <summary>
    /// Los álbumes que el lote dejó sin una opción segura se revisan <b>de a
    /// uno</b>: con uno, su hoja de siempre; con varios, la cola que dice
    /// "Álbum 2 de 7" y ofrece omitir ese o cancelar el resto (ST-205).
    /// </summary>
    private async Task ReviewPendingCoversAsync(IReadOnlyList<AlbumCoverJob> pending)
    {
        if (pending.Count == 0) return;

        if (pending is [{ } only])
        {
            await ShowAlbumCoverPickerAsync(only);
            return;
        }

        int applied = await AlbumCoverPicker.ReviewQueueAsync(
            XamlRoot, pending, _preferences.DeezerEnabled,
            (job, chosen) => ViewModel.Library.ApplyAlbumCover(job.AlbumKey, chosen.Data, inBatch: true));

        if (applied == 0) return;

        ViewModel.Library.FinishAlbumCoverBatch();
        ViewModel.Refresh();
    }

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
            case "album.covers": await SearchAlbumCoversAsync(reached); break;

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
