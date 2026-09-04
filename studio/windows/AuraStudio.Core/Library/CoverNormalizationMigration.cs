namespace AuraStudio.Core.Library;

/// <summary>
/// La pasada única que deja cuadradas las carátulas de una biblioteca hecha
/// antes de ST-141. Port de <c>CoverNormalizationMigration.swift</c>: es la
/// mitad "recorrer y reescribir"; qué archivos entran lo decide quien llama
/// (<see cref="FilesToNormalize"/>), que es quien sabe cuáles son de música y
/// cuáles son pósters de video — <b>los pósters no se tocan: son 3:4 por
/// diseño</b> (contrato §A.1).
///
/// <para>Tres propiedades que no son negociables:</para>
/// <list type="bullet">
/// <item><b>No reescribe lo que ya cumple.</b> Un archivo cuadrado de lado
/// ≤ 1000 se salta sin decodificarlo: leer la cabecera cuesta casi nada y
/// recomprimirlo de gratis solo perdería calidad.</item>
/// <item><b>Se puede cancelar</b>, y se consulta antes de cada archivo. Uno
/// empezado se termina (la escritura es atómica), pero no se empieza el
/// siguiente.</item>
/// <item><b>Se puede retomar.</b> No hace falta un archivo de progreso: como
/// saltarse lo ya hecho es la regla, la segunda corrida arranca donde quedó la
/// primera. Por eso la marca <c>coversNormalized</c> se escribe <b>solo al
/// terminar la pasada completa</b>.</item>
/// </list>
/// </summary>
public static class CoverNormalizationMigration
{
    /// <param name="Normalized">Cuántas se reescribieron de verdad.</param>
    /// <param name="Visited">Cuántas se miraron (normalizadas + ya correctas + ilegibles).</param>
    /// <param name="Cancelled">Quedó trabajo pendiente porque se canceló.</param>
    public readonly record struct Result(int Normalized, int Visited, bool Cancelled);

    /// <summary>
    /// Recorre <paramref name="files"/> en orden. La cancelación se consulta
    /// antes de cada archivo; <paramref name="onProgress"/> recibe (hechas,
    /// total) después de cada uno.
    /// </summary>
    public static Result Run(IReadOnlyList<string> files, CoverArtNormalizer normalizer,
                             CancellationToken ct = default, Action<int, int>? onProgress = null)
    {
        int normalized = 0, visited = 0;

        foreach (string path in files)
        {
            if (ct.IsCancellationRequested) return new Result(normalized, visited, Cancelled: true);

            if (normalizer.NormalizeFile(path)) normalized++;
            visited++;
            onProgress?.Invoke(visited, files.Count);
        }

        return new Result(normalized, visited, Cancelled: false);
    }

    /// <summary>
    /// Los archivos de <c>.portadas\</c> que la migración debe mirar: las
    /// carátulas de las <b>canciones</b> y todas las fotos de artista.
    ///
    /// <para>Lo que queda deliberadamente afuera: los <b>pósters de video</b>,
    /// que viven en la misma carpeta y con el mismo nombre (<c>&lt;id&gt;.jpg</c>)
    /// pero son 3:4 por diseño — por eso esto se arma desde los items del
    /// catálogo, con su <c>Kind</c>, y no listando el directorio a ciegas; las
    /// <b>imágenes de las listas</b> (<c>playlist-&lt;id&gt;.jpg</c>), que ya nacen
    /// cuadradas; y los <b>archivos originales del usuario</b>, que la migración
    /// no toca nunca.</para>
    /// </summary>
    public static List<string> FilesToNormalize(IEnumerable<LibraryItem> items, LibraryStore store)
    {
        var files = new List<string>();

        foreach (LibraryItem item in items)
        {
            if (item.Kind != LibraryItemKind.Music) continue;
            string path = store.CoverPath(item.Id);
            if (File.Exists(path)) files.Add(path);
        }

        string artists = Path.Combine(store.CoversDirectory, "artistas");
        if (Directory.Exists(artists))
        {
            try { files.AddRange(Directory.EnumerateFiles(artists, "*.jpg")); }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
        }

        return files;
    }
}
