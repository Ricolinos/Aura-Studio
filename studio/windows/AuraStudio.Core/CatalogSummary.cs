namespace AuraStudio.Core;

/// <summary>
/// Contadores y bytes por tipo de contenido tras un sync, para que
/// "Acerca de" en el firmware pueda mostrar cuánto hay realmente en
/// el dispositivo. El firmware no tiene parser de JSON (su único formato
/// de config es el `key: value` plano que ya usa `aura.cfg`), así que
/// `CatalogSummaryWriter` emite ese mismo formato plano.
/// </summary>
public struct CatalogTypeSummary : IEquatable<CatalogTypeSummary>
{
    public int Count;
    public long Bytes;

    public bool Equals(CatalogTypeSummary other) =>
        Count == other.Count && Bytes == other.Bytes;

    public override bool Equals(object? obj) =>
        obj is CatalogTypeSummary other && Equals(other);

    public override int GetHashCode() => HashCode.Combine(Count, Bytes);

    public static bool operator ==(CatalogTypeSummary left, CatalogTypeSummary right) => left.Equals(right);
    public static bool operator !=(CatalogTypeSummary left, CatalogTypeSummary right) => !left.Equals(right);
}

/// <summary>
/// Resumen completo del catálogo en el iPod: conteos y bytes por tipo,
/// más conteos por subcategoría de video/foto que Studio clasificó al
/// importar pero el firmware no puede clasificar por sí solo.
/// </summary>
public struct CatalogSummary : IEquatable<CatalogSummary>
{
    public CatalogTypeSummary Music;
    public CatalogTypeSummary Video;
    public CatalogTypeSummary Photo;
    public int PlaylistCount;

    /// <summary>video_movies, video_series, video_clips: subcategorías de video clasificadas por Studio.</summary>
    public int VideoMovies;
    public int VideoSeries;
    public int VideoClips;

    /// <summary>photo_images, photo_photos, photo_ai: subcategorías de foto clasificadas por Studio.</summary>
    public int PhotoImages;
    public int PhotoPhotos;
    public int PhotoAI;

    public bool Equals(CatalogSummary other) =>
        Music.Equals(other.Music) &&
        Video.Equals(other.Video) &&
        Photo.Equals(other.Photo) &&
        PlaylistCount == other.PlaylistCount &&
        VideoMovies == other.VideoMovies &&
        VideoSeries == other.VideoSeries &&
        VideoClips == other.VideoClips &&
        PhotoImages == other.PhotoImages &&
        PhotoPhotos == other.PhotoPhotos &&
        PhotoAI == other.PhotoAI;

    public override bool Equals(object? obj) =>
        obj is CatalogSummary other && Equals(other);

    public override int GetHashCode() =>
        HashCode.Combine(HashCode.Combine(Music, Video, Photo, PlaylistCount,
            VideoMovies, VideoSeries, VideoClips),
            PhotoImages, PhotoPhotos, PhotoAI);

    public static bool operator ==(CatalogSummary left, CatalogSummary right) => left.Equals(right);
    public static bool operator !=(CatalogSummary left, CatalogSummary right) => !left.Equals(right);
}

/// <summary>
/// Lee de vuelta el mismo archivo que escribe <see cref="CatalogSummaryWriter"/>.
/// Studio lo usa para contar lo que YA hay en el iPod sin recorrer el
/// disco entero: el resumen lo dejó el último sync, y el firmware lo lee
/// igual para su pantalla "Acerca de".
/// </summary>
public static class CatalogSummaryReader
{
    public static CatalogSummary Parse(string text)
    {
        var values = new Dictionary<string, long>();

        foreach (var line in text.Split('\n'))
        {
            var parts = line.Split(':', 2);
            if (parts.Length != 2) continue;

            var key = parts[0].Trim();
            var raw = parts[1].Trim();

            if (!long.TryParse(raw, out var value)) continue;

            values[key] = value;
        }

        return new CatalogSummary
        {
            Music = new CatalogTypeSummary
            {
                Count = (int)(values.TryGetValue("music_count", out var mc) ? mc : 0),
                Bytes = values.TryGetValue("music_bytes", out var mb) ? mb : 0
            },
            Video = new CatalogTypeSummary
            {
                Count = (int)(values.TryGetValue("video_count", out var vc) ? vc : 0),
                Bytes = values.TryGetValue("video_bytes", out var vb) ? vb : 0
            },
            Photo = new CatalogTypeSummary
            {
                Count = (int)(values.TryGetValue("photo_count", out var pc) ? pc : 0),
                Bytes = values.TryGetValue("photo_bytes", out var pb) ? pb : 0
            },
            PlaylistCount = (int)(values.TryGetValue("playlist_count", out var pl) ? pl : 0),
            VideoMovies = (int)(values.TryGetValue("video_movies_count", out var vm) ? vm : 0),
            VideoSeries = (int)(values.TryGetValue("video_series_count", out var vs) ? vs : 0),
            VideoClips = (int)(values.TryGetValue("video_clips_count", out var vcl) ? vcl : 0),
            PhotoImages = (int)(values.TryGetValue("photo_images_count", out var pi) ? pi : 0),
            PhotoPhotos = (int)(values.TryGetValue("photo_photos_count", out var pp) ? pp : 0),
            PhotoAI = (int)(values.TryGetValue("photo_ai_count", out var pa) ? pa : 0)
        };
    }
}

/// <summary>
/// Escribe el formato plano `key: value` que el firmware puede leer
/// sin necesidad de un parser JSON.
/// </summary>
public static class CatalogSummaryWriter
{
    public static string Serialize(CatalogSummary summary) =>
        $"music_count: {summary.Music.Count}\n" +
        $"music_bytes: {summary.Music.Bytes}\n" +
        $"video_count: {summary.Video.Count}\n" +
        $"video_bytes: {summary.Video.Bytes}\n" +
        $"photo_count: {summary.Photo.Count}\n" +
        $"photo_bytes: {summary.Photo.Bytes}\n" +
        $"playlist_count: {summary.PlaylistCount}\n" +
        $"video_movies_count: {summary.VideoMovies}\n" +
        $"video_series_count: {summary.VideoSeries}\n" +
        $"video_clips_count: {summary.VideoClips}\n" +
        $"photo_images_count: {summary.PhotoImages}\n" +
        $"photo_photos_count: {summary.PhotoPhotos}\n" +
        $"photo_ai_count: {summary.PhotoAI}\n";
}
