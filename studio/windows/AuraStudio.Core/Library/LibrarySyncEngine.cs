namespace AuraStudio.Core.Library;

/// <summary>Un archivo que el plan marcó para copiar y que no se pudo escribir.</summary>
public sealed record SyncFailure(string SourcePath, string DestinationRelativePath, string Message);

/// <param name="Copied">Archivos escritos en el iPod.</param>
/// <param name="Swept">Lugares viejos que se limpiaron porque el archivo se movió.</param>
/// <param name="Deleted">Huérfanos que el usuario confirmó quitar.</param>
/// <param name="Failures">Lo que no se pudo escribir, con el motivo. El resto siguió.</param>
/// <param name="Cancelled">Si se detuvo a mitad. Lo ya copiado quedó completo y anunciado.</param>
/// <param name="Sections">Qué secciones tocó de verdad — es lo que se le pide reconstruir al firmware.</param>
public sealed record SyncOutcome(
    IReadOnlyList<string> Copied,
    IReadOnlyList<string> Swept,
    IReadOnlyList<string> Deleted,
    IReadOnlyList<SyncFailure> Failures,
    bool Cancelled,
    SyncPendingSections Sections)
{
    public bool MarkerWritten => !Sections.IsEmpty;
}

/// <param name="InstallationId">
/// Quién escribe. Dos equipos sincronizando el mismo iPod no se pisan los
/// registros: cada uno solo trata como propios los suyos.
/// </param>
/// <param name="ApprovedOrphanSourcePaths">
/// Los huérfanos que el usuario confirmó borrar. Vacío = <b>no se borra
/// ninguno</b>, que es el valor por omisión a propósito.
/// </param>
/// <param name="OnProgress">Se llama con (copiados, total) después de cada archivo.</param>
public sealed record SyncEngineOptions
{
    public string? InstallationId { get; init; }

    public IReadOnlyCollection<string> ApprovedOrphanSourcePaths { get; init; } = [];

    public Action<int, int>? OnProgress { get; init; }

    public CancellationToken CancellationToken { get; init; }
}

/// <summary>
/// Aplica un plan de sincronización al volumen del iPod. Port de la parte
/// ejecutora de <c>LibrarySync.swift</c>.
///
/// <para>Lo que decide está en <see cref="SyncPlanner"/> y
/// <see cref="SyncLayout"/>, ya probado sin disco. Acá solo se escribe — y lo
/// que importa es <b>que ningún corte deje el volumen peor que antes</b>: cada
/// archivo se escribe entero o no se escribe, y el manifiesto se guarda después
/// de cada uno para que desconectar el iPod a mitad conserve lo ya copiado.</para>
/// </summary>
public static class LibrarySyncEngine
{
    /// <summary>
    /// Extensión de los temporales de la copia. <b>Desconocida para el
    /// firmware</b> a propósito: un <c>.aura-tmp</c> a medio escribir nunca se
    /// indexa, mientras que un <c>.mp3</c> truncado sí se indexaría, con
    /// metadata basura y todo.
    ///
    /// <para>Es la misma que usa la app de macOS: cada una barre los
    /// temporales que dejó la otra.</para>
    /// </summary>
    public const string TemporaryFileExtension = ".aura-tmp";

    /// <summary>
    /// Presente mientras un sync está en curso; ausente = el último cerró
    /// limpio. Si sigue ahí al conectar, el sync anterior se cortó de golpe.
    /// </summary>
    public const string InProgressMarkerRelativePath = ".rockbox/aura/sync_in_progress";

    /// <summary>
    /// Bloque de la copia interrumpible: chico como para que cancelar responda
    /// rápido, grande como para no ahogar la copia en llamadas al sistema sobre
    /// USB 2.0.
    /// </summary>
    public const int CopyBlockSize = 4 * 1024 * 1024;

    /// <summary>
    /// Crea las cuatro carpetas del contrato. El firmware también las crea al
    /// arrancar, así que ninguno depende del otro — pero un iPod recién
    /// formateado tiene que quedar utilizable sin arrancarlo primero.
    /// </summary>
    public static void EnsureDeviceDirectories(string volumeRoot)
    {
        foreach (string directory in SyncLayout.DeviceDirectories)
            Directory.CreateDirectory(Path.Combine(volumeRoot, directory));
    }

    public static bool HasInProgressMarker(string volumeRoot) =>
        File.Exists(Path.Combine(volumeRoot, ToNative(InProgressMarkerRelativePath)));

    /// <summary>
    /// Borra los <c>.aura-tmp</c> que hayan quedado de un sync cortado de golpe
    /// (desconexión, cierre de la app). Nunca toca nada que no sea un temporal
    /// propio.
    /// </summary>
    public static int SweepOrphanedTempFiles(string volumeRoot)
    {
        int swept = 0;

        foreach (string directoryName in SyncLayout.DeviceDirectories)
        {
            string root = Path.Combine(volumeRoot, directoryName);
            if (!Directory.Exists(root)) continue;

            foreach (string path in Directory.EnumerateFiles(root, "*" + TemporaryFileExtension,
                         SearchOption.AllDirectories))
            {
                try { File.Delete(path); swept++; }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
            }
        }

        return swept;
    }

    /// <summary>
    /// Copia lo que el plan marcó, barre los lugares viejos, borra <b>solo</b>
    /// los huérfanos confirmados, y deja el marcador para que el firmware
    /// reconstruya las secciones tocadas.
    ///
    /// <para>Cancelar no es abortar: lo ya copiado está completo en el disco, y
    /// el manifiesto y el marcador se escriben igual. El iPod queda consistente,
    /// con menos archivos de los pedidos.</para>
    /// </summary>
    public static SyncOutcome Apply(string volumeRoot, SyncPlanResult plan, SyncEngineOptions? options = null)
    {
        options ??= new SyncEngineOptions();

        EnsureDeviceDirectories(volumeRoot);
        SweepOrphanedTempFiles(volumeRoot);
        WriteInProgressMarker(volumeRoot);

        DeviceSyncManifest manifest = DeviceSyncManifest.Load(volumeRoot);

        var copied = new List<string>();
        var swept = new List<string>();
        var deleted = new List<string>();
        var failures = new List<SyncFailure>();
        var sections = new SyncPendingSections();
        bool cancelled = false;

        List<SyncPlanItem> work = [.. plan.ToCopy];

        foreach (SyncPlanItem item in work)
        {
            // La cancelación se revisa también en la frontera de archivo: si ya
            // se pidió, para este archivo ni se toca el disco.
            if (options.CancellationToken.IsCancellationRequested) { cancelled = true; break; }

            try
            {
                if (item.StaleDestinationRelativePath is { Length: > 0 } stale)
                {
                    if (DeleteWithLyrics(volumeRoot, stale))
                    {
                        swept.Add(stale);
                        sections = sections.Including(stale);
                    }
                }

                string destination = Path.Combine(volumeRoot, ToNative(item.DestinationRelativePath));

                if (!CopyTransactionally(item.SourcePath, destination, options.CancellationToken))
                {
                    cancelled = true;
                    break;
                }

                copied.Add(item.DestinationRelativePath);
                sections = sections.Including(item.DestinationRelativePath);
                options.OnProgress?.Invoke(copied.Count, work.Count);

                CopyPosterSidecar(item.SourcePath, destination);

                manifest.Records[item.SourcePath] = RecordFor(item, destination, options.InstallationId);

                // Después de CADA archivo, no al final: es lo que hace que
                // cancelar o desconectar conserve el progreso ya copiado.
                manifest.Save(volumeRoot);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or NotSupportedException
                                           or ArgumentException)
            {
                // Un archivo con un nombre imposible para FAT32, corrupto o sin
                // permisos no puede abortar el resto: el usuario prefiere 900
                // canciones y un aviso, a nada y un aviso.
                failures.Add(new SyncFailure(item.SourcePath, item.DestinationRelativePath, ex.Message));
            }
        }

        foreach (string sourcePath in options.ApprovedOrphanSourcePaths)
        {
            if (!manifest.Records.TryGetValue(sourcePath, out DeviceSyncRecord? record)) continue;

            if (DeleteWithLyrics(volumeRoot, record.DestinationRelativePath))
            {
                deleted.Add(record.DestinationRelativePath);
                sections = sections.Including(record.DestinationRelativePath);
            }

            manifest.Records.Remove(sourcePath);
        }

        manifest.Save(volumeRoot);

        if (!sections.IsEmpty) WriteMarkerAndMaybeClearDatabases(volumeRoot, sections);

        RemoveInProgressMarker(volumeRoot);

        return new SyncOutcome(copied, swept, deleted, failures, cancelled, sections);
    }

    /// <summary>
    /// El marcador de <c>/.aura/sync-pending.json</c> para que el firmware
    /// reconstruya solo las secciones tocadas (contrato §4).
    ///
    /// <para><b>La base de datos solo se borra si el firmware NO anuncia
    /// <c>sync_marker_supported</c></b> (contrato §4.4). Con un firmware que sí
    /// lo anuncia, borrarla le quitaría al usuario su música vieja mientras el
    /// firmware decide cuándo reconstruir.</para>
    /// </summary>
    private static void WriteMarkerAndMaybeClearDatabases(string volumeRoot, SyncPendingSections sections)
    {
        new SyncPendingMarker(new SyncPendingMarker.Changes(sections.Music, sections.Video, sections.Images))
            .Write(volumeRoot);

        if (FirmwareCapabilities.SupportedSyncMarkerVersion(volumeRoot) is null && sections.Music)
            ClearFirmwareDatabases(volumeRoot);
    }

    /// <summary>
    /// El mecanismo previo al marcador, para firmwares anteriores a D-293: se
    /// borra la base de tagcache y el firmware la levanta de cero al arrancar.
    ///
    /// <para>Nunca toca <c>/.aura/thumbs/</c> ni <c>/.aura/art/</c>: son
    /// propiedad del firmware, sus claves no dependen de la base, y
    /// reconstruirlas cuesta minutos de espera para nada (contrato v15/v16).</para>
    /// </summary>
    public static void ClearFirmwareDatabases(string volumeRoot)
    {
        foreach (string directory in (string[])[".rockbox", ".aura/tagcache"])
        {
            string full = Path.Combine(volumeRoot, ToNative(directory));
            if (!Directory.Exists(full)) continue;

            foreach (string name in DatabaseFileNames)
            {
                string path = Path.Combine(full, name);
                try { if (File.Exists(path)) File.Delete(path); }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
            }
        }
    }

    private static readonly string[] DatabaseFileNames =
    [
        "database_idx.tcd", "database_0.tcd", "database_1.tcd", "database_2.tcd",
        "database_3.tcd", "database_4.tcd", "database_5.tcd", "database_6.tcd",
        "database_tmp.tcd", "database_state.tcd", "db_stamp.txt"
    ];

    private static DeviceSyncRecord RecordFor(SyncPlanItem item, string destination, string? installationId)
    {
        var source = new FileInfo(item.SourcePath);
        var written = new FileInfo(destination);

        return new DeviceSyncRecord(
            item.SourcePath,
            source.Length,
            DeviceSyncRecord.ToTimeInterval(source.LastWriteTimeUtc),
            item.DestinationRelativePath)
        {
            DestinationSize = written.Length,
            DestinationModifiedAt = DeviceSyncRecord.ToTimeInterval(written.LastWriteTimeUtc),
            WrittenBy = installationId,
            SyncedAt = DeviceSyncRecord.ToTimeInterval(DateTimeOffset.UtcNow)
        };
    }

    /// <summary>
    /// El póster de un video viaja pegado a su video (<c>&lt;video&gt;.jpg</c>)
    /// y no tiene entrada propia en el manifiesto: sigue el mismo diferencial
    /// que el archivo principal.
    ///
    /// <para>Sin transacción a propósito: es contenido derivado y regenerable,
    /// no dato del usuario.</para>
    /// </summary>
    private static void CopyPosterSidecar(string sourcePath, string destinationPath)
    {
        string poster = Path.ChangeExtension(sourcePath, ".jpg");
        if (!File.Exists(poster)) return;

        try { File.Copy(poster, Path.ChangeExtension(destinationPath, ".jpg"), overwrite: true); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    }

    /// <summary>
    /// Borra un archivo del iPod y <b>la letra que viajaba con él</b>. Dejar el
    /// <c>.lrc</c> de una canción que ya no está es exactamente el huérfano que
    /// el contrato §3 prohíbe.
    /// </summary>
    private static bool DeleteWithLyrics(string volumeRoot, string relativePath)
    {
        bool existed = false;

        try
        {
            string path = Path.Combine(volumeRoot, ToNative(relativePath));
            if (File.Exists(path)) { File.Delete(path); existed = true; }

            string lyrics = Path.Combine(volumeRoot, ToNative(SyncLayout.LyricsRelativePath(relativePath)));
            if (File.Exists(lyrics)) File.Delete(lyrics);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return false;
        }

        return existed;
    }

    /// <summary>
    /// Copia por bloques a <c>&lt;destino&gt;.aura-tmp</c> y recién al final
    /// renombra. El firmware nunca ve un archivo final a medio escribir, y una
    /// cancelación o una desconexión deja como mucho un temporal huérfano —que
    /// el próximo sync barre— en vez de un mp3 truncado.
    ///
    /// <para><b>No se conservan las fechas</b>: el tagcache decide "ya indexado,
    /// sin cambios" por <c>mtime</c>, así que todo lo que Studio escribe tiene
    /// fecha nueva y se vuelve a leer (contrato §4).</para>
    /// </summary>
    /// <returns><c>false</c> si se canceló a mitad; el destino queda intacto.</returns>
    private static bool CopyTransactionally(string sourcePath, string destinationPath, CancellationToken token)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(destinationPath)!);

        string temporary = destinationPath + TemporaryFileExtension;

        try
        {
            using (var input = new FileStream(sourcePath, FileMode.Open, FileAccess.Read, FileShare.Read))
            using (var output = new FileStream(temporary, FileMode.Create, FileAccess.Write, FileShare.None))
            {
                byte[] buffer = new byte[CopyBlockSize];

                while (true)
                {
                    if (token.IsCancellationRequested)
                    {
                        output.Dispose();
                        TryDelete(temporary);
                        return false;
                    }

                    int read = input.Read(buffer, 0, buffer.Length);
                    if (read == 0) break;
                    output.Write(buffer, 0, read);
                }
            }

            File.Move(temporary, destinationPath, overwrite: true);
            return true;
        }
        catch
        {
            TryDelete(temporary);
            throw;
        }
    }

    private static void TryDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    }

    private static void WriteInProgressMarker(string volumeRoot)
    {
        string path = Path.Combine(volumeRoot, ToNative(InProgressMarkerRelativePath));
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);

        // Mismo formato `clave: valor` que escribe la app de macOS.
        File.WriteAllText(path,
            $"started_at: {DeviceSyncRecord.ToTimeInterval(DateTimeOffset.UtcNow).ToString("0.###", System.Globalization.CultureInfo.InvariantCulture)}\n");
    }

    private static void RemoveInProgressMarker(string volumeRoot) =>
        TryDelete(Path.Combine(volumeRoot, ToNative(InProgressMarkerRelativePath)));

    /// <summary>
    /// Quita las carpetas que quedaron vacías bajo <c>/Music/</c> después de
    /// mover o borrar. Sin esto, cambiar el layout deja el iPod lleno de
    /// carpetas de artista vacías.
    ///
    /// <para>Solo bajo Music: Videos y Photos son planos, y borrar carpetas
    /// vacías en otro lado podría tocar algo que no es de Studio.</para>
    /// </summary>
    public static int PruneEmptyMusicFolders(string volumeRoot)
    {
        string music = Path.Combine(volumeRoot, SyncLayout.MusicDirectory);
        if (!Directory.Exists(music)) return 0;

        int removed = 0;

        // De las hojas hacia la raíz: borrar la hija puede dejar vacía a la
        // madre, y hay que darle la oportunidad de irse también.
        foreach (string directory in Directory.GetDirectories(music, "*", SearchOption.AllDirectories)
                     .OrderByDescending(path => path.Length))
        {
            try
            {
                if (Directory.EnumerateFileSystemEntries(directory).Any()) continue;
                Directory.Delete(directory);
                removed++;
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Una carpeta que no se deja borrar no puede detener el sync.
            }
        }

        return removed;
    }

    /// <summary>
    /// Las rutas del contrato usan "/" siempre; en Windows hay que traducirlas
    /// para tocar el disco.
    /// </summary>
    private static string ToNative(string relativePath) =>
        relativePath.Replace('/', Path.DirectorySeparatorChar);
}
