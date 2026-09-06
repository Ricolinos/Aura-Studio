using System.Diagnostics;
using AuraStudio.App.Services;
using AuraStudio.App.ViewModels;
using AuraStudio.Core.Library;
using AuraStudio.App.Platform;
using AuraStudio.Tools.LibraryPerfCheck;

// Cómo correrlo:
//   dotnet run --project tools/LibraryPerfCheck -- [álbumes] [pistas por álbum] [ms de disco lento]
//
// Por omisión, 1000 álbumes de 12 pistas (12 000 canciones, la biblioteca del
// dueño) con una carátula JPEG real de verdad (~15 KB, generada con semilla
// fija) por álbum, compartida por sus pistas. El tercer argumento (0 por
// omisión) activa la sección "disco lento" -- ver más abajo; con 0 se salta,
// porque a varios ms por llamada y miles de llamadas tarda minutos.
//
// Mide lo que la app hace de verdad: SaveItems/LoadItems reales de
// LibraryStore (con ReadCover por ítem), el arranque completo de
// LibraryViewModel (Reload real), y la cascada de selección con
// MediaGridViewModel + SongsViewModel + PlaylistsViewModel **de verdad**,
// suscritos entre sí exactamente como los arma ConfigureServices en App --
// eso es lo que reproduce el trabón al 3er álbum: no es la cuadrícula sola,
// es que seleccionar dispara Refresh() de Canciones (FileSizeOf por canción)
// y de Listas encima.
//
// No borra nada de nadie: trabaja solo dentro de su carpeta temporal, y la
// borra al terminar.

Console.OutputEncoding = System.Text.Encoding.UTF8;

int albums = args.Length > 0 && int.TryParse(args[0], out int a) ? a : 1000;
int tracksPerAlbum = args.Length > 1 && int.TryParse(args[1], out int t) ? t : 12;
int diskDelayMs = args.Length > 2 && int.TryParse(args[2], out int d) ? d : 0;
int total = albums * tracksPerAlbum;

string root = Path.Combine(Path.GetTempPath(), "aura-perf-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);

Console.WriteLine($"Biblioteca de prueba: {albums} álbumes x {tracksPerAlbum} pistas = {total} canciones, con carátula real por álbum");
Console.WriteLine($"Carpeta: {root}");
Console.WriteLine();

try
{
    IReadOnlyList<byte[]> covers = await MeasureAsync("Generar carátulas JPEG reales (una por álbum)",
        () => CoverFixtureGenerator.GenerateAsync(albums));

    List<LibraryItem> items = Measure("Generar el catálogo en memoria (con esas carátulas)", () =>
    {
        var generated = new List<LibraryItem>(total);

        for (int album = 0; album < albums; album++)
        {
            // 40 artistas repartidos: una biblioteca real tiene muchos álbumes
            // por artista, no uno por uno.
            string artist = $"Artista {album % 40:000}";
            string albumName = $"Álbum {album:0000}";
            byte[] cover = covers[album];

            for (int track = 1; track <= tracksPerAlbum; track++)
            {
                generated.Add(new LibraryItem
                {
                    // SourcePath primero: su setter borra FileSizeBytes al
                    // cambiar (ST-201), así que FileSizeBytes tiene que ir
                    // DESPUÉS en este inicializador o quedaría en null.
                    SourcePath = Path.Combine(root, "Música", artist, albumName, $"{track:00} Canción.mp3"),
                    Kind = LibraryItemKind.Music,
                    Status = LibraryItemStatus.Ready,
                    Metadata = new TrackMetadata
                    {
                        Title = $"Canción {track:00} de {albumName}",
                        Artist = artist,
                        AlbumArtist = artist,
                        Album = albumName,
                        Genre = "Rock",
                        Year = "1986",
                        TrackNumber = track,
                        DurationSeconds = 210 + track,
                        CoverArtData = cover
                    },
                    // Addendum de ST-200: la biblioteca del arnés nace con el
                    // tamaño ya conocido -- estado estable, la migración de
                    // ST-201 se mide aparte, más abajo, con FileSizeBytes en
                    // null a propósito.
                    FileSizeBytes = CoverFixtureGenerator.DeterministicFileSizeBytes(album, track)
                });
            }
        }

        return generated;
    });

    // --- a. SaveItems/LoadItems reales de LibraryStore, con carátulas ---

    var store = new LibraryStore(root)
    {
        // Ya "migrada": si no, LibraryViewModel.Reload() dispara de fondo la
        // normalización de carátulas (ST-141) y esa tarea en paralelo
        // contaminaría las medidas de más abajo. Una biblioteca real del
        // dueño, tras la primera apertura, también queda así.
        CoversNormalized = CoverArtNormalization.NormalizedVersion
    };

    Measure("Guardar biblioteca.json (SaveItems, con carátulas)", () => { store.SaveItems(items); return 0; });

    long catalogBytes = new FileInfo(Path.Combine(root, "biblioteca.json")).Length;
    long coversBytes = Directory.Exists(store.CoversDirectory)
        ? Directory.EnumerateFiles(store.CoversDirectory).Sum(f => new FileInfo(f).Length)
        : 0;
    Console.WriteLine($"    biblioteca.json: {catalogBytes / 1024.0 / 1024.0:0.0} MB -- .portadas/: {coversBytes / 1024.0 / 1024.0:0.0} MB ({albums} archivos)");

    // ST-204: cuánto costaba la sangría. Se mide sobre el archivo ya escrito,
    // reindentándolo tal cual: el mismo contenido exacto, con espacios.
    long indentedBytes;
    {
        using var document = System.Text.Json.JsonDocument.Parse(
            File.ReadAllBytes(Path.Combine(root, "biblioteca.json")));
        using var buffer = new MemoryStream();
        using (var writer = new System.Text.Json.Utf8JsonWriter(
            buffer, new System.Text.Json.JsonWriterOptions { Indented = true }))
        {
            document.WriteTo(writer);
        }

        indentedBytes = buffer.Length;
    }

    Console.WriteLine($"    con sangría, el mismo catálogo ocuparía {indentedBytes / 1024.0 / 1024.0:0.0} MB"
                      + $" ({(indentedBytes - catalogBytes) / 1024.0 / 1024.0:0.0} MB de espacios, +{(indentedBytes - catalogBytes) * 100.0 / catalogBytes:0}%)");

    IReadOnlyList<LibraryItem> loaded = Measure("Leer biblioteca.json (LoadItems, ReadCover por ítem)", () => store.LoadItems());
    Console.WriteLine($"    elementos leídos: {loaded.Count}, con carátula: {loaded.Count(i => i.HasCover)}");
    Console.WriteLine($"    con los BYTES de la carátula en memoria: {loaded.Count(i => i.Metadata?.CoverArtData is { Length: > 0 })} (ST-208: debe ser 0)");
    ReportMemory("tras leer el catálogo");

    Measure("Comprobar que los archivos estén (disco local, como RefreshAvailable)", () =>
        loaded.Count(item => File.Exists(item.SourcePath)));

    Measure("Planificar una sincronización completa", () =>
    {
        var files = loaded.Select(item => new SyncSourceFile(
            item.SourcePath, 5_000_000, DateTimeOffset.UtcNow,
            SyncLayout.DestinationRelativePath(item))).ToList();

        return SyncPlanner.Plan(files, new DeviceSyncManifest()).Items.Count;
    });

    // AvailableItems (lo que usan las cuadrículas y la tabla) exige que el
    // archivo exista de verdad: sin esto, RefreshAvailable() descarta las
    // 12000 canciones y toda la sección de abajo mide una biblioteca vacía.
    // No es una métrica de producto -- es la fixture misma -- así que no se
    // reporta como fila del arnés, solo se avisa cuánto tardó.
    Measure("(fixture) Crear archivos de audio vacíos en disco para RefreshAvailable", () =>
    {
        foreach (LibraryItem item in items)
        {
            string? dir = Path.GetDirectoryName(item.SourcePath);
            if (dir is { Length: > 0 }) Directory.CreateDirectory(dir);
            File.WriteAllBytes(item.SourcePath, []);
        }

        return items.Count;
    });

    Console.WriteLine();
    Console.WriteLine("--- b/c. Arranque real y cascada de selección (ViewModels de verdad) ---");
    Console.WriteLine();

    // --- Arranque real: LibraryViewModel.ctor -> Reload() (LoadItems +
    // RefreshAvailable + chequeo de normalización), tal cual arranca la app ---

    string prefsPath = Path.Combine(root, "prefs.json");
    var preferences = new AppPreferences(prefsPath) { LibraryPath = root };

    // ST-203: el constructor ya no espera a que la biblioteca esté. Esta fila
    // mide el criterio —lo que tarda en poder verse la pantalla— y la de abajo,
    // lo que tarda la carga completa, que ahora ocurre en segundo plano.
    LibraryViewModel library = Measure("Arranque: LibraryViewModel ctor (vuelve enseguida)",
        () => new LibraryViewModel(preferences, new NoOpLibraryProcessor(), new NoOpEnrichmentService(),
            new AuraStudio.App.Services.BackgroundTaskCenter()));

    await MeasureAsync("Carga completa de la biblioteca (en segundo plano)", async () =>
    {
        await library.LoadingTask;
        return library.AvailableItems.Count;
    });

    Console.WriteLine($"    ítems disponibles: {library.AvailableItems.Count}");

    // --- Escenario aislado: solo la cuadrícula, sin Canciones ni Listas
    // suscritas -- para separar "cuesta la cuadrícula" de "cuesta la cascada" ---

    var isolatedGrid = new MediaGridViewModel(library);
    Measure("MediaGridViewModel.Show(Albums): Refresh() completo, 1000 álbumes (aislado)",
        () => { isolatedGrid.Show(MediaGridKind.Albums); return isolatedGrid.Cards.Count; });

    MeasureVoid("Selección aislada: clic en álbum 1 (sin Canciones/Listas suscritas)",
        () => Click(isolatedGrid, isolatedGrid.Cards[0]));
    MeasureVoid("Selección aislada: clic en álbum 2 (sin Canciones/Listas suscritas)",
        () => Click(isolatedGrid, isolatedGrid.Cards[1]));
    MeasureVoid("Selección aislada: clic en álbum 3 (sin Canciones/Listas suscritas)",
        () => Click(isolatedGrid, isolatedGrid.Cards[2]));

    // ST-202: Ctrl+A es UN gesto. `GridView.SelectAll()` manda un solo
    // `SelectionChanged` con todo lo que faltaba, no mil avisos.
    ClearSelection(isolatedGrid);
    MeasureVoid($"Ctrl+A en Álbumes: el gesto real, un solo aviso ({isolatedGrid.Cards.Count} álbumes, aislado)",
        () => CtrlA(isolatedGrid));

    // Y la misma fila que medía W0 —mil Ctrl+clic seguidos—, para poder comparar
    // contra su línea base. No es lo que hace un Ctrl+A ni lo que hace una
    // persona: es el peor caso de sumar de a uno.
    ClearSelection(isolatedGrid);
    var ctrlAWatch = Stopwatch.StartNew();
    foreach (MediaCard card in isolatedGrid.Cards) CtrlClick(isolatedGrid, card);
    ctrlAWatch.Stop();
    Console.WriteLine($"{ctrlAWatch.ElapsedMilliseconds,6} ms  Álbumes: {isolatedGrid.Cards.Count} Ctrl+clic seguidos (la fila con la que compara W0, aislado)");
    Console.WriteLine($"    promedio por álbum: {ctrlAWatch.ElapsedMilliseconds / (double)isolatedGrid.Cards.Count:0.000} ms (sin Canciones/Listas suscritas)");

    Measure("Álbumes: abrir menú contextual con 1000 seleccionados (ScopeOf)",
        () => isolatedGrid.ScopeOf(isolatedGrid.Cards));

    // --- Escenario real: MediaGridViewModel + SongsViewModel +
    // PlaylistsViewModel, todos suscritos a LibraryViewModel como los arma
    // ConfigureServices (todo singleton, todo vivo a la vez) ---

    var grid = new MediaGridViewModel(library);
    grid.Show(MediaGridKind.Albums);

    SongsViewModel songs = Measure("SongsViewModel ctor (Refresh inicial, 12000 filas, FileSizeOf por canción)",
        () => new SongsViewModel(library));

    PlaylistsViewModel playlists = Measure("PlaylistsViewModel ctor (Reload + Refresh inicial)",
        () => new PlaylistsViewModel(library));

    MeasureVoid("Selección CON cascada: clic en álbum 1 (dispara Songs.Refresh + Playlists.Refresh)",
        () => Click(grid, grid.Cards[0]));
    MeasureVoid("Selección CON cascada: clic en álbum 2 (dispara Songs.Refresh + Playlists.Refresh)",
        () => Click(grid, grid.Cards[1]));
    MeasureVoid("Selección CON cascada: clic en álbum 3 -- el clic que hoy traba la app",
        () => Click(grid, grid.Cards[2]));
    MeasureVoid("Selección CON cascada: Ctrl+clic en álbum 4",
        () => CtrlClick(grid, grid.Cards[3]));

    Console.WriteLine($"    (para comparar: cada clic de arriba paga un SongsViewModel.Refresh() completo -- ver la fila de más arriba con su costo aislado)");

    Console.WriteLine();
    Console.WriteLine("--- Canciones: Ctrl+A (12 000) + clic derecho ---");
    Console.WriteLine();

    // --- Réplica exacta de SongsPage.xaml.cs:311-314 (clic derecho tras
    // Ctrl+A: List<Guid>.Contains dentro de un Where, O(N²)) y de
    // SongsPage.xaml.cs:353-370 (ScopeOf: AlbumKeyOf recalculado para toda la
    // selección). Se replica el cómputo con tipos de Core en vez de instanciar
    // SongsPage (Page de WinUI, no se puede construir headless) -- misma
    // lógica, mismo costo. ---

    List<Guid> reachedAfterSelectAll = [.. library.Items.Where(i => i.Kind == LibraryItemKind.Music).Select(i => i.Id)];
    Console.WriteLine($"    (Ctrl+A en Canciones: {reachedAfterSelectAll.Count} seleccionadas)");

    List<LibraryItem> rightClickItems = Measure(
        "Canciones: clic derecho tras Ctrl+A -- Where(reached.Contains(id)), réplica de SongsPage.xaml.cs:311-314",
        () => library.Items.Where(item => reachedAfterSelectAll.Contains(item.Id)).ToList());

    Measure("Canciones: ScopeOf tras Ctrl+A -- AlbumKeyOf recalculado 12000 veces, réplica de SongsPage.xaml.cs:353-370",
        () => rightClickItems.Select(item => LibraryGrouping.AlbumKeyOf(item, library.ArtistGrouping)).Distinct().Count());

    // --- Lo mismo, como quedó en ST-206: por índice. Las dos filas de arriba se
    // conservan a propósito para el contraste directo. ---

    LibraryCatalogIndex catalogIndex = Measure(
        "Armar LibraryCatalogIndex de 12 000 elementos (una vez; en la app lo calienta el fondo)",
        () => LibraryCatalogIndex.Build(library.AvailableItems, library.ArtistGrouping));

    List<LibraryItem> byIndex = Measure(
        "Canciones: clic derecho tras Ctrl+A -- por índice (ST-206)",
        () =>
        {
            List<LibraryItem> reached = [];
            foreach (Guid id in reachedAfterSelectAll)
            {
                if (catalogIndex.ById(id) is { } item) reached.Add(item);
            }

            return reached;
        });

    Measure("Canciones: ScopeOf tras Ctrl+A -- por índice (ST-206)",
        () =>
        {
            IReadOnlyList<string> keys = catalogIndex.AlbumKeysOf(byIndex);

            return keys.Count(
                key => catalogIndex.ByAlbumKey(key).FirstOrDefault()?.Metadata?.Album is { Length: > 0 });
        });

    long menuMs = MeasureVoidTimed(
        "Canciones: ABRIR el menú con 12 000 seleccionadas (alcance + ScopeOf, índice ya armado)",
        () =>
        {
            List<LibraryItem> reached = [];
            foreach (Guid id in reachedAfterSelectAll)
            {
                if (catalogIndex.ById(id) is { } item) reached.Add(item);
            }

            IReadOnlyList<string> keys = catalogIndex.AlbumKeysOf(reached);
            _ = keys.Count(
                key => catalogIndex.ByAlbumKey(key).FirstOrDefault()?.Metadata?.Album is { Length: > 0 });
            _ = reached.All(item => item.Metadata?.IsFavorite == true);
            _ = reached.Any(item => item.HasCover);
        });

    Console.WriteLine($"    objetivo del plan: < 200 ms -- {(menuMs < 200 ? "cumplido" : "NO CUMPLIDO")}");

    Console.WriteLine();
    Console.WriteLine("--- Migración única de fileSizeBytes (biblioteca vieja, ST-201) ---");
    Console.WriteLine();

    // Réplica de abrir una biblioteca guardada ANTES de ST-201: los mismos
    // 12000 archivos en disco (los ya creados arriba), pero el catálogo sin
    // fileSizeBytes -- lo que dispara FileSizeBackfill en segundo plano al
    // arrancar (ViewModels/LibraryViewModel.cs:429-486). Se llama al mismo
    // Core que usa esa ruta (FileSizeBackfill.Run/Apply), directo y sin
    // Task.Run/Dispatch: acá no hace falta medir la vuelta al hilo de UI,
    // solo el trabajo real -- medir cada archivo y el guardado final.
    List<LibraryItem> migrationItems =
    [
        .. loaded.Select(item => new LibraryItem
        {
            SourcePath = item.SourcePath,
            Kind = item.Kind,
            Status = item.Status,
            Metadata = item.Metadata
            // FileSizeBytes queda en null a propósito -- es lo que dispara la migración.
        })
    ];

    long measureMs = MeasureVoidTimed("Migración: medir 12000 archivos en segundo plano (FileSizeBackfill.Run)", () =>
    {
        int applied = 0;
        FileSizeBackfill.Run(migrationItems, batch => applied += FileSizeBackfill.Apply(batch));
    });

    long saveMs = MeasureVoidTimed("Migración: guardado final (SaveItems, una vez, no por lote)",
        () => store.SaveItems(migrationItems));

    Console.WriteLine($"    Migración única, total: {measureMs + saveMs} ms (medir + guardar; la próxima apertura ya no la paga)");

    // --- c-bis. Guardado del catálogo: coalescencia (ST-204) ---
    //
    // "Aplicar la tapa recomendada a N álbumes" llama a ApplyAlbumCover en
    // bucle, un álbum por vuelta. Antes de ST-204 cada vuelta escribía el
    // catálogo ENTERO, de inmediato y en el hilo de interfaz. Acá se mide el
    // antes con un N chico —con el N de verdad la corrida tardaría minutos— y
    // el después con el número completo de pedidos.

    Console.WriteLine();
    Console.WriteLine("--- c-bis. Guardado del catálogo: una ráfaga, un guardado (ST-204) ---");
    Console.WriteLine();

    int coverBatch = Math.Min(20, albums);

    long beforeMs = MeasureVoidTimed(
        $"Antes: {coverBatch} álbumes = {coverBatch} guardados completos, en el hilo que los pide",
        () =>
        {
            for (int i = 0; i < coverBatch; i++) store.SaveItems(items);
        });

    Console.WriteLine($"    proyectado a {albums} álbumes: ~{beforeMs / (double)coverBatch * albums / 1000.0:0.0} s solo de guardado");

    var persisterHost = new PersisterHarnessHost();
    var persister = new CatalogPersister(
        persisterHost,
        () => new CatalogSnapshotRequest(false, store.Root, () => store.Snapshot(items, [])));

    int callerThread = Environment.CurrentManagedThreadId;

    long afterMs = MeasureVoidTimed(
        $"Después: {albums} pedidos seguidos + el temporizador = UN guardado",
        () =>
        {
            // Un pedido por álbum, como el bucle de verdad.
            for (int i = 0; i < albums; i++) persister.Schedule();

            persisterHost.Fire();
        });

    Console.WriteLine($"    pedidos: {persisterHost.ScheduleCount} -- escrituras de verdad: {persister.WriteCount} (debe ser 1)");
    Console.WriteLine($"    hilo que pidió: {callerThread} -- hilo que escribió: {persisterHost.LastWriteThreadId}"
                      + $" ({(persisterHost.LastWriteThreadId != callerThread ? "fuera del de interfaz, correcto" : "MISMO HILO: mal")})");
    Console.WriteLine($"    un guardado suelto: {afterMs} ms (antes eran {beforeMs / (double)coverBatch:0} ms x {albums} álbumes)");

    // --- c-ter. Miniaturas de carátula (ST-205) ---
    //
    // Lo que hace la cuadrícula al aparecer cada tarjeta: pedir la miniatura de
    // la tapa del álbum. Antes de ST-205 eso era leer el archivo y decodificar
    // la carátula ENTERA cada vez, también al volver a desplazarse.

    Console.WriteLine();
    Console.WriteLine("--- c-ter. Miniaturas de carátula (ST-205) ---");
    Console.WriteLine();

    // Una por álbum: la primera pista de cada uno, que es de donde sale la tapa
    // de la tarjeta.
    List<LibraryItem> albumCovers =
    [
        .. loaded.Where((_, position) => position % tracksPerAlbum == 0)
    ];

    var thumbnails = new CoverThumbnailCache();
    const int thumbnailSide = 304;   // 152 pt a 2x, el lado de la tarjeta

    async Task<int> RequestAsync(IEnumerable<LibraryItem> requested)
    {
        int asked = 0;

        foreach (LibraryItem item in requested)
        {
            asked++;

            string key = CoverThumbnailKey.ForHash(item.CoverHash, thumbnailSide)
                         ?? CoverThumbnailKey.ForPath(item.SourcePath, thumbnailSide)!;

            await thumbnails.ThumbnailAsync(
                key, thumbnailSide, _ => Task.FromResult(store.ReadCover(item)));
        }

        return asked;
    }

    Console.WriteLine($"    (pedidos por pasada: {albumCovers.Count})");

    await MeasureAsync("Miniaturas: pasada en frío (caché vacía)",
        () => RequestAsync(albumCovers));

    Console.WriteLine($"    aciertos: {thumbnails.Hits} -- decodificaciones: {thumbnails.Misses}");

    Console.WriteLine($"    en caché: {thumbnails.Count} miniaturas, "
                      + $"{thumbnails.Cost / 1024.0 / 1024.0:0.0} MB (tope {ThumbnailCacheIndex.DefaultCostLimit / 1024 / 1024} MB)");

    await MeasureAsync("Miniaturas: la misma pasada otra vez (con expulsión de por medio)",
        () => RequestAsync(albumCovers));

    Console.WriteLine($"    aciertos: {thumbnails.Hits} -- decodificaciones: {thumbnails.Misses}");

    // Lo que de verdad pasa al desplazarse un poco y volver: lo último visto
    // sigue estando.
    int recent = Math.Min(thumbnails.Count, albumCovers.Count);

    await MeasureAsync($"Miniaturas: las últimas {recent} otra vez (todas en caché)",
        () => RequestAsync(albumCovers.TakeLast(recent)));

    Console.WriteLine($"    aciertos: {thumbnails.Hits} -- decodificaciones: {thumbnails.Misses}");
    ReportMemory("con la caché de miniaturas llena");

    thumbnails.Clear();

    if (diskDelayMs > 0)
    {
        Console.WriteLine();
        Console.WriteLine($"--- d. Disco lento simulado ({diskDelayMs} ms/llamada, réplica calibrada -- ver ST-200) ---");
        Console.WriteLine();

        long refreshMs = SlowDiskReplica.Run("Réplica de RefreshAvailable (File.Exists por ítem)", loaded, diskDelayMs,
            item => File.Exists(item.SourcePath));

        long loadMs = SlowDiskReplica.Run("Réplica de ReadCover en LoadItems (File.Exists + ReadAllBytes por ítem con carátula)", loaded, diskDelayMs,
            item => { _ = File.Exists(store.CoverPath(item.Id)); return true; });

        Console.WriteLine($"    Arranque estimado a {diskDelayMs} ms/llamada: ~{(refreshMs + loadMs) / 1000.0:0.0} s (RefreshAvailable + ReadCover; no incluye el resto de Reload)");
    }
    else
    {
        Console.WriteLine();
        Console.WriteLine("--- d. Disco lento simulado: omitido (pasa un 3er argumento > 0, p. ej. 3, para correrlo -- tarda del orden de minutos) ---");
    }
}
finally
{
    try { Directory.Delete(root, recursive: true); } catch (IOException) { }
}

// --- Réplica de lo que manda el GridView (ST-202) ---
//
// Desde ST-202 la selección de la cuadrícula la lleva el CONTROL
// (`SelectionMode="Extended"`), y el modelo solo anota lo que él avisa. Acá no
// hay control —esto corre sin ventana—, así que se replica exactamente el aviso
// que mandaría: `SelectionChanged` con lo que entró y lo que salió.
//
// Es la razón por la que estas filas ya no llaman a `SelectOnly`/
// `ToggleSelection`: esos envoltorios se fueron con los gestos a mano.

/// <summary>Clic simple: reemplaza la selección por esa tarjeta.</summary>
static void Click(MediaGridViewModel grid, MediaCard card) =>
    grid.SyncFromControl([card], [.. grid.SelectedCards.Where(other => !ReferenceEquals(other, card))]);

/// <summary>Ctrl+clic: suma o quita esa tarjeta, sin tocar el resto.</summary>
static void CtrlClick(MediaGridViewModel grid, MediaCard card) =>
    grid.SyncFromControl(card.IsSelected ? [] : [card], card.IsSelected ? [card] : []);

/// <summary>
/// Ctrl+A: <b>un</b> aviso con todo lo que faltaba, que es lo que hace
/// <c>GridView.SelectAll()</c>.
/// </summary>
static void CtrlA(MediaGridViewModel grid) =>
    grid.SyncFromControl([.. grid.Cards.Where(card => !card.IsSelected)], []);

static void ClearSelection(MediaGridViewModel grid) =>
    grid.SyncFromControl([], [.. grid.SelectedCards]);

/// <summary>
/// Memoria residente del proceso, para el criterio de ST-208 —"sin JPEG
/// completos en RAM"—. Se fuerza una recolección antes: sin eso, lo que se mide
/// incluye basura que el recolector todavía no tocó y el número no dice nada.
/// </summary>
static void ReportMemory(string what)
{
    GC.Collect();
    GC.WaitForPendingFinalizers();
    GC.Collect();

    using var process = System.Diagnostics.Process.GetCurrentProcess();
    process.Refresh();

    Console.WriteLine($"    memoria residente {what}: {process.WorkingSet64 / 1024.0 / 1024.0:0} MB"
                      + $" (montón administrado: {GC.GetTotalMemory(false) / 1024.0 / 1024.0:0} MB)");
}

static T Measure<T>(string what, Func<T> action)
{
    var watch = Stopwatch.StartNew();
    T result = action();
    watch.Stop();

    Console.WriteLine($"{watch.ElapsedMilliseconds,6} ms  {what}");
    return result;
}

static async Task<T> MeasureAsync<T>(string what, Func<Task<T>> action)
{
    var watch = Stopwatch.StartNew();
    T result = await action();
    watch.Stop();

    Console.WriteLine($"{watch.ElapsedMilliseconds,6} ms  {what}");
    return result;
}

static void MeasureVoid(string what, Action action)
{
    var watch = Stopwatch.StartNew();
    action();
    watch.Stop();

    Console.WriteLine($"{watch.ElapsedMilliseconds,6} ms  {what}");
}

static long MeasureVoidTimed(string what, Action action)
{
    var watch = Stopwatch.StartNew();
    action();
    watch.Stop();

    Console.WriteLine($"{watch.ElapsedMilliseconds,6} ms  {what}");
    return watch.ElapsedMilliseconds;
}

// La espera precisa (Stopwatch + SpinWait en vez de Thread.Sleep, que en
// Windows no duerme lo pedido) vive en SlowDiskReplica.cs -- 2.º addendum de
// ST-200.
