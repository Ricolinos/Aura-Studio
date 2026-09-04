using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using AuraStudio.App.Platform;
using AuraStudio.App.Resources;
using AuraStudio.App.Services;
using AuraStudio.Core;
using AuraStudio.Core.Library;
using AuraStudio.Core.Networking;

namespace AuraStudio.App.ViewModels;

/// <summary>
/// La biblioteca local: un solo modelo para todas las secciones (Canciones,
/// Álbumes, Artistas, Películas, Series, Fotos). Es singleton a propósito —
/// todas las vistas miran el mismo catálogo, y con una instancia por página el
/// arrastre en una no se vería en la otra.
///
/// <para>Todo lo que decide algo —clasificar, agrupar, ordenar, qué entra al
/// soltar— vive en Core y está probado ahí. Acá solo queda el estado observable
/// y lo que la interfaz necesita.</para>
/// </summary>
public sealed partial class LibraryViewModel : ViewModelBase
{
    private readonly IAppPreferences _preferences;
    private readonly ILibraryProcessor _processor;
    private readonly IEnrichmentService _enrichment;
    private LibraryStore _store;

    /// <summary>
    /// El catálogo <b>entero</b>, incluidos los elementos cuyo archivo no está
    /// accesible ahora. Es lo que se guarda: cualquier cosa que se escriba a
    /// partir de una lista más chica pierde datos del usuario.
    /// </summary>
    [ObservableProperty]
    public partial IReadOnlyList<LibraryItem> Items { get; private set; }

    /// <summary>
    /// Lo que se puede mostrar: los elementos cuyo archivo existe. <b>Todas las
    /// vistas usan esta</b>; ninguna ruta de guardado la usa jamás.
    /// </summary>
    [ObservableProperty]
    public partial IReadOnlyList<LibraryItem> AvailableItems { get; private set; }

    [ObservableProperty]
    public partial string StatusMessage { get; set; }

    /// <summary>Lo último que pasó al soltar archivos; `null` mientras no haya nada que decir.</summary>
    [ObservableProperty]
    public partial string? LastDropMessage { get; set; }

    /// <summary>
    /// Por qué no se pudo leer el catálogo, si es que no se pudo. <b>No es lo
    /// mismo que estar vacía</b>, y hasta que esto existió se veían igual.
    /// </summary>
    [ObservableProperty]
    public partial string? LoadError { get; private set; }

    /// <summary>
    /// Cuántos elementos del catálogo tienen su archivo faltante. Pasa al
    /// apuntar a la carpeta de biblioteca de otra computadora: el catálogo se
    /// lee bien, pero los archivos no están donde dice.
    /// </summary>
    [ObservableProperty]
    public partial int MissingFileCount { get; private set; }

    public LibraryViewModel(IAppPreferences preferences, ILibraryProcessor processor, IEnrichmentService enrichment)
    {
        _preferences = preferences;
        _processor = processor;
        _enrichment = enrichment;
        _store = new LibraryStore(preferences.LibraryPath);
        Items = [];
        AvailableItems = [];
        StatusMessage = "";
        Reload();

        // R2-4: cambiar cómo se agrupan las colaboraciones reagrupa la
        // biblioteca entera. Sin esto, el ajuste solo surtiría efecto al
        // reiniciar la app, que es la clase de cosa que se siente como un bug.
        preferences.Changed += (_, property) =>
        {
            if (property is nameof(IAppPreferences.GroupCollaborations)
                         or nameof(IAppPreferences.ArtistGroupingExceptions))
            {
                OnPropertyChanged(nameof(Items));
            }
        };
    }

    // MARK: - Completar en línea

    /// <summary>
    /// Completa lo que falte: álbum, año, número de pista, carátula y letra.
    ///
    /// <para>Sin selección trabaja sobre <b>lo que está incompleto</b>, que es
    /// lo que el usuario quiere arreglar; con selección, solo sobre eso. Nunca
    /// pisa lo que se editó a mano.</para>
    /// </summary>
    public async Task EnrichAsync(IReadOnlyCollection<Guid>? ids = null, CancellationToken ct = default)
    {
        List<LibraryItem> targets = ids is { Count: > 0 }
            ? [.. Items.Where(item => ids.Contains(item.Id))]
            : [.. Items.Where(item => item.Kind == LibraryItemKind.Music && item.Metadata?.IsComplete != true)];

        if (targets.Count == 0)
        {
            StatusMessage = "No hay nada que completar: todo tiene título, artista y álbum.";
            return;
        }

        IsEnriching = true;
        StatusMessage = $"Completando {targets.Count} elemento(s)…";

        try
        {
            EnrichmentReport report = await _enrichment.EnrichAsync(
                targets, new Progress<string>(title => StatusMessage = $"Completando {title}…"), ct);

            Save();
            RefreshAvailable();
            OnPropertyChanged(nameof(Items));

            StatusMessage = report.Summary;
        }
        catch (OperationCanceledException) { StatusMessage = "Se detuvo la búsqueda en línea."; }
        finally { IsEnriching = false; }
    }

    /// <summary>
    /// Le pone una tapa elegida a mano a <b>todas las canciones del álbum</b> y
    /// la marca como decisión del usuario: ningún enriquecimiento posterior la
    /// puede pisar (ST-104).
    ///
    /// <para>En el iPod la tapa llega como <c>cover.jpg</c> en la carpeta del
    /// álbum, que la escribe la sincronización — acá no hace falta volver a
    /// preparar los archivos, a diferencia de macOS, que sí re-incrusta la
    /// imagen en el preparado.</para>
    /// </summary>
    /// <param name="markEditedByUser">
    /// Solo cuando la eligió el usuario a mano. La <b>automática</b> de R2-3 no
    /// la marca: <c>MetadataEditedByUser</c> significa "el usuario lo decidió",
    /// no "algo lo escribió", y blindar una tapa que nadie miró dejaría al
    /// álbum con ella para siempre, incluso cuando después aparezca una mejor.
    /// </param>
    public int ApplyAlbumCover(string albumKey, byte[] cover, bool markEditedByUser = true)
    {
        if (cover.Length == 0) return 0;

        // ST-141: la elegida a mano, la arrastrada y la recomendada entran
        // todas por acá, y todas quedan cuadradas. Se normaliza UNA vez, no una
        // por canción: es la misma imagen para todo el álbum.
        cover = WicSquareImageEncoder.SharedNormalizer.Normalize(cover);

        int applied = 0;

        foreach (LibraryItem item in Items.Where(item => item.Kind == LibraryItemKind.Music
                                                         && LibraryGrouping.AlbumKeyOf(item, ArtistGrouping) == albumKey))
        {
            (item.Metadata ??= new TrackMetadata()).CoverArtData = cover;
            if (markEditedByUser) item.MetadataEditedByUser = true;
            applied++;
        }

        if (applied == 0) return 0;

        Save();
        RefreshAvailable();
        OnPropertyChanged(nameof(Items));

        StatusMessage = applied == 1
            ? "Se cambió la tapa de 1 canción."
            : $"Se cambió la tapa de {applied} canciones.";

        return applied;
    }

    /// <summary>Los pósters de video que falten. Viajan pegados a su video.</summary>
    public async Task FetchVideoPostersAsync(CancellationToken ct = default)
    {
        IsEnriching = true;
        StatusMessage = "Buscando pósters de video…";

        try
        {
            int found = await _enrichment.FetchVideoPostersAsync(
                Items, new Progress<string>(text => StatusMessage = text), ct);

            if (found > 0) Save();

            StatusMessage = found == 0
                ? "No se consiguió ningún póster nuevo."
                : $"Se consiguieron {found} póster(s).";
        }
        catch (OperationCanceledException) { StatusMessage = "Se detuvo la búsqueda de pósters."; }
        finally { IsEnriching = false; }
    }

    /// <summary>Las fotos de artista que falten. Viajan al iPod en el próximo sync.</summary>
    public async Task FetchArtistImagesAsync(CancellationToken ct = default)
    {
        IsEnriching = true;
        StatusMessage = "Buscando fotos de artista…";

        try
        {
            ArtistImageBatch batch = await _enrichment.FetchArtistImagesAsync(
                Items, _preferences.LibraryPath,
                new Progress<string>(text => StatusMessage = text), ct);

            // El resumen sale del propio lote: distingue "no había nada" de
            // "el servicio está saturado", que mandan al usuario a hacer cosas
            // distintas.
            StatusMessage = batch.Summary;
        }
        catch (OperationCanceledException) { StatusMessage = "Se detuvo la búsqueda de fotos."; }
        finally { IsEnriching = false; }
    }

    [ObservableProperty]
    public partial bool IsEnriching { get; private set; }

    public string LibraryPath => _preferences.LibraryPath;

    // MARK: - Carga y guardado

    [RelayCommand]
    public void Reload()
    {
        _store = new LibraryStore(_preferences.LibraryPath);

        // Un archivo que el usuario borró del disco desde afuera deja de estar
        // en la biblioteca: mostrarlo sería ofrecer sincronizar algo que no
        // existe.
        IReadOnlyList<LibraryItem> loaded = _store.LoadItems(out string? error);
        LoadError = error;

        // **El catálogo se conserva completo, incluso lo que no se puede ver.**
        //
        // macOS descarta al leer los elementos cuyo archivo no está, y allá no
        // pasa nada: es su propia biblioteca, los archivos siempre están. En
        // Windows, con la biblioteca compartida del dueño, esa misma lógica
        // costó 2408 entradas reales: se descartaba al leer y después se
        // guardaba la lista recortada como si fuera el catálogo entero.
        //
        // Lo que no se puede abrir se oculta de las vistas (`AvailableItems`),
        // pero **nunca se pierde**: sigue en `Items` y se vuelve a escribir tal
        // cual. Si el archivo reaparece —otra computadora, un disco que se
        // vuelve a montar—, el elemento vuelve con toda su metadata.
        Items = loaded;
        RefreshAvailable();

        // Lo que quedó en cola —porque la app se cerró a media importación, o
        // porque un intento anterior falló— se reintenta al abrir. El catálogo
        // guarda esos estados como "en cola" justamente para esto; sin
        // reintentarlos, se quedarían así para siempre.
        // Solo lo DISPONIBLE: procesar un elemento cuyo archivo no está lo
        // marcaría como fallido y guardaría esa mentira en el catálogo del
        // usuario. Que no se pueda abrir ahora no significa que esté roto.
        IReadOnlyList<LibraryItem> pending =
            [.. AvailableItems.Where(item => item.Status.State == LibraryItemState.Queued)];

        if (pending.Count > 0) _ = ProcessAsync(pending);

        StartCoverNormalizationIfNeeded();
    }

    // --- Migración de carátulas a cuadradas (ST-141) ---

    private CancellationTokenSource? _coverNormalization;

    /// <summary>
    /// El hilo de la interfaz, capturado al construirse. La migración corre en
    /// el pool y escribe <c>StatusMessage</c> desde ahí; sin esto pasa lo mismo
    /// que en ST-131 —la sincronización se moría porque el avance se escribía
    /// desde otro hilo—. <c>null</c> si el modelo se construyera fuera del hilo
    /// de interfaz: entonces se escribe directo, que es degradar, no romper.
    /// </summary>
    private readonly Microsoft.UI.Dispatching.DispatcherQueue? _dispatcher =
        Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread();

    private void Dispatch(Action work)
    {
        if (_dispatcher is { HasThreadAccess: false })
        {
            _dispatcher.TryEnqueue(() => work());
            return;
        }

        work();
    }

    /// <summary>
    /// <c>true</c> mientras la pasada única de carátulas corre. La interfaz lo
    /// usa para mostrar el botón de detenerla.
    /// </summary>
    [ObservableProperty]
    public partial bool IsNormalizingCovers { get; private set; }

    /// <summary>
    /// Deja cuadradas las carátulas de una biblioteca hecha antes de ST-141.
    /// Corre <b>una sola vez</b> por biblioteca (la marca vive en
    /// <c>biblioteca.json</c>), en segundo plano y sin bloquear nada.
    ///
    /// <para>Se puede detener (<see cref="CancelCoverNormalization"/>) y se
    /// retoma sola: lo que ya está cuadrado se salta, así que la próxima
    /// apertura termina lo que falte. La marca se escribe <b>solo</b> si la
    /// pasada llegó al final.</para>
    /// </summary>
    private void StartCoverNormalizationIfNeeded()
    {
        if (_coverNormalization is not null) return;
        if (_store.CoversNormalized == CoverArtNormalization.NormalizedVersion) return;

        List<string> files = CoverNormalizationMigration.FilesToNormalize(Items, _store);
        if (files.Count == 0)
        {
            // Nada que migrar (biblioteca vacía, o sin carátulas): se marca
            // igual, para no volver a recorrer en cada apertura.
            MarkCoversNormalized();
            return;
        }

        var cancellation = new CancellationTokenSource();
        _coverNormalization = cancellation;
        IsNormalizingCovers = true;
        StatusMessage = $"Normalizando carátulas… 0 de {files.Count}";

        _ = Task.Run(() =>
        {
            CoverNormalizationMigration.Result result = CoverNormalizationMigration.Run(
                files, WicSquareImageEncoder.SharedNormalizer, cancellation.Token,
                onProgress: (done, total) =>
                    Dispatch(() => StatusMessage = $"Normalizando carátulas… {done} de {total}"));

            Dispatch(() => FinishCoverNormalization(result));
        }, cancellation.Token);
    }

    private void FinishCoverNormalization(CoverNormalizationMigration.Result result)
    {
        _coverNormalization?.Dispose();
        _coverNormalization = null;
        IsNormalizingCovers = false;

        if (result.Cancelled)
        {
            StatusMessage = "Se detuvo la normalización de carátulas. Lo que falte sigue la próxima vez.";
            return;
        }

        MarkCoversNormalized();

        if (result.Normalized == 0)
        {
            StatusMessage = "";
            return;
        }

        // Lo que quedó en memoria es la versión vieja (rectangular): se relee de
        // disco para que la app muestre lo mismo que se va a sincronizar.
        Reload();
        StatusMessage = result.Normalized == 1
            ? "Se normalizó 1 carátula: ahora es cuadrada."
            : $"Se normalizaron {result.Normalized} carátulas: ahora son cuadradas.";
    }

    private void MarkCoversNormalized()
    {
        _store.CoversNormalized = CoverArtNormalization.NormalizedVersion;
        Save();
    }

    /// <summary>
    /// Detiene la pasada. Lo hecho queda hecho; lo que falta se retoma la
    /// próxima vez que se abra la biblioteca.
    /// </summary>
    public void CancelCoverNormalization() => _coverNormalization?.Cancel();

    /// <summary>
    /// Guarda y vuelve a publicar la biblioteca. Lo usan las acciones que mutan
    /// elementos desde otra pantalla —los menús contextuales de las
    /// cuadrículas— para no tener que repetir los tres pasos y olvidarse de
    /// uno.
    /// </summary>
    public void SaveAndRefresh()
    {
        Save();
        RefreshAvailable();
        OnPropertyChanged(nameof(Items));
    }

    private void Save()
    {
        // SIEMPRE el catálogo entero. Guardar cualquier lista más chica —la
        // filtrada por archivos presentes, por ejemplo— borra datos del usuario.
        _store.SaveItems(Items);
        RefreshAvailable();
    }

    /// <summary>
    /// Vuelve a calcular qué se puede mostrar. Se llama después de CADA cambio
    /// de `Items`: si las dos listas se desincronizan, la interfaz muestra algo
    /// que el catálogo ya no dice, o al revés.
    /// </summary>
    private void RefreshAvailable()
    {
        AvailableItems = [.. Items.Where(item => File.Exists(item.SourcePath))];
        MissingFileCount = Items.Count - AvailableItems.Count;
        UpdateStatus();
    }

    // La barra de estado cuenta lo que el usuario puede ver, no lo que hay
    // guardado: lo que falta se explica aparte, en Ajustes.
    private void UpdateStatus() => StatusMessage = SummaryOf(AvailableItems);

    /// <summary>
    /// "128 canciones · 12 videos · 340 fotos" para la barra de estado. Se
    /// nombran solo las secciones con contenido: "0 videos" no le dice nada a
    /// nadie.
    /// </summary>
    public static string SummaryOf(IReadOnlyList<LibraryItem> items)
    {
        if (items.Count == 0) return AppStrings.LibraryEmpty;

        var parts = new List<string>();

        int songs = items.Count(item => item.Kind == LibraryItemKind.Music);
        int videos = items.Count(item => item.Kind == LibraryItemKind.Video);
        int photos = items.Count(item => item.Kind == LibraryItemKind.Photo);

        if (songs > 0) parts.Add(songs == 1 ? "1 canción" : $"{songs} canciones");
        if (videos > 0) parts.Add(videos == 1 ? "1 video" : $"{videos} videos");
        if (photos > 0) parts.Add(photos == 1 ? "1 foto" : $"{photos} fotos");

        return string.Join(" · ", parts);
    }

    // MARK: - Arrastrar y soltar

    /// <summary>
    /// Ingiere lo que se soltó en una sección. <b>Cada sección solo acepta su
    /// tipo</b> y las carátulas nunca entran a Imágenes (ST-012): la decisión es
    /// de <see cref="LibraryIngest"/>, acá solo se aplica el resultado y se le
    /// cuenta al usuario.
    /// </summary>
    public void AddDroppedFiles(IEnumerable<string> paths, LibraryItemKind section)
    {
        List<string> expanded = [.. Expand(paths)];

        LibraryIngestResult result = LibraryIngest.Ingest(
            expanded, section, Items.Select(item => item.SourcePath));

        if (result.AddedAnything)
        {
            Items = [.. Items, .. result.Added];
            Save();
            _ = ProcessAsync(result.Added);
        }

        LastDropMessage = LibraryIngest.Summary(result, section);
        RefreshAvailable();
    }

    /// <summary>
    /// Lee etiquetas y clasifica lo recién agregado, sin bloquear la interfaz:
    /// una carpeta de mil canciones tarda, y mientras tanto la lista ya se ve
    /// con los nombres de archivo.
    ///
    /// <para>Se guarda <b>una vez al final</b>, no por elemento: mil escrituras
    /// del catálogo por una importación son mil veces el trabajo necesario.</para>
    /// </summary>
    private async Task ProcessAsync(IReadOnlyList<LibraryItem> items)
    {
        bool changed = false;

        foreach (LibraryItem item in items)
            changed |= await _processor.ProcessAsync(item).ConfigureAwait(true);

        if (!changed) return;

        Save();
        OnPropertyChanged(nameof(Items));
    }

    /// <summary>
    /// Una carpeta soltada entra con todo lo que tiene adentro, recursivamente —
    /// es lo que espera quien arrastra el álbum entero.
    /// </summary>
    private static IEnumerable<string> Expand(IEnumerable<string> paths)
    {
        foreach (string path in paths)
        {
            if (File.Exists(path)) { yield return path; continue; }
            if (!Directory.Exists(path)) continue;

            IEnumerable<string> inside;
            try
            {
                inside = Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Una carpeta sin permisos no puede tumbar el resto del arrastre.
                continue;
            }

            foreach (string file in inside) yield return file;
        }
    }

    public void Remove(IEnumerable<Guid> ids)
    {
        var doomed = ids.ToHashSet();
        if (doomed.Count == 0) return;

        // Se quita de la biblioteca, NO del disco: el archivo es del usuario.
        Items = [.. Items.Where(item => !doomed.Contains(item.Id))];
        Save();
    }

    // MARK: - Listas de reproducción

    public IReadOnlyList<Playlist> LoadPlaylists() => _store.LoadPlaylists();

    public void SavePlaylists(IEnumerable<Playlist> playlists) => _store.SavePlaylists(playlists);

    // MARK: - Agrupaciones para las cuadrículas

    /// <summary>
    /// La selección de la vista de biblioteca <b>activa</b> en este instante
    /// (R3-4). Alimenta «Solo la selección» en la ficha de General.
    ///
    /// <para>La publica cada vista al aparecer, al cambiar la selección y al
    /// irse — <b>la de la vista activa manda</b>, y se limpia al salir. Sin esa
    /// limpieza, "solo la selección" seguiría apuntando a lo que había
    /// seleccionado dos pantallas atrás, que es la clase de cosa que hace copiar
    /// lo que no era.</para>
    /// </summary>
    public IReadOnlyCollection<Guid> SelectionForSync { get; private set; } = [];

    public int SelectionForSyncCount => SelectionForSync.Count;

    public void PublishSelectionForSync(IReadOnlyCollection<Guid> ids)
    {
        SelectionForSync = ids;
        OnPropertyChanged(nameof(SelectionForSync));
        OnPropertyChanged(nameof(SelectionForSyncCount));
    }

    /// <summary>Se llama al dejar una vista: lo de la anterior no puede sobrevivirla.</summary>
    public void ClearSelectionForSync() => PublishSelectionForSync([]);

    /// <summary>
    /// Cuántos elementos están listos para viajar. Es una <b>aproximación</b>
    /// que sirve antes de comparar contra el iPod: alguno puede estar ya
    /// sincronizado con ESE aparato, y eso solo lo sabe «Revisar cambios».
    /// </summary>
    public int PendingCount => SyncScopeResolver.PendingCount(Items);

    /// <summary>
    /// Con qué criterio se agrupan las colaboraciones (R2-4). Sale de las
    /// preferencias y <b>tiene que ser el mismo en todos lados</b> —
    /// cuadrículas, fotos de artista y sincronización—: dos criterios distintos
    /// dan dos artistas donde el usuario ve uno.
    /// </summary>
    public ArtistGroupingOptions ArtistGrouping => _preferences.ArtistGrouping;

    // Todas las agrupaciones parten de lo DISPONIBLE: una cuadrícula no puede
    // ofrecer un álbum cuyos archivos no están.
    public IReadOnlyList<AlbumGroup> Albums() => LibraryGrouping.Albums(AvailableItems, ArtistGrouping);

    public IReadOnlyList<ArtistGroup> Artists() => LibraryGrouping.Artists(AvailableItems, ArtistGrouping);

    public IReadOnlyList<VideoCollectionGroup> VideoCollections() =>
        LibraryGrouping.VideoCollections(AvailableItems);

    public IReadOnlyList<PhotoAlbumGroup> PhotoAlbums(string category) =>
        LibraryGrouping.PhotoAlbums(AvailableItems, category);

    /// <summary>Los videos que no son película ni serie: los clips sueltos.</summary>
    public IReadOnlyList<LibraryItem> Clips() =>
        [.. AvailableItems.Where(item => item.Kind == LibraryItemKind.Video
            && !MediaCategoryNames.IsMoviesCategory(item.Category)
            && !MediaCategoryNames.IsSeriesCategory(item.Category))];

    public IReadOnlyList<LibraryItem> OfKind(LibraryItemKind kind) =>
        [.. AvailableItems.Where(item => item.Kind == kind)];

    // MARK: - Tabla de Canciones (ST-030)

    public IReadOnlyList<MusicTableColumn> VisibleColumns
    {
        get => _preferences.MusicVisibleColumns;
        set
        {
            _preferences.MusicVisibleColumns = value;
            OnPropertyChanged();
        }
    }

    public MusicSortField SortField
    {
        get => _preferences.MusicSortField;
        set
        {
            _preferences.MusicSortField = value;
            OnPropertyChanged();
        }
    }

    public bool SortAscending
    {
        get => _preferences.MusicSortAscending;
        set
        {
            _preferences.MusicSortAscending = value;
            OnPropertyChanged();
        }
    }

    public bool FavoritesOnly
    {
        get => _preferences.MusicFavoritesOnly;
        set
        {
            _preferences.MusicFavoritesOnly = value;
            OnPropertyChanged();
        }
    }

    /// <summary>
    /// Los renglones de la tabla para un ámbito dado, filtrados y ordenados como
    /// el usuario los dejó. El tamaño de cada archivo se lee <b>una vez acá</b>,
    /// no en cada comparación del ordenamiento.
    /// </summary>
    public IReadOnlyList<MediaTableRow> Rows(MusicScope scope)
    {
        IEnumerable<LibraryItem> items = InScope(scope);

        if (FavoritesOnly) items = items.Where(item => item.Metadata?.IsFavorite == true);

        return items
            .Select(item => new MediaTableRow(item, SimilarItemsDetector.FileSizeOf(item.SourcePath)))
            .Sorted(SortField, SortAscending);
    }

    private IEnumerable<LibraryItem> InScope(MusicScope scope) => scope switch
    {
        MusicScope.Album album => AvailableItems.Where(item =>
            item.Kind == LibraryItemKind.Music && LibraryGrouping.AlbumKeyOf(item, ArtistGrouping) == album.Key),

        MusicScope.Artist artist => AvailableItems.Where(item =>
            item.Kind == LibraryItemKind.Music && LibraryGrouping.ArtistKeyOf(item, ArtistGrouping) == artist.Key),

        MusicScope.VideoCollection collection => AvailableItems.Where(item =>
            item.Kind == LibraryItemKind.Video
            && LibraryGrouping.VideoCollectionKeyOf(item) == collection.Key),

        MusicScope.Season season => AvailableItems.Where(item =>
            item.Kind == LibraryItemKind.Video
            && LibraryGrouping.VideoCollectionKeyOf(item) == season.CollectionKey
            && (item.Season ?? VideoCollectionGroup.NoSeasonNumber) == season.Number),

        MusicScope.PhotoAlbum photoAlbum => AvailableItems.Where(item =>
            item.Kind == LibraryItemKind.Photo
            && LibraryGrouping.PhotoAlbumKeyOf(item, item.Category ?? "") == photoAlbum.Key),

        _ => AvailableItems.Where(item => item.Kind == LibraryItemKind.Music)
    };

    /// <summary>
    /// Aplica una edición hecha a mano en la hoja de información.
    ///
    /// <para>Marca el elemento como <b>corregido por el usuario</b>: a partir de
    /// ahí, el enriquecimiento automático solo llena huecos y nunca pisa lo que
    /// se escribió acá. Es la única vía que enciende esa marca — leer etiquetas
    /// o completar en línea jamás lo hacen.</para>
    /// </summary>
    public void ApplyMetadataEdit(Guid id, TrackMetadata metadata)
    {
        LibraryItem? item = Items.FirstOrDefault(candidate => candidate.Id == id);
        if (item is null) return;

        item.Metadata = metadata;
        item.MetadataEditedByUser = true;

        // Lo que el usuario acaba de completar puede haber sacado al elemento de
        // "necesita revisión": se recalcula en vez de dejarlo marcado para
        // siempre.
        if (item.Status.State == LibraryItemState.NeedsReview
            && !string.IsNullOrEmpty(metadata.Artist)
            && !string.IsNullOrEmpty(metadata.Album))
        {
            item.Status = LibraryItemStatus.Ready;
        }

        Save();
        OnPropertyChanged(nameof(Items));
    }

    /// <summary>Aplica los datos de un video editados a mano.</summary>
    public void ApplyVideoEdit(Guid id, string? title, string? seriesName, int? season, int? episode, string? category)
    {
        LibraryItem? item = Items.FirstOrDefault(candidate => candidate.Id == id);
        if (item is null) return;

        item.Metadata ??= new TrackMetadata();
        item.Metadata.Title = title;
        item.SeriesName = seriesName;
        item.Season = season;
        item.Episode = episode;
        if (category is { Length: > 0 }) item.Category = category;
        item.MetadataEditedByUser = true;

        Save();
        OnPropertyChanged(nameof(Items));
    }

    /// <summary>Cambia solo la categoría (foto o video), sin tocar el resto.</summary>
    public void ApplyCategory(Guid id, string category)
    {
        LibraryItem? item = Items.FirstOrDefault(candidate => candidate.Id == id);
        if (item is null || category.Length == 0) return;

        item.Category = category;
        item.MetadataEditedByUser = true;
        Save();
        OnPropertyChanged(nameof(Items));
    }

    /// <summary>
    /// Marca o desmarca favorito. Es lo único que la tabla edita directo: el
    /// resto de la metadata pasa por la hoja de información.
    /// </summary>
    public void ToggleFavorite(Guid id)
    {
        LibraryItem? item = Items.FirstOrDefault(candidate => candidate.Id == id);
        if (item is null) return;

        item.Metadata ??= new TrackMetadata();
        item.Metadata.IsFavorite = !item.Metadata.IsFavorite;
        Save();
        OnPropertyChanged(nameof(Items));
    }

    // MARK: - Acciones de los menús contextuales

    /// <summary>
    /// Marca o desmarca varios de una vez. <b>Quita</b> si todos los alcanzados
    /// ya son favoritos, marca si alguno no lo es — el mismo criterio con el que
    /// el menú eligió su texto.
    /// </summary>
    public void SetFavorite(IReadOnlyCollection<Guid> ids, bool favorite)
    {
        foreach (LibraryItem item in ItemsWith(ids))
        {
            (item.Metadata ??= new TrackMetadata()).IsFavorite = favorite;
        }

        Save();
        OnPropertyChanged(nameof(Items));
    }

    /// <summary>
    /// Quita la carátula de lo alcanzado. <b>No toca el archivo original</b>:
    /// solo la imagen que Studio guarda para el iPod.
    /// </summary>
    public void RemoveCover(IReadOnlyCollection<Guid> ids)
    {
        int removed = 0;

        foreach (LibraryItem item in ItemsWith(ids).Where(item => item.Metadata?.CoverArtData is { Length: > 0 }))
        {
            item.Metadata!.CoverArtData = null;
            item.MetadataEditedByUser = true;
            removed++;
        }

        if (removed == 0) return;

        Save();
        RefreshAvailable();
        OnPropertyChanged(nameof(Items));
        StatusMessage = removed == 1 ? "Se quitó 1 carátula." : $"Se quitaron {removed} carátulas.";
    }

    /// <summary>El póster de un video vive junto al preparado, así que quitarlo es borrar ese archivo.</summary>
    public void RemovePoster(IReadOnlyCollection<Guid> ids)
    {
        int removed = 0;

        foreach (LibraryItem item in ItemsWith(ids).Where(item => item.Kind == LibraryItemKind.Video))
        {
            if (item.Metadata?.CoverArtData is { Length: > 0 })
            {
                item.Metadata.CoverArtData = null;
                removed++;
            }

            if (item.PreparedPath is not { Length: > 0 } prepared) continue;

            try
            {
                string poster = Path.ChangeExtension(prepared, ".jpg");
                if (File.Exists(poster)) File.Delete(poster);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Un póster que no se deja borrar no puede tumbar la acción.
            }
        }

        Save();
        OnPropertyChanged(nameof(Items));
        StatusMessage = removed == 0 ? "No había ningún póster que quitar." : "Se quitó el póster.";
    }

    /// <summary>
    /// Vuelve a leer las etiquetas del archivo, <b>pisando lo que hubiera</b>:
    /// es justo lo que se pide cuando alguien corrigió las etiquetas por fuera.
    /// La carátula que Studio ya tenía se conserva si el archivo no trae una.
    /// </summary>
    public void RetagFromFile(IReadOnlyCollection<Guid> ids)
    {
        int read = 0;

        foreach (LibraryItem item in ItemsWith(ids).Where(item => item.Kind == LibraryItemKind.Music))
        {
            if (!File.Exists(item.SourcePath)) continue;

            TrackMetadata fresh = LocalTagReader.Read(item.SourcePath);
            // ST-141: la del archivo entra cuadrada; la que ya estaba en la
            // biblioteca ya lo está (o la migración se encargará de ella).
            if (fresh.CoverArtData is { Length: > 0 } fromFile)
                fresh.CoverArtData = WicSquareImageEncoder.SharedNormalizer.Normalize(fromFile);
            fresh.CoverArtData ??= item.Metadata?.CoverArtData;
            fresh.SyncedLyrics ??= item.Metadata?.SyncedLyrics;
            fresh.IsFavorite = item.Metadata?.IsFavorite ?? false;
            fresh.Rating = item.Metadata?.Rating;

            item.Metadata = fresh;

            // Releer del archivo es lo contrario de una edición a mano: deja de
            // estar protegido contra el enriquecimiento.
            item.MetadataEditedByUser = false;
            read++;
        }

        if (read == 0)
        {
            StatusMessage = "No se pudo leer ninguna etiqueta: los archivos no están disponibles.";
            return;
        }

        Save();
        RefreshAvailable();
        OnPropertyChanged(nameof(Items));
        StatusMessage = read == 1 ? "Se releyeron las etiquetas de 1 canción." : $"Se releyeron las etiquetas de {read} canciones.";
    }

    /// <summary>Solo la letra, sin tocar el resto de la metadata.</summary>
    public async Task FetchLyricsAsync(IReadOnlyCollection<Guid> ids, CancellationToken ct = default)
    {
        List<LibraryItem> targets = [.. ItemsWith(ids).Where(item => item.Kind == LibraryItemKind.Music)];
        if (targets.Count == 0) return;

        IsEnriching = true;
        StatusMessage = "Buscando letra…";

        try
        {
            EnrichmentReport report = await _enrichment.EnrichAsync(
                targets, new Progress<string>(title => StatusMessage = $"Buscando letra de {title}…"), ct);

            Save();
            OnPropertyChanged(nameof(Items));

            StatusMessage = report.Lyrics == 0
                ? "No se encontró letra para lo seleccionado."
                : $"Se consiguieron {report.Lyrics} letra(s).";
        }
        catch (OperationCanceledException) { StatusMessage = "Se detuvo la búsqueda de letra."; }
        finally { IsEnriching = false; }
    }

    /// <summary>Los ids de todas las canciones del mismo álbum que la primera alcanzada.</summary>
    public IReadOnlyList<Guid> SameAlbumAs(Guid id)
    {
        LibraryItem? item = Items.FirstOrDefault(candidate => candidate.Id == id);
        if (item is null) return [];

        string key = LibraryGrouping.AlbumKeyOf(item, ArtistGrouping);

        return [.. AvailableItems.Where(other => other.Kind == LibraryItemKind.Music
                                                 && LibraryGrouping.AlbumKeyOf(other, ArtistGrouping) == key)
            .Select(other => other.Id)];
    }

    public IReadOnlyList<Guid> SameArtistAs(Guid id)
    {
        LibraryItem? item = Items.FirstOrDefault(candidate => candidate.Id == id);
        if (item is null) return [];

        string key = LibraryGrouping.ArtistKeyOf(item, ArtistGrouping);

        return [.. AvailableItems.Where(other => other.Kind == LibraryItemKind.Music
                                                 && LibraryGrouping.ArtistKeyOf(other, ArtistGrouping) == key)
            .Select(other => other.Id)];
    }

    private IEnumerable<LibraryItem> ItemsWith(IReadOnlyCollection<Guid> ids) =>
        Items.Where(item => ids.Contains(item.Id));
}
