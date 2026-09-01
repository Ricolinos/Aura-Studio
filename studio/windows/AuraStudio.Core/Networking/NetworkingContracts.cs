namespace AuraStudio.Core.Networking;

/// <summary>
/// User-Agent que todos los clientes envían (requisito de MusicBrainz,
/// Deezer, etc. por su política de uso). Port de
/// <c>MusicBrainzClient.userAgent</c> (Swift).
/// </summary>
public static class HttpUserAgent
{
    public const string Value = "AuraStudio/0.1.0 (https://github.com/Ricolinos/Aura-Proyect)";
}

/// <summary>
/// Error tipado de enriquecimiento. Port fiel del enum
/// <c>EnrichmentError</c> de Swift, que declara MusicBrainzClient y
/// reutilizan el resto de los clientes de red.
/// </summary>
public sealed class EnrichmentError : Exception
{
    public int? StatusCode { get; private init; }
    public bool IsNoMatch { get; private init; }

    public static EnrichmentError Http(int statusCode) =>
        new($"Error de red (HTTP {statusCode})") { StatusCode = statusCode };

    public static EnrichmentError NoMatch =>
        new("No se encontró ningún resultado") { IsNoMatch = true };

    private EnrichmentError(string message) : base(message) { }
}

/// <summary>
/// Valida la respuesta HTTP, port fiel de <c>MusicBrainzClient.validate(_:)</c>
/// (Swift): solo comprueba que el status code sea 2xx y lanza
/// <see cref="EnrichmentError"/>. El reintento de 503/429 vive en el
/// cliente (performThrottled), no aquí.
/// </summary>
public static class HttpResponseGuard
{
    public static void EnsureSuccess(int statusCode)
    {
        if (statusCode is >= 200 and < 300) return;
        throw EnrichmentError.Http(statusCode);
    }

    public static void EnsureSuccess(HttpResponseMessage response) =>
        EnsureSuccess((int)response.StatusCode);
}
