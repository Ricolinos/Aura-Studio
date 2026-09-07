namespace AuraStudio.Core.Library;

/// <summary>
/// Encuentra en disco el archivo que el catálogo dice, incluso cuando una
/// carpeta de la biblioteca la creó la Mac y quedó en NFD mientras el
/// catálogo guarda NFC (adición de A1 al contrato de ST-241: "Música",
/// "Café Tacvba", cualquier segmento con acento puede venir en cualquiera de
/// las dos formas).
///
/// <para><b>Es una envoltura, no una segunda implementación</b>: el contrato
/// dice que hay un solo resolvedor de rutas de biblioteca, y esta clase no
/// repite su comparación NFC — la llama.</para>
///
/// <para><b>Integrado en B4</b> (ST-244): el recorrido componente a componente
/// es ahora <c>MediaRoots.Resolve</c>, y esta clase lo llama. Lo que queda acá
/// es lo suyo y no se repite en ningún lado: el camino rápido, la comprobación
/// de que la ruta cae dentro de la biblioteca, y que <b>el último componente se
/// resuelva contra los archivos que hay</b> —buscar uno que ya existe— en vez
/// de darse por canónico, que es lo que corresponde cuando se elige dónde
/// escribir uno nuevo. Las pruebas de este archivo estaban escritas contra el
/// comportamiento y siguen en verde sin tocarlas, que era el punto.</para>
///
/// <para>El camino rápido sigue siendo que el archivo esté exactamente donde
/// el catálogo dice —el caso normal, cuando esta misma instalación de Windows
/// creó la carpeta—; el recorrido por <c>MediaRoots.Resolve</c> solo corre
/// cuando ese camino falla.</para>
/// </summary>
public static class LibraryDiskPathResolver
{
    /// <summary>
    /// La ruta real de <paramref name="storedAbsolutePath"/>: tal cual, si
    /// existe; o la que tiene el mismo texto en otra forma Unicode en alguno
    /// de sus componentes dentro de <paramref name="libraryRoot"/>.
    /// <c>null</c> si de verdad no está en ningún lado.
    /// </summary>
    public static string? ResolveExisting(
        string libraryRoot,
        string storedAbsolutePath,
        Func<string, bool>? fileExists = null,
        Func<string, IEnumerable<string>>? enumerateDirectories = null,
        Func<string, IEnumerable<string>>? enumerateFiles = null)
    {
        fileExists ??= File.Exists;

        if (storedAbsolutePath is not { Length: > 0 }) return null;
        if (fileExists(storedAbsolutePath)) return storedAbsolutePath;

        string relative;
        try
        {
            relative = Path.GetRelativePath(libraryRoot, storedAbsolutePath);
        }
        catch (ArgumentException)
        {
            return null;
        }

        // Fuera de la biblioteca: no hay ninguna carpeta nuestra que recorrer.
        if (Path.IsPathRooted(relative) || relative.StartsWith("..", StringComparison.Ordinal))
            return null;

        if (relative.Length == 0 || relative == ".") return null;

        // ST-244: el recorrido componente a componente vive en UN solo lugar.
        // Pasarle un enumerador de archivos es lo que hace que el ÚLTIMO
        // componente —el nombre del archivo, que la Mac también pudo dejar en
        // NFD— se resuelva contra lo que hay en disco, en vez de darse por
        // canónico como cuando se elige dónde escribir uno nuevo.
        string candidate = MediaRoots.Resolve(
            libraryRoot, relative, enumerateDirectories, enumerateFiles: enumerateFiles ?? DefaultFiles);

        return fileExists(candidate) ? candidate : null;
    }

    private static IEnumerable<string> DefaultFiles(string directory)
    {
        try
        {
            return Directory.Exists(directory) ? Directory.EnumerateFiles(directory) : [];
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return [];
        }
    }
}
