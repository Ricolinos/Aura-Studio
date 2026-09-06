namespace AuraStudio.Core.Library;

/// <summary>
/// Un tamaño ya medido y todavía sin aplicar. Existe para separar las dos
/// mitades del trabajo: <b>medir toca el disco</b> y va en segundo plano;
/// <b>aplicar toca elementos que la tabla está leyendo</b> y va en el hilo de
/// interfaz. Escribir desde el hilo de fondo en algo que la interfaz lee es
/// exactamente lo que costó ST-131.
/// </summary>
/// <param name="Path">
/// De qué archivo son esos bytes. Se guarda para poder descartar la medición si
/// al elemento le cambió la ruta mientras tanto (D-228: al procesarlo se puede
/// copiar a la biblioteca): esos bytes serían de otro archivo.
/// </param>
public readonly record struct MeasuredFileSize(LibraryItem Item, string Path, long Bytes);

/// <summary>
/// Llena el tamaño de archivo que falte en el catálogo, por lotes y fuera del
/// hilo de interfaz (ST-201).
///
/// <para><b>Por qué existe.</b> La columna "Tamaño" de la tabla de Canciones
/// necesita los bytes de cada archivo. Se leían con un <c>FileInfo</c> por fila,
/// cada vez que se armaba la tabla; con la biblioteca del dueño en una unidad de
/// red eso son 12 000 consultas al servidor por refresco — y la tabla se
/// refrescaba ante cualquier aviso del modelo, incluida cada publicación de
/// selección. De ahí venía el trabón al tercer álbum.</para>
///
/// <para>El tamaño ahora vive en el catálogo (<see cref="LibraryItem.FileSizeBytes"/>).
/// Un catálogo anterior no lo trae: se mide una vez, en segundo plano, y se
/// guarda. La migración es transparente — no hay nada que el usuario tenga que
/// hacer ni que esperar; mientras tanto la columna dice "--", que es lo mismo
/// que decía cuando el archivo no se podía leer.</para>
///
/// <para>Lo que <b>no</b> se hace: dar por perdido lo que no se pudo medir. Un
/// archivo en un disco desmontado no pesa 0 bytes, así que se deja sin tamaño y
/// se vuelve a intentar en la próxima apertura. Escribir un 0 ahí sería guardar
/// una conclusión sacada de una lectura que nunca ocurrió.</para>
/// </summary>
public static class FileSizeBackfill
{
    /// <summary>
    /// Cuántos se miden entre guardado y guardado. Suficientemente grande para
    /// que no sean 12 000 escrituras del catálogo, suficientemente chico para
    /// que cerrar la app a mitad no tire todo el trabajo.
    /// </summary>
    public const int DefaultBatchSize = 500;

    /// <summary>
    /// El tamaño real, o <c>null</c> si no se pudo leer. <b>Ausente y cero no
    /// son lo mismo</b>: cero es un archivo vacío de verdad, y ese sí se guarda.
    /// </summary>
    public static long? Measure(string path)
    {
        try
        {
            var info = new FileInfo(path);
            return info.Exists ? info.Length : null;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            return null;
        }
    }

    /// <summary>
    /// Si a este elemento le falta el tamaño. Lo que no se puede sincronizar
    /// tampoco se mide: no hay ninguna columna que lo muestre.
    /// </summary>
    public static bool NeedsSize(LibraryItem item) =>
        item.FileSizeBytes is null
        && item.Kind != LibraryItemKind.Unsupported
        && item.SourcePath.Length > 0;

    /// <summary>Los que hay que medir, en el orden del catálogo.</summary>
    public static IReadOnlyList<LibraryItem> Pending(IEnumerable<LibraryItem> items) =>
        [.. items.Where(NeedsSize)];

    /// <summary>
    /// Mide un lote <b>sin tocar los elementos</b>. El medidor se inyecta para
    /// poder probar esto sin disco.
    /// </summary>
    public static IReadOnlyList<MeasuredFileSize> MeasureBatch(
        IReadOnlyList<LibraryItem> batch, Func<string, long?>? sizeOf = null, CancellationToken ct = default)
    {
        Func<string, long?> measure = sizeOf ?? Measure;
        List<MeasuredFileSize> measured = [];

        foreach (LibraryItem item in batch)
        {
            ct.ThrowIfCancellationRequested();
            if (!NeedsSize(item)) continue;

            string path = item.SourcePath;
            if (measure(path) is { } size) measured.Add(new MeasuredFileSize(item, path, size));
        }

        return measured;
    }

    /// <summary>
    /// Escribe lo medido. Va en el <b>hilo de interfaz</b>: son los mismos
    /// elementos que la tabla está leyendo.
    /// </summary>
    /// <returns>Cuántos quedaron con tamaño nuevo.</returns>
    public static int Apply(IReadOnlyList<MeasuredFileSize> measured)
    {
        int applied = 0;

        foreach ((LibraryItem item, string path, long bytes) in measured)
        {
            // Pudo cambiarle la ruta entre que se midió y ahora: entonces esos
            // bytes son de otro archivo y no valen.
            if (!NeedsSize(item)) continue;
            if (!string.Equals(item.SourcePath, path, StringComparison.Ordinal)) continue;

            item.FileSizeBytes = bytes;
            applied++;
        }

        return applied;
    }

    /// <summary>
    /// Recorre todo lo pendiente por lotes, entregando cada lote medido para que
    /// quien llama lo aplique y guarde el catálogo. <b>Nada de esto toca la
    /// interfaz</b>: se espera que corra en una tarea de fondo y que
    /// <paramref name="onBatch"/> sea el que vuelve al hilo de interfaz.
    /// </summary>
    /// <returns>Cuántos se midieron en total.</returns>
    public static int Run(
        IEnumerable<LibraryItem> items,
        Action<IReadOnlyList<MeasuredFileSize>> onBatch,
        Func<string, long?>? sizeOf = null,
        int batchSize = DefaultBatchSize,
        CancellationToken ct = default)
    {
        IReadOnlyList<LibraryItem> pending = Pending(items);
        if (pending.Count == 0) return 0;

        int size = Math.Max(1, batchSize);
        int total = 0;

        for (int start = 0; start < pending.Count; start += size)
        {
            ct.ThrowIfCancellationRequested();

            IReadOnlyList<MeasuredFileSize> measured =
                MeasureBatch([.. pending.Skip(start).Take(size)], sizeOf, ct);

            if (measured.Count == 0) continue;

            total += measured.Count;
            onBatch(measured);
        }

        return total;
    }
}
