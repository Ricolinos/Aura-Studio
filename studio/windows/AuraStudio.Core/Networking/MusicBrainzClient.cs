using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace AuraStudio.Core.Networking;

/// <summary>
/// Cliente de la API pública de MusicBrainz
/// (musicbrainz.org/doc/MusicBrainz_API), sin API key — solo requiere un
/// User-Agent descriptivo por su política de uso, que es lo único
/// "especial" que hace falta configurar acá. Se usa para resolver
/// título/artista/álbum/año/género a partir de lo poco que ya tenga el
/// archivo (tags existentes o el nombre del archivo), buscando la
/// grabación más parecida. Port de MusicBrainzClient.swift.
/// </summary>
public sealed class MusicBrainzClient
{
    public const string BaseURL = "https://musicbrainz.org/ws/2";

    public sealed class Recording
    {
        [JsonPropertyName("id")] public string Id { get; init; } = "";
        [JsonPropertyName("title")] public string Title { get; init; } = "";
        [JsonPropertyName("score")] public int? Score { get; init; }
        [JsonPropertyName("artist-credit")] public List<ArtistCredit>? ArtistCredit { get; init; }
        [JsonPropertyName("releases")] public List<Release>? Releases { get; init; }
    }

    public sealed class ArtistCredit
    {
        [JsonPropertyName("name")] public string Name { get; init; } = "";
    }

    public sealed class Release
    {
        [JsonPropertyName("id")] public string Id { get; init; } = "";
        [JsonPropertyName("title")] public string Title { get; init; } = "";
        [JsonPropertyName("date")] public string? Date { get; init; }
        [JsonPropertyName("release-group")] public ReleaseGroup? ReleaseGroup { get; init; }

        // Lo que hace falta para recomendar una tapa (R2-3,
        // `docs/caratula-recomendada.md`). La búsqueda de MusicBrainz ya los
        // devuelve; antes se descartaban al deserializar.
        [JsonPropertyName("status")] public string? Status { get; init; }
        [JsonPropertyName("country")] public string? Country { get; init; }
        [JsonPropertyName("track-count")] public int? TrackCount { get; init; }
    }

    public sealed class ReleaseGroup
    {
        [JsonPropertyName("id")] public string Id { get; init; } = "";
    }

    public sealed class Artist
    {
        [JsonPropertyName("id")] public string Id { get; init; } = "";
        [JsonPropertyName("name")] public string Name { get; init; } = "";
        [JsonPropertyName("score")] public int? Score { get; init; }
    }

    private sealed class SearchResponse
    {
        [JsonPropertyName("recordings")] public List<Recording> Recordings { get; init; } = new();
    }

    private sealed class ArtistSearchResponse
    {
        [JsonPropertyName("artists")] public List<Artist> Artists { get; init; } = new();
    }

    private readonly HttpClient _http;
    private readonly string _baseURL;
    private readonly MusicBrainzRateLimiter _rateLimiter;

    /// <param name="retryDelays">
    /// Cuánto esperar entre reintentos. Se inyecta <b>solo para las pruebas</b>:
    /// esperar de verdad los 17 s del backoff por cada caso de saturación
    /// convertía un suite de 5 s en uno de 52 s, y un suite lento se deja de
    /// correr.
    /// </param>
    public MusicBrainzClient(
        HttpClient? http = null,
        string baseURL = BaseURL,
        MusicBrainzRateLimiter? rateLimiter = null,
        IReadOnlyList<TimeSpan>? retryDelays = null)
    {
        _http = http ?? new HttpClient();
        _baseURL = baseURL;
        _rateLimiter = rateLimiter ?? MusicBrainzRateLimiter.Shared;
        _retryDelays = retryDelays ?? DefaultRetryDelays;
    }

    /// <summary>
    /// 2 s, 5 s y 10 s: paciente de verdad, no tres intentos seguidos que
    /// fallan igual. Con tope, porque el usuario está esperando.
    /// </summary>
    public static readonly IReadOnlyList<TimeSpan> DefaultRetryDelays =
        [TimeSpan.FromSeconds(2), TimeSpan.FromSeconds(5), TimeSpan.FromSeconds(10)];

    /// <summary>Para las pruebas: reintenta sin esperar.</summary>
    public static readonly IReadOnlyList<TimeSpan> NoRetryDelays =
        [TimeSpan.Zero, TimeSpan.Zero, TimeSpan.Zero];

    private readonly IReadOnlyList<TimeSpan> _retryDelays;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    /// <summary>
    /// Busca la grabación más parecida a <paramref name="title"/>/
    /// <paramref name="artist"/> (si se conoce alguno; ambos son opcionales
    /// porque puede ser lo único que se pudo sacar del nombre del archivo).
    /// Devuelve el resultado con mayor <c>score</c>, o <c>null</c> si no
    /// hubo ningún match razonable.
    /// </summary>
    public async Task<Recording?> SearchRecordingAsync(string? title, string? artist,
        CancellationToken ct = default)
    {
        if (string.IsNullOrEmpty(title) && string.IsNullOrEmpty(artist)) return null;

        var query = BuildQuery(title, artist);
        var url = $"{_baseURL}/recording?query={Uri.EscapeDataString(query)}&fmt=json&limit=5";

        var data = await PerformThrottledAsync(url, ct).ConfigureAwait(false);
        var decoded = JsonSerializer.Deserialize<SearchResponse>(data, JsonOptions);
        if (decoded == null) return null;
        return decoded.Recordings.OrderByDescending(r => r.Score ?? 0).FirstOrDefault();
    }

    /// <summary>
    /// ST-032: busca el artista por nombre. Devuelve el de mayor
    /// <c>score</c> si supera <paramref name="minimumScore"/> (MusicBrainz
    /// puntúa 100 la coincidencia exacta; por debajo de ~85 suelen ser
    /// homónimos parciales — mejor sin foto que con la de otro).
    /// </summary>
    public async Task<Artist?> SearchArtistAsync(string name, int minimumScore = 85,
        CancellationToken ct = default)
    {
        var trimmed = name.Trim();
        if (trimmed.Length == 0) return null;

        var query = $"artist:\"{EscapeLuceneQuoted(trimmed)}\"";
        var url = $"{_baseURL}/artist?query={Uri.EscapeDataString(query)}&fmt=json&limit=5";

        var data = await PerformThrottledAsync(url, ct).ConfigureAwait(false);
        var decoded = JsonSerializer.Deserialize<ArtistSearchResponse>(data, JsonOptions);
        if (decoded == null) return null;
        var best = decoded.Artists.OrderByDescending(a => a.Score ?? 0).FirstOrDefault();
        if (best == null || (best.Score ?? 0) < minimumScore) return null;
        return best;
    }

    /// <summary>
    /// ST-104: varias EDICIONES del mismo álbum. Es lo que da la variedad real
    /// de tapas: dos ediciones de un disco suelen tener arte distinto, y <b>las
    /// dos son correctas</b>.
    ///
    /// <para>Distinto de <see cref="SearchRecordingAsync"/>, que busca UNA
    /// grabación y se queda con la mejor: acá no hay una respuesta correcta que
    /// elegir sola.</para>
    /// </summary>
    public async Task<IReadOnlyList<Release>> SearchReleasesAsync(
        string album, string? artist, int limit = 5, CancellationToken ct = default)
    {
        var title = (album ?? "").Trim();
        if (title.Length == 0) return [];

        var query = $"release:\"{EscapeLuceneQuoted(title)}\"";
        if (artist is { Length: > 0 } name && name.Trim().Length > 0)
            query += $" AND artist:\"{EscapeLuceneQuoted(name.Trim())}\"";

        var url = $"{_baseURL}/release?query={Uri.EscapeDataString(query)}&fmt=json&limit={limit}";

        var data = await PerformThrottledAsync(url, ct).ConfigureAwait(false);
        var decoded = JsonSerializer.Deserialize<ReleaseSearchResponse>(data, JsonOptions);

        return decoded?.Releases ?? [];
    }

    private sealed class ReleaseSearchResponse
    {
        [JsonPropertyName("releases")] public List<Release> Releases { get; init; } = new();
    }

    /// <summary>
    /// D-203: arma la query de búsqueda Lucene. <c>title</c>/<c>artist</c>
    /// van entre comillas para buscar la frase exacta — si traen una
    /// comilla o una barra invertida sin escapar (títulos reales como
    /// <c>Rock "N" Roll</c> o <c>Y\N</c>), rompen la sintaxis y MusicBrainz
    /// devuelve 400. No hace falta escapar el resto de los caracteres
    /// especiales de Lucene: dentro de una frase se toman literales, solo
    /// la comilla y la barra invertida rompen la frase en sí.
    /// </summary>
    public static string BuildQuery(string? title, string? artist)
    {
        var query = "";
        if (!string.IsNullOrEmpty(title))
            query += $"recording:\"{EscapeLuceneQuoted(title!)}\"";
        if (!string.IsNullOrEmpty(artist))
        {
            if (query.Length > 0) query += " AND ";
            query += $"artist:\"{EscapeLuceneQuoted(artist!)}\"";
        }
        return query;
    }

    private static string EscapeLuceneQuoted(string value) =>
        value.Replace("\\", "\\\\").Replace("\"", "\\\"");

    /// <summary>
    /// MusicBrainz aplica 1 request/segundo por IP y, además, devuelve 503
    /// transitorios incluso cuando estás dentro del límite. Sin esto, una
    /// biblioteca grande se enriquece a toda velocidad, se come throttling
    /// y pierde metadata en silencio. Sólo se reintenta lo transitorio
    /// (503/429); un 404 o 400 no mejoran esperando.
    /// </summary>
    private async Task<byte[]> PerformThrottledAsync(string url, CancellationToken ct,
        int maxAttempts = 4)
    {
        var lastStatus = 0;

        for (var attempt = 1; attempt <= maxAttempts; attempt++)
        {
            await _rateLimiter.WaitForTurnAsync().ConfigureAwait(false);

            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.TryAddWithoutValidation("User-Agent", HttpUserAgent.Value);
            using var response = await _http.SendAsync(request, ct).ConfigureAwait(false);
            var status = (int)response.StatusCode;

            if (status is >= 200 and < 300)
                return await response.Content.ReadAsByteArrayAsync(ct).ConfigureAwait(false);

            lastStatus = status;

            // Solo se reintenta lo transitorio.
            if (status != 503 && status != 429) break;
            if (attempt >= maxAttempts) break;

            await Task.Delay(RetryDelay(response, attempt), ct).ConfigureAwait(false);
        }

        throw EnrichmentError.Http(lastStatus);
    }

    /// <summary>
    /// Cuánto esperar antes de reintentar. <b>Si el servidor dice cuánto, se le
    /// hace caso</b>: insistir antes de tiempo es justo lo que mantiene saturado
    /// a un servidor saturado.
    ///
    /// <para>Sin ese dato, la espera crece 2 s, 5 s, 10 s: paciente de verdad,
    /// no tres intentos seguidos que fallan igual. Con tope, porque el usuario
    /// está esperando.</para>
    /// </summary>
    private TimeSpan RetryDelay(HttpResponseMessage response, int attempt)
    {
        if (response.Headers.RetryAfter?.Delta is { } delta && delta > TimeSpan.Zero)
            return delta > MaxRetryDelay ? MaxRetryDelay : delta;

        return _retryDelays[Math.Min(attempt - 1, _retryDelays.Count - 1)];
    }

    private static readonly TimeSpan MaxRetryDelay = TimeSpan.FromSeconds(15);

    /// <summary>
    /// Si el error es "el servidor está saturado" y no "esto no existe". Lo
    /// mira quien procesa un lote: con saturación tiene sentido seguir con el
    /// siguiente y avisar al final; con un 400 no.
    /// </summary>
    public static bool IsSaturation(Exception exception) =>
        exception is EnrichmentError { StatusCode: 503 or 429 };
}
