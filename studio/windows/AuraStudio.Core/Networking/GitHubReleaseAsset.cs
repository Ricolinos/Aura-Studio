using System.Text.Json.Serialization;

namespace AuraStudio.Core.Networking;

/// <summary>
/// Un asset publicado en un Release. ST-077: <c>Url</c> es la del **API**
/// (<c>/repos/:owner/:repo/releases/assets/:id</c>), no <c>browser_download_url</c>
/// -- en un repositorio privado la segunda no sirve con un token
/// (redirige a un host de almacenamiento que no acepta la cabecera
/// <c>Authorization</c>); la del API sí, pidiendo
/// <c>Accept: application/octet-stream</c>.
/// </summary>
public sealed record GitHubReleaseAsset
{
    [JsonPropertyName("name")]
    public string Name { get; init; } = "";

    [JsonPropertyName("url")]
    public string Url { get; init; } = "";

    [JsonPropertyName("size")]
    public int Size { get; init; }

    /// <summary>
    /// La URL pública de descarga (ST-193): es la que se le ofrece al usuario y
    /// la que Windows usa para bajar el instalador. La del API (<c>Url</c>) sigue
    /// siendo la que sirve con token en un repo privado.
    /// </summary>
    [JsonPropertyName("browser_download_url")]
    public string BrowserDownloadUrl { get; init; } = "";

    /// <summary>
    /// El resumen que publica la propia API, en la forma <c>sha256:&lt;hex&gt;</c>
    /// (ST-211). Es lo que se verifica contra lo descargado antes de ejecutar
    /// nada; ausente en respuestas viejas o recortadas, y entonces se cae a
    /// comparar el tamaño exacto.
    /// </summary>
    [JsonPropertyName("digest")]
    public string? Digest { get; init; }
}