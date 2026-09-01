using AuraStudio.Core.Networking;

namespace AuraStudio.Core;

/// <summary>Por qué se concluyó que hay (o no hay) actualización. La UI lo dice, no lo adivina.</summary>
public enum UpdateVerdictReason
{
    /// <summary>Se comparó el tag instalado contra el del Release más nuevo conocido.</summary>
    VersionTag,

    /// <summary>Sin tag legible: se comparó el SHA-256 del `rockbox.ipod` instalado contra el local.</summary>
    BinaryHash,

    /// <summary>Hay árbol de la familia pero no se encontró el binario — reinstalar lo arregla.</summary>
    InstalledBinaryMissing,

    /// <summary>No se pudo concluir nada (familia desconocida, sin artefactos, sin volumen).</summary>
    Unknown
}

/// <param name="UpdateAvailable">`false` cuando no se pudo concluir: nunca se ofrece actualizar a ciegas.</param>
public readonly record struct UpdateVerdict(bool UpdateAvailable, UpdateVerdictReason Reason, string? LatestTag = null)
{
    public static UpdateVerdict Unknown { get; } = new(false, UpdateVerdictReason.Unknown);
}

/// <summary>
/// Decide si el firmware instalado en el iPod es más viejo que el que conoce
/// esta copia de Aura Studio.
///
/// Dos criterios, en orden (port de `AuraUpdateChecker` de macOS):
///
/// 1. **Por tag** — `.rockbox/aura/version.txt` (D-290) trae el tag exacto del
///    Release con el que se empaquetó el árbol instalado. Si se puede leer y hay
///    un tag más nuevo conocido, esa es la respuesta.
/// 2. **Por hash del binario** — respaldo sin red, y el único camino para
///    dispositivos instalados antes de que `version.txt` existiera. Compara el
///    SHA-256 del `rockbox.ipod` instalado contra el de los artefactos locales
///    de **la misma familia**.
///
/// El punto 2 se compara siempre **contra la propia familia** (ST-046): comparar
/// el `rockbox.ipod` de Metro contra el de Aura da siempre distinto, o sea
/// "hay actualización" eternamente, o sea ofrecerle sobrescribir Metro con Aura.
/// Una familia de la que no hay artefactos locales devuelve
/// <see cref="UpdateVerdictReason.Unknown"/>: sin binario propio con qué
/// comparar, no comparar es mejor que comparar mal.
/// </summary>
public static class AuraUpdateChecker
{
    /// <summary>
    /// Rutas candidatas del binario instalado, en orden de preferencia: el que
    /// arranca el bootloader es `/.rockbox/rockbox.ipod` (viaja en el árbol
    /// desde D-178); el de la raíz es la copia que el instalador dejaba antes.
    /// </summary>
    public static readonly string[] InstalledRelativePaths = [".rockbox/rockbox.ipod", "rockbox.ipod"];

    /// <summary>
    /// `.rockbox/aura/version.txt` (D-290 en Aura-Firmware): el tag exacto del
    /// Release con el que se empaquetó el `rockbox.zip` instalado, escrito por
    /// `package_dist.sh --release-tag`. El firmware nunca lo lee de vuelta — es
    /// puramente para Studio.
    /// </summary>
    public const string VersionMarkerRelativePath = ".rockbox/aura/version.txt";

    public static string? InstalledVersionTag(string volumeRoot)
    {
        if (string.IsNullOrWhiteSpace(volumeRoot)) return null;
        string path = Combine(volumeRoot, VersionMarkerRelativePath);
        try
        {
            if (!File.Exists(path)) return null;
            string text = File.ReadAllText(path).Trim();
            return text.Length == 0 ? null : text;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    /// <summary>Ruta del `rockbox.ipod` instalado, o `null` si no hay ninguno.</summary>
    public static string? InstalledFirmwareBinary(string volumeRoot)
    {
        if (string.IsNullOrWhiteSpace(volumeRoot)) return null;
        foreach (string relative in InstalledRelativePaths)
        {
            string path = Combine(volumeRoot, relative);
            if (File.Exists(path)) return path;
        }
        return null;
    }

    /// <summary>
    /// Veredicto sin red: tag instalado contra <paramref name="latestKnownTag"/>
    /// (que quien llama saca del caché de Releases, si lo tiene), con respaldo
    /// por hash. <paramref name="latestKnownTag"/> en `null` salta directo al hash.
    /// </summary>
    public static UpdateVerdict Check(string volumeRoot,
                                      FirmwareArtifacts? artifacts,
                                      string? latestKnownTag = null)
    {
        if (string.IsNullOrWhiteSpace(volumeRoot) || !Directory.Exists(volumeRoot))
        {
            return UpdateVerdict.Unknown;
        }

        if (latestKnownTag is { Length: > 0 }
            && InstalledVersionTag(volumeRoot) is { } installedTag
            && SemVer.Parse(installedTag) is { } installed
            && SemVer.Parse(latestKnownTag) is { } latest)
        {
            return new UpdateVerdict(installed < latest, UpdateVerdictReason.VersionTag, latestKnownTag);
        }

        return CompareBinaries(volumeRoot, artifacts);
    }

    /// <summary>
    /// Respaldo por hash contra el binario local de LA MISMA familia. Público
    /// para poder probarlo aislado del camino por tag.
    /// </summary>
    public static UpdateVerdict CompareBinaries(string volumeRoot, FirmwareArtifacts? artifacts)
    {
        if (artifacts is null || !File.Exists(artifacts.RockboxImage))
        {
            return UpdateVerdict.Unknown;
        }

        string? installedPath = InstalledFirmwareBinary(volumeRoot);
        if (installedPath is null)
        {
            // Familia detectada pero sin binario a la vista (árbol a medio
            // copiar): eso lo arregla reinstalar, así que cuenta como
            // actualización disponible.
            return new UpdateVerdict(true, UpdateVerdictReason.InstalledBinaryMissing, artifacts.ReleaseTag);
        }

        try
        {
            string local = FirmwareArtifactVerifier.Sha256Hex(artifacts.RockboxImage);
            string installed = FirmwareArtifactVerifier.Sha256Hex(installedPath);
            return new UpdateVerdict(!string.Equals(local, installed, StringComparison.OrdinalIgnoreCase),
                                     UpdateVerdictReason.BinaryHash,
                                     artifacts.ReleaseTag);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return UpdateVerdict.Unknown;
        }
    }

    private static string Combine(string volumeRoot, string relative)
        => Path.Combine(volumeRoot, relative.Replace('/', Path.DirectorySeparatorChar));
}
