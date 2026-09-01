using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Arma una carpeta con el layout de design-system/out/ del firmware
/// (fonts/a26-&lt;rol&gt;-&lt;px&gt;.fnt, icons/masks/*.bmp, icons/{light,dark}/ y
/// icons/aura/{backgrounds,tile-icons}/ opcionales) -- lo que ThemePackager
/// espera como sourceRoot.
/// </summary>
public class ThemePackagerTests : IDisposable
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

    private string Track(string path)
    {
        _tempRoots.Add(path);
        return path;
    }

    private static string MakeTempDir(string prefix) =>
        Path.Combine(Path.GetTempPath(), $"{prefix}-{Guid.NewGuid()}");

    private static string MakeDesignSystemOut(bool includeOptional = false)
    {
        var root = MakeTempDir("DesignSystemOut");
        var fontsDir = Path.Combine(root, "fonts");
        var masksDir = Path.Combine(root, "icons", "masks");
        Directory.CreateDirectory(fontsDir);
        Directory.CreateDirectory(masksDir);

        foreach (var (role, px) in ThemeFormat.FontRoles)
            File.WriteAllText(Path.Combine(fontsDir, $"a26-{role}-{px}.fnt"), $"fake-{role}");

        File.WriteAllText(Path.Combine(masksDir, "music-12.bmp"), "m");

        if (includeOptional)
        {
            var lightDir = Path.Combine(root, "icons", "light");
            Directory.CreateDirectory(lightDir);
            File.WriteAllText(Path.Combine(lightDir, "music-12.bmp"), "l");

            var backgroundsDir = Path.Combine(root, "icons", "aura", "backgrounds");
            Directory.CreateDirectory(backgroundsDir);
            File.WriteAllText(Path.Combine(backgroundsDir, "pink.bmp"), "p");
        }

        return root;
    }

    // ------------------------------------------------------------------ //
    // Tests
    // ------------------------------------------------------------------ //

    [Fact]
    public void PackageRenamesFontsByRole()
    {
        var source = Track(MakeDesignSystemOut());
        var destination = Track(MakeTempDir("Packaged"));
        var manifest = new AuraThemeManifest(id: "test", name: "Test");

        ThemePackager.Package(source, manifest, destination);

        foreach (var (role, _) in ThemeFormat.FontRoles)
            Assert.True(File.Exists(Path.Combine(destination, "fonts", $"{role}.fnt")),
                $"falta fonts/{role}.fnt");
    }

    [Fact]
    public void PackageCopiesMasksAndWritesManifest()
    {
        var source = Track(MakeDesignSystemOut());
        var destination = Track(MakeTempDir("Packaged"));
        var manifest = new AuraThemeManifest(id: "test", name: "Test",
            license: ThemeLicense.Open, redistributable: true);

        ThemePackager.Package(source, manifest, destination);

        Assert.True(File.Exists(Path.Combine(destination, "icons", "masks", "music-12.bmp")));
        var cfgText = File.ReadAllText(Path.Combine(destination, "theme.cfg"));
        Assert.Contains("theme_id: test", cfgText);
        Assert.Contains("theme_redistributable: yes", cfgText);
    }

    [Fact]
    public void PackageIncludesOptionalAssetsWhenPresent()
    {
        var source = Track(MakeDesignSystemOut(includeOptional: true));
        var destination = Track(MakeTempDir("Packaged"));
        var manifest = new AuraThemeManifest(id: "test", name: "Test");

        ThemePackager.Package(source, manifest, destination);

        Assert.True(File.Exists(Path.Combine(destination, "icons", "light", "music-12.bmp")));
        Assert.True(File.Exists(Path.Combine(destination, "backgrounds", "pink.bmp")));
    }

    [Fact]
    public void PackageSkipsAbsentOptionalAssetsWithoutFailing()
    {
        var source = Track(MakeDesignSystemOut(includeOptional: false));
        var destination = Track(MakeTempDir("Packaged"));
        var manifest = new AuraThemeManifest(id: "test", name: "Test");

        ThemePackager.Package(source, manifest, destination);

        Assert.False(Directory.Exists(Path.Combine(destination, "icons", "light")));
        Assert.False(Directory.Exists(Path.Combine(destination, "icons", "dark")));
        Assert.False(Directory.Exists(Path.Combine(destination, "backgrounds")));
        Assert.False(Directory.Exists(Path.Combine(destination, "tile-icons")));
    }

    [Fact]
    public void MissingSourceFontThrows()
    {
        var source = Track(MakeTempDir("Incomplete"));
        Directory.CreateDirectory(Path.Combine(source, "fonts"));
        Directory.CreateDirectory(Path.Combine(source, "icons", "masks"));
        var destination = Track(MakeTempDir("Packaged"));
        var manifest = new AuraThemeManifest(id: "test", name: "Test");

        var ex = Assert.Throws<ThemePackagerException.SourceFontMissing>(() =>
            ThemePackager.Package(source, manifest, destination));

        Assert.Equal("a26-title-20.fnt", ex.FileName);
    }

    [Fact]
    public void MissingSourceMasksThrows()
    {
        var source = Track(MakeTempDir("NoMasks"));
        var fontsDir = Path.Combine(source, "fonts");
        Directory.CreateDirectory(fontsDir);
        foreach (var (role, px) in ThemeFormat.FontRoles)
            File.WriteAllText(Path.Combine(fontsDir, $"a26-{role}-{px}.fnt"), "");
        var destination = Track(MakeTempDir("Packaged"));
        var manifest = new AuraThemeManifest(id: "test", name: "Test");

        Assert.Throws<ThemePackagerException.SourceMasksMissing>(() =>
            ThemePackager.Package(source, manifest, destination));
    }
}
