namespace AuraStudio.Core.Library;

/// <summary>
/// Lo que la confirmación le tiene que decir al usuario antes de eliminar
/// (§0.4 del plan): cuántos archivos van a la Papelera y cuánto ocupan —solo
/// los de modo copia, que son los únicos que se tocan en disco— y cuántos son
/// puramente de catálogo.
/// </summary>
/// <param name="CopyCount">Elementos en modo copia: su archivo va a la Papelera.</param>
/// <param name="CopyBytes">
/// Lo que ocupan esos archivos, sumando <see cref="LibraryItem.FileSizeBytes"/>.
/// Un tamaño todavía no medido (<c>null</c>) cuenta como 0 — es una
/// aproximación con la que ya vive el resto de la app (ST-201), no un
/// tamaño exacto garantizado.
/// </param>
/// <param name="ReferenceCount">
/// Elementos en modo referencia: se quitan del catálogo, su original nunca
/// se toca.
/// </param>
public readonly record struct DeletionPreview(int CopyCount, long CopyBytes, int ReferenceCount)
{
    public int TotalCount => CopyCount + ReferenceCount;
}

/// <summary>Qué pasó con el archivo propio de un elemento al eliminarlo.</summary>
public enum DeletionOutcome
{
    /// <summary>Modo copia: el archivo fue a la Papelera de reciclaje.</summary>
    SentToRecycleBin,

    /// <summary>
    /// Modo copia, pero el archivo no estaba donde el catálogo decía —ni
    /// siquiera resolviendo NFC/NFD— así que no hubo nada que mandar a la
    /// Papelera. El elemento se quita del catálogo igual.
    /// </summary>
    SourceMissing,

    /// <summary>Modo referencia: solo se quitó del catálogo. El original nunca se toca.</summary>
    ReferenceOnly
}

public readonly record struct DeletionResult(Guid ItemId, DeletionOutcome Outcome);

/// <summary>
/// Eliminar elementos de la biblioteca (ST-245, B5 de "ajustes 3", plan §0.4
/// y §2).
///
/// <para><b>Modo copia</b>: el archivo de la biblioteca va a la <b>Papelera de
/// reciclaje</b> — nunca un borrado definitivo (<see cref="WindowsRecycleBin"/>).
/// <b>Modo referencia</b>: el original del usuario <b>nunca se toca</b>; solo
/// se quita del catálogo. En los dos modos se borran el preparado y la
/// carátula del elemento, que si no quedarían huérfanos en <c>.preparados/</c>
/// y <c>.portadas/</c> (<see cref="OrphanFinder"/> limpia lo que ya haya
/// quedado de antes de esta ronda).</para>
///
/// <para><b>El <c>.lrc</c>: no hay nada que borrar acá, y es a propósito, no
/// un olvido.</b> A diferencia de la Mac, Windows no escribe hoy ningún
/// sidecar <c>.lrc</c> local: <see cref="LibrarySyncFinalizer"/> lo escribe
/// solo en el volumen del iPod al sincronizar, nunca al lado del archivo de
/// la biblioteca. Verificado contra el código real antes de escribir esto
/// (ver DECISIONS.md ST-245) — el día que Windows tenga un <c>.lrc</c> local,
/// este es el lugar donde hay que borrarlo.</para>
///
/// <para><b>Nunca lanza.</b> Un archivo que ya no está, un disco desconectado
/// o un permiso que falta no pueden tumbar el borrado de los demás
/// elementos del lote.</para>
/// </summary>
public static class LibraryDeletion
{
    public static DeletionPreview Preview(IEnumerable<LibraryItem> items)
    {
        int copyCount = 0, referenceCount = 0;
        long copyBytes = 0;

        foreach (LibraryItem item in items)
        {
            if (item.StorageKind == ItemStorage.Copy)
            {
                copyCount++;
                copyBytes += item.FileSizeBytes ?? 0;
            }
            else
            {
                referenceCount++;
            }
        }

        return new DeletionPreview(copyCount, copyBytes, referenceCount);
    }

    public static IReadOnlyList<DeletionResult> Delete(
        string libraryRoot,
        IEnumerable<LibraryItem> items,
        IRecycleBin? recycleBin = null,
        ILibraryFileSystem? fileSystem = null)
    {
        IRecycleBin trash = recycleBin ?? DefaultRecycleBin();
        ILibraryFileSystem files = fileSystem ?? LibraryFileSystem.Shared;
        var results = new List<DeletionResult>();

        foreach (LibraryItem item in items)
        {
            DeletionOutcome outcome = item.StorageKind == ItemStorage.Copy
                ? DeleteCopySource(libraryRoot, item, trash, files)
                : DeletionOutcome.ReferenceOnly;

            DeletePrepared(item, files);
            DeleteCover(libraryRoot, item, files);

            results.Add(new DeletionResult(item.Id, outcome));
        }

        return results;
    }

    /// <summary>
    /// <see cref="AuraStudio.Core"/> apunta a un <c>net10.0</c> portable —no a
    /// un TFM de Windows— para que sus pruebas corran sin pedir Windows; la
    /// guarda de <see cref="OperatingSystem.IsWindows"/> es lo que le permite
    /// al analizador de plataforma dejar pasar <see cref="WindowsRecycleBin"/>
    /// acá. La app real es Windows siempre, así que el <c>else</c> nunca se
    /// ejecuta fuera de una prueba.
    /// </summary>
    private static IRecycleBin DefaultRecycleBin() =>
        OperatingSystem.IsWindows() ? WindowsRecycleBin.Shared : NoOpRecycleBin.Instance;

    private static DeletionOutcome DeleteCopySource(
        string libraryRoot, LibraryItem item, IRecycleBin trash, ILibraryFileSystem files)
    {
        string? actual = LibraryDiskPathResolver.ResolveExisting(libraryRoot, item.SourcePath, files.FileExists);
        if (actual is null) return DeletionOutcome.SourceMissing;

        return trash.MoveToRecycleBin(actual) ? DeletionOutcome.SentToRecycleBin : DeletionOutcome.SourceMissing;
    }

    /// <summary>
    /// El preparado y su póster hermano (video). <b>La música copiada no
    /// entra</b>: por la invariante de ST-241, <c>PreparedPath == SourcePath</c>
    /// para música en modo copia, así que "borrar el preparado" sería borrar el
    /// archivo de la biblioteca por segunda vez —el mismo que
    /// <see cref="DeleteCopySource"/> ya mandó a la Papelera—.
    /// </summary>
    private static void DeletePrepared(LibraryItem item, ILibraryFileSystem files)
    {
        if (item.Kind == LibraryItemKind.Music && item.StorageKind == ItemStorage.Copy) return;
        if (item.PreparedPath is not { Length: > 0 } prepared) return;
        if (string.Equals(prepared, item.SourcePath, StringComparison.OrdinalIgnoreCase)) return;

        files.TryDelete(prepared);
        files.TryDelete(CatalogPath.PosterFor(prepared));
    }

    private static void DeleteCover(string libraryRoot, LibraryItem item, ILibraryFileSystem files)
    {
        if (item.CoverRelativePath is not { Length: > 0 } relative) return;

        files.TryDelete(CatalogPath.Resolve(libraryRoot, relative));
    }
}
