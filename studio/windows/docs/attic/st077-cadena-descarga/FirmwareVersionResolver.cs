// ============================================================================
// ÁTICO — implementación de REFERENCIA, no forma parte del build.
// Ver README.md en esta misma carpeta antes de reutilizar nada de acá.
// Cuelga de un modelo de artefactos (`BundledArtifacts`) que se descartó al
// reconciliar la Fase 2; el que sobrevivió es `AuraStudio.Core/FirmwareArtifacts.cs`.
// ============================================================================

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
        BundledArtifacts localArtifacts,   // ← Fase 6: FirmwareArtifacts
        HttpClient http,
        IReleaseCacheStore cache,
        string? token = null,
        bool force = false,
        CancellationToken ct = default)
    {
        string? local = localArtifacts.ReleaseTag;

        var releases = force ? null : ReleaseCache.Load(cache, family);
        if (releases is null && family.ReleaseRepository is not null)
        {
            try
            {
                var fetched = await GitHubReleaseChecker.FetchReleasesAsync(http, family, token, ct).ConfigureAwait(false);
                // ST-074: `[]` con fallo de token NO se cachea — arreglar el token
                // en Ajustes debe surtir efecto de inmediato, no en 24 h.
                if (!(fetched.Count == 0 && GitHubReleaseChecker.LastAuthFailure))
                {
                    ReleaseCache.Store(fetched, cache, family);
                }
                releases = fetched;
            }
            catch (Exception ex) when (ex is HttpRequestException or GitHubReleaseCheckerError or TaskCanceledException)
            {
                // Sin red no se falla: se cae al tag local, marcado como local.
                releases = null;
            }
        }

        if (releases is not null && GitHubReleaseChecker.PickLatest(releases, includePrereleases: true) is { } latest)
        {
            return new FirmwareVersionEntry(latest.TagName, FromGitHub: true);
        }
        return new FirmwareVersionEntry(local, FromGitHub: false);
    }
}
