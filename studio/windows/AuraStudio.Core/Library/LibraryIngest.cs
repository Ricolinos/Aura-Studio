using AuraStudio.Core.Resources;

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

        // Normalizadas antes de comparar (addendum de ST-241): dos rutas al mismo
        // archivo pueden traer el acento escrito de las dos maneras —una del
        // Explorador, otra del catálogo que escribió la Mac— y sin normalizar la
        // misma canción entraría dos veces.
        var existing = new HashSet<string>(
            (existingPaths ?? []).Select(CatalogPath.Normalize), StringComparer.OrdinalIgnoreCase);

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

            if (!existing.Add(CatalogPath.Normalize(path)))
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
            parts.Add(Strings.Plural("library-ingest.added", result.Added.Count));

        if (result.CoverAssets.Count > 0)
            parts.Add(Strings.Plural("library-ingest.cover-assets", result.CoverAssets.Count));

        if (result.AlreadyInLibrary.Count > 0)
            parts.Add(Strings.Plural("library-ingest.already-in-library", result.AlreadyInLibrary.Count));

        if (result.WrongSection.Count > 0)
            parts.Add(Strings.Plural("library-ingest.wrong-section",
                result.WrongSection.Count, SectionNoun(section)));

        if (result.Unsupported.Count > 0)
            parts.Add(Strings.Plural("library-ingest.unsupported", result.Unsupported.Count));

        return parts.Count == 0 ? Strings.Get("library-ingest.nothing-to-add") : string.Join(" ", parts);
    }

    // El sustantivo entra a media frase ("1 archivo no es {} y no se agregó
    // acá"), así que arrastra su artículo y su género. Se mueve tal cual: si
    // en otro idioma no compone, se parte la frase entera, no el sustantivo —
    // pero eso es redactar, y B7a solo mueve.
    private static string SectionNoun(LibraryItemKind section) => section switch
    {
        LibraryItemKind.Music => Strings.Get("library-ingest.section-noun-music"),
        LibraryItemKind.Video => Strings.Get("library-ingest.section-noun-video"),
        LibraryItemKind.Photo => Strings.Get("library-ingest.section-noun-photo"),
        _ => Strings.Get("library-ingest.section-noun-other")
    };
}
