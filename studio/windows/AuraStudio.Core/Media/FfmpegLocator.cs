namespace AuraStudio.Core.Media;

/// <summary>
/// Encuentra un ffmpeg instalado en el sistema. Port de <c>FFmpegLocator</c>,
/// con los lugares donde queda en Windows.
///
/// <para><b>ffmpeg no viene embebido</b> (D-038): es un binario grande, con su
/// propia licencia y su propio ciclo de actualizaciones, y embeberlo cambiaría
/// las obligaciones de distribución de la app entera.</para>
/// </summary>
public static class FfmpegLocator
{
    public const string ExecutableName = "ffmpeg.exe";

    /// <summary>
    /// Dónde lo dejan los instaladores más comunes de Windows, en el orden en
    /// que conviene mirarlos. Se resuelven contra las variables de entorno al
    /// consultarlos, no acá, para que el orden se pueda leer de un vistazo.
    /// </summary>
    public static IReadOnlyList<string> CommonPaths(Func<string, string?> environment) =>
    [
        // winget, que es lo que casi todo el mundo va a usar.
        .. Combine(environment("LOCALAPPDATA"), @"Microsoft\WinGet\Links", ExecutableName),
        .. Combine(environment("ProgramFiles"), @"ffmpeg\bin", ExecutableName),
        .. Combine(environment("ProgramData"), @"chocolatey\bin", ExecutableName),
        .. Combine(environment("USERPROFILE"), @"scoop\shims", ExecutableName)
    ];

    /// <summary>
    /// La ruta al ejecutable, o <c>null</c> si no hay ninguno.
    ///
    /// <para><paramref name="configuredPath"/> es lo que el usuario eligió a
    /// mano y gana siempre: alguien que tiene ffmpeg en una carpeta propia no
    /// tiene por qué moverlo para que Studio lo encuentre.</para>
    /// </summary>
    public static string? Locate(
        string? configuredPath = null,
        Func<string, bool>? fileExists = null,
        Func<string, string?>? environment = null)
    {
        fileExists ??= File.Exists;
        environment ??= Environment.GetEnvironmentVariable;

        if (configuredPath is { Length: > 0 } configured && fileExists(configured)) return configured;

        foreach (string candidate in CommonPaths(environment))
            if (fileExists(candidate)) return candidate;

        foreach (string directory in (environment("PATH") ?? "").Split(';', StringSplitOptions.RemoveEmptyEntries))
        {
            string candidate;

            // Una entrada inválida en el PATH —pasa— no puede tirar abajo la
            // búsqueda entera.
            try { candidate = Path.Combine(directory.Trim(), ExecutableName); }
            catch (ArgumentException) { continue; }

            if (fileExists(candidate)) return candidate;
        }

        return null;
    }

    /// <summary>
    /// Qué decirle al usuario cuando no está. Nombra el comando exacto: es más
    /// útil que "instala ffmpeg" y no obliga a nadie a buscarlo.
    /// </summary>
    public const string NotFoundMessage =
        "No se encontró ffmpeg en esta computadora. Instálalo con "
        + "\"winget install Gyan.FFmpeg\", o elige dónde está en Ajustes › Video.";

    private static IEnumerable<string> Combine(string? root, string relativeDirectory, string fileName) =>
        root is { Length: > 0 } ? [Path.Combine(root, relativeDirectory, fileName)] : [];
}
