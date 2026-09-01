namespace AuraStudio.Core.Library;

/// <summary>
/// Metadata de una pista, leída del archivo original o completada en línea
/// (MusicBrainz / Cover Art Archive / LRCLIB). Port de `TrackMetadata.swift`:
/// mismos campos y mismos significados, porque es lo que viaja al
/// `biblioteca.json` y de ahí al iPod.
///
/// <para>Es un tipo mutable a propósito (como el `struct` de Swift): el
/// enriquecimiento va completando campos de a uno.</para>
/// </summary>
public sealed class TrackMetadata
{
    public string? Title { get; set; }
    public string? Artist { get; set; }
    public string? Album { get; set; }
    public string? AlbumArtist { get; set; }
    public string? Year { get; set; }
    public string? Genre { get; set; }

    /// <summary>
    /// Autor/compositor (`TCOM` en ID3, `tag_composer` en el tagcache de
    /// Rockbox). El firmware ya sabe organizar música por "Autores"; este campo
    /// es lo que hace falta para poblarlo.
    /// </summary>
    public string? Composer { get; set; }

    public int? TrackNumber { get; set; }

    /// <summary>Número de disco (`TPOS` / `disk` en MP4), para ordenar cajas de varios discos.</summary>
    public int? DiscNumber { get; set; }

    /// <summary>Carátula embebida tal como venía en el archivo, sin recodificar.</summary>
    public byte[]? CoverArtData { get; set; }

    /// <summary>
    /// Letra en formato LRC. Normalmente con marcas `[mm:ss.xx]`; puede ser
    /// letra plana si solo había esa (ST-012). El nombre se conserva por
    /// compatibilidad con `biblioteca.json`.
    /// </summary>
    public string? SyncedLyrics { get; set; }

    public string? MusicBrainzRecordingId { get; set; }
    public string? MusicBrainzReleaseId { get; set; }

    /// <summary>
    /// Duración real del archivo. Best-effort: si no se pudo medir queda `null`
    /// y la tabla muestra "—" — nunca bloquea el procesamiento.
    /// </summary>
    public double? DurationSeconds { get; set; }

    /// <summary>
    /// Calificación 0–5 estrellas. `null` = sin calificar, que es **distinto**
    /// de 0 (cero estrellas puestas a propósito).
    /// </summary>
    public int? Rating { get; set; }

    /// <summary>
    /// Favorito (ST-030): marca binaria independiente de <see cref="Rating"/>.
    /// Vive solo en el catálogo de Studio — no hay frame ID3 estándar para esto.
    /// </summary>
    public bool IsFavorite { get; set; }

    /// <summary>Lo mínimo para no tener que preguntar nada: título, artista y álbum.</summary>
    public bool IsComplete => Title is not null && Artist is not null && Album is not null;
}
