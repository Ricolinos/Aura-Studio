using AuraStudio.Core;

namespace AuraStudio.App.Services;

/// <summary>
/// Los temas del iPod conectado. Envuelve <c>ThemeValidator</c>,
/// <c>ThemePackager</c> y <c>ThemeActivation</c> del Core, que son los que
/// deciden; acá solo se toca el disco del aparato.
/// </summary>
public interface IThemeService
{
    /// <summary>
    /// Los temas instalados, <b>incluidos los que no cargan</b>, con el motivo.
    /// Esconder uno roto dejaría al usuario sin entender por qué el tema que
    /// copió no aparece. No incluye el tema integrado del firmware: ese lo pone
    /// la pantalla aparte, siempre primero y siempre disponible.
    /// </summary>
    Task<IReadOnlyList<InstalledTheme>> ListInstalledAsync(string volumeRoot);

    /// <summary>
    /// Valida <b>antes</b> de copiar nada — nunca después. Un tema inválido no
    /// llega a tocar el iPod.
    /// </summary>
    Task<AuraThemeManifest> InstallAsync(string volumeRoot, string themePackagePath);

    /// <summary>Construye el paquete desde una carpeta de assets ya generados y lo instala.</summary>
    Task<AuraThemeManifest> BuildAndInstallAsync(string volumeRoot, string sourceFolder, AuraThemeManifest manifest);

    Task<bool> UninstallAsync(string volumeRoot, string themeId);

    /// <summary>El tema que el firmware va a cargar en el próximo arranque.</summary>
    string ActiveThemeId(string volumeRoot);

    Task ActivateAsync(string volumeRoot, string themeId);

    /// <summary>
    /// Guarda una copia del tema como <c>.zip</c> para compartirlo.
    ///
    /// <para><b>Un tema no redistribuible nunca se exporta</b> (ST-003): la
    /// pantalla deshabilita la opción con la explicación a la vista, y acá se
    /// vuelve a verificar por si alguien llega por otro camino.</para>
    /// </summary>
    Task<string> ExportAsync(string volumeRoot, string themeId, string destinationFolder);

    Task<ThemeValidationResult> ValidateAsync(string themePath, string? volumeRoot = null);
}
