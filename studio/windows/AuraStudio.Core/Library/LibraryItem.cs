namespace AuraStudio.Core.Library;

/// <summary>Qué es este archivo dentro de la biblioteca.</summary>
public enum LibraryItemKind
{
    Music,
    Video,
    Photo,
    Unsupported
}

/// <summary>En qué punto de su camino hacia el iPod está el archivo.</summary>
public enum LibraryItemState
{
    Queued,
    Enriching,
    Transcoding,
    Ready,

    /// <summary>Falta algo que solo el usuario puede decidir.</summary>
    NeedsReview,

    Failed
}

/// <param name="State">El estado.</param>
/// <param name="Progress">Solo para <see cref="LibraryItemState.Transcoding"/>: 0–1.</param>
/// <param name="Error">Solo para <see cref="LibraryItemState.Failed"/>.</param>
public readonly record struct LibraryItemStatus(LibraryItemState State, double Progress = 0, string? Error = null)
{
    public static LibraryItemStatus Queued { get; } = new(LibraryItemState.Queued);
    public static LibraryItemStatus Enriching { get; } = new(LibraryItemState.Enriching);
    public static LibraryItemStatus Ready { get; } = new(LibraryItemState.Ready);
    public static LibraryItemStatus NeedsReview { get; } = new(LibraryItemState.NeedsReview);

    public static LibraryItemStatus Transcoding(double progress) =>
        new(LibraryItemState.Transcoding, Math.Clamp(progress, 0, 1));

    public static LibraryItemStatus Failed(string error) =>
        new(LibraryItemState.Failed, 0, error);
}

/// <summary>
/// Un archivo que el usuario soltó en Aura Studio, en algún punto de su camino
/// hacia el iPod: música nativa que solo necesita metadata, video que hay que
/// transcodificar, o una foto que hay que redimensionar. Port de
/// `LibraryItem.swift`.
///
/// <see cref="SourcePath"/> es el archivo original del usuario;
/// <see cref="PreparedPath"/> es el resultado listo para copiar al dispositivo
/// (el mismo archivo para música nativa, o la salida del transcodificado o del
/// redimensionado).
/// </summary>
public sealed class LibraryItem
{
    /// <summary>
    /// Estable entre sesiones: las playlists referencian por id, así que
    /// restaurar el catálogo tiene que conservarlo o se rompen.
    /// </summary>
    public Guid Id { get; init; } = Guid.NewGuid();

    /// <summary>
    /// Mutable a propósito (D-228): con "copiar medios a la biblioteca" activo,
    /// el archivo se copia al procesarlo —cuando ya se conocen artista, álbum y
    /// categoría—, no al soltarlo, y esto pasa a apuntar a esa copia.
    /// </summary>
    public string SourcePath { get; set; } = "";

    public LibraryItemKind Kind { get; init; }

    public LibraryItemStatus Status { get; set; } = LibraryItemStatus.Queued;

    public TrackMetadata? Metadata { get; set; }

    public string? PreparedPath { get; set; }

    /// <summary>
    /// Solo para foto y video. Para video es uno de los nombres fijos de
    /// <see cref="MediaCategory"/>; para foto, un nombre libre de las
    /// colecciones del usuario (D-228: antes ambos compartían el enum, ahora
    /// solo el video lo usa puertas adentro). Se sugiere sola al procesar y el
    /// usuario la puede corregir.
    /// </summary>
    public string? Category { get; set; }

    /// <summary>
    /// Solo para video en la categoría Series: determinan el nombre de destino
    /// en el iPod (`SxxEyy`, que el firmware agrupa) y el póster de temporada.
    /// `null` para todo lo que no sea un episodio.
    /// </summary>
    public string? SeriesName { get; set; }

    public int? Season { get; set; }
    public int? Episode { get; set; }

    /// <summary>
    /// Solo para foto: álbum **local** dentro de Aura Studio. Nunca viaja al
    /// iPod — `/Photos` sigue plano (D-192).
    /// </summary>
    public string? PhotoAlbum { get; set; }

    /// <summary>
    /// `true` la primera vez que el usuario corrige metadata a mano. **Nunca**
    /// lo pone el enriquecimiento ni la lectura de etiquetas, que solo llenan
    /// huecos: protege esas correcciones de una relectura masiva. La acción
    /// explícita del menú contextual, en cambio, siempre pisa.
    /// </summary>
    public bool MetadataEditedByUser { get; set; }

    /// <summary>Cuándo se agregó. `null` solo en items de un catálogo anterior a este campo.</summary>
    public DateTimeOffset? AddedAt { get; set; }

    /// <summary>
    /// El título de la etiqueta si ya se leyó; si no, el nombre del archivo
    /// <b>sin extensión</b>, igual que macOS (<c>LibraryGrouping.displayTitle</c>).
    /// El lector de etiquetas nunca deja un título vacío —guarda <c>null</c>—,
    /// así que tratar el vacío como ausente coincide con macOS y además evita
    /// una fila en blanco si el usuario borra el título a mano.
    /// </summary>
    public string DisplayTitle => string.IsNullOrEmpty(Metadata?.Title)
        ? Path.GetFileNameWithoutExtension(SourcePath)
        : Metadata!.Title!;

    public LibraryItem() { }

    /// <summary>Un archivo recién soltado: su tipo sale de la extensión.</summary>
    public static LibraryItem FromDroppedFile(string path, DateTimeOffset? addedAt = null) => new()
    {
        SourcePath = path,
        Kind = ClassifyKind(path),
        Status = LibraryItemStatus.Queued,
        AddedAt = addedAt ?? DateTimeOffset.Now
    };

    /// <summary>
    /// Misma clasificación por extensión que macOS, apoyada en las listas de
    /// <see cref="CoverArtAssets"/> para que importar y decidir "esto es
    /// carátula" nunca discrepen sobre qué es audio, video o imagen.
    /// </summary>
    public static LibraryItemKind ClassifyKind(string path)
    {
        if (CoverArtAssets.IsAudio(path)) return LibraryItemKind.Music;
        if (CoverArtAssets.IsVideo(path)) return LibraryItemKind.Video;
        if (CoverArtAssets.IsImage(path)) return LibraryItemKind.Photo;
        return LibraryItemKind.Unsupported;
    }
}
