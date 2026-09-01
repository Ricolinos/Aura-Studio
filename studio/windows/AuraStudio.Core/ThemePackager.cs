namespace AuraStudio.Core;

// ---------------------------------------------------------------------------
// ThemePackagerException
// ---------------------------------------------------------------------------

/// <summary>
/// Errores que lanza ThemePackager durante el reempaquetado.
/// Equivalente a ThemePackagerError (enum con associated values) en Swift.
/// </summary>
public abstract class ThemePackagerException(string message) : Exception(message)
{
    public sealed class SourceFontMissing(string fileName)
        : ThemePackagerException($"No se encontró {fileName} en la carpeta de origen.")
    {
        public string FileName { get; } = fileName;
    }

    public sealed class SourceMasksMissing()
        : ThemePackagerException("La carpeta de origen no tiene icons/masks/") { }

    public sealed class WriteFailed(string reason)
        : ThemePackagerException($"No se pudo escribir el paquete: {reason}.")
    {
        public string Reason { get; } = reason;
    }
}

// ---------------------------------------------------------------------------
// ThemePackager
// ---------------------------------------------------------------------------

/// <summary>
/// Reempaqueta una carpeta con el layout de design-system/out/ del firmware
/// (fonts/a26-&lt;rol&gt;-&lt;px&gt;.fnt, icons/masks/*.bmp, y opcionalmente
/// icons/{light,dark}/, icons/aura/{backgrounds,tile-icons}/) al formato
/// de tema instalable (CONTRATO-formato-tema.md).
///
/// Fase 2A (PLAN-themes-impl.md Q4): solo reempaqueta assets YA GENERADOS
/// -- no rasteriza fuentes ni iconos desde el sistema del usuario.
/// </summary>
public static class ThemePackager
{
    public static void Package(
        string sourceRoot,
        AuraThemeManifest manifest,
        string destinationRoot)
    {
        if (Directory.Exists(destinationRoot))
            Directory.Delete(destinationRoot, recursive: true);

        Directory.CreateDirectory(destinationRoot);

        var fontsOut = Path.Combine(destinationRoot, "fonts");
        Directory.CreateDirectory(fontsOut);

        foreach (var (role, px) in ThemeFormat.FontRoles)
        {
            var sourceName = $"a26-{role}-{px}.fnt";
            var sourcePath = Path.Combine(sourceRoot, "fonts", sourceName);
            if (!File.Exists(sourcePath))
                throw new ThemePackagerException.SourceFontMissing(sourceName);

            File.Copy(sourcePath, Path.Combine(fontsOut, $"{role}.fnt"), overwrite: true);
        }

        var masksSource = Path.Combine(sourceRoot, "icons", "masks");
        if (!Directory.Exists(masksSource))
            throw new ThemePackagerException.SourceMasksMissing();

        CopyDirectory(masksSource, Path.Combine(destinationRoot, "icons", "masks"));

        CopyDirectoryIfPresent(
            Path.Combine(sourceRoot, "icons", "light"),
            Path.Combine(destinationRoot, "icons", "light"));

        CopyDirectoryIfPresent(
            Path.Combine(sourceRoot, "icons", "dark"),
            Path.Combine(destinationRoot, "icons", "dark"));

        CopyDirectoryIfPresent(
            Path.Combine(sourceRoot, "icons", "aura", "backgrounds"),
            Path.Combine(destinationRoot, "backgrounds"));

        CopyDirectoryIfPresent(
            Path.Combine(sourceRoot, "icons", "aura", "tile-icons"),
            Path.Combine(destinationRoot, "tile-icons"));

        var manifestPath = Path.Combine(destinationRoot, "theme.cfg");
        try
        {
            File.WriteAllText(manifestPath, manifest.Serialized());
        }
        catch (Exception ex)
        {
            throw new ThemePackagerException.WriteFailed(ex.Message);
        }
    }

    // -----------------------------------------------------------------------
    // Helpers privados
    // -----------------------------------------------------------------------

    private static void CopyDirectoryIfPresent(string source, string destination)
    {
        if (!Directory.Exists(source)) return;
        CopyDirectory(source, destination);
    }

    private static void CopyDirectory(string source, string destination)
    {
        var parentDir = Path.GetDirectoryName(destination);
        if (parentDir is not null)
            Directory.CreateDirectory(parentDir);

        if (Directory.Exists(destination))
            Directory.Delete(destination, recursive: true);

        CopyDirectoryRecursive(source, destination);
    }

    private static void CopyDirectoryRecursive(string source, string destination)
    {
        Directory.CreateDirectory(destination);

        foreach (var file in Directory.GetFiles(source))
        {
            var destFile = Path.Combine(destination, Path.GetFileName(file));
            File.Copy(file, destFile, overwrite: true);
        }

        foreach (var dir in Directory.GetDirectories(source))
        {
            var destDir = Path.Combine(destination, Path.GetFileName(dir));
            CopyDirectoryRecursive(dir, destDir);
        }
    }
}
