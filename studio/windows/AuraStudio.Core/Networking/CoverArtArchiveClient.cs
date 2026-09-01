using System.Net.Http;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace AuraStudio.Core.Networking;

/// <summary>
/// Cliente de Cover Art Archive (coverartarchive.org), sin API key.
/// Complementa a MusicBrainzClient: una vez que se sabe el release id de
/// MusicBrainz, esto trae la imagen de tapa real. Port de
/// CoverArtArchiveClient.swift.
/// </summary>
public sealed class CoverArtArchiveClient
{
    private sealed class ImageEntry
    {
        [JsonPropertyName("image")] public string Image { get; init; } = "";
        [JsonPropertyName("front")] public bool Front { get; init; }
        [JsonPropertyName("thumbnails")] public Thumbnails? Thumbnails { get; init; }
    }

    private sealed class Thumbnails
    {
        [JsonPropertyName("large")] public string? Large { get; init; }
        [JsonPropertyName("small")] public string? Small { get; init; }
    }

    private sealed class CoverArtResponse
    {
        [JsonPropertyName("images")] public List<ImageEntry> Images { get; init; } = new();
    }

    private readonly HttpClient _http;
    private readonly string _baseURL;

    public CoverArtArchiveClient(HttpClient? http = null, string baseURL = "https://coverartarchive.org")
    {
        _http = http ?? new HttpClient();
        _baseURL = baseURL;
    }

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    /// <summary>
    /// Devuelve los bytes de la tapa (preferentemente el thumbnail
    /// "large", que alcanza de sobra para el LCD de 320x240 del iPod y
    /// pesa mucho menos que la imagen original) para el release dado,
    /// o nil si ese release no tiene tapa registrada.
    /// </summary>
    public async Task<byte[]?> FetchFrontCoverAsync(string releaseID, CancellationToken ct = default) =>
        (await FetchCoverAsync(releaseID, ct).ConfigureAwait(false)).Data;

    /// <summary>
    /// Lo mismo, pero diciendo además <b>si la imagen venía marcada como
    /// frontal</b>. Importa para recomendar (R2-3,
    /// <c>docs/caratula-recomendada.md</c>): cuando ninguna imagen del release
    /// está marcada `front`, se cae a la primera que haya, y esa puede ser la
    /// contratapa o la cara del disco. Sirve como último recurso; no como
    /// recomendación.
    /// </summary>
    public async Task<(byte[]? Data, bool IsFront)> FetchCoverAsync(
        string releaseID, CancellationToken ct = default)
    {
        using var request = new HttpRequestMessage(
            HttpMethod.Get, $"{_baseURL}/release/{Uri.EscapeDataString(releaseID)}");
        request.Headers.TryAddWithoutValidation("User-Agent", HttpUserAgent.Value);

        using var response = await _http.SendAsync(request, ct).ConfigureAwait(false);
        if ((int)response.StatusCode == 404) return (null, false);
        HttpResponseGuard.EnsureSuccess(response);

        var json = await response.Content.ReadAsStringAsync(ct).ConfigureAwait(false);
        var decoded = JsonSerializer.Deserialize<CoverArtResponse>(json, JsonOptions);
        var front = decoded?.Images.FirstOrDefault(i => i.Front) ?? decoded?.Images.FirstOrDefault();
        if (front == null) return (null, false);

        // La API a veces devuelve URLs "http://" (nunca "https://") para
        // los thumbnails — App Transport Security las bloquea por default
        // en la app real (a diferencia de `swift test`/`curl`, que no
        // aplican ATS), así que se fuerza https antes de pedirla. El
        // propio servidor sirve el mismo contenido por ambos, así que no
        // hace falta ningún cambio de configuración en Info.plist.
        var imageURLString = (front.Thumbnails?.Large ?? front.Image).Replace("http://", "https://");
        if (string.IsNullOrEmpty(imageURLString)) return (null, false);

        using var imageRequest = new HttpRequestMessage(HttpMethod.Get, imageURLString);
        imageRequest.Headers.TryAddWithoutValidation("User-Agent", HttpUserAgent.Value);
        using var imageResponse = await _http.SendAsync(imageRequest, ct).ConfigureAwait(false);
        HttpResponseGuard.EnsureSuccess(imageResponse);
        return (await imageResponse.Content.ReadAsByteArrayAsync(ct).ConfigureAwait(false), front.Front);
    }
}
