using AuraStudio.Core;

namespace AuraStudio.App.Services;

/// <summary>
/// La costura entre la app y <see cref="ThemeInstaller"/>. Todo lo que decide
/// —validar, activar, exportar, y la regla de licencia— vive en Core, donde el
/// ciclo completo se prueba contra un volumen de mentira, sin un iPod.
/// </summary>
public sealed class ThemeService : IThemeService
{
    public Task<IReadOnlyList<InstalledTheme>> ListInstalledAsync(string volumeRoot) =>
        ThemeInstaller.ListInstalled(volumeRoot);

    public Task<AuraThemeManifest> InstallAsync(string volumeRoot, string themePackagePath) =>
        ThemeInstaller.Install(volumeRoot, themePackagePath);

    public Task<AuraThemeManifest> BuildAndInstallAsync(
        string volumeRoot, string sourceFolder, AuraThemeManifest manifest) =>
        ThemeInstaller.BuildAndInstall(volumeRoot, sourceFolder, manifest);

    public Task<bool> UninstallAsync(string volumeRoot, string themeId) =>
        ThemeInstaller.Uninstall(volumeRoot, themeId);

    public string ActiveThemeId(string volumeRoot) => ThemeInstaller.ActiveThemeId(volumeRoot);

    public Task ActivateAsync(string volumeRoot, string themeId) =>
        ThemeInstaller.Activate(volumeRoot, themeId);

    public Task<string> ExportAsync(string volumeRoot, string themeId, string destinationFolder) =>
        ThemeInstaller.Export(volumeRoot, themeId, destinationFolder);

    public Task<ThemeValidationResult> ValidateAsync(string themePath, string? volumeRoot = null) =>
        ThemeInstaller.Validate(themePath, volumeRoot);
}
