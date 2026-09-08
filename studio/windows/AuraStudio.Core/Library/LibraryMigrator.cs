using AuraStudio.Core.Resources;

namespace AuraStudio.Core.Library;

/// <summary>
/// Pone al día una biblioteca de una versión anterior (ST-246).
///
/// <para><b>Nunca corre sola.</b> La dispara el usuario, desde el aviso o desde
/// Ajustes. Abrir la biblioteca <b>no escribe un solo archivo</b>: lo único que
/// pasa al cargar es que <c>storage</c> se infiere en memoria (ST-241) y se
/// persiste con el próximo guardado del catálogo. Migrar sin avisar sería tocar
/// los archivos del usuario porque sí — y son suyos.</para>
///
/// <para><b>Qué hace</b>, por elemento y en este orden:</para>
///
/// <list type="number">
/// <item>A las copias de <c>Música/</c> les escribe las etiquetas del catálogo.
/// El escritor no hace nada si ya coinciden, así que esto es gratis en una
/// biblioteca ya al día.</item>
/// <item>A los preparados con el nombre viejo los <b>renombra</b> al
/// identificador (ST-241), con su póster hermano si lo tienen. Renombrar y no
/// recopiar: son gigabytes, y el archivo ya está bien.</item>
/// <item>A la música referenciada le asegura su preparado con la regla de
/// ST-244 — <b>solo si hace falta uno</b>: si el archivo del usuario ya dice lo
/// que dice el catálogo, no se prepara nada.</item>
/// <item>Y al final borra lo que quedó huérfano en <c>.preparados/</c> y
/// <c>.portadas/</c>, con el detector de ST-245.</item>
/// </list>
///
/// <para><b>Es idempotente y se puede reanudar.</b> Cada paso pregunta antes de
/// escribir, así que correrla dos veces no toca nada la segunda, y cancelarla a
/// mitad deja hecho lo hecho —que es trabajo válido— y lo que falta se hace en
/// la siguiente. Nada de esto necesita una marca de "ya migrada" en el catálogo
/// compartido: las señales que disparan el aviso se apagan solas al
/// arreglarlas.</para>
///
/// <para><b>Nunca borra un elemento del catálogo</b> ni toca un archivo de
/// afuera de la biblioteca. Un original que no está se salta y sigue como no
/// disponible (ST-241).</para>
/// </summary>
public static class LibraryMigrator
{
    /// <param name="onProgress">Cuántos van, cuántos son, y qué se está tocando.</param>
    /// <param name="readCover">
    /// Los bytes de la carátula de un elemento, para cuando la política es por
    /// pista. Lo pone quien llama porque vive en <c>.portadas/</c> y esto no
    /// conoce el almacén.
    /// </param>
    public static async Task<LibraryMigrationSummary> RunAsync(
        string libraryRoot,
        IReadOnlyList<LibraryItem> items,
        AudioQuality quality = AudioQuality.OriginalLossless,
        CoverArtPolicy coverArt = CoverArtPolicy.AlbumOnly,
        Func<LibraryItem, byte[]?>? readCover = null,
        Func<string, string, AudioCodec, CancellationToken, Task<long>>? transcode = null,
        Action<int, int, string>? onProgress = null,
        ILibraryFileSystem? fileSystem = null,
        IPreparedMusicFiles? preparedFiles = null,
        CancellationToken ct = default)
    {
        ILibraryFileSystem files = fileSystem ?? LibraryFileSystem.Shared;
        IPreparedMusicFiles disk = preparedFiles ?? PreparedMusicFiles.Shared;

        string staging = Path.Combine(libraryRoot, PersistedLibrary.PreparedDirName);

        int tagged = 0;
        int renamed = 0;
        int built = 0;
        var errors = new List<string>();
        bool cancelled = false;

        for (int index = 0; index < items.Count; index++)
        {
            if (ct.IsCancellationRequested) { cancelled = true; break; }

            LibraryItem item = items[index];
            onProgress?.Invoke(index, items.Count, item.DisplayTitle);

            try
            {
                if (RenamePreparedToIdentifier(item, files)) renamed++;

                if (item.Kind != LibraryItemKind.Music) continue;

                if (item.StorageKind == ItemStorage.Copy)
                {
                    if (WriteTagsIntoCopy(item, coverArt, readCover)) tagged++;
                    continue;
                }

                PreparedMusicResult prepared = await PreparedMusicBuilder.EnsureAsync(
                    item, staging, quality, coverArt,
                    coverArt == CoverArtPolicy.PerTrack ? readCover?.Invoke(item) : null,
                    transcode, disk, ct).ConfigureAwait(false);

                if (prepared.Action == PreparedMusicAction.Build) built++;
                if (prepared.Path is { Length: > 0 } path) item.PreparedPath = path;
            }
            catch (OperationCanceledException)
            {
                cancelled = true;
                break;
            }
            catch (Exception ex) when (ex is not OutOfMemoryException)
            {
                // Que un elemento falle no puede tumbar la migración de los
                // otros doce mil: se anota con nombre y motivo, y sigue.
                errors.Add($"{item.DisplayTitle}: {ex.Message}");
            }
        }

        // Y una vez más al salir: cancelar durante el ÚLTIMO elemento no lo ve
        // la comprobación de arriba —el bucle ya no da otra vuelta— y el
        // resumen diría "terminé" cuando el usuario pidió parar.
        if (ct.IsCancellationRequested) cancelled = true;

        onProgress?.Invoke(items.Count, items.Count, "");

        // Los huérfanos van al final, cuando los renombrados ya dejaron de
        // apuntar a los nombres viejos: hacerlo antes borraría el archivo que
        // el paso siguiente iba a renombrar.
        int orphans = cancelled ? 0 : DeleteOrphans(libraryRoot, items, files, errors);

        return new LibraryMigrationSummary(tagged, renamed, built, orphans, errors.Count, errors, cancelled);
    }

    /// <summary>
    /// Renombra el preparado al identificador, con su póster hermano.
    ///
    /// <para><b>Se renombra, no se recopia.</b> El archivo ya está bien; lo que
    /// está mal es su nombre. Recopiarlo serían gigabytes movidos para nada, y
    /// una ventana en la que el preparado no existe.</para>
    ///
    /// <para>Si el destino ya está ocupado no se toca nada: eso significa que ya
    /// hay un preparado con el nombre bueno, y el viejo es un huérfano que el
    /// paso final se lleva.</para>
    /// </summary>
    private static bool RenamePreparedToIdentifier(LibraryItem item, ILibraryFileSystem files)
    {
        if (!LibraryMigrationScanner.HasLegacyPreparedName(item)) return false;
        if (item.PreparedPath is not { Length: > 0 } old || !files.FileExists(old)) return false;

        string directory = Path.GetDirectoryName(old)!;
        string target = Path.Combine(directory, CatalogPath.PreparedFileName(item.Id, Path.GetExtension(old)));

        if (files.FileExists(target)) return false;

        files.Move(old, target);
        item.PreparedPath = target;

        // El póster de un video es `<preparado>.jpg` hermano (ST-241): si se
        // queda con el nombre viejo, el video pierde su carátula sin que nadie
        // lo note.
        string oldPoster = CatalogPath.PosterFor(old);
        if (files.FileExists(oldPoster)) files.Move(oldPoster, CatalogPath.PosterFor(target));

        return true;
    }

    private static bool WriteTagsIntoCopy(
        LibraryItem item, CoverArtPolicy coverArt, Func<LibraryItem, byte[]?>? readCover)
    {
        byte[]? cover = coverArt == CoverArtPolicy.PerTrack ? readCover?.Invoke(item) : null;

        return LocalTagWriter.Write(item.SourcePath, item.Metadata, coverArt, cover).Written;
    }

    /// <summary>
    /// Lo que quedó en <c>.preparados/</c> y <c>.portadas/</c> sin que nadie lo
    /// referencie, con el detector de ST-245 — no con uno propio: dos formas de
    /// decidir qué es huérfano es cómo se termina borrando algo que sí hacía
    /// falta.
    /// </summary>
    private static int DeleteOrphans(
        string libraryRoot, IReadOnlyList<LibraryItem> items, ILibraryFileSystem files, List<string> errors)
    {
        try
        {
            OrphanScanResult scan = OrphanFinder.Scan(libraryRoot, items);
            if (scan.Count == 0) return 0;

            OrphanFinder.Delete(scan, files);
            return scan.Count;
        }
        catch (Exception ex) when (ex is not OutOfMemoryException)
        {
            errors.Add(Strings.Format("library-migrator.orphans-delete-failed", ex.Message));
            return 0;
        }
    }
}
