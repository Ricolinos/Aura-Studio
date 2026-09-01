using System.Net;
using System.Net.Http;
using System.Text.Json;
using System.Text.Json.Serialization;
using AuraStudio.Core;

namespace AuraStudio.Core.Networking;

/// <summary>
/// Consume <c>GET /repos/&lt;owner&gt;/&lt;repo&gt;/releases</c>. ST-074: los repos
/// del firmware son privados desde 2026-08; si el usuario guardó un token de
/// solo lectura (<c>GitHubToken</c>), la petición va autenticada; sin token se
/// sigue preguntando como repo público (GitHub contesta 404 y el aviso de
/// versiones simplemente calla). Se usa <c>/releases</c> (lista) y no
/// <c>/releases/latest</c> a propósito: <c>/latest</c> excluye prereleases y
/// drafts por definición de GitHub, y mientras el firmware siga en beta esa
/// llamada nunca devolvería nada útil. Acá es Studio quien decide, con
/// <c>PickLatest</c>, si una prerelease cuenta como "la más nueva".
/// </summary>
public static class GitHubReleaseChecker
{
    /// <summary>URL del repo por defecto (Aura).</summary>
    public const string DefaultApiURL = "https://api.github.com/repos/Ricolinos/Aura-Firmware/releases";

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    /// <summary>
    /// ST-046: el repositorio ya no es uno solo. Metro-Aura es un firmware
    /// hermano que publica sus propios Releases con los mismos assets
    /// (<c>rockbox.ipod</c>, <c>rockbox.zip</c>, <c>bootloader-ipod6g.ipod</c>,
    /// <c>mks5lboot</c>), así que la maquinaria sirve igual — lo único que
    /// cambia es a qué repo se le pregunta. <c>null</c> para una familia
    /// desconocida: sin repo no hay a dónde preguntar.
    /// </summary>
    public static string? ApiURLFor(FirmwareFamily family) =>
        family.ReleaseRepository is { } repo ? $"https://api.github.com/repos/{repo}/releases" : null;

    /// <summary>
    /// ST-074: <c>true</c> si la última consulta CON token fue rechazada por
    /// GitHub (401/403: token inválido, expirado o revocado; 404: el token
    /// existe pero no tiene acceso a ese repo). Se vuelve <c>false</c> en
    /// cuanto una consulta con token responde 200. Sin token nunca se toca:
    /// un 404 público no dice nada del token. Estado global de proceso (no
    /// hay instancia).
    /// </summary>
    public static bool LastAuthFailure { get; set; }

    /// <summary>Status que, con token, significan un rechazo de autenticación.</summary>
    public static readonly HashSet<int> AuthFailureStatusCodes = new() { 401, 403, 404 };

    /// <summary>
    /// Con token, un rechazo de autenticación NO lanza: devuelve una lista
    /// vacía ("sin información") y deja <see cref="LastAuthFailure"/> en
    /// <c>true</c>. El chequeo automático así calla en vez de fallar. Sin
    /// token, un status distinto de 200 sigue lanzando
    /// <see cref="GitHubReleaseCheckerError.BadResponse"/> como siempre.
    /// </summary>
    public static async Task<List<GitHubRelease>> FetchReleasesAsync(
        HttpClient http,
        FirmwareFamily family,
        string? token,
        CancellationToken ct = default)
    {
        var url = ApiURLFor(family) ?? throw GitHubReleaseCheckerError.UnknownFamily;

        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.TryAddWithoutValidation("User-Agent", "AuraStudio");
        if (token != null)
        {
            request.Headers.TryAddWithoutValidation("Authorization", $"Bearer {token}");
            request.Headers.TryAddWithoutValidation("Accept", "application/vnd.github+json");
            request.Headers.TryAddWithoutValidation("X-GitHub-Api-Version", "2022-11-28");
        }

        using var response = await http.SendAsync(request, ct).ConfigureAwait(false);
        var status = (int)response.StatusCode;

        if (token != null && AuthFailureStatusCodes.Contains(status))
        {
            LastAuthFailure = true;
            return new List<GitHubRelease>();
        }
        if (status != 200) throw GitHubReleaseCheckerError.BadResponse;
        if (token != null) LastAuthFailure = false;

        var json = await response.Content.ReadAsStringAsync(ct).ConfigureAwait(false);
        return JsonSerializer.Deserialize<List<GitHubRelease>>(json, JsonOptions) ?? new List<GitHubRelease>();
    }

    /// <summary>
    /// Ignora drafts siempre (nunca son instalables). <paramref name="includePrereleases"/>
    /// decide si una beta cuenta como candidata. Devuelve la más nueva que
    /// pase el filtro, o <c>null</c> si no hay ninguna con tag parseable.
    /// </summary>
    public static GitHubRelease? PickLatest(IReadOnlyList<GitHubRelease> releases, bool includePrereleases)
    {
        GitHubRelease? best = null;
        SemVer? bestSem = null;
        foreach (var release in releases)
        {
            if (release.Draft) continue;
            if (!includePrereleases && release.Prerelease) continue;
            var sem = SemVer.Parse(release.TagName);
            if (sem is null) continue;
            if (bestSem is null || sem.Value > bestSem.Value)
            {
                best = release;
                bestSem = sem;
            }
        }
        return best;
    }
}

/// <summary>
/// Errores del chequeo de Releases de GitHub. Port del enum
/// <c>GitHubReleaseCheckerError</c> de Swift (<c>badResponse</c>,
/// <c>unknownFamily</c>).
/// </summary>
public sealed class GitHubReleaseCheckerError : Exception
{
    public static GitHubReleaseCheckerError BadResponse { get; } =
        new("GitHub respondió algo inesperado (status distinto de 200)");

    public static GitHubReleaseCheckerError UnknownFamily { get; } =
        new("la familia instalada no tiene repositorio al que preguntar (ST-046)");

    private GitHubReleaseCheckerError(string message) : base(message) { }
}