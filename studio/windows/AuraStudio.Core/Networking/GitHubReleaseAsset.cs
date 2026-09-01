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
}