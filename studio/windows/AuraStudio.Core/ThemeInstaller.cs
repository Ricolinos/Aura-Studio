using System.IO.Compression;


namespace AuraStudio.Core;

/// <summary>Algo que el usuario tiene que leer: el motivo ya viene en español.</summary>
public sealed class ThemeInstallException(string message) : Exception(message);

/// <summary>
/// Los temas del iPod. Port de <c>ThemeInstaller.swift</c>.
///
/// <para>Dos reglas del repo se cumplen en cada método y no dependen de que la
/// pantalla se acuerde: <b>se valida antes de instalar, nunca después</b>, y
/// <b>el id pasa por <see cref="AuraThemeID.IsValid"/> antes de tocar
/// cualquier ruta que lo contenga</b> — un id con <c>..</c> o con barras
/// escribiría fuera de la carpeta de temas.</para>
/// </summary>
public static class ThemeInstaller
{
    public const string ThemesRelativeDir = ".rockbox/aura/themes";

    public static Task<IReadOnlyList<InstalledTheme>> ListInstalled(string volumeRoot) =>
        Task.Run<IReadOnlyList<InstalledTheme>>(() =>
        {
            string root = Path.Combine(volumeRoot, ToNative(ThemesRelativeDir));
            if (!Directory.Exists(root)) return [];

            int? supported = FirmwareCapabilities.SupportedThemeFormat(volumeRoot);
            var themes = new List<InstalledTheme>();

            foreach (string directory in Directory.GetDirectories(root).OrderBy(path => path, StringComparer.Ordinal))
            {
                string id = Path.GetFileName(directory);

                // Una carpeta con un nombre que no es un id válido no la
                // escribió Studio: no se toca ni se muestra.
                if (!AuraThemeID.IsValid(id)) continue;

                themes.Add(ThemeValidator.Validate(directory, supported) switch
                {
                    ThemeValidationResult.Success success =>
                        new InstalledTheme(id, success.Manifest.Name.Length == 0 ? id : success.Manifest.Name, true),
                    ThemeValidationResult.Failure failure =>
                        new InstalledTheme(id, id, false, Describe(failure.Error)),
                    _ => new InstalledTheme(id, id, false, "No se pudo revisar el tema.")
                });
            }

            return themes;
        });

    public static async Task<AuraThemeManifest> Install(string volumeRoot, string themePackagePath)
    {
        ThemeValidationResult result = ThemeValidator.Validate(
            themePackagePath, FirmwareCapabilities.SupportedThemeFormat(volumeRoot));

        if (result is not ThemeValidationResult.Success success)
        {
            string reason = result is ThemeValidationResult.Failure failure
                ? Describe(failure.Error)
                : "No se pudo revisar el tema.";

            throw new ThemeInstallException($"Ese tema no se puede instalar: {reason}");
        }

        string destination = ThemeDirectory(volumeRoot, success.Manifest.Id);

        await Task.Run(() =>
        {
            if (Directory.Exists(destination)) Directory.Delete(destination, recursive: true);
            CopyDirectory(themePackagePath, destination);
        }).ConfigureAwait(false);

        return success.Manifest;
    }

    public static async Task<AuraThemeManifest> BuildAndInstall(
        string volumeRoot, string sourceFolder, AuraThemeManifest manifest)
    {
        if (!AuraThemeID.IsValid(manifest.Id))
            throw new ThemeInstallException($"Ese nombre no produce un id de tema válido: \"{manifest.Id}\".");

        string temporary = Path.Combine(Path.GetTempPath(), "AuraThemeBuild-" + Guid.NewGuid().ToString("N"));

        try
        {
            await Task.Run(() => ThemePackager.Package(sourceFolder, manifest, temporary)).ConfigureAwait(false);
            return await Install(volumeRoot, temporary).ConfigureAwait(false);
        }
        catch (ThemePackagerException ex)
        {
            throw new ThemeInstallException(Describe(ex));
        }
        finally
        {
            try { if (Directory.Exists(temporary)) Directory.Delete(temporary, recursive: true); }
            catch (IOException) { }
        }
    }

    public static Task<bool> Uninstall(string volumeRoot, string themeId) =>
        Task.Run(() =>
        {
            if (!AuraThemeID.IsValid(themeId)) return false;

            string directory = ThemeDirectory(volumeRoot, themeId);
            if (!Directory.Exists(directory)) return false;

            try { Directory.Delete(directory, recursive: true); return true; }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { return false; }
        });

    public static string ActiveThemeId(string volumeRoot)
    {
        string path = Path.Combine(volumeRoot, ToNative(ThemeActivation.AuraConfigRelativePath));

        try
        {
            return ThemeActivation.ActiveThemeId(File.Exists(path) ? File.ReadAllText(path) : null);
        }
        catch (IOException)
        {
            return ThemeActivation.DefaultThemeId;
        }
    }

    public static Task Activate(string volumeRoot, string themeId) =>
        Task.Run(() =>
        {
            if (themeId != ThemeActivation.DefaultThemeId && !AuraThemeID.IsValid(themeId))
                throw new ThemeInstallException($"Id de tema inválido: {themeId}");

            string path = Path.Combine(volumeRoot, ToNative(ThemeActivation.AuraConfigRelativePath));
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);

            string? current = File.Exists(path) ? File.ReadAllText(path) : null;
            string updated = ThemeActivation.WithActiveTheme(current, themeId);

            // `aura.cfg` son los ajustes del usuario: se escribe a un temporal y
            // se reemplaza, para que un corte no deje el archivo a medias.
            string temporary = path + ".tmp";
            File.WriteAllText(temporary, updated, new System.Text.UTF8Encoding(false));
            File.Move(temporary, path, overwrite: true);
        });

    public static Task<string> Export(string volumeRoot, string themeId, string destinationFolder) =>
        Task.Run(() =>
        {
            if (!AuraThemeID.IsValid(themeId))
                throw new ThemeInstallException($"Id de tema inválido: {themeId}");

            string source = ThemeDirectory(volumeRoot, themeId);
            if (!Directory.Exists(source))
                throw new ThemeInstallException("Ese tema ya no está en el iPod.");

            if (ThemeValidator.Validate(source, null) is not ThemeValidationResult.Success success)
                throw new ThemeInstallException("Ese tema no se puede leer para exportarlo.");

            // ST-003: Studio construye temas, no los distribuye. Un tema hecho
            // con material de licencia restringida no sale de la computadora
            // de quien lo armó, y esto no depende de que la pantalla se acuerde
            // de deshabilitar el botón.
            if (!success.Manifest.Redistributable)
                throw new ThemeInstallException(
                    $"\"{success.Manifest.Name}\" está marcado como de uso personal: no se puede compartir.");

            Directory.CreateDirectory(destinationFolder);

            string destination = Path.Combine(destinationFolder, themeId + ".zip");
            if (File.Exists(destination)) File.Delete(destination);

            ZipFile.CreateFromDirectory(source, destination, CompressionLevel.Optimal, includeBaseDirectory: false);

            return destination;
        });

    public static Task<ThemeValidationResult> Validate(string themePath, string? volumeRoot = null) =>
        Task.Run(() => ThemeValidator.Validate(
            themePath,
            // Sin iPod conectado se compara contra el formato que Studio conoce:
            // es lo mejor que se puede saber sin preguntarle al firmware.
            volumeRoot is { Length: > 0 } ? FirmwareCapabilities.SupportedThemeFormat(volumeRoot) : null));

    // MARK: - Mensajes

    /// <summary>
    /// En español y diciendo qué hacer. Un error de validación que solo dijera
    /// "MissingFonts" no le sirve a nadie.
    /// </summary>
    private static string Describe(ThemeValidationError error) => error switch
    {
        ThemeValidationError.ManifestMissing => "le falta el archivo theme.cfg.",
        ThemeValidationError.ManifestUnreadable => "su theme.cfg no se puede leer.",
        ThemeValidationError.InvalidId invalid => $"su id no es válido: \"{invalid.Id}\".",
        ThemeValidationError.FormatUnsupported format =>
            $"está hecho para la versión {format.Found} del formato y este firmware entiende hasta la "
            + $"{format.Supported}. Actualiza el firmware del iPod.",
        ThemeValidationError.MissingFonts fonts =>
            $"le faltan {fonts.Roles.Count} fuente(s): {string.Join(", ", fonts.Roles)}.",
        ThemeValidationError.MissingMasks masks =>
            $"tiene {masks.Found} máscaras de ícono y hacen falta {masks.Required}.",
        _ => "no pasó la revisión."
    };

    private static string Describe(ThemePackagerException exception) => exception switch
    {
        ThemePackagerException.SourceFontMissing font =>
            $"En la carpeta de assets falta la fuente {font.FileName}. "
            + "Genérala con el design-system del firmware antes de construir el tema.",
        ThemePackagerException.SourceMasksMissing =>
            "En la carpeta de assets falta icons/masks/, que es donde viven las máscaras de los íconos.",
        ThemePackagerException.WriteFailed failed => $"No se pudo escribir el tema: {failed.Reason}",
        _ => exception.Message
    };

    private static string ThemeDirectory(string volumeRoot, string themeId) =>
        Path.Combine(volumeRoot, ToNative(ThemesRelativeDir), themeId);

    private static string ToNative(string relativePath) =>
        relativePath.Replace('/', Path.DirectorySeparatorChar);

    private static void CopyDirectory(string source, string destination)
    {
        Directory.CreateDirectory(destination);

        foreach (string file in Directory.GetFiles(source))
            File.Copy(file, Path.Combine(destination, Path.GetFileName(file)), overwrite: true);

        foreach (string directory in Directory.GetDirectories(source))
            CopyDirectory(directory, Path.Combine(destination, Path.GetFileName(directory)));
    }
}
