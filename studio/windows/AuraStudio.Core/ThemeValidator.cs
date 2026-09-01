namespace AuraStudio.Core;

// ---------------------------------------------------------------------------
// ThemeValidationError
// ---------------------------------------------------------------------------

/// <summary>
/// Errores de validación de un paquete de tema.
/// Equivalente a ThemeValidationError (enum con associated values) en Swift.
/// Usa records anidados para conservar igualdad por valor.
/// </summary>
public abstract record ThemeValidationError
{
    public sealed record ManifestMissing : ThemeValidationError;
    public sealed record ManifestUnreadable : ThemeValidationError;
    public sealed record InvalidId(string Id) : ThemeValidationError;
    public sealed record FormatUnsupported(int Found, int Supported) : ThemeValidationError;
    public sealed record MissingFonts(IReadOnlyList<string> Roles) : ThemeValidationError;
    public sealed record MissingMasks(int Found, int Required) : ThemeValidationError;
}

// ---------------------------------------------------------------------------
// ThemeValidationResult
// ---------------------------------------------------------------------------

/// <summary>
/// Resultado de ThemeValidator.Validate -- Success o Failure, con igualdad
/// por valor (record) para que los tests puedan comparar directamente.
/// </summary>
public abstract record ThemeValidationResult
{
    public sealed record Success(AuraThemeManifest Manifest) : ThemeValidationResult;
    public sealed record Failure(ThemeValidationError Error) : ThemeValidationResult;
}

// ---------------------------------------------------------------------------
// ThemeValidator
// ---------------------------------------------------------------------------

/// <summary>
/// Valida un paquete YA en el layout del contrato (theme.cfg + fonts/ +
/// icons/masks/ bajo packageRoot). Equivalente a ThemeValidator (enum con
/// métodos estáticos que retornan Result) en Swift.
/// </summary>
public static class ThemeValidator
{
    /// <summary>
    /// Valida un paquete de tema. firmwareSupportedFormat: lo que reportó
    /// el iPod montado (aura.cfg -> theme_format_supported); null si no se
    /// pudo leer -- en ese caso se compara contra ThemeFormat.Current como
    /// mejor esfuerzo.
    /// </summary>
    public static ThemeValidationResult Validate(string packageRoot, int? firmwareSupportedFormat)
    {
        var manifestPath = Path.Combine(packageRoot, "theme.cfg");
        if (!File.Exists(manifestPath))
            return new ThemeValidationResult.Failure(new ThemeValidationError.ManifestMissing());

        string text;
        try
        {
            text = File.ReadAllText(manifestPath);
        }
        catch
        {
            return new ThemeValidationResult.Failure(new ThemeValidationError.ManifestUnreadable());
        }

        var manifest = AuraThemeManifest.Parse(text);
        if (manifest is null)
            return new ThemeValidationResult.Failure(new ThemeValidationError.ManifestUnreadable());

        if (!AuraThemeID.IsValid(manifest.Id))
            return new ThemeValidationResult.Failure(new ThemeValidationError.InvalidId(manifest.Id));

        var supported = firmwareSupportedFormat ?? ThemeFormat.Current;
        if (manifest.Format > supported)
            return new ThemeValidationResult.Failure(
                new ThemeValidationError.FormatUnsupported(manifest.Format, supported));

        // Verificar las 14 fuentes (solo existencia, no cabecera binaria).
        var fontsDir = Path.Combine(packageRoot, "fonts");
        var missingFonts = ThemeFormat.FontRoles
            .Select(fr => fr.Role)
            .Where(role => !File.Exists(Path.Combine(fontsDir, $"{role}.fnt")))
            .ToList();

        if (missingFonts.Count > 0)
            return new ThemeValidationResult.Failure(
                new ThemeValidationError.MissingFonts(missingFonts));

        // Verificar las 801 mascaras.
        var masksDir = Path.Combine(packageRoot, "icons", "masks");
        int maskCount;
        if (Directory.Exists(masksDir))
        {
            maskCount = Directory.GetFiles(masksDir)
                .Count(f => f.EndsWith(".bmp", StringComparison.Ordinal));
        }
        else
        {
            maskCount = 0;
        }

        if (maskCount < ThemeFormat.RequiredMaskCount)
            return new ThemeValidationResult.Failure(
                new ThemeValidationError.MissingMasks(maskCount, ThemeFormat.RequiredMaskCount));

        return new ThemeValidationResult.Success(manifest);
    }
}
