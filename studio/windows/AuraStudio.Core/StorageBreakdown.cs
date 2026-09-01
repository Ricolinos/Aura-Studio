namespace AuraStudio.Core;

/// <summary>Un tramo de la barra de capacidad: cuánto ocupa y cómo se llama.</summary>
public readonly record struct StorageSegment(string Label, long Bytes);

/// <summary>
/// En qué se va el espacio del iPod (R3-3). Es el <b>ancla</b> de la ficha de
/// General: una barra segmentada dice de un vistazo lo que cuatro filas de
/// números obligan a leer y restar.
///
/// <para>Los tamaños NO salen de recorrer el disco: salen del
/// <c>sync_summary.cfg</c> que dejó el último sync — el mismo archivo que lee
/// el firmware para su pantalla "Acerca de". Si nunca se sincronizó, no hay
/// desglose y la barra muestra solo lo usado contra lo libre, que es la verdad
/// disponible.</para>
///
/// <para>Vive en Core y no en la pantalla porque es aritmética con reglas —qué
/// entra en "Otro", qué pasa si los números no cierran— y eso se prueba; el
/// color y la forma son de la vista.</para>
/// </summary>
public static class StorageBreakdown
{
    public const string Music = "Música";
    public const string Video = "Video";
    public const string Photos = "Fotos";
    public const string Other = "Otro";
    public const string Free = "Libre";

    /// <summary>
    /// Los cinco tramos, siempre en el mismo orden y siempre los cinco —
    /// los de cero los descarta quien dibuja, no este cálculo.
    ///
    /// <para>"Otro" es lo usado que no es biblioteca: el firmware, sus fuentes,
    /// los temas, lo que el usuario haya copiado a mano. <b>Nunca es
    /// negativo</b>: si el resumen del último sync quedó viejo y suma más que
    /// lo usado, el sobrante se recorta a cero en vez de dibujar una barra
    /// imposible.</para>
    /// </summary>
    public static IReadOnlyList<StorageSegment> Segments(IPodDiskInfo device)
    {
        CatalogSummary? summary = device.LibrarySummary;

        long music = summary?.Music.Bytes ?? 0;
        long video = summary?.Video.Bytes ?? 0;
        long photo = summary?.Photo.Bytes ?? 0;
        long other = Math.Max(device.UsedBytes - music - video - photo, 0);
        long free = Math.Max(device.SizeBytes - device.UsedBytes, 0);

        return
        [
            new StorageSegment(Music, music),
            new StorageSegment(Video, video),
            new StorageSegment(Photos, photo),
            new StorageSegment(Other, other),
            new StorageSegment(Free, free)
        ];
    }

    /// <summary>
    /// Lo que se dibuja como leyenda: los tramos con contenido, <b>sin
    /// "Libre"</b> — es el resto implícito de la barra y ponerle su propia
    /// entrada solo agrega ruido. Mismo criterio que la barra del firmware
    /// (D-282).
    /// </summary>
    public static IReadOnlyList<StorageSegment> Legend(IPodDiskInfo device) =>
        [.. Segments(device).Where(segment => segment.Bytes > 0 && segment.Label != Free)];

    /// <summary>
    /// Qué fracción del ancho le toca a un tramo, entre 0 y 1. Con capacidad
    /// desconocida devuelve 0: una barra vacía dice "no sé" mejor que una
    /// barra llena de un solo color.
    /// </summary>
    public static double Fraction(StorageSegment segment, IPodDiskInfo device) =>
        device.SizeBytes <= 0 ? 0 : Math.Clamp((double)segment.Bytes / device.SizeBytes, 0, 1);

    /// <summary>"12.3 GB usados de 125.0 GB — 112.7 GB libres".</summary>
    public static string UsageLine(IPodDiskInfo device) =>
        $"{device.UsedDisplay} usados de {device.CapacityDisplay} — {device.FreeDisplay} libres";
}
