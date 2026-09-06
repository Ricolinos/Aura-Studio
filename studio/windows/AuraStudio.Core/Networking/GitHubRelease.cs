using System.Text.Json.Serialization;

namespace AuraStudio.Core.Networking;

/// <summary>
/// Un Release de la API publica de GitHub -- solo los campos que hacen
/// falta para decidir cual es el mas nuevo utilizable y, desde ST-077,
/// para bajar sus artefactos.
/// </summary>
public sealed record GitHubRelease
{
    [JsonPropertyName("tag_name")]
    public string TagName { get; init; } = "";

    [JsonPropertyName("draft")]
    public bool Draft { get; init; }

    [JsonPropertyName("prerelease")]
    public bool Prerelease { get; init; }

    /// <summary>
    /// Las notas del Release (ST-211). De ahí sale el SHA-256 publicado del
    /// instalador, que es lo que se verifica antes de ejecutarlo. Ausente en el
    /// caché viejo: se decodifica como cadena vacía, y sin notas simplemente no
    /// hay resumen que comparar.
    /// </summary>
    [JsonPropertyName("body")]
    public string Body { get; init; } = "";

    /// <summary>
    /// La página del Release en github.com (ST-193). Se prefiere esta a armarla
    /// a mano; ausente en respuestas recortadas o en caché viejo.
    /// </summary>
    [JsonPropertyName("html_url")]
    public string? HtmlUrl { get; init; }

    /// <summary>
    /// Ausente en el cache viejo (anterior a ST-077) y en cualquier
    /// respuesta recortada: se decodifica como lista vacia en vez de
    /// hacer fallar el Release entero, que dejaria sin aviso de version
    /// a quien todavia tenga cache de la version anterior de Studio.
    /// </summary>
    [JsonPropertyName("assets")]
    public List<GitHubReleaseAsset> Assets { get; init; } = new();

    /// <summary>
    /// El asset con ese nombre exacto, o <c>null</c>. Los nombres son los de la
    /// tabla §A del contrato (<c>rockbox.ipod</c>, <c>rockbox.zip</c>,
    /// <c>bootloader-ipod6g.ipod</c>, <c>mks5lboot</c>, <c>checksums.txt</c>).
    /// </summary>
    public GitHubReleaseAsset? Asset(string name) =>
        Assets.FirstOrDefault(a => a.Name == name);
}