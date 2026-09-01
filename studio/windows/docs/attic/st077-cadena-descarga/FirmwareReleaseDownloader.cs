// ============================================================================
// ÁTICO — implementación de REFERENCIA, no forma parte del build.
// Ver README.md en esta misma carpeta antes de reutilizar nada de acá.
// Cuelga de un modelo de artefactos (`BundledArtifacts`) que se descartó al
// reconciliar la Fase 2; el que sobrevivió es `AuraStudio.Core/FirmwareArtifacts.cs`.
//
// Al remontarlo (Fase 6), los dos cambios de forma que importan:
//   · `new BundledArtifacts(dir, family)`  →  `FirmwareArtifacts.Load(dir, family)`
//   · `artifacts.VerifyAll()` LANZABA;  `FirmwareArtifactVerifier.Verify(a, scope)`
//     DEVUELVE un resultado — hay que mirar `.IsValid` en los dos puntos donde
//     esto verifica (lo recién bajado, y el atajo de "ya estaba bajado").
// ============================================================================

using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using AuraStudio.Core.Networking;

namespace AuraStudio.Core.Installer;

/// <summary>Un Release ya bajado, verificado y publicado en su directorio final.</summary>
public sealed record PreparedRelease(string Tag, string Directory);

/// <summary>
/// ST-077 / contrato v17: instalar desde cero baja el Release <b>más nuevo</b> de
/// la familia elegida; el pin de <c>FIRMWARE_VERSION</c> (lo que
/// <c>FirmwareFetch.ps1</c> dejó en <c>artifacts\</c>) pasa a ser el respaldo.
/// Port de <c>Services/FirmwareReleaseDownloader.swift</c>.
///
/// Puntos que no son obvios y que el Swift pagó caro:
/// <list type="bullet">
/// <item><b>La URL del API, no <c>browser_download_url</c></b>: la segunda
/// redirige a un host de almacenamiento que rechaza la cabecera
/// <c>Authorization</c> de GitHub, así que en un repo privado (ST-074) falla. Se
/// pide <c>/repos/:owner/:repo/releases/assets/:id</c> con
/// <c>Accept: application/octet-stream</c>, y se suelta <c>Authorization</c> si el
/// 302 cambia de host — <c>HttpClient</c>, como <c>URLSession</c>, la reenviaría
/// sola.</item>
/// <item><b>Publicación atómica</b>: se baja a <c>.descarga-&lt;tag&gt;\</c> y solo
/// se renombra al directorio final cuando todo pasó la verificación. Un corte a
/// la mitad no puede dejar un directorio que la próxima corrida dé por completo.</item>
/// <item><b>El tag nunca entra crudo a una ruta</b>: <see cref="IsSafeTagComponent"/>
/// antes de componer el directorio de caché — mismo criterio que
/// <c>AuraThemeID.IsValid()</c> para los ids de tema.</item>
/// <item><b>Fallar nunca detiene la instalación</b>: cualquier problema lanza un
/// <c>InstallerException</c> que el llamador convierte en "se instala lo que ya
/// estaba, y por esto". Los errores existen para poder DECIR por qué, no para
/// abortar.</item>
/// </list>
///
/// <b>Diferencia con macOS</b>: allá se bajan los cinco assets, <c>mks5lboot</c>
/// incluido, y se le pone el bit de ejecución. Acá el ejecutable de Windows
/// (<c>mks5lboot.exe</c>) NO es un asset del Release — se cross-compila en este
/// repo — así que se bajan los cuatro que sí publica y el <c>mks5lboot.exe</c>
/// local se copia junto a ellos, para que el runner y el bootloader sigan
/// saliendo del mismo directorio. El bootloader y el árbol sí salen SIEMPRE del
/// mismo Release: flashear el bootloader de una versión y copiar el árbol de otra
/// sería una mezcla que ningún release probó nunca.
/// </summary>
public static class FirmwareReleaseDownloader
{
    /// <summary>Los assets que se bajan del Release (todo lo de §A menos el ejecutable de Windows).</summary>
    public static readonly IReadOnlyList<ArtifactName> DownloadedAssets =
        [ArtifactName.Firmware, ArtifactName.RockboxTree, ArtifactName.Bootloader, ArtifactName.Checksums];

    /// <summary>
    /// Un tag jamás se concatena a una ruta sin pasar por acá: alfanuméricos,
    /// <c>.</c>, <c>-</c> y <c>_</c>; sin separadores, sin <c>..</c>, ≤ 64.
    /// </summary>
    public static bool IsSafeTagComponent(string tag)
    {
        if (string.IsNullOrEmpty(tag) || tag.Length > 64) return false;
        if (tag.Contains("..", StringComparison.Ordinal)) return false;
        return tag.All(c => char.IsAsciiLetterOrDigit(c) || c is '.' or '-' or '_');
    }

    /// <summary>
    /// <c>&lt;cacheRoot&gt;\&lt;familia&gt;\&lt;tag&gt;</c>. <c>null</c> si el tag no
    /// es seguro o la familia no es instalable.
    /// </summary>
    public static string? CacheDirectory(string cacheRoot, FirmwareFamily family, string tag)
    {
        if (!family.IsInstallable) return null;
        if (!IsSafeTagComponent(tag)) return null;
        return Path.Combine(cacheRoot, family.ConfigValue ?? "aura", tag);
    }

    /// <summary>
    /// Baja y verifica el Release más nuevo de <paramref name="family"/>, dejando
    /// sus artefactos utilizables. Si ese Release ya está en caché y verificado,
    /// no vuelve a bajar nada.
    /// </summary>
    /// <param name="fallback">
    /// Los artefactos locales (<c>artifacts\</c>): de ahí sale el
    /// <c>mks5lboot.exe</c> que se copia junto a lo descargado.
    /// </param>
    /// <exception cref="InstallerException">
    /// Siempre con un <c>InstallerError.ReleaseDownloadFailed</c> o
    /// <c>ReleaseMissingAsset</c>: el llamador los muestra y sigue con lo local —
    /// nunca aborta la instalación por esto.
    /// </exception>
    public static async Task<PreparedRelease> PrepareLatestAsync(
        FirmwareFamily family,
        BundledArtifacts fallback,          // ← Fase 6: FirmwareArtifacts
        string cacheRoot,
        HttpClient http,
        string? token = null,
        IProgress<string>? progress = null,
        CancellationToken ct = default)
    {
        if (family.ReleaseRepository is null)
        {
            throw Failed(family, "Aura Studio no conoce el repositorio de esa familia.");
        }

        progress?.Report($"Consultando la versión más reciente de {family.DisplayName}…");

        List<GitHubRelease> releases;
        try
        {
            releases = await GitHubReleaseChecker.FetchReleasesAsync(http, family, token, ct).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is HttpRequestException or GitHubReleaseCheckerError or TaskCanceledException)
        {
            throw Failed(family, "no se pudo consultar GitHub.");
        }

        if (releases.Count == 0 && GitHubReleaseChecker.LastAuthFailure)
        {
            throw Failed(family, "el token de GitHub no tiene acceso a ese repositorio.");
        }

        var latest = GitHubReleaseChecker.PickLatest(releases, includePrereleases: true)
            ?? throw Failed(family, "el repositorio no publica ningún Release utilizable.");

        string tag = latest.TagName;
        string? finalDir = CacheDirectory(cacheRoot, family, tag);
        if (finalDir is null)
        {
            throw Failed(family, $"el tag \"{tag}\" no se puede usar como nombre de carpeta.");
        }

        // Ya bajado y verificado antes: no se vuelve a bajar 9 MB por gusto.
        var cached = new BundledArtifacts(finalDir, family);
        if (cached.IsComplete && TryVerify(cached))
        {
            return new PreparedRelease(tag, finalDir);
        }

        string stagingDir = Path.Combine(Path.GetDirectoryName(finalDir)!, $".descarga-{tag}");
        try
        {
            if (Directory.Exists(stagingDir)) Directory.Delete(stagingDir, true);
            Directory.CreateDirectory(stagingDir);

            foreach (var asset in DownloadedAssets)
            {
                ct.ThrowIfCancellationRequested();
                string assetName = BundledArtifacts.ReleaseAssetNameOf(asset);
                var published = latest.Asset(assetName)
                    ?? throw new InstallerException(new InstallerError.ReleaseMissingAsset(tag, assetName));

                progress?.Report($"Descargando {assetName} de {family.DisplayName} {tag}…");
                byte[] bytes = await DownloadAssetAsync(http, published, token, ct).ConfigureAwait(false);

                // El tamaño que el propio Release declara: una descarga truncada
                // no llega a checksums.txt con un error entendible.
                if (published.Size > 0 && bytes.Length != published.Size)
                {
                    throw Failed(family, $"{assetName} llegó incompleto ({bytes.Length} de {published.Size} bytes).");
                }
                await File.WriteAllBytesAsync(Path.Combine(stagingDir, BundledArtifacts.FileNameOf(asset)), bytes, ct)
                          .ConfigureAwait(false);
            }

            // El ejecutable local, junto al Release: ver la nota de plataforma del
            // encabezado. Sin esto el directorio bajado no sería instalable por sí
            // solo. (Fase 6: acá va el `mks5lboot.exe` cuya procedencia describe
            // `ToolOrigin`/`ToolProvenance` en FirmwareArtifacts.cs.)
            string? tool = fallback.PathOf(ArtifactName.Mks5lboot);
            if (tool is null)
            {
                throw new InstallerException(new InstallerError.MissingArtifact(
                    BundledArtifacts.FileNameOf(ArtifactName.Mks5lboot)));
            }
            File.Copy(tool, Path.Combine(stagingDir, BundledArtifacts.FileNameOf(ArtifactName.Mks5lboot)), overwrite: true);

            // El tag exacto junto a los artefactos, para que la pantalla de
            // Licencias (§B) y el manifiesto de instalación (v11) citen la versión
            // que de verdad se instaló (contrato v17).
            await File.WriteAllTextAsync(Path.Combine(stagingDir, BundledArtifacts.VersionMarkerFileName),
                                         tag + "\n",
                                         new UTF8Encoding(encoderShouldEmitUTF8Identifier: false), ct).ConfigureAwait(false);

            progress?.Report("Verificando lo descargado…");
            new BundledArtifacts(stagingDir, family).VerifyAll();

            // Publicación atómica: recién ahora el directorio final existe.
            Directory.CreateDirectory(Path.GetDirectoryName(finalDir)!);
            if (Directory.Exists(finalDir)) Directory.Delete(finalDir, true);
            Directory.Move(stagingDir, finalDir);
            return new PreparedRelease(tag, finalDir);
        }
        catch (InstallerException)
        {
            throw;
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            throw Failed(family, ex.Message);
        }
        finally
        {
            if (Directory.Exists(stagingDir))
            {
                try { Directory.Delete(stagingDir, true); } catch { /* mejor esfuerzo */ }
            }
        }
    }

    /// <summary>
    /// Descarga por la URL del API con <c>Accept: application/octet-stream</c>.
    /// <c>Authorization</c> se manda solo al host del API: si GitHub redirige a su
    /// almacenamiento, esa cabecera hace que el host responda error, así que el
    /// salto se sigue a mano y sin ella.
    /// </summary>
    private static async Task<byte[]> DownloadAssetAsync(HttpClient http, GitHubReleaseAsset asset, string? token, CancellationToken ct)
    {
        var uri = new Uri(asset.Url);
        for (int hop = 0; hop < 5; hop++)
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, uri);
            request.Headers.TryAddWithoutValidation("User-Agent", "AuraStudio");
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/octet-stream"));
            bool sameHost = uri.Host.Equals("api.github.com", StringComparison.OrdinalIgnoreCase);
            if (token is not null && sameHost)
            {
                request.Headers.TryAddWithoutValidation("Authorization", $"Bearer {token}");
                request.Headers.TryAddWithoutValidation("X-GitHub-Api-Version", "2022-11-28");
            }

            using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct).ConfigureAwait(false);

            if ((int)response.StatusCode is >= 300 and < 400 && response.Headers.Location is { } location)
            {
                uri = location.IsAbsoluteUri ? location : new Uri(uri, location);
                continue;
            }
            if (!response.IsSuccessStatusCode)
            {
                throw new HttpRequestException($"GitHub respondió {(int)response.StatusCode} al pedir {asset.Name}.");
            }
            return await response.Content.ReadAsByteArrayAsync(ct).ConfigureAwait(false);
        }
        throw new HttpRequestException($"demasiadas redirecciones al descargar {asset.Name}.");
    }

    private static bool TryVerify(BundledArtifacts artifacts)
    {
        try
        {
            artifacts.VerifyAll();
            return true;
        }
        catch (InstallerException)
        {
            return false;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    private static InstallerException Failed(FirmwareFamily family, string reason) =>
        new(new InstallerError.ReleaseDownloadFailed(family.DisplayName, reason));
}
