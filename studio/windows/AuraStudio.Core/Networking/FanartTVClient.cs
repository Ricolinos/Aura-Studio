using System.Net;
using System.Net.Http;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace AuraStudio.Core.Networking;

/// <summary>
/// Cliente de fanart.tv (D-203): carátulas y arte de disco en alta
/// resolución, fuente OPCIONAL con API key propia. Sin key configurada
/// no tiene sentido intentar la llamada (fanart.tv siempre devuelve 401):
/// se devuelve null de una, mismo criterio de "mejor esfuerzo" que ya usan
/// los demás clientes.
/// </summary>
public sealed class FanartTVClient
{
    private sealed class AlbumsResponse
    {
        [JsonPropertyName("albums")] public Dictionary<string, AlbumImages>? Albums { get; init; }
    }

    private sealed class AlbumImages
    {
        [JsonPropertyName("albumcover")] public List<Image>? AlbumCover { get; init; }
    }

    private sealed class Image
    {
        [JsonPropertyName("url")] public string Url { get; init; } = "";
    }

    private sealed class ArtistResponse
    {
        [JsonPropertyName("artistthumb")] public List<Image>? ArtistThumb { get; init; }
        [JsonPropertyName("artistbackground")] public List<Image>? ArtistBackground { get; init; }
    }

    private sealed class MovieResponse
    {
        [JsonPropertyName("movieposter")] public List<Image>? MoviePoster { get; init; }
    }

    private sealed class TVResponse
    {
        [JsonPropertyName("tvposter")] public List<Image>? TvPoster { get; init; }
    }

    private readonly HttpClient _http;
    private readonly string _rootURL;
    private readonly IApiKeyStore _apiKeyStore;

    public FanartTVClient(
        HttpClient? http = null,
        IApiKeyStore? apiKeyStore = null,
        string rootURL = "https://webservice.fanart.tv/v3")
    {
        _http = http ?? new HttpClient();
        _rootURL = rootURL;
        _apiKeyStore = apiKeyStore ?? new SimpleApiKeyStore();
    }

    /// <summary>GET autenticado; 404 = "fanart.tv no lo tiene" (null, no error).</summary>
    private async Task<T?> FetchJSONAsync<T>(string path, CancellationToken ct = default) where T : class
    {
        var apiKey = _apiKeyStore.Load("fanarttv");
        if (apiKey == null) return null;

        var url = $"{_rootURL}/{path}?api_key={Uri.EscapeDataString(apiKey)}";
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.TryAddWithoutValidation("User-Agent", HttpUserAgent.Value);

        using var response = await _http.SendAsync(request, ct).ConfigureAwait(false);
        if (response.StatusCode == HttpStatusCode.NotFound) return null;
        HttpResponseGuard.EnsureSuccess(response);

        var json = await response.Content.ReadAsStringAsync(ct).ConfigureAwait(false);
        return JsonSerializer.Deserialize<T>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
    }

    /// <summary>Descarga la imagen desde la URL dada.</summary>
    private async Task<byte[]?> DownloadAsync(string? urlString, CancellationToken ct = default)
    {
        if (string.IsNullOrEmpty(urlString)) return null;
        using var request = new HttpRequestMessage(HttpMethod.Get, urlString);
        using var response = await _http.SendAsync(request, ct).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadAsByteArrayAsync(ct).ConfigureAwait(false);
    }

    /// <summary>ST-032: foto de artista (artistthumb, cuadrada, ~1000 px) por MusicBrainz artist ID.</summary>
    public async Task<byte[]?> FetchArtistThumbAsync(string musicBrainzArtistID, CancellationToken ct = default)
    {
        var decoded = await FetchJSONAsync<ArtistResponse>($"music/{musicBrainzArtistID}", ct).ConfigureAwait(false);
        return await DownloadAsync(decoded?.ArtistThumb?.FirstOrDefault()?.Url, ct).ConfigureAwait(false);
    }

    /// <summary>ST-033: póster de película. fanart.tv acepta TMDB ID o IMDb ID en la misma ruta.</summary>
    public async Task<byte[]?> FetchMoviePosterAsync(string tmdbOrIMDbID, CancellationToken ct = default)
    {
        var decoded = await FetchJSONAsync<MovieResponse>($"movies/{tmdbOrIMDbID}", ct).ConfigureAwait(false);
        return await DownloadAsync(decoded?.MoviePoster?.FirstOrDefault()?.Url, ct).ConfigureAwait(false);
    }

    /// <summary>ST-033: póster de serie, por ID de TheTVDB.</summary>
    public async Task<byte[]?> FetchTVPosterAsync(string tvdbID, CancellationToken ct = default)
    {
        var decoded = await FetchJSONAsync<TVResponse>($"tv/{tvdbID}", ct).ConfigureAwait(false);
        return await DownloadAsync(decoded?.TvPoster?.FirstOrDefault()?.Url, ct).ConfigureAwait(false);
    }

    /// <summary>Cover de álbum por MusicBrainz release-group ID.</summary>
    public async Task<byte[]?> FetchAlbumCoverAsync(string releaseGroupID, CancellationToken ct = default)
    {
        var apiKey = _apiKeyStore.Load("fanarttv");
        if (apiKey == null) return null;

        var url = $"https://webservice.fanart.tv/v3/music/albums/{releaseGroupID}?api_key={Uri.EscapeDataString(apiKey)}";
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.TryAddWithoutValidation("User-Agent", HttpUserAgent.Value);

        using var response = await _http.SendAsync(request, ct).ConfigureAwait(false);
        if (response.StatusCode == HttpStatusCode.NotFound) return null;
        HttpResponseGuard.EnsureSuccess(response);

        var json = await response.Content.ReadAsStringAsync(ct).ConfigureAwait(false);
        var decoded = JsonSerializer.Deserialize<AlbumsResponse>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        var urlString = decoded?.Albums?.GetValueOrDefault(releaseGroupID)?.AlbumCover?.FirstOrDefault()?.Url;
        return await DownloadAsync(urlString, ct).ConfigureAwait(false);
    }

    private sealed class SimpleApiKeyStore : IApiKeyStore
    {
        public string? Load(string service) => null;
    }
}