using System.Globalization;
using System.Net;
using System.Net.Http;
using System.Text.Json;
using System.Text.Json.Serialization;
using AuraStudio.Core.Resources;

namespace AuraStudio.Core.Networking;

/// <summary>
/// Cliente de The Movie Database (ST-033) -- API v3, key propia
/// (gratuita). Cumple dos papeles para los pósters de video:
/// 1. <b>Resolvedor de identificadores</b>: fanart.tv no busca por título;
///    indexa películas por ID de TMDB/IMDb y series por ID de TheTVDB.
///    TMDB resuelve título → ID de película, y título → ID de serie →
///    <c>external_ids.tvdb_id</c>.
/// 2. <b>Póster de respaldo</b>: TMDB trae su propio <c>poster_path</c>
///    (<c>image.tmdb.org</c>), que se usa cuando fanart.tv no tiene el
///    título (o no hay key de fanart.tv).
/// Sin key no toca la red (null), como los demás clientes opcionales.
/// </summary>
public sealed class TMDBClient
{
    /// <summary>Película encontrada por título (y año).</summary>
    public sealed class Movie
    {
        [JsonPropertyName("id")] public int Id { get; init; }
        [JsonPropertyName("title")] public string Title { get; init; } = "";
        [JsonPropertyName("release_date")] public string? ReleaseDate { get; init; }
        [JsonPropertyName("poster_path")] public string? PosterPath { get; init; }

        /// <summary>Año de estreno (extraído de release_date).</summary>
        public string? Year => ReleaseDate?.Length >= 4 ? ReleaseDate[..4] : null;
    }

    /// <summary>Serie de TV encontrada por nombre.</summary>
    public sealed class TVShow
    {
        [JsonPropertyName("id")] public int Id { get; init; }
        [JsonPropertyName("name")] public string Name { get; init; } = "";
        [JsonPropertyName("first_air_date")] public string? FirstAirDate { get; init; }
        [JsonPropertyName("poster_path")] public string? PosterPath { get; init; }

        /// <summary>Año de premiere (extraído de first_air_date).</summary>
        public string? Year => FirstAirDate?.Length >= 4 ? FirstAirDate[..4] : null;
    }

    /// <summary>IDs externos (TheTVDB, IMDb) de una serie.</summary>
    private sealed class ExternalIDs
    {
        [JsonPropertyName("tvdb_id")] public int? TvdbID { get; init; }
        [JsonPropertyName("imdb_id")] public string? ImdbID { get; init; }
    }

    private sealed class SearchResponse<T>
    {
        [JsonPropertyName("results")] public List<T> Results { get; init; } = new();
    }

    private readonly HttpClient _http;
    private readonly string _baseURL;
    private readonly string _imageBaseURL;
    private readonly IApiKeyStore _apiKeyStore;
    private readonly string? _language;

    /// <param name="language">
    /// Idioma en el que se le piden los datos a TMDB. Por omisión, el de la
    /// interfaz.
    ///
    /// <para>Estaba fijo en <c>"es-MX"</c>, y con la app en un solo idioma eso
    /// era correcto. Con seis deja de serlo: de acá salen los títulos y las
    /// sinopsis de películas y series, así que la app en japonés le mostraba al
    /// usuario texto en español recién traído de la red. No es una cadena de
    /// interfaz —es un parámetro de una consulta—, y por eso ninguna prueba de
    /// extracción lo iba a ver nunca (ST-247, B7c).</para>
    /// </param>
    public TMDBClient(
        HttpClient? http = null,
        IApiKeyStore? apiKeyStore = null,
        string baseURL = "https://api.themoviedb.org/3",
        string imageBaseURL = "https://image.tmdb.org/t/p/w780",
        string? language = null)
    {
        _http = http ?? new HttpClient();
        _baseURL = baseURL;
        _imageBaseURL = imageBaseURL;
        _apiKeyStore = apiKeyStore ?? new SimpleApiKeyStore();
        _language = language;
    }

    /// <summary>
    /// El idioma que viaja en la consulta. Se resuelve al consultar y no al
    /// construir el cliente, para que valga la cultura del momento.
    ///
    /// <para>La cultura invariante no tiene nombre y dejaría
    /// <c>&amp;language=</c> vacío: ahí la interfaz se ve en español, que es la
    /// cultura neutra, y eso es lo que se pide.</para>
    /// </summary>
    private string Language
    {
        get
        {
            if (_language is { Length: > 0 }) return _language;

            string name = CultureInfo.CurrentUICulture.Name;
            return name.Length > 0 ? name : AppLanguages.NeutralCulture;
        }
    }

    /// <summary>True si hay clave de API configurada.</summary>
    public bool HasAPIKey => _apiKeyStore.Load("tmdb") != null;

    /// <summary>Película por título (y año si se conoce). Devuelve el primer resultado.</summary>
    public async Task<Movie?> SearchMovieAsync(string title, string? year = null, CancellationToken ct = default)
    {
        var query = BuildQuery(title, year);
        var response = await GetAsync<SearchResponse<Movie>>("search/movie", query, ct).ConfigureAwait(false);
        return response?.Results.FirstOrDefault();
    }

    /// <summary>Serie de TV por nombre (y año si se conoce).</summary>
    public async Task<TVShow?> SearchTVAsync(string name, string? year = null, CancellationToken ct = default)
    {
        var query = BuildQuery(name, year);
        // TMDB usa first_air_date_year para series, no year
        var q = new List<KeyValuePair<string, string>>();
        foreach (var (k, v) in query) q.Add(new(k, v));
        q.Add(new("first_air_date_year", year ?? ""));
        q.RemoveAll(x => string.IsNullOrEmpty(x.Value));
        var response = await GetAsync<SearchResponse<TVShow>>("search/tv", q, ct).ConfigureAwait(false);
        return response?.Results.FirstOrDefault();
    }

    /// <summary>ID de TheTVDB de una serie — lo único que fanart.tv acepta para TV.</summary>
    public async Task<int?> GetTvdbIDAsync(int tvShowId, CancellationToken ct = default)
    {
        var ids = await GetAsync<ExternalIDs>($"tv/{tvShowId}/external_ids", [], ct).ConfigureAwait(false);
        return ids?.TvdbID;
    }

    /// <summary>
    /// Descarga el póster de TMDB (<c>poster_path</c> relativo, p. ej.
    /// <c>/abc.jpg</c>) a 780 px de ancho — de sobra para los ≤640 px que
    /// admite el iPod, sin bajar el original de 2000 px.
    /// </summary>
    public async Task<byte[]?> DownloadPosterAsync(string? path, CancellationToken ct = default)
    {
        if (string.IsNullOrEmpty(path)) return null;
        var url = $"{_imageBaseURL}{path}";
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        using var response = await _http.SendAsync(request, ct).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadAsByteArrayAsync(ct).ConfigureAwait(false);
    }

    private List<KeyValuePair<string, string>> BuildQuery(string title, string? year)
    {
        var q = new List<KeyValuePair<string, string>>
        {
            new("query", title),
            new("include_adult", "false"),
        };
        if (!string.IsNullOrEmpty(year)) q.Add(new("year", year));
        return q;
    }

    private async Task<T?> GetAsync<T>(string path, List<KeyValuePair<string, string>> query, CancellationToken ct)
        where T : class
    {
        var apiKey = _apiKeyStore.Load("tmdb");
        if (apiKey == null) return null;

        var qs = string.Join("&", query
            .Where(x => !string.IsNullOrEmpty(x.Value))
            .Select(x => $"{Uri.EscapeDataString(x.Key)}={Uri.EscapeDataString(x.Value)}"));
        qs += $"&language={Uri.EscapeDataString(Language)}&api_key={Uri.EscapeDataString(apiKey)}";

        var url = $"{_baseURL}/{path}?{qs}";
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.TryAddWithoutValidation("User-Agent", HttpUserAgent.Value);

        using var response = await _http.SendAsync(request, ct).ConfigureAwait(false);
        if (response.StatusCode == HttpStatusCode.NotFound) return null;
        HttpResponseGuard.EnsureSuccess(response);

        var json = await response.Content.ReadAsStringAsync(ct).ConfigureAwait(false);
        return JsonSerializer.Deserialize<T>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
    }

    /// <summary>
    /// Implementación simple que devuelve null (para cuando no se inyecta
    /// <c>IApiKeyStore</c> real en Core — el DefaultApiKeyStore se usa en
    /// la implementación real de Windows).
    /// </summary>
    private sealed class SimpleApiKeyStore : IApiKeyStore
    {
        public string? Load(string service) => null;
    }
}