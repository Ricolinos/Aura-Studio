using System.Globalization;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace AuraStudio.Core.Networking;

/// <summary>
/// Cliente de Deezer (D-203): carátula alternativa de álbum, 1000x1000.
/// Sin API key ni registro — es la única fuente opcional cuyos términos
/// permiten explícitamente el uso no comercial de este tipo de app (ver
/// <c>ServicesSettingsView</c>). Una sola portada por álbum, la del primer
/// resultado de búsqueda. Port de DeezerClient.swift.
/// </summary>
public sealed class DeezerClient
{
    private sealed class SearchResponse
    {
        [JsonPropertyName("data")] public List<Track> Data { get; init; } = new();
    }

    private sealed class Track
    {
        [JsonPropertyName("album")] public Album Album { get; init; } = new();
    }

    private sealed class Album
    {
        [JsonPropertyName("cover_xl")] public string CoverXL { get; init; } = "";
    }

    private sealed class ArtistSearchResponse
    {
        [JsonPropertyName("data")] public List<Artist> Data { get; init; } = new();
    }

    private sealed class Artist
    {
        [JsonPropertyName("name")] public string Name { get; init; } = "";
        [JsonPropertyName("picture_xl")] public string? PictureXL { get; init; }
    }

    private readonly HttpClient _http;
    private readonly string _baseURL;

    public DeezerClient(HttpClient? http = null, string baseURL = "https://api.deezer.com/search")
    {
        _http = http ?? new HttpClient();
        _baseURL = baseURL;
    }

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    /// <summary>
    /// Port de <c>fetchAlbumCover(title:artist:)</c>: trae la portada del
    /// primer resultado de búsqueda (carátula alternativa, 1000x1000), o
    /// nil si no hay ninguno.
    /// </summary>
    public async Task<byte[]?> FetchAlbumCoverAsync(string title, string artist,
        CancellationToken ct = default)
    {
        var query = $"artist:\"{EscapeQuoted(artist)}\" track:\"{EscapeQuoted(title)}\"";
        var url = $"{_baseURL}?q={Uri.EscapeDataString(query)}&limit=1";

        var data = await GetBytesAndValidateAsync(url, ct).ConfigureAwait(false);
        var decoded = JsonSerializer.Deserialize<SearchResponse>(data, JsonOptions);
        var urlString = decoded?.Data.FirstOrDefault()?.Album.CoverXL;
        if (string.IsNullOrEmpty(urlString)) return null;

        return await GetBytesAndValidateAsync(urlString, ct).ConfigureAwait(false);
    }

    /// <summary>
    /// ST-104: varias portadas de álbum para elegir, con el título y el artista
    /// de cada una — sin eso, dos tapas parecidas son indistinguibles.
    /// </summary>
    public async Task<IReadOnlyList<AlbumMatch>> SearchAlbumCoversAsync(
        string title, string? artist, int limit = 5, CancellationToken ct = default)
    {
        var albumTitle = (title ?? "").Trim();
        if (albumTitle.Length == 0) return [];

        var query = $"album:\"{EscapeQuoted(albumTitle)}\"";
        if (artist is { Length: > 0 } name && name.Trim().Length > 0)
            query += $" artist:\"{EscapeQuoted(name.Trim())}\"";

        var url = $"{_baseURL}/album?q={Uri.EscapeDataString(query)}&limit={limit}";

        var data = await GetBytesAndValidateAsync(url, ct).ConfigureAwait(false);
        var decoded = JsonSerializer.Deserialize<AlbumSearchResponse>(data, JsonOptions);

        return decoded?.Data
            .Where(album => album.CoverXL is { Length: > 0 })
            .Select(album => new AlbumMatch(album.Title, album.Artist?.Name ?? "", album.CoverXL!))
            .ToList() ?? [];
    }

    /// <summary>La imagen de una portada ya elegida.</summary>
    public Task<byte[]?> FetchImageAsync(string url, CancellationToken ct = default) =>
        GetBytesOrNullAsync(url, ct);

    /// <param name="CoverUrl">De dónde bajarla, cuando el usuario la elija.</param>
    public readonly record struct AlbumMatch(string Title, string Artist, string CoverUrl);

    private sealed class AlbumSearchResponse
    {
        [JsonPropertyName("data")] public List<AlbumEntry> Data { get; init; } = new();
    }

    private sealed class AlbumEntry
    {
        [JsonPropertyName("title")] public string Title { get; init; } = "";
        [JsonPropertyName("cover_xl")] public string? CoverXL { get; init; }
        [JsonPropertyName("artist")] public Artist? Artist { get; init; }
    }

    private async Task<byte[]?> GetBytesOrNullAsync(string url, CancellationToken ct)
    {
        try { return await GetBytesAndValidateAsync(url, ct).ConfigureAwait(false); }
        catch (EnrichmentError) { return null; }
    }

    /// <summary>
    /// ST-032: foto de artista (<c>picture_xl</c>, 1000x1000) del primer
    /// resultado cuyo nombre coincida (sin mayúsculas/acentos) — Deezer
    /// devuelve también parecidos, y "Gorillaz" no debe llevarse la foto
    /// de "Gorillaz Sound System". <c>baseURL</c> es <c>/search</c>; el
    /// buscador de artistas es su hermano <c>/search/artist</c>.
    /// </summary>
    public async Task<byte[]?> FetchArtistPictureAsync(string name, CancellationToken ct = default)
    {
        var trimmed = (name ?? "").Trim();
        if (trimmed.Length == 0) return null;

        var url = $"{_baseURL}/artist?q={Uri.EscapeDataString(EscapeQuoted(trimmed))}&limit=5";

        var data = await GetBytesAndValidateAsync(url, ct).ConfigureAwait(false);
        var decoded = JsonSerializer.Deserialize<ArtistSearchResponse>(data, JsonOptions);
        var wanted = Normalize(trimmed);
        var match = decoded?.Data.FirstOrDefault(a => Normalize(a.Name) == wanted);
        var urlString = match?.PictureXL;
        if (string.IsNullOrEmpty(urlString)) return null;

        return await GetBytesAndValidateAsync(urlString, ct).ConfigureAwait(false);
    }

    private async Task<byte[]> GetBytesAndValidateAsync(string url, CancellationToken ct)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.TryAddWithoutValidation("User-Agent", HttpUserAgent.Value);
        using var response = await _http.SendAsync(request, ct).ConfigureAwait(false);
        HttpResponseGuard.EnsureSuccess(response);
        return await response.Content.ReadAsByteArrayAsync(ct).ConfigureAwait(false);
    }

    /// <summary>
    /// La query de Deezer no es Lucene (no acepta escape con barra
    /// invertida) — una comilla doble sin cerrar simplemente rompe la
    /// frase de búsqueda, así que se quita en vez de escaparse.
    /// </summary>
    private static string EscapeQuoted(string value) => value.Replace("\"", "");

    /// <summary>
    /// Equivalente privado de <c>LibraryGrouping.normalize(_:)</c> (Swift):
    /// recorta espacios y pliega a minúsculas sin diacríticos, para el
    /// match de artistas contra Deezer. No existe <c>LibraryGrouping</c> en
    /// C# todavía, así que se implementa localmente.
    /// </summary>
    private static string Normalize(string? value)
    {
        var trimmed = (value ?? "").Trim();
        var decomposed = trimmed.Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder(decomposed.Length);
        foreach (var c in decomposed)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark)
                sb.Append(c);
        }
        return sb.ToString().ToLowerInvariant();
    }
}
