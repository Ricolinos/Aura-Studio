
using System.Net.Http;
using AuraStudio.Core.Networking;

namespace AuraStudio.Core.Installer;

/// <summary>
/// Qué versión de una familia se instalaría HOY.
/// </summary>
/// <param name="Tag">El tag, o <c>null</c> si no hay ni Release consultable ni marcador local.</param>
/// <param name="FromGitHub">
/// <c>true</c> si <paramref name="Tag"/> es el Release más nuevo de GitHub;
/// <c>false</c> si es el que ya está en <c>artifacts\</c>. La UI necesita
/// distinguirlo para poder decir "incluida" en vez de aparentar que eso es lo
/// último publicado (ST-053: una pastilla que dice una versión tiene que decir
/// de dónde salió).
/// </param>
public readonly record struct FirmwareVersionEntry(string? Tag, bool FromGitHub);

/// <summary>
/// ST-077: qué versión de cada firmware se instalaría <b>hoy</b>, para que Extras
/// muestre eso y no el pin de <c>FIRMWARE_VERSION</c> horneado al poblar
/// <c>artifacts\</c>. Port de la lógica de
/// <c>ViewModels/AvailableFirmwareVersions.swift</c> — acá sin estado observable:
/// es una consulta pura sobre red+caché, y el ViewModel de la app se queda con lo
/// suyo (la lista publicada, el "revisar de nuevo", el indicador de carga).
///
/// El bug que arregla (reporte del dueño, 2026-08-27): la pastilla de cada
/// tarjeta de firmware salía del marcador local, así que un Release publicado
/// después de poblar <c>artifacts\</c> era invisible ahí — aunque el aviso de
/// actualizaciones (con el token de ST-074) ya lo conociera. Extras y el
/// instalador tienen que coincidir: los dos miran el Release más nuevo.
///
/// Nunca deja la pastilla vacía: sin red, sin token o con un repo sin Releases
/// utilizables, cae al tag local y lo marca como tal.
/// </summary>
public static class FirmwareVersionResolver
{
    /// <param name="force">
    /// Saltea el caché de 24 h — el botón "Revisar de nuevo". Misma razón que
    /// <c>forceRefresh</c> en <c>AuraUpdateChecker</c> (D-300): una revisión
    /// manual del usuario debe ser una consulta en vivo de verdad, si no, un
    /// caché que se llenó justo antes de publicarse el Release nuevo lo esconde
    /// hasta que el TTL venza solo.
    /// </param>
    public static async Task<FirmwareVersionEntry> ResolveAsync(
        FirmwareFamily family,
        FirmwareArtifacts localArtifacts,
        HttpClient http,
        IReleaseCacheStore cache,
        string? token = null,
        bool force = false,
        CancellationToken ct = default)
    {
        string? local = localArtifacts.ReleaseTag;

        ReleaseLookup lookup = await LookupAsync(family, http, cache, token, force, ct).ConfigureAwait(false);

        if (lookup.Releases is { } found
            && GitHubReleaseChecker.PickLatest(found, includePrereleases: true) is { } latest)
        {
            return new FirmwareVersionEntry(latest.TagName, FromGitHub: true);
        }

        return new FirmwareVersionEntry(local, FromGitHub: false);
    }

    /// <summary>
    /// El tag del Release más nuevo publicado de esa familia, o por qué no se
    /// sabe (ST-210).
    ///
    /// <para>Es lo que "Buscar actualizaciones" necesita y
    /// <see cref="ResolveAsync"/> no puede dar: ese cae al tag local cuando
    /// GitHub no contesta, y para decidir si hay actualización hace falta
    /// distinguir "no hay nada más nuevo" de "no se pudo preguntar".</para>
    /// </summary>
    public static async Task<LatestReleaseLookup> LatestPublishedAsync(
        FirmwareFamily family,
        HttpClient http,
        IReleaseCacheStore cache,
        string? token = null,
        bool force = false,
        CancellationToken ct = default)
    {
        ReleaseLookup lookup = await LookupAsync(family, http, cache, token, force, ct).ConfigureAwait(false);

        string? tag = lookup.Releases is { } found
            ? GitHubReleaseChecker.PickLatest(found, includePrereleases: true)?.TagName
            : null;

        return new LatestReleaseLookup(tag, lookup.Failed);
    }

    private readonly record struct ReleaseLookup(IReadOnlyList<GitHubRelease>? Releases, bool Failed);

    /// <summary>
    /// La consulta con caché, compartida por las dos formas de preguntar: dos
    /// copias de esto serían dos criterios de cuándo se cachea un fallo de token.
    /// </summary>
    private static async Task<ReleaseLookup> LookupAsync(
        FirmwareFamily family,
        HttpClient http,
        IReleaseCacheStore cache,
        string? token,
        bool force,
        CancellationToken ct)
    {
        IReadOnlyList<GitHubRelease>? releases = force ? null : ReleaseCache.Load(cache, family);
        if (releases is not null) return new ReleaseLookup(releases, Failed: false);

        // Sin repositorio no hay a quién preguntar; eso no es un fallo de red.
        if (family.ReleaseRepository is null) return new ReleaseLookup(null, Failed: false);

        try
        {
            List<GitHubRelease> fetched =
                await GitHubReleaseChecker.FetchReleasesAsync(http, family, token, ct).ConfigureAwait(false);

            // ST-074: `[]` con fallo de token NO se cachea — arreglar el token
            // en Ajustes debe surtir efecto de inmediato, no en 24 h.
            bool tokenRejected = fetched.Count == 0 && GitHubReleaseChecker.LastAuthFailure;
            if (!tokenRejected) ReleaseCache.Store(fetched, cache, family);

            return new ReleaseLookup(fetched, Failed: tokenRejected);
        }
        catch (Exception ex) when (ex is HttpRequestException or GitHubReleaseCheckerError or TaskCanceledException)
        {
            // Sin red no se falla: se dice que no se pudo, y quien llama decide
            // qué mostrar. Lo que nunca se hace es concluir "está al día".
            return new ReleaseLookup(null, Failed: true);
        }
    }
}

/// <summary>
/// Lo que se supo al preguntar por el Release más nuevo (ST-210).
/// </summary>
/// <param name="Tag">El tag más nuevo publicado, o <c>null</c> si no se supo.</param>
/// <param name="Failed">
/// Si la consulta se intentó y no se pudo: sin red, GitHub caído, o el token
/// rechazado. Con <c>Tag</c> nulo y esto en <c>false</c>, es que no había a quién
/// preguntar o que el repo no tiene Releases utilizables.
/// </param>
public readonly record struct LatestReleaseLookup(string? Tag, bool Failed);
