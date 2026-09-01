using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Arma un paquete de tema MINIMO pero completo (14 fuentes vacías + 801
/// máscaras vacías -- ThemeValidator solo comprueba existencia y cantidad)
/// bajo un directorio temporal.
/// </summary>
public class ThemeValidatorTests : IDisposable
{
    private readonly List<string> _tempRoots = [];

    public void Dispose()
    {
        foreach (var root in _tempRoots)
        {
            try { Directory.Delete(root, recursive: true); }
            catch { /* no nos importa si ya no existe */ }
        }
        _tempRoots.Clear();
    }

    private string Fixture(string path)
    {
        _tempRoots.Add(path);
        return path;
    }

    private static string MakeTempDir(string prefix) =>
        Path.Combine(Path.GetTempPath(), $"{prefix}-{Guid.NewGuid()}");

    private static string MakeCompletePackage(
        string id = "fixture-tema",
        string name = "Fixture",
        int format = ThemeFormat.Current,
        int omitMasks = 0,
        string[]? omitFontRoles = null)
    {
        var root = MakeTempDir("ThemeFixture");
        var fontsDir = Path.Combine(root, "fonts");
        var masksDir = Path.Combine(root, "icons", "masks");
        Directory.CreateDirectory(fontsDir);
        Directory.CreateDirectory(masksDir);

        var omit = omitFontRoles ?? [];
        foreach (var (role, _) in ThemeFormat.FontRoles)
        {
            if (!omit.Contains(role))
                File.WriteAllText(Path.Combine(fontsDir, $"{role}.fnt"), "fake");
        }

        var written = 0;
        var required = ThemeFormat.RequiredMaskCount - omitMasks;
        for (var key = 0; key < ThemeFormat.IconKeyCount && written < required; key++)
        {
            foreach (var size in ThemeFormat.IconSizes)
            {
                if (written >= required) break;
                File.WriteAllText(Path.Combine(masksDir, $"icon{key}-{size}.bmp"), "m");
                written++;
            }
        }

        var manifest = $"theme_format: {format}\ntheme_id: {id}\ntheme_name: {name}\n";
        File.WriteAllText(Path.Combine(root, "theme.cfg"), manifest);

        return root;
    }

    // ------------------------------------------------------------------ //
    // Tests
    // ------------------------------------------------------------------ //

    [Fact]
    public void CompletePackageIsValid()
    {
        var root = Fixture(MakeCompletePackage());
        var result = ThemeValidator.Validate(root, firmwareSupportedFormat: 1);
        var success = Assert.IsType<ThemeValidationResult.Success>(result);
        Assert.Equal("fixture-tema", success.Manifest.Id);
    }

    [Fact]
    public void MissingManifestFails()
    {
        var root = Fixture(MakeTempDir("Empty"));
        Directory.CreateDirectory(root);

        Assert.Equal(
            new ThemeValidationResult.Failure(new ThemeValidationError.ManifestMissing()),
            ThemeValidator.Validate(root, 1));
    }

    [Fact]
    public void FormatNewerThanSupportedFails()
    {
        var root = Fixture(MakeCompletePackage(format: 99));

        Assert.Equal(
            new ThemeValidationResult.Failure(new ThemeValidationError.FormatUnsupported(99, 1)),
            ThemeValidator.Validate(root, 1));
    }

    [Fact]
    public void FormatFallsBackToCurrentWhenFirmwareUnknown()
    {
        var root = Fixture(MakeCompletePackage(format: ThemeFormat.Current));

        var result = ThemeValidator.Validate(root, firmwareSupportedFormat: null);
        Assert.IsType<ThemeValidationResult.Success>(result);
    }

    [Fact]
    public void InvalidIdInManifestFails()
    {
        var root = Fixture(MakeCompletePackage(id: "Con Mayusculas"));

        Assert.Equal(
            new ThemeValidationResult.Failure(new ThemeValidationError.InvalidId("Con Mayusculas")),
            ThemeValidator.Validate(root, 1));
    }

    [Fact]
    public void MissingFontFails()
    {
        var root = Fixture(MakeCompletePackage(omitFontRoles: ["ds_medium_16"]));

        var result = ThemeValidator.Validate(root, 1);
        var failure = Assert.IsType<ThemeValidationResult.Failure>(result);
        var error = Assert.IsType<ThemeValidationError.MissingFonts>(failure.Error);
        Assert.Equal((IEnumerable<string>)new[] { "ds_medium_16" }, error.Roles);
    }

    [Fact]
    public void MissingMasksFails()
    {
        var root = Fixture(MakeCompletePackage(omitMasks: 5));

        var result = ThemeValidator.Validate(root, 1);
        var failure = Assert.IsType<ThemeValidationResult.Failure>(result);
        var error = Assert.IsType<ThemeValidationError.MissingMasks>(failure.Error);
        Assert.Equal(ThemeFormat.RequiredMaskCount, error.Required);
        Assert.Equal(ThemeFormat.RequiredMaskCount - 5, error.Found);
    }
}
