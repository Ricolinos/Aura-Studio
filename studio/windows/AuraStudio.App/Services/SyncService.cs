using AuraStudio.Core;
using AuraStudio.Core.Library;

namespace AuraStudio.App.Services;

/// <summary>
/// Sincroniza la biblioteca con el iPod. Es la costura entre la app y el motor:
/// arma la lista de archivos con las preferencias del usuario, deja que
/// <see cref="SyncPlanner"/> decida y que <see cref="LibrarySyncEngine"/>
/// escriba, y traduce el resultado a lo que muestra la pantalla.
///
/// <para>Nada de lo que decide o escribe vive acá: todo eso está en Core, donde
/// se puede probar sin un iPod conectado.</para>
/// </summary>
public sealed class SyncService : ISyncService
{
    private readonly IAppPreferences _preferences;

    public SyncService(IAppPreferences preferences) => _preferences = preferences;

    public event EventHandler<SyncProgressEventArgs>? ProgressChanged;

    public Task<SyncPlanResult> BuildPlanAsync(string volumeRoot, SyncOptions options, CancellationToken ct = default)
    {
        ct.ThrowIfCancellationRequested();
        return Task.Run(() => BuildPlan(volumeRoot, options), ct);
    }

    public async Task<SyncResult> PreviewSyncAsync(string volumeRoot, SyncOptions options, CancellationToken ct = default)
    {
        DateTimeOffset started = DateTimeOffset.UtcNow;
        if (!Directory.Exists(volumeRoot)) return Failure("El volumen del iPod ya no está disponible.", started);

        Report(SyncPhase.Scanning);
        SyncPlanResult plan = await BuildPlanAsync(volumeRoot, options, ct);
        Report(SyncPhase.Comparing, total: plan.ToCopy.Count());

        return new SyncResult
        {
            Success = true,
            FilesCopied = plan.ToCopy.Count(),
            FilesSwept = plan.ToSweep.Count,
            OrphansProposed = plan.Orphans.Count,
            BytesToCopy = BytesOf(plan),
            Duration = DateTimeOffset.UtcNow - started
        };
    }

    public async Task<SyncResult> SyncAsync(string volumeRoot, SyncOptions options, CancellationToken ct = default)
    {
        DateTimeOffset started = DateTimeOffset.UtcNow;
        if (!Directory.Exists(volumeRoot)) return Failure("El volumen del iPod ya no está disponible.", started);

        if (options.DryRun) return await PreviewSyncAsync(volumeRoot, options, ct);

        try
        {
            Report(SyncPhase.Scanning);
            LibraryScan scan = await Task.Run(() => Scan(options), ct);
            SyncPlanResult plan = SyncPlanner.Plan(scan.Files, DeviceSyncManifest.Load(volumeRoot));

            int total = plan.ToCopy.Count();
            long bytes = BytesOf(plan);
            Report(SyncPhase.Comparing, total: total, totalBytes: bytes);

            string installationId = _preferences.InstallationId;
            IReadOnlyCollection<string> approved = options.OrphansToRemove;

            SyncOutcome outcome = await Task.Run(() => LibrarySyncEngine.Apply(volumeRoot, plan,
                new SyncEngineOptions
                {
                    InstallationId = installationId,
                    ApprovedOrphanSourcePaths = approved,
                    CancellationToken = ct,
                    OnProgress = (copied, all) => Report(SyncPhase.Copying, copied, all, bytes)
                }), CancellationToken.None);

            // Todo lo que el firmware lee para armar sus pantallas se escribe
            // ahora, con lo que de verdad quedó en el iPod. Corre también si se
            // canceló: lo copiado ya está ahí y tiene que quedar anunciado.
            Report(SyncPhase.WritingManifest);
            await Task.Run(() => Finalize(volumeRoot, scan, outcome, options), CancellationToken.None);

            Report(SyncPhase.Complete, outcome.Copied.Count, total, bytes);

            return new SyncResult
            {
                Success = true,
                Cancelled = outcome.Cancelled,
                FilesCopied = outcome.Copied.Count,
                FilesSwept = outcome.Swept.Count,
                FilesDeleted = outcome.Deleted.Count,
                OrphansProposed = plan.Orphans.Count - outcome.Deleted.Count,
                BytesToCopy = bytes,
                Duration = DateTimeOffset.UtcNow - started,
                Failures = [.. outcome.Failures.Select(failure => $"{failure.DestinationRelativePath}: {failure.Message}")]
            };
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception ex)
        {
            return Failure($"No se pudo completar la sincronización: {ex.Message}", started);
        }
    }

    /// <summary>
    /// Letras, carátulas, listas, pósters e índices, con lo que de verdad
    /// quedó en el iPod: lo que falló al copiar se saca del mapa, así ningún
    /// índice apunta a un archivo que no está.
    /// </summary>
    private void Finalize(string volumeRoot, LibraryScan scan, SyncOutcome outcome, SyncOptions options)
    {
        var failed = outcome.Failures
            .Select(failure => failure.DestinationRelativePath)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        Dictionary<Guid, string> destinations = scan.DestinationByItemId
            .Where(pair => !failed.Contains(pair.Value))
            .ToDictionary(pair => pair.Key, pair => pair.Value);

        SyncFinalizeResult finalized = LibrarySyncFinalizer.Run(volumeRoot, new SyncFinalizeInput
        {
            Items = scan.Items,
            DestinationByItemId = destinations,
            Playlists = options.SyncPlaylists ? new LibraryStore(scan.LibraryRoot).LoadPlaylists() : [],
            LibraryRoot = scan.LibraryRoot,
            CoverArtPolicy = CoverArtPolicy.AlbumOnly,
            Downscale = options.SyncArtistImages ? Downscale : null,
            SquareCrop = SquareCrop,
            PlaylistArt = ComposePlaylistArt,

            // ST-208: las carátulas ya no viven en memoria, así que el
            // finalizador necesita de dónde sacarlas. Salen del mismo almacén de
            // la biblioteca que se está sincronizando, y se lee <b>una por
            // carpeta de álbum</b>, no una por canción.
            CoverBytes = new LibraryStore(scan.LibraryRoot).ReadCover,

            // El MISMO criterio que usan las pantallas (R2-4): si acá se
            // agrupara distinto, el iPod recibiría dos fotos para el artista
            // que en Studio se ve como uno solo.
            ArtistGrouping = _preferences.ArtistGrouping
        });

        // ST-142: un sync que no copió ni una canción, pero cambió carátulas o
        // fotos de artista, SÍ tocó la sección Música — desde v18 el firmware
        // rehace su caché maestra por una clave que incluye el `mtime` de
        // `cover.jpg`. El marcador se une con el que dejó el motor: sumar
        // secciones, nunca perderlas.
        if (finalized.AlbumCoversChanged || finalized.ArtistImagesChanged)
        {
            SyncPendingMarker.Merge(volumeRoot,
                new SyncPendingMarker.Changes(Music: true, Video: false, Images: false));
        }
    }

    /// <summary>
    /// Los codificadores de Windows son asíncronos y el finalizador es
    /// síncrono; esto corre siempre en un hilo de fondo, nunca en el de la
    /// interfaz, así que esperar acá no bloquea nada que se vea.
    /// </summary>
    private static byte[]? Downscale(byte[] source, int maxDimension)
    {
        try { return Platform.ImageResizer.EncodeAsync(source, maxDimension, Platform.ImageResizer.DefaultQuality).GetAwaiter().GetResult(); }
        catch (Exception ex) when (ex is Platform.ImageResizeException or IOException) { return null; }
    }

    /// <summary>
    /// ST-142: el recorte cuadrado con el que la carátula (320) y la foto de
    /// artista (128) llegan al iPod. Mismo motivo que <see cref="Downscale"/>
    /// para esperar acá: esto corre en un hilo de fondo, nunca en el de la
    /// interfaz.
    /// </summary>
    private static byte[]? SquareCrop(byte[] source, int side)
    {
        try { return Platform.ImageResizer.EncodeSquareAsync(source, side, Platform.ImageResizer.DefaultQuality).GetAwaiter().GetResult(); }
        catch (Exception ex) when (ex is Platform.ImageResizeException or IOException) { return null; }
    }

    private static byte[]? ComposePlaylistArt(IReadOnlyList<byte[]> covers)
    {
        try { return Platform.PlaylistArtGenerator.ComposeAsync(covers).GetAwaiter().GetResult(); }
        catch (Exception ex) when (ex is Platform.ImageResizeException or IOException) { return null; }
    }

    // MARK: - Armado del plan

    /// <summary>
    /// El plan: qué copiar y qué quedó huérfano.
    ///
    /// <para><b>Los huérfanos SIEMPRE se calculan contra la biblioteca
    /// entera</b>, aunque el usuario haya acotado la copia a su selección
    /// (R3-4). Si no, "solo la selección" haría que todo lo demás del iPod
    /// apareciera como "ya no está en tu biblioteca" — una lista de cientos de
    /// archivos ofrecidos para borrar que en realidad sí están. Es la clase de
    /// error que se paga con archivos del usuario.</para>
    /// </summary>
    private SyncPlanResult BuildPlan(string volumeRoot, SyncOptions options)
    {
        DeviceSyncManifest manifest = DeviceSyncManifest.Load(volumeRoot);
        SyncPlanResult plan = SyncPlanner.Plan(Scan(options).Files, manifest);

        if (options.RestrictToSourcePaths is not { Count: > 0 }) return plan;

        SyncPlanResult whole = SyncPlanner.Plan(
            Scan(options with { RestrictToSourcePaths = null }).Files, manifest);

        return plan with { Orphans = whole.Orphans };
    }

    /// <param name="Files">Lo que hay que planificar.</param>
    /// <param name="Items">El catálogo completo, para lo que se escribe al final.</param>
    /// <param name="DestinationByItemId">Dónde va cada elemento, para las letras, los índices y las listas.</param>
    /// <param name="LibraryRoot">La carpeta de la biblioteca configurada, para las portadas y las fotos de artista.</param>
    private readonly record struct LibraryScan(
        List<SyncSourceFile> Files,
        IReadOnlyList<LibraryItem> Items,
        Dictionary<Guid, string> DestinationByItemId,
        string LibraryRoot);

    /// <summary>
    /// Lo que viaja al iPod: lo que está listo, del tipo que el usuario eligió
    /// sincronizar, con la ruta que le toca según sus preferencias de
    /// organización.
    /// </summary>
    private LibraryScan Scan(SyncOptions options)
    {
        var store = new LibraryStore(_preferences.LibraryPath);
        MusicOrganization organization = _preferences.MusicOrganization;
        MusicFilenameFormat filenameFormat = _preferences.MusicFilenameFormat;

        IReadOnlyList<LibraryItem> items = store.LoadItems();
        var files = new List<SyncSourceFile>();
        var destinations = new Dictionary<Guid, string>();
        var claimed = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        // R3-4: con "Solo la selección", la copia se acota a estas rutas de
        // origen. `null` = toda la biblioteca. Se compara por ruta de ORIGEN y
        // no por id porque es lo que el resolvedor de alcance ya calculó, y
        // porque el preparado puede no existir todavía.
        HashSet<string>? restricted = options.RestrictToSourcePaths is { Count: > 0 } paths
            ? new HashSet<string>(paths, StringComparer.OrdinalIgnoreCase)
            : null;

        foreach (LibraryItem item in items)
        {
            if (item.Status.State != LibraryItemState.Ready) continue;
            if (!Included(item.Kind, options)) continue;
            if (restricted is not null && !restricted.Contains(item.SourcePath)) continue;

            // Al iPod viaja lo preparado (transcodificado, redimensionado, con
            // las etiquetas reescritas); el original solo si ya era apto.
            string source = item.PreparedPath ?? item.SourcePath;
            if (!File.Exists(source)) continue;

            string destination = UniqueDestination(
                SyncLayout.DestinationRelativePath(item, organization, filenameFormat), claimed);

            var info = new FileInfo(source);
            files.Add(new SyncSourceFile(source, info.Length, info.LastWriteTimeUtc, destination));
            destinations[item.Id] = destination;
        }

        return new LibraryScan(files, items, destinations, store.Root);
    }

    /// <summary>
    /// Dos canciones distintas pueden caer en la misma ruta: mismo título en el
    /// mismo álbum, o dos fotos que se llaman <c>IMG_0001.jpg</c> en carpetas
    /// distintas. <b>Sin esto una pisaría a la otra en silencio</b> y el usuario
    /// terminaría con menos archivos de los que mandó, sin ningún aviso.
    /// </summary>
    private static string UniqueDestination(string destination, HashSet<string> claimed)
    {
        if (claimed.Add(destination)) return destination;

        string extension = Path.GetExtension(destination);
        string withoutExtension = destination[..^extension.Length];

        for (int suffix = 2; ; suffix++)
        {
            string candidate = $"{withoutExtension} ({suffix}){extension}";
            if (claimed.Add(candidate)) return candidate;
        }
    }

    private static bool Included(LibraryItemKind kind, SyncOptions options) => kind switch
    {
        LibraryItemKind.Music => options.SyncMusic,
        LibraryItemKind.Video => options.SyncVideos,
        LibraryItemKind.Photo => options.SyncImages,
        _ => false
    };

    private static long BytesOf(SyncPlanResult plan)
    {
        long bytes = 0;
        foreach (SyncPlanItem item in plan.ToCopy)
        {
            try { bytes += new FileInfo(item.SourcePath).Length; }
            catch (IOException) { }
        }
        return bytes;
    }

    private void Report(SyncPhase phase, int processed = 0, int total = 0, long totalBytes = 0) =>
        ProgressChanged?.Invoke(this, new SyncProgressEventArgs
        {
            Phase = phase, ProcessedFiles = processed, TotalFiles = total, TotalBytes = totalBytes
        });

    private static SyncResult Failure(string message, DateTimeOffset started) => new()
    {
        Success = false, ErrorMessage = message, Duration = DateTimeOffset.UtcNow - started
    };
}
