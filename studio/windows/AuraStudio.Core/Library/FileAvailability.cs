namespace AuraStudio.Core.Library;

/// <summary>
/// Qué archivos del catálogo están de verdad en disco (ST-203).
///
/// <para><b>Por qué existe.</b> `RefreshAvailable` preguntaba por los 12 000
/// archivos, uno por uno, <b>en el hilo de interfaz</b>, y no solo al abrir:
/// también después de cada guardado, de cada edición de metadata y de cada
/// cambio de categoría. Con la biblioteca del dueño en una unidad de red eso
/// son doce mil viajes al servidor cada vez que el usuario toca algo.</para>
///
/// <para>Acá la barrida se hace por lotes y fuera del hilo de interfaz, y el
/// resultado queda anotado para que las recargas siguientes no vuelvan a
/// preguntarle al disco por lo que ya saben.</para>
/// </summary>
public static class FileAvailability
{
    /// <summary>
    /// Cuántos se miran entre aviso y aviso de avance. Lo bastante grande para
    /// que el progreso no sea un chorro de avisos, lo bastante chico para que
    /// se vea moverse.
    /// </summary>
    public const int DefaultBatchSize = 250;

    /// <summary>
    /// Si el archivo está. <b>Nunca lanza</b>: una ruta inválida o un permiso
    /// denegado son "no está", no un error que tumbe la carga de la biblioteca.
    /// </summary>
    public static bool Exists(string path)
    {
        try
        {
            return path.Length > 0 && File.Exists(path);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            return false;
        }
    }

    /// <summary>
    /// Mira todos los elementos y anota en <paramref name="known"/> qué rutas
    /// están. Va por lotes para poder avisar del avance y para poder pararse a
    /// mitad.
    ///
    /// <para>Se escribe en un diccionario que pasa quien llama —y no se
    /// devuelve uno nuevo— porque ese mapa sobrevive a la carga: es lo que
    /// después evita volver a preguntar.</para>
    /// </summary>
    /// <param name="onProgress">Cuántos van y cuántos son, al terminar cada lote.</param>
    public static void Sweep(
        IReadOnlyList<LibraryItem> items,
        IDictionary<string, bool> known,
        Func<string, bool>? exists = null,
        Action<int, int>? onProgress = null,
        int batchSize = DefaultBatchSize,
        CancellationToken ct = default)
    {
        Func<string, bool> probe = exists ?? Exists;
        int size = Math.Max(1, batchSize);

        for (int index = 0; index < items.Count; index++)
        {
            ct.ThrowIfCancellationRequested();

            string path = items[index].SourcePath;
            known[path] = probe(path);

            if ((index + 1) % size == 0) onProgress?.Invoke(index + 1, items.Count);
        }

        if (items.Count > 0) onProgress?.Invoke(items.Count, items.Count);
    }

    /// <summary>
    /// Los elementos que se pueden mostrar, según lo ya anotado.
    ///
    /// <para>Lo que <b>no</b> esté en el mapa se pregunta en el momento y se
    /// anota: son los que acaban de entrar a la biblioteca, un puñado. Suponer
    /// que están sería mostrar un archivo que quizá no está; volver a barrer el
    /// catálogo entero para averiguarlo es justo lo que ST-203 quitó.</para>
    /// </summary>
    public static IReadOnlyList<LibraryItem> Available(
        IReadOnlyList<LibraryItem> items,
        IDictionary<string, bool> known,
        Func<string, bool>? exists = null)
    {
        Func<string, bool> probe = exists ?? Exists;
        List<LibraryItem> available = new(items.Count);

        foreach (LibraryItem item in items)
        {
            if (!known.TryGetValue(item.SourcePath, out bool present))
            {
                present = probe(item.SourcePath);
                known[item.SourcePath] = present;
            }

            if (present) available.Add(item);
        }

        return available;
    }
}
