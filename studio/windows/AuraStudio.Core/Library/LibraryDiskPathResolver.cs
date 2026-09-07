namespace AuraStudio.Core.Library;

/// <summary>
/// Encuentra en disco el archivo que el catálogo dice, incluso cuando una
/// carpeta de la biblioteca la creó la Mac y quedó en NFD mientras el
/// catálogo guarda NFC (adición de A1 al contrato de ST-241: "Música",
/// "Café Tacvba", cualquier segmento con acento puede venir en cualquiera de
/// las dos formas).
///
/// <para><b>Es una envoltura, no una segunda implementación</b>: el contrato
/// dice que hay un solo resolvedor de rutas de biblioteca,
/// <see cref="MediaRoots.Directory(string, string, Func{string,
/// IEnumerable{string}}?)"/>, y esta clase no repite su comparación NFC —la
/// llama, una vez por componente de la ruta relativa (artista, álbum, el
/// nombre del archivo), porque el acento puede estar en cualquiera de ellos y
/// <c>MediaRoots.Directory</c> solo resuelve un nivel a la vez. Para el último
/// componente —un archivo, no una carpeta— se le inyecta un enumerador de
/// archivos en vez del de carpetas por omisión: la comparación es la misma,
/// lo único que cambia es qué se lista.</para>
///
/// <para><b>Pendiente de B4</b> (ST-245, anotado también en DECISIONS.md): el
/// Experto está ampliando esto mismo como <c>MediaRoots.Resolve</c> (NFC
/// componente a componente) para B4. Al integrar, esta clase pasa a llamar a
/// <c>MediaRoots.Resolve</c> directo y puede reducirse a nada o quedar como
/// alias fino — lo que decida esa integración. Las pruebas de este archivo
/// están escritas contra el comportamiento (una ruta con acento en NFD en
/// disco y NFC en el catálogo se encuentra igual), no contra los métodos
/// internos, para sobrevivir ese cambio sin tocarlas.</para>
///
/// <para>El camino rápido sigue siendo que el archivo esté exactamente donde
/// el catálogo dice —el caso normal, cuando esta misma instalación de Windows
/// creó la carpeta—; el recorrido por <c>MediaRoots.Directory</c> solo corre
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

        string[] segments = relative.Split(
            [Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar],
            StringSplitOptions.RemoveEmptyEntries);

        if (segments.Length == 0) return null;

        string current = libraryRoot;

        // Todos los segmentos salvo el último son carpetas: un nivel por vez,
        // con el mismo MediaRoots.Directory que ya resuelve Música/Imágenes/Videos.
        for (int i = 0; i < segments.Length - 1; i++)
            current = MediaRoots.Directory(current, segments[i], enumerateDirectories);

        // El último es el archivo: misma función, listando archivos en vez de carpetas.
        current = MediaRoots.Directory(current, segments[^1], enumerateFiles ?? DefaultFiles);

        return fileExists(current) ? current : null;
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
