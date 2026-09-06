using System.Net.Http;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using AuraStudio.Core.Networking;

namespace AuraStudio.App.Platform;

/// <summary>Cómo terminó bajar y lanzar el instalador (ST-211).</summary>
public enum AppUpdateDownloadOutcome
{
    Started,

    /// <summary>No se pudo bajar: sin red, GitHub caído, disco lleno.</summary>
    DownloadFailed,

    /// <summary>
    /// Lo bajado <b>no coincide</b> con lo que el Release dice que debería ser.
    /// Se borra y no se ejecuta nada.
    /// </summary>
    ChecksumMismatch,

    /// <summary>Se bajó pero Windows no lo dejó arrancar.</summary>
    LaunchFailed,

    Cancelled
}

public readonly record struct AppUpdateDownloadResult(AppUpdateDownloadOutcome Outcome, string Message);

/// <summary>
/// Baja el instalador de una versión nueva de Aura Studio y lo ejecuta (ST-211,
/// §5 de la propuesta).
///
/// <para><b>Por qué se ejecuta y no solo se muestra</b>, a diferencia de macOS:
/// el instalador de Windows ya existe, es Inno Setup por usuario y sin UAC
/// (ST-135), y ya sabe actualizar sobre lo instalado. No hay componente nuevo
/// que mantener ni en el que confiar.</para>
///
/// <para><b>Nada se ejecuta sin que el usuario lo pida</b>, y nada se ejecuta sin
/// verificar: se compara contra el <c>digest</c> que publica la propia API de
/// GitHub y, si esa respuesta no lo trae, contra el tamaño exacto del asset. Si
/// no coincide, el archivo se borra y no se abre nada. Es la diferencia
/// deliberada con macOS, donde solo se abre la URL y no se ejecuta nada.</para>
///
/// <para>Solo se baja de la URL de asset que devolvió la propia API de GitHub,
/// nunca de una construida a mano.</para>
/// </summary>
internal static class AppUpdateInstaller
{
    /// <summary>
    /// Baja a una carpeta temporal propia y lanza el instalador. Devuelve
    /// <see cref="AppUpdateDownloadOutcome.Started"/> cuando el instalador ya
    /// arrancó: de ahí en adelante manda él, y la app se cierra.
    /// </summary>
    public static async Task<AppUpdateDownloadResult> DownloadAndRunAsync(
        HttpClient http,
        GitHubReleaseAsset asset,
        string? token,
        IProgress<double>? progress = null,
        CancellationToken ct = default)
    {
        string folder = Path.Combine(Path.GetTempPath(), "AuraStudio-actualizacion");
        string destination = Path.Combine(folder, asset.Name);

        try
        {
            Directory.CreateDirectory(folder);

            await DownloadAsync(http, asset, destination, token, progress, ct).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            Discard(destination);
            return new AppUpdateDownloadResult(AppUpdateDownloadOutcome.Cancelled, "Se detuvo la descarga.");
        }
        catch (Exception ex) when (ex is HttpRequestException or IOException or UnauthorizedAccessException)
        {
            Discard(destination);
            return new AppUpdateDownloadResult(
                AppUpdateDownloadOutcome.DownloadFailed,
                $"No se pudo descargar el instalador: {ex.Message}");
        }

        if (await VerifyAsync(destination, asset, ct).ConfigureAwait(false) is { } problem)
        {
            Discard(destination);
            return new AppUpdateDownloadResult(AppUpdateDownloadOutcome.ChecksumMismatch, problem);
        }

        try
        {
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(destination)
            {
                UseShellExecute = true
            });
        }
        catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or IOException)
        {
            return new AppUpdateDownloadResult(
                AppUpdateDownloadOutcome.LaunchFailed,
                $"El instalador se descargó en {destination}, pero no se pudo abrir: {ex.Message}");
        }

        return new AppUpdateDownloadResult(
            AppUpdateDownloadOutcome.Started,
            "El instalador está abriéndose. Aura Studio se cerrará para poder actualizarse.");
    }

    /// <summary>
    /// Qué está mal con lo bajado, o <c>null</c> si pasa (ST-211).
    ///
    /// <para>El <b>resumen que publica la API</b> es lo que se verifica cuando
    /// viene (<c>digest: "sha256:…"</c>). Cuando no viene —respuesta vieja o
    /// recortada— queda el <b>tamaño exacto</b>, que no es una firma pero sí
    /// atrapa una descarga cortada, que es el fallo frecuente. Lo que no se hace
    /// nunca es ejecutar algo sin haber comprobado <b>nada</b>.</para>
    /// </summary>
    private static async Task<string?> VerifyAsync(
        string path, GitHubReleaseAsset asset, CancellationToken ct)
    {
        if (Sha256From(asset.Digest) is { Length: > 0 } expected)
        {
            string actual = await Task.Run(() => Sha256Of(path), ct).ConfigureAwait(false);

            return string.Equals(actual, expected, StringComparison.OrdinalIgnoreCase)
                ? null
                : "Lo descargado no coincide con el resumen que publica GitHub para ese archivo. "
                  + "Se borró y no se abrió nada; vuelve a intentarlo más tarde.";
        }

        if (asset.Size <= 0) return null;

        long size = new FileInfo(path).Length;

        return size == asset.Size
            ? null
            : $"Lo descargado mide {size} bytes y el Release dice {asset.Size}: la descarga quedó "
              + "incompleta. Se borró y no se abrió nada.";
    }

    /// <summary>
    /// El hexadecimal de un <c>digest</c> de la API, que viene como
    /// <c>sha256:&lt;hex&gt;</c>. Otro algoritmo se ignora: verificar con el
    /// algoritmo equivocado no verifica nada.
    /// </summary>
    private static string? Sha256From(string? digest)
    {
        const string prefix = "sha256:";

        if (digest is not { Length: > 0 }) return null;
        if (!digest.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) return null;

        return digest[prefix.Length..].Trim();
    }

    private static async Task DownloadAsync(
        HttpClient http,
        GitHubReleaseAsset asset,
        string destination,
        string? token,
        IProgress<double>? progress,
        CancellationToken ct)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, asset.Url);
        request.Headers.TryAddWithoutValidation("User-Agent", "AuraStudio");

        // ST-077: la URL del API con `application/octet-stream` es la que sirve
        // con token; `browser_download_url` redirige a un host que no acepta la
        // cabecera de autorización.
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/octet-stream"));
        if (token is not null) request.Headers.TryAddWithoutValidation("Authorization", $"Bearer {token}");

        using HttpResponseMessage response =
            await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct).ConfigureAwait(false);

        response.EnsureSuccessStatusCode();

        long total = response.Content.Headers.ContentLength ?? asset.Size;

        await using Stream source = await response.Content.ReadAsStreamAsync(ct).ConfigureAwait(false);
        await using var file = new FileStream(destination, FileMode.Create, FileAccess.Write, FileShare.None);

        byte[] buffer = new byte[81920];
        long written = 0;

        while (true)
        {
            int read = await source.ReadAsync(buffer, ct).ConfigureAwait(false);
            if (read == 0) break;

            await file.WriteAsync(buffer.AsMemory(0, read), ct).ConfigureAwait(false);

            written += read;
            if (total > 0) progress?.Report((double)written / total);
        }
    }

    private static string Sha256Of(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream));
    }

    /// <summary>
    /// Un instalador a medias o que no verifica no se deja tirado: el próximo
    /// intento no puede encontrarse un archivo con el nombre correcto y el
    /// contenido equivocado.
    /// </summary>
    private static void Discard(string path)
    {
        try
        {
            if (File.Exists(path)) File.Delete(path);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Si no se puede borrar, tampoco se puede hacer más: lo que importa
            // es que no se ejecutó.
        }
    }
}
