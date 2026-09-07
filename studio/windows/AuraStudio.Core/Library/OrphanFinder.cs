namespace AuraStudio.Core.Library;

/// <summary>Un archivo huérfano: nadie en el catálogo lo referencia.</summary>
public readonly record struct OrphanFile(string AbsolutePath, long SizeBytes);

/// <summary>Lo que encontró la búsqueda, listo para mostrarle al usuario y para borrar.</summary>
public sealed record OrphanScanResult(IReadOnlyList<OrphanFile> Files)
{
    public int Count => Files.Count;
    public long TotalBytes => Files.Sum(file => file.SizeBytes);
}

/// <summary>
/// Detector de huérfanos en <c>.preparados/</c> y <c>.portadas/</c> (ST-245,
/// B5 de "ajustes 3", plan §2): archivos que quedaron ahí de "Eliminar" antes
/// de esta ronda —que no tocaba ninguna de las dos carpetas— o de un
/// reprocesamiento que dejó atrás el preparado o la carátula vieja.
///
/// <para><b>"Referenciado" se compara normalizando Unicode (NFC), nunca por
/// igualdad cruda</b> (adición de A1 al contrato de ST-241): el nombrado
/// viejo de <c>.preparados/</c> (<see cref="StagingPaths.Resolve"/>, todavía
/// en uso hasta B4) sale del nombre del archivo de origen, que puede llevar
/// acento, y catálogo y disco no siempre lo escriben en la misma forma
/// Unicode. Comparar crudo haría que un preparado con acento que SÍ está en
/// uso apareciera como huérfano — y de ahí se borraría algo que un elemento
/// del catálogo todavía necesita. <see cref="CatalogPath.Normalize"/> es la
/// misma normalización que usa el resto del catálogo, para que esta
/// comparación no pueda discrepar de las demás.</para>
///
/// <para><b>Nunca toca disco por su cuenta</b>: <see cref="Scan"/> solo mira y
/// devuelve lo que encontró; borrar es un segundo paso explícito
/// (<see cref="Delete"/>), para que Ajustes pueda mostrar la lista y pedir
/// confirmación antes.</para>
/// </summary>
public static class OrphanFinder
{
    public static OrphanScanResult Scan(
        string libraryRoot,
        IReadOnlyList<LibraryItem> items,
        Func<string, IEnumerable<string>>? enumerateFiles = null,
        Func<string, long>? fileLength = null)
    {
        enumerateFiles ??= SafeFiles;
        fileLength ??= LengthOf;

        var referencedPrepared = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var referencedCovers = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (LibraryItem item in items)
        {
            // La música copiada no vive en .preparados/ (PreparedPath ==
            // SourcePath, ST-241): incluir su nombre acá no protegería nada
            // real y podría, por coincidencia, "proteger" un huérfano de
            // verdad que se llame igual.
            bool preparedLivesElsewhere = item.Kind == LibraryItemKind.Music
                && item.StorageKind == ItemStorage.Copy;

            if (!preparedLivesElsewhere && item.PreparedPath is { Length: > 0 } prepared)
            {
                AddName(referencedPrepared, prepared);
                if (item.Kind == LibraryItemKind.Video) AddName(referencedPrepared, CatalogPath.PosterFor(prepared));
            }

            // Las dos formas del nombre de carátula (ST-087: la canónica en
            // mayúsculas y guiones, y la legacy en minúsculas sin separadores)
            // — son ASCII puro (un GUID), así que acá el acento no aplica; se
            // cubren las dos igual porque LibraryStore todavía puede dejar la
            // legacy sin renombrar si el renombrado falló al cargar.
            AddName(referencedCovers, CatalogPath.CoverFileName(item.Id));
            AddName(referencedCovers, item.Id.ToString("N") + ".jpg");
        }

        var orphans = new List<OrphanFile>();

        CollectOrphans(
            Path.Combine(libraryRoot, PersistedLibrary.PreparedDirName),
            referencedPrepared, enumerateFiles, fileLength, orphans);

        CollectOrphans(
            Path.Combine(libraryRoot, PersistedLibrary.CoversDirName),
            referencedCovers, enumerateFiles, fileLength, orphans);

        return new OrphanScanResult(orphans);
    }

    private static void CollectOrphans(
        string directory,
        HashSet<string> referencedNames,
        Func<string, IEnumerable<string>> enumerateFiles,
        Func<string, long> fileLength,
        List<OrphanFile> orphans)
    {
        foreach (string file in enumerateFiles(directory))
        {
            string name = CatalogPath.Normalize(Path.GetFileName(file));
            if (referencedNames.Contains(name)) continue;

            orphans.Add(new OrphanFile(file, fileLength(file)));
        }
    }

    private static void AddName(HashSet<string> names, string pathOrName) =>
        names.Add(CatalogPath.Normalize(Path.GetFileName(pathOrName)));

    public static void Delete(OrphanScanResult scan, ILibraryFileSystem? fileSystem = null)
    {
        ILibraryFileSystem files = fileSystem ?? LibraryFileSystem.Shared;
        foreach (OrphanFile file in scan.Files) files.TryDelete(file.AbsolutePath);
    }

    private static IEnumerable<string> SafeFiles(string directory)
    {
        try
        {
            return Directory.Exists(directory) ? Directory.EnumerateFiles(directory) : [];
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return [];
        }
    }

    private static long LengthOf(string path)
    {
        try
        {
            return new FileInfo(path).Length;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return 0;
        }
    }
}
