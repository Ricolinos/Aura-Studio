namespace AuraStudio.Core.Library;

/// <summary>
/// Lo que el usuario tiene escrito en la hoja de "Más información", tal cual:
/// puro texto, sin interpretar. Port de la lógica de <c>MediaInfoView.swift</c>.
///
/// <para>Vive en Core y no en la vista porque acá está lo que <b>decide</b>: qué
/// cuenta como completo, qué se guarda y qué se descarta. La vista solo dibuja
/// campos.</para>
/// </summary>
public sealed record MediaInfoDraft
{
    public string Title { get; init; } = "";
    public string Artist { get; init; } = "";
    public string Album { get; init; } = "";
    public string AlbumArtist { get; init; } = "";
    public string Year { get; init; } = "";
    public string Genre { get; init; } = "";
    public string Composer { get; init; } = "";
    public string TrackNumber { get; init; } = "";
    public string Lyrics { get; init; } = "";
    public int Rating { get; init; }

    // Solo video.
    public string VideoTitle { get; init; } = "";
    public string SeriesName { get; init; } = "";
    public string Season { get; init; } = "";
    public string Episode { get; init; } = "";

    /// <summary>Los campos tal como estaban antes de abrir la hoja.</summary>
    public static MediaInfoDraft From(LibraryItem item)
    {
        TrackMetadata metadata = item.Metadata ?? new TrackMetadata();

        return new MediaInfoDraft
        {
            Title = metadata.Title ?? "",
            Artist = metadata.Artist ?? "",
            Album = metadata.Album ?? "",
            AlbumArtist = metadata.AlbumArtist ?? "",
            Year = metadata.Year ?? "",
            Genre = metadata.Genre ?? "",
            Composer = metadata.Composer ?? "",
            TrackNumber = metadata.TrackNumber?.ToString() ?? "",
            Lyrics = metadata.SyncedLyrics ?? "",
            Rating = metadata.Rating ?? 0,
            VideoTitle = metadata.Title ?? "",
            SeriesName = item.SeriesName ?? "",
            Season = item.Season?.ToString() ?? "",
            Episode = item.Episode?.ToString() ?? ""
        };
    }
}

public static class MediaInfoEdit
{
    /// <summary>
    /// Los tres campos que el iPod necesita para no dejar la canción en
    /// "Desconocido": <b>título, artista y álbum</b>. Sin ellos no se puede
    /// guardar, y la hoja lo dice — no se deshabilita el botón sin explicar.
    ///
    /// <para>Para foto y video no aplica: ahí no hay nada obligatorio.</para>
    /// </summary>
    public static bool IsCompleteForSync(MediaInfoDraft draft, LibraryItemKind kind)
    {
        if (kind != LibraryItemKind.Music) return true;

        return draft.Title.Trim().Length > 0
            && draft.Artist.Trim().Length > 0
            && draft.Album.Trim().Length > 0;
    }

    public static string IncompleteReason => "Título, artista y álbum son obligatorios para sincronizar.";

    /// <summary>
    /// Deja solo dígitos y corta a <paramref name="maxDigits"/>. Se aplica
    /// mientras se escribe: un número de pista con letras no es un error del
    /// usuario que haya que reportarle, es algo que no debió poder escribir.
    /// </summary>
    public static string DigitsOnly(string text, int maxDigits = 3)
    {
        string digits = new([.. text.Where(char.IsAsciiDigit)]);
        return digits.Length <= maxDigits ? digits : digits[..maxDigits];
    }

    /// <summary>
    /// La metadata resultante. <b>Un campo vacío se guarda como ausente</b>, no
    /// como cadena vacía: "" y "no sé" son cosas distintas, y una cadena vacía
    /// se vería como un artista llamado "" en el iPod.
    ///
    /// <para>La carátula y los identificadores de MusicBrainz se conservan del
    /// original: la hoja no los edita y no puede borrarlos por omisión.</para>
    /// </summary>
    public static TrackMetadata ToMetadata(MediaInfoDraft draft, TrackMetadata? existing)
    {
        TrackMetadata metadata = existing ?? new TrackMetadata();

        metadata.Title = Trimmed(draft.Title);
        metadata.Artist = Trimmed(draft.Artist);
        metadata.Album = Trimmed(draft.Album);
        metadata.AlbumArtist = Trimmed(draft.AlbumArtist);
        metadata.TrackNumber = int.TryParse(draft.TrackNumber, out int track) ? track : null;
        metadata.Year = Trimmed(draft.Year);
        metadata.Genre = Trimmed(draft.Genre);
        metadata.Composer = Trimmed(draft.Composer);

        // La letra se guarda **sin recortar**: los espacios y saltos de un LRC
        // son parte del formato. Lo que se comprueba recortado es si quedó
        // vacía, para no guardar una letra que son solo espacios.
        metadata.SyncedLyrics = draft.Lyrics.Trim().Length == 0 ? null : draft.Lyrics;

        // Cero es "sin calificar", no una calificación de cero.
        metadata.Rating = draft.Rating == 0 ? null : draft.Rating;

        return metadata;
    }

    /// <summary>Lo que se guarda de un video: título, y serie solo si es una serie.</summary>
    public static (string? Title, string? SeriesName, int? Season, int? Episode) ToVideoInfo(
        MediaInfoDraft draft, bool isSeries)
    {
        string? title = Trimmed(draft.VideoTitle);

        if (!isSeries) return (title, null, null, null);

        return (
            title,
            Trimmed(draft.SeriesName),
            int.TryParse(draft.Season, out int season) ? season : null,
            int.TryParse(draft.Episode, out int episode) ? episode : null);
    }

    /// <summary>
    /// La estrella que se toca. Volver a tocar la que ya estaba activa borra la
    /// calificación — el mismo gesto que Música.app.
    /// </summary>
    public static int RatingAfterTapping(int current, int star) => current == star ? 0 : star;

    private static string? Trimmed(string value)
    {
        string trimmed = value.Trim();
        return trimmed.Length == 0 ? null : trimmed;
    }
}
