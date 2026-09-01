namespace AuraStudio.Core.Library;

/// <summary>
/// Qué pasó con cada archivo que se soltó. Se devuelve entero —no solo lo que
/// entró— para poder decirle al usuario por qué algo no aparece, en vez de que
/// desaparezca en silencio.
/// </summary>
/// <param name="Added">Los elementos nuevos, en el orden en que se soltaron.</param>
/// <param name="CoverAssets">
/// Imágenes que son carátula de una canción o póster de un video, no fotos.
/// </param>
/// <param name="WrongSection">
/// Archivos válidos pero de otro tipo: se soltó un MP3 en Fotos, por ejemplo.
/// </param>
/// <param name="AlreadyInLibrary">Ya estaban; no se duplican.</param>
/// <param name="Unsupported">Ni audio, ni video, ni imagen.</param>
public sealed record LibraryIngestResult(
    IReadOnlyList<LibraryItem> Added,
    IReadOnlyList<string> CoverAssets,
    IReadOnlyList<string> WrongSection,
    IReadOnlyList<string> AlreadyInLibrary,
    IReadOnlyList<string> Unsupported)
{
    public bool AddedAnything => Added.Count > 0;
}

/// <summary>
/// Decide qué entra a la biblioteca cuando el usuario suelta archivos en una
/// sección. Puro: no toca disco salvo para preguntar si una carpeta contiene
/// audio, y no muta nada — quien llama decide qué hacer con el resultado.
///
/// <para><b>Cada sección ingiere solo su tipo</b> (ST-012). Soltar un MP3 en
/// Fotos no lo mete a Fotos: se reporta, y la interfaz lo explica.</para>
/// </summary>
public static class LibraryIngest
{
    /// <summary>
    /// <paramref name="section"/> es la sección donde se soltó.
    /// <paramref name="existingPaths"/> son las rutas que ya están en la
    /// biblioteca.
    /// </summary>
    public static LibraryIngestResult Ingest(
        IEnumerable<string> droppedPaths,
        LibraryItemKind section,
        IEnumerable<string>? existingPaths = null,
        DateTimeOffset? addedAt = null)
    {
        List<string> paths = [.. droppedPaths];
        var context = new CoverArtDropContext(paths);
        bool intoPhotos = section == LibraryItemKind.Photo;

        var existing = new HashSet<string>(existingPaths ?? [], StringComparer.OrdinalIgnoreCase);

        var added = new List<LibraryItem>();
        var covers = new List<string>();
        var wrongSection = new List<string>();
        var duplicates = new List<string>();
        var unsupported = new List<string>();

        foreach (string path in paths)
        {
            LibraryItemKind kind = LibraryItem.ClassifyKind(path);

            if (kind == LibraryItemKind.Unsupported)
            {
                unsupported.Add(path);
                continue;
            }

            // ST-012: una carátula o un póster es un asset de su canción o su
            // video, nunca una entrada de Imágenes. Se revisa antes que la
            // sección, porque una carátula soltada junto a su álbum llega en el
            // mismo arrastre que la música.
            if (kind == LibraryItemKind.Photo
                && CoverArtAssets.IsCoverAsset(path, context, intoPhotos))
            {
                covers.Add(path);
                continue;
            }

            if (kind != section)
            {
                wrongSection.Add(path);
                continue;
            }

            if (!existing.Add(path))
            {
                duplicates.Add(path);
                continue;
            }

            added.Add(LibraryItem.FromDroppedFile(path, addedAt));
        }

        return new LibraryIngestResult(added, covers, wrongSection, duplicates, unsupported);
    }

    /// <summary>
    /// El resumen que se le muestra al usuario después de soltar. Nombra lo que
    /// <b>no</b> entró y por qué: un archivo que desaparece sin explicación se
    /// lee como que la app está rota.
    /// </summary>
    public static string Summary(LibraryIngestResult result, LibraryItemKind section)
    {
        var parts = new List<string>();

        if (result.Added.Count > 0)
            parts.Add(result.Added.Count == 1
                ? "Se agregó 1 elemento."
                : $"Se agregaron {result.Added.Count} elementos.");

        if (result.CoverAssets.Count > 0)
            parts.Add(result.CoverAssets.Count == 1
                ? "1 imagen se tomó como carátula, no como foto."
                : $"{result.CoverAssets.Count} imágenes se tomaron como carátulas, no como fotos.");

        if (result.AlreadyInLibrary.Count > 0)
            parts.Add(result.AlreadyInLibrary.Count == 1
                ? "1 ya estaba en tu biblioteca."
                : $"{result.AlreadyInLibrary.Count} ya estaban en tu biblioteca.");

        if (result.WrongSection.Count > 0)
            parts.Add(result.WrongSection.Count == 1
                ? $"1 archivo no es {SectionNoun(section)} y no se agregó acá."
                : $"{result.WrongSection.Count} archivos no son {SectionNoun(section)} y no se agregaron acá.");

        if (result.Unsupported.Count > 0)
            parts.Add(result.Unsupported.Count == 1
                ? "1 archivo no es compatible."
                : $"{result.Unsupported.Count} archivos no son compatibles.");

        return parts.Count == 0 ? "No había nada que agregar." : string.Join(" ", parts);
    }

    private static string SectionNoun(LibraryItemKind section) => section switch
    {
        LibraryItemKind.Music => "música",
        LibraryItemKind.Video => "video",
        LibraryItemKind.Photo => "una imagen",
        _ => "compatible"
    };
}
