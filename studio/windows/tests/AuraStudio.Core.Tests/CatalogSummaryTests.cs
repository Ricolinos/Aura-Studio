using AuraStudio.Core;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Port de CatalogSummaryWriterTests.swift -- verifica que el formato plano
/// `key: value` se serializa y parsea correctamente, manteniendo compatibilidad
/// con el firmware que lee sync_summary.cfg.
/// </summary>
public class CatalogSummaryTests
{
    // ── Serialización ──────────────────────────────────────────────

    /// Equivalente Swift: testSerializesAllFieldsAsFlatKeyValue
    [Fact]
    public void SerializesAllFieldsAsFlatKeyValue()
    {
        var summary = new CatalogSummary
        {
            Music = new CatalogTypeSummary { Count = 120, Bytes = 489_234_931 },
            Video = new CatalogTypeSummary { Count = 3, Bytes = 1_234_567_890 },
            Photo = new CatalogTypeSummary { Count = 40, Bytes = 85_000_000 },
            PlaylistCount = 2
        };

        var text = CatalogSummaryWriter.Serialize(summary);
        var lines = text.Split('\n');

        Assert.Contains("music_count: 120", lines);
        Assert.Contains("music_bytes: 489234931", lines);
        Assert.Contains("video_count: 3", lines);
        Assert.Contains("video_bytes: 1234567890", lines);
        Assert.Contains("photo_count: 40", lines);
        Assert.Contains("photo_bytes: 85000000", lines);
        Assert.Contains("playlist_count: 2", lines);
    }

    /// Equivalente Swift: testZeroedSummarySerializesCleanly
    [Fact]
    public void ZeroedSummarySerializesCleanly()
    {
        var text = CatalogSummaryWriter.Serialize(new CatalogSummary());

        Assert.Contains("music_count: 0", text);
        Assert.Contains("playlist_count: 0", text);
    }

    // ── Round-trip serialización → parse ───────────────────────────

    /// Verifica que el orden exacto de serialización coincide con lo que
    /// el firmware espera en sync_summary.cfg (mismo orden que Aura).
    [Fact]
    public void SerializeProducesExactLineOrder()
    {
        var summary = new CatalogSummary
        {
            Music = new CatalogTypeSummary { Count = 10, Bytes = 2000 },
            Video = new CatalogTypeSummary { Count = 5, Bytes = 3000 },
            Photo = new CatalogTypeSummary { Count = 3, Bytes = 1000 },
            PlaylistCount = 1,
            VideoMovies = 2,
            VideoSeries = 1,
            VideoClips = 2,
            PhotoImages = 1,
            PhotoPhotos = 1,
            PhotoAI = 1
        };

        var text = CatalogSummaryWriter.Serialize(summary);
        var expected =
            "music_count: 10\n" +
            "music_bytes: 2000\n" +
            "video_count: 5\n" +
            "video_bytes: 3000\n" +
            "photo_count: 3\n" +
            "photo_bytes: 1000\n" +
            "playlist_count: 1\n" +
            "video_movies_count: 2\n" +
            "video_series_count: 1\n" +
            "video_clips_count: 2\n" +
            "photo_images_count: 1\n" +
            "photo_photos_count: 1\n" +
            "photo_ai_count: 1\n";

        Assert.Equal(expected, text);
    }

    /// Round-trip completo: serializar y volver a parsear recupera todos los campos.
    [Fact]
    public void RoundTrip_PreservesAllFields()
    {
        var original = new CatalogSummary
        {
            Music = new CatalogTypeSummary { Count = 120, Bytes = 489_234_931 },
            Video = new CatalogTypeSummary { Count = 3, Bytes = 1_234_567_890 },
            Photo = new CatalogTypeSummary { Count = 40, Bytes = 85_000_000 },
            PlaylistCount = 2,
            VideoMovies = 1,
            VideoSeries = 1,
            VideoClips = 1,
            PhotoImages = 15,
            PhotoPhotos = 20,
            PhotoAI = 5
        };

        var text = CatalogSummaryWriter.Serialize(original);
        var parsed = CatalogSummaryReader.Parse(text);

        Assert.Equal(original, parsed);
    }

    // ── Parse tolerante ────────────────────────────────────────────

    /// Líneas malformadas (sin dos-puntos) se saltan silenciosamente.
    [Fact]
    public void ParseSkipsMalformedLines()
    {
        var input =
            "music_count: 7\n" +
            "esto_no_tiene_dos_puntos\n" +
            "video_count: 3\n";

        var result = CatalogSummaryReader.Parse(input);

        Assert.Equal(7, result.Music.Count);
        Assert.Equal(3, result.Video.Count);
    }

    /// Valores no numéricos se ignoran (mismo comportamiento que Swift Int64(raw) -> nil).
    [Fact]
    public void ParseSkipsNonNumericValues()
    {
        var input =
            "music_count: not_a_number\n" +
            "video_count: 5\n";

        var result = CatalogSummaryReader.Parse(input);

        Assert.Equal(0, result.Music.Count);
        Assert.Equal(5, result.Video.Count);
    }

    /// Claves desconocidas se ignoran sin error.
    [Fact]
    public void ParseSkipsUnknownKeys()
    {
        var input =
            "music_count: 4\n" +
            "unknown_key: 999\n" +
            "video_count: 2\n";

        var result = CatalogSummaryReader.Parse(input);

        Assert.Equal(4, result.Music.Count);
        Assert.Equal(2, result.Video.Count);
    }

    /// Valores vacíos después de `:` se saltan (TryParse falla con cadena vacía).
    [Fact]
    public void ParseSkipsEmptyValues()
    {
        var input =
            "music_count: \n" +
            "video_count: 3\n";

        var result = CatalogSummaryReader.Parse(input);

        Assert.Equal(0, result.Music.Count);
        Assert.Equal(3, result.Video.Count);
    }

    /// Texto completamente vacío produce un CatalogSummary en ceros.
    [Fact]
    public void ParseEmptyText_ReturnsDefaultSummary()
    {
        var result = CatalogSummaryReader.Parse("");

        Assert.Equal(new CatalogSummary(), result);
    }

    // ── Subcategorías ──────────────────────────────────────────────

    /// Verifica que las subcategorías de video/foto (D-283) se serializan
    /// y parsean correctamente.
    [Fact]
    public void Subcategories_SerializeAndParseCorrectly()
    {
        var summary = new CatalogSummary
        {
            VideoMovies = 5,
            VideoSeries = 3,
            VideoClips = 12,
            PhotoImages = 20,
            PhotoPhotos = 15,
            PhotoAI = 8
        };

        var text = CatalogSummaryWriter.Serialize(summary);

        Assert.Contains("video_movies_count: 5", text);
        Assert.Contains("video_series_count: 3", text);
        Assert.Contains("video_clips_count: 12", text);
        Assert.Contains("photo_images_count: 20", text);
        Assert.Contains("photo_photos_count: 15", text);
        Assert.Contains("photo_ai_count: 8", text);

        var parsed = CatalogSummaryReader.Parse(text);
        Assert.Equal(5, parsed.VideoMovies);
        Assert.Equal(3, parsed.VideoSeries);
        Assert.Equal(12, parsed.VideoClips);
        Assert.Equal(20, parsed.PhotoImages);
        Assert.Equal(15, parsed.PhotoPhotos);
        Assert.Equal(8, parsed.PhotoAI);
    }
}
