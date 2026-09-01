using System.Net.Http;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace AuraStudio.Core.Networking;

/// <summary>
/// Cliente de LRCLIB (lrclib.net), sin API key. Devuelve letras
/// sincronizadas en formato .lrc — el mismo formato que aura_lrc.c ya
/// sabe parsear en el firmware (D-019), así que el archivo que este
/// cliente trae se puede escribir tal cual como sidecar junto a la
/// pista, sin ninguna conversión. Port de LRCLIBClient.swift.
/// </summary>
public sealed class LRCLIBClient
{
    private sealed class SearchResult
    {
        [JsonPropertyName("syncedLyrics")] public string? SyncedLyrics { get; init; }
        /// <summary>
        /// ST-012 / contrato SS3: si LRCLIB solo tiene la letra sin marcas
        /// de tiempo, se usa igual — Studio la escribe como .lrc y el
        /// firmware decide qué hacer sin timestamps (hoy la ignora; el día
        /// que muestre letra estática, ya está en el iPod).
        /// </summary>
        [JsonPropertyName("plainLyrics")] public string? PlainLyrics { get; init; }
        [JsonPropertyName("duration")] public double? Duration { get; init; }
    }

    public const string ClientIdentifier = "AuraStudio v0.1.0 (https://github.com/Ricolinos/Aura-Proyect)";

    private readonly HttpClient _http;
    private readonly string _baseURL;

    public LRCLIBClient(HttpClient? http = null, string baseURL = "https://lrclib.net/api")
    {
        _http = http ?? new HttpClient();
        _baseURL = baseURL;
    }

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    /// <summary>
    /// Port de <c>fetchSyncedLyrics(title:artist:album:durationSeconds:)</c>.
    /// <paramref name="durationSeconds"/> es opcional pero mejora mucho la
    /// precisión del match — LRCLIB usa duración +/- 2s como señal fuerte
    /// de que es la versión correcta de la canción. Devuelve nil si no hay
    /// letra (404) o si la que hay está vacía.
    /// </summary>
    public async Task<string?> FetchSyncedLyricsAsync(string title, string artist,
        string? album = null, int? durationSeconds = null, CancellationToken ct = default)
    {
        var items = new List<string>
        {
            $"track_name={Uri.EscapeDataString(title)}",
            $"artist_name={Uri.EscapeDataString(artist)}",
        };
        if (album != null) items.Add($"album_name={Uri.EscapeDataString(album)}");
        if (durationSeconds != null) items.Add($"duration={durationSeconds.Value}");
        var url = $"{_baseURL}/get?{string.Join("&", items)}";

        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.TryAddWithoutValidation("User-Agent", HttpUserAgent.Value);
        // LRCLIB hoy no aplica ningún límite de tasa, pero su propio
        // cliente web se identifica con esta cabecera y su documentación
        // la pide por cortesía: si algún día tienen que limitar, quieren
        // poder distinguir clientes en vez de cortar por IP a ciegas.
        request.Headers.TryAddWithoutValidation("Lrclib-Client", ClientIdentifier);

        using var response = await _http.SendAsync(request, ct).ConfigureAwait(false);
        if ((int)response.StatusCode == 404) return null;
        HttpResponseGuard.EnsureSuccess(response);

        var json = await response.Content.ReadAsStringAsync(ct).ConfigureAwait(false);
        var decoded = JsonSerializer.Deserialize<SearchResult>(json, JsonOptions);
        if (decoded == null) return null;

        if (!string.IsNullOrWhiteSpace(decoded.SyncedLyrics)) return decoded.SyncedLyrics;
        if (!string.IsNullOrWhiteSpace(decoded.PlainLyrics)) return decoded.PlainLyrics;
        return null;
    }
}
