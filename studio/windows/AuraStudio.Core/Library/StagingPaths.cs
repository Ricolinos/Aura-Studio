namespace AuraStudio.Core.Library;

/// <summary>
/// Dónde va lo preparado: el <c>.mpg</c> transcodificado, la foto
/// redimensionada, el audio comprimido.
///
/// <para><c>.preparados/</c> es una carpeta <b>plana</b> compartida por toda la
/// biblioteca y nombrada por el nombre del archivo de origen. Por eso hay que
/// desambiguar: dos canciones distintas que se llamen igual —justo el caso de
/// los duplicados— compartirían el mismo preparado, y borrar uno dejaría al
/// otro apuntando a un archivo que no existe (ST-064).</para>
///
/// <para><b>Esta carpeta nunca se limpia</b>: es la reconstrucción latente de
/// la biblioteca, con los archivos ya convertidos y sus etiquetas escritas.</para>
/// </summary>
public static class StagingPaths
{
    /// <summary>
    /// La ruta para un elemento nuevo, o la que ya tenía si ese archivo sigue
    /// ahí — reprocesar algo no puede dejarle un preparado nuevo y abandonar el
    /// anterior.
    /// </summary>
    /// <param name="exists">
    /// Si una ruta ya está ocupada. Se inyecta para poder probar la
    /// desambiguación sin escribir archivos.
    /// </param>
    public static string Resolve(
        string stagingDirectory, string baseName, string extension,
        string? existingPrepared = null, Func<string, bool>? exists = null)
    {
        exists ??= File.Exists;

        if (existingPrepared is { Length: > 0 } existing && exists(existing)) return existing;

        string suffix = extension.Length == 0 ? "" : "." + extension.TrimStart('.');
        string candidate = Path.Combine(stagingDirectory, baseName + suffix);

        for (int counter = 2; exists(candidate); counter++)
            candidate = Path.Combine(stagingDirectory, $"{baseName} {counter}{suffix}");

        return candidate;
    }
}
