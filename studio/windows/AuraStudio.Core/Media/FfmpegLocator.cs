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

    /// <summary>Donde winget desempaqueta lo que instala, relativo a <c>LOCALAPPDATA</c>.</summary>
    public const string WinGetPackagesDirectory = @"Microsoft\WinGet\Packages";

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
    /// El ffmpeg que winget dejó <b>desempaquetado</b>, dentro de la carpeta del
    /// paquete.
    ///
    /// <para><b>Por qué hace falta mirar acá también.</b> Lo normal es que winget
    /// deje un atajo en <c>WinGet\Links</c>, y eso ya lo cubre
    /// <see cref="CommonPaths"/>. Pero ese atajo no siempre aparece —el paquete
    /// no declara alias, la instalación fue de máquina y no de usuario, o el
    /// <c>Links</c> quedó fuera del PATH— y entonces el ffmpeg <b>está instalado
    /// y Studio decía que no</b>, mandando al usuario a instalar de nuevo algo
    /// que ya tenía.</para>
    ///
    /// <para>La ruta real es
    /// <c>…\WinGet\Packages\Gyan.FFmpeg_…\ffmpeg-7.1-full_build\bin\ffmpeg.exe</c>:
    /// una carpeta por paquete y adentro una por versión, con el nombre que trae
    /// el zip. Por eso hay que <b>listar</b>, no adivinar la ruta — y se listan
    /// de más nueva a más vieja, comparando los números como números
    /// (<c>ffmpeg-10</c> es más nuevo que <c>ffmpeg-7</c>, aunque
    /// alfabéticamente vaya antes).</para>
    ///
    /// <para>Se acepta cualquier paquete cuyo nombre mencione ffmpeg, no solo
    /// <c>Gyan.FFmpeg</c>: hay más de un publicador. Un falso positivo no cuesta
    /// nada, porque solo se devuelve si el ejecutable existe de verdad.</para>
    /// </summary>
    public static IEnumerable<string> WinGetPackagePaths(
        Func<string, string?> environment,
        Func<string, IEnumerable<string>>? enumerateDirectories = null)
    {
        enumerateDirectories ??= SafeDirectories;

        if (environment("LOCALAPPDATA") is not { Length: > 0 } local) yield break;

        string packages = Path.Combine(local, WinGetPackagesDirectory);

        foreach (string package in NewestFirst(enumerateDirectories(packages)))
        {
            if (!Path.GetFileName(package).Contains("ffmpeg", StringComparison.OrdinalIgnoreCase)) continue;

            // Algún paquete deja el `bin` colgando directo del paquete.
            yield return Path.Combine(package, "bin", ExecutableName);

            foreach (string build in NewestFirst(enumerateDirectories(package)))
                yield return Path.Combine(build, "bin", ExecutableName);
        }
    }

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
        Func<string, string?>? environment = null,
        Func<string, IEnumerable<string>>? enumerateDirectories = null)
    {
        fileExists ??= File.Exists;
        environment ??= Environment.GetEnvironmentVariable;

        if (configuredPath is { Length: > 0 } configured && fileExists(configured)) return configured;

        foreach (string candidate in CommonPaths(environment))
            if (fileExists(candidate)) return candidate;

        // Después de los atajos y antes del PATH: listar carpetas cuesta más que
        // preguntar por una ruta fija, y solo hace falta cuando el atajo de
        // winget no está.
        foreach (string candidate in WinGetPackagePaths(environment, enumerateDirectories))
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

    /// <summary>
    /// Las carpetas que hay, o ninguna. Una carpeta que no existe —el caso
    /// normal en una máquina sin winget— no es un error que tenga que ver nadie.
    ///
    /// <para>Se materializa adentro del <c>try</c> porque
    /// <see cref="Directory.EnumerateDirectories(string)"/> es perezoso: si no,
    /// la excepción saldría al recorrer, ya fuera de acá.</para>
    /// </summary>
    private static IEnumerable<string> SafeDirectories(string path)
    {
        try
        {
            return Directory.EnumerateDirectories(path).ToArray();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            return [];
        }
    }

    private static IEnumerable<string> NewestFirst(IEnumerable<string> directories) =>
        directories.OrderByDescending(Path.GetFileName, NaturalOrder.Instance);

    /// <summary>
    /// Ordena comparando los números como números. Sin esto, <c>ffmpeg-10.0</c>
    /// quedaría por debajo de <c>ffmpeg-7.1</c> y Studio elegiría la versión
    /// vieja de alguien que tiene las dos.
    /// </summary>
    private sealed class NaturalOrder : IComparer<string?>
    {
        public static readonly NaturalOrder Instance = new();

        public int Compare(string? left, string? right)
        {
            string a = left ?? "";
            string b = right ?? "";
            int i = 0, j = 0;

            while (i < a.Length && j < b.Length)
            {
                if (char.IsDigit(a[i]) && char.IsDigit(b[j]))
                {
                    int startA = i, startB = j;
                    while (i < a.Length && char.IsDigit(a[i])) i++;
                    while (j < b.Length && char.IsDigit(b[j])) j++;

                    ReadOnlySpan<char> numberA = a.AsSpan(startA, i - startA).TrimStart('0');
                    ReadOnlySpan<char> numberB = b.AsSpan(startB, j - startB).TrimStart('0');

                    // Más dígitos es más grande; con la misma cantidad manda el
                    // orden de texto, que para dígitos es el numérico.
                    if (numberA.Length != numberB.Length) return numberA.Length - numberB.Length;

                    int digits = numberA.CompareTo(numberB, StringComparison.Ordinal);
                    if (digits != 0) return digits;
                }
                else
                {
                    int letters = char.ToLowerInvariant(a[i]).CompareTo(char.ToLowerInvariant(b[j]));
                    if (letters != 0) return letters;

                    i++;
                    j++;
                }
            }

            return (a.Length - i) - (b.Length - j);
        }
    }
}
