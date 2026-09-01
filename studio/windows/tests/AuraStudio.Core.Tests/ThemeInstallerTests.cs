using System.IO.Compression;
using AuraStudio.Core;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El ciclo completo contra un volumen de mentira: construir, validar,
/// instalar, activar y eliminar.
///
/// <para>Dos reglas del repo se prueban acá porque no pueden depender de que
/// la pantalla se acuerde: <b>se valida antes de instalar, nunca después</b>, y
/// <b>un tema de uso personal nunca se exporta</b> (ST-003).</para>
/// </summary>
public sealed class ThemeInstallerTests : IDisposable
{
    private readonly string _volume = Path.Combine(Path.GetTempPath(), "aura-tema-vol-" + Guid.NewGuid().ToString("N"));
    private readonly string _work = Path.Combine(Path.GetTempPath(), "aura-tema-src-" + Guid.NewGuid().ToString("N"));

    public ThemeInstallerTests()
    {
        Directory.CreateDirectory(_volume);
        Directory.CreateDirectory(_work);
    }

    public void Dispose()
    {
        foreach (string directory in (string[])[_volume, _work])
            try { Directory.Delete(directory, recursive: true); } catch (IOException) { }
    }

    // MARK: - Ayudas

    /// <summary>
    /// Una carpeta con el layout que produce el design-system del firmware: las
    /// 14 fuentes y las 801 máscaras. El contenido no importa —el validador
    /// solo comprueba que estén— pero el conteo sí, y es justo lo que hay que
    /// probar.
    /// </summary>
    private string AssetsFolder(int maskCount = ThemeFormat.RequiredMaskCount, bool allFonts = true)
    {
        string root = Path.Combine(_work, "assets-" + Guid.NewGuid().ToString("N")[..8]);

        string fonts = Path.Combine(root, "fonts");
        Directory.CreateDirectory(fonts);

        foreach ((string role, int px) in allFonts ? ThemeFormat.FontRoles : ThemeFormat.FontRoles[..10])
            File.WriteAllText(Path.Combine(fonts, $"a26-{role}-{px}.fnt"), "fuente");

        string masks = Path.Combine(root, "icons", "masks");
        Directory.CreateDirectory(masks);

        for (int i = 0; i < maskCount; i++)
            File.WriteAllText(Path.Combine(masks, $"m{i:0000}.bmp"), "mascara");

        return root;
    }

    private static AuraThemeManifest Manifest(string id, string name, bool restricted = false) =>
        new(id: id, name: name, author: "Ricardo",
            license: restricted ? ThemeLicense.Personal : ThemeLicense.Open,
            redistributable: !restricted);

    private string ThemeDirectory(string id) =>
        Path.Combine(_volume, ".rockbox", "aura", "themes", id);

    private void SetFirmwareThemeFormat(int format)
    {
        string path = Path.Combine(_volume, ".rockbox", "aura", "aura.cfg");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, $"theme_format_supported: {format}\n");
    }

    // MARK: - El ciclo completo

    [Fact]
    public async Task BuildInstallActivateAndRemove()
    {
        AuraThemeManifest installed = await ThemeInstaller.BuildAndInstall(
            _volume, AssetsFolder(), Manifest("apple-personal", "Apple"));

        Assert.Equal("apple-personal", installed.Id);
        Assert.True(File.Exists(Path.Combine(ThemeDirectory("apple-personal"), "theme.cfg")));

        // Aparece en la lista y se puede cargar.
        InstalledTheme listed = Assert.Single(await ThemeInstaller.ListInstalled(_volume));
        Assert.Equal("Apple", listed.Name);
        Assert.True(listed.Loadable);
        Assert.Null(listed.Reason);

        // Antes de activarlo, el activo es el integrado del firmware.
        Assert.Equal("default", ThemeInstaller.ActiveThemeId(_volume));

        await ThemeInstaller.Activate(_volume, "apple-personal");
        Assert.Equal("apple-personal", ThemeInstaller.ActiveThemeId(_volume));

        Assert.True(await ThemeInstaller.Uninstall(_volume, "apple-personal"));
        Assert.Empty(await ThemeInstaller.ListInstalled(_volume));
        Assert.False(Directory.Exists(ThemeDirectory("apple-personal")));
    }

    [Fact]
    public async Task ActivatingKeepsEveryOtherFirmwareSetting()
    {
        string path = Path.Combine(_volume, ".rockbox", "aura", "aura.cfg");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "volume: -25\naccent_rgb24: 4283215696\n");

        await ThemeInstaller.Activate(_volume, "aura");

        string result = File.ReadAllText(path);
        Assert.Contains("volume: -25", result);
        Assert.Contains("accent_rgb24: 4283215696", result);
        Assert.Equal("aura", ThemeInstaller.ActiveThemeId(_volume));
    }

    // MARK: - Se valida ANTES de instalar

    [Fact]
    public async Task AThemeMissingFontsNeverTouchesTheDevice()
    {
        string package = Path.Combine(_work, "roto");
        await ThemeInstaller.BuildAndInstall(_volume, AssetsFolder(), Manifest("bueno", "Bueno"));

        // Un paquete al que le faltan fuentes.
        Directory.CreateDirectory(package);
        File.WriteAllText(Path.Combine(package, "theme.cfg"), Manifest("roto", "Roto").Serialized());

        ThemeInstallException error = await Assert.ThrowsAsync<ThemeInstallException>(
            () => ThemeInstaller.Install(_volume, package));

        Assert.Contains("fuente", error.Message);
        Assert.False(Directory.Exists(ThemeDirectory("roto")));

        // Y el que ya estaba sigue intacto.
        Assert.Single(await ThemeInstaller.ListInstalled(_volume));
    }

    [Fact]
    public async Task AThemeMadeForANewerFirmwareSaysSoAndOffersTheFix()
    {
        SetFirmwareThemeFormat(1);

        string package = Path.Combine(_work, "futuro");
        Directory.CreateDirectory(package);

        AuraThemeManifest manifest = Manifest("futuro", "Del futuro");
        manifest.Format = 99;
        File.WriteAllText(Path.Combine(package, "theme.cfg"), manifest.Serialized());

        ThemeInstallException error = await Assert.ThrowsAsync<ThemeInstallException>(
            () => ThemeInstaller.Install(_volume, package));

        Assert.Contains("Actualiza el firmware", error.Message);
    }

    [Fact]
    public async Task AFolderThatIsNotDesignSystemOutputSaysWhatIsMissing()
    {
        // "No se pudo" no le sirve a nadie: el mensaje nombra el archivo que
        // falta y de dónde sale.
        ThemeInstallException error = await Assert.ThrowsAsync<ThemeInstallException>(
            () => ThemeInstaller.BuildAndInstall(_volume, Path.Combine(_work, "no-existe"), Manifest("x", "X")));

        Assert.Contains("fuente", error.Message);
        Assert.Contains("design-system", error.Message);
    }

    [Fact]
    public async Task ANameThatDoesNotProduceAValidIdIsRefusedBeforeBuildingAnything()
    {
        await Assert.ThrowsAsync<ThemeInstallException>(
            () => ThemeInstaller.BuildAndInstall(_volume, AssetsFolder(), Manifest("", "")));

        // "default" es el tema compilado del firmware: taparlo dejaría al
        // usuario sin a dónde volver.
        await Assert.ThrowsAsync<ThemeInstallException>(
            () => ThemeInstaller.BuildAndInstall(_volume, AssetsFolder(), Manifest("default", "Default")));
    }

    // MARK: - Un tema que no carga se muestra igual

    [Fact]
    public async Task ABrokenThemeIsListedWithItsReasonInsteadOfHidden()
    {
        // Copiado a mano al iPod, sin fuentes. Esconderlo dejaría al usuario sin
        // entender por qué no aparece.
        string directory = ThemeDirectory("copiado");
        Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory, "theme.cfg"), Manifest("copiado", "Copiado").Serialized());

        InstalledTheme listed = Assert.Single(await ThemeInstaller.ListInstalled(_volume));

        Assert.False(listed.Loadable);
        Assert.Contains("fuente", listed.Reason);
    }

    [Fact]
    public async Task AFolderThatIsNotAValidIdIsIgnoredEntirely()
    {
        // No la escribió Studio: ni se muestra ni se toca.
        Directory.CreateDirectory(Path.Combine(_volume, ".rockbox", "aura", "themes", "Con Mayúsculas"));

        Assert.Empty(await ThemeInstaller.ListInstalled(_volume));
    }

    // MARK: - Licencia (ST-003)

    [Fact]
    public async Task AnOpenThemeCanBeShared()
    {
        await ThemeInstaller.BuildAndInstall(_volume, AssetsFolder(), Manifest("libre", "Libre"));

        string zip = await ThemeInstaller.Export(_volume, "libre", Path.Combine(_work, "salida"));

        Assert.True(File.Exists(zip));
        using ZipArchive archive = ZipFile.OpenRead(zip);
        Assert.Contains(archive.Entries, entry => entry.FullName == "theme.cfg");
    }

    [Fact]
    public async Task APersonalThemeIsNeverExportedEvenIfSomeoneAsksDirectly()
    {
        // La pantalla deshabilita el botón, pero la regla no puede depender de
        // que la pantalla se acuerde.
        await ThemeInstaller.BuildAndInstall(_volume, AssetsFolder(), Manifest("apple", "Apple", restricted: true));

        ThemeInstallException error = await Assert.ThrowsAsync<ThemeInstallException>(
            () => ThemeInstaller.Export(_volume, "apple", Path.Combine(_work, "salida")));

        Assert.Contains("uso personal", error.Message);
        Assert.False(Directory.Exists(Path.Combine(_work, "salida")));
    }

    [Fact]
    public async Task ThePersonalLicenseSurvivesTheRoundTripToTheDevice()
    {
        await ThemeInstaller.BuildAndInstall(_volume, AssetsFolder(), Manifest("apple", "Apple", restricted: true));

        ThemeValidationResult result = await ThemeInstaller.Validate(ThemeDirectory("apple"), _volume);

        AuraThemeManifest manifest = Assert.IsType<ThemeValidationResult.Success>(result).Manifest;
        Assert.False(manifest.Redistributable);
        Assert.Equal(ThemeLicense.Personal, manifest.License);
    }

    // MARK: - El id nunca sale de su carpeta

    [Theory]
    [InlineData("../../..")]
    [InlineData("..")]
    [InlineData("con/barra")]
    [InlineData("Con Mayúsculas")]
    public async Task AnIdThatCouldEscapeItsFolderIsRefused(string id)
    {
        // Sin esta comprobación, un id con ".." borraría o escribiría fuera de
        // la carpeta de temas del iPod.
        Assert.False(await ThemeInstaller.Uninstall(_volume, id));
        await Assert.ThrowsAsync<ThemeInstallException>(() => ThemeInstaller.Activate(_volume, id));
        await Assert.ThrowsAsync<ThemeInstallException>(
            () => ThemeInstaller.Export(_volume, id, Path.Combine(_work, "salida")));
    }

    [Fact]
    public async Task GoingBackToTheBuiltInThemeIsAllowed()
    {
        // "default" no es un id válido de paquete, pero sí es un destino válido
        // de activación: es a donde se vuelve al eliminar el tema activo.
        await ThemeInstaller.Activate(_volume, "default");

        Assert.Equal("default", ThemeInstaller.ActiveThemeId(_volume));
    }

    [Fact]
    public async Task RemovingSomethingThatIsNotThereIsNotAnError()
    {
        Assert.False(await ThemeInstaller.Uninstall(_volume, "no-esta"));
    }
}
