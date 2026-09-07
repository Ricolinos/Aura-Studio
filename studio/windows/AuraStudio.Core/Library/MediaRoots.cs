namespace AuraStudio.Core.Library;

/// <summary>
/// Dónde viven las copias: <c>Música/</c>, <c>Imágenes/</c> y <c>Videos/</c>
/// dentro de la biblioteca (addendum de ST-241).
///
/// <para><b>Por qué no alcanza con <c>Path.Combine</c>.</b> Dos de esos tres
/// nombres llevan acento, y un acento se puede escribir de dos maneras que se
/// ven idénticas: compuesta (una sola letra acentuada) o descompuesta (la letra
/// y el acento por separado). La Mac crea las carpetas de una forma y Windows
/// las buscaría de la otra — y como <b>en Windows el nombre en disco es la
/// secuencia exacta de caracteres con la que se creó</b>, no la encontraría y
/// crearía una segunda "Música" al lado de la primera. Dos carpetas que se ven
/// iguales, la biblioteca partida en dos, y nadie entendiendo por qué.</para>
///
/// <para>Por eso se <b>lista</b> el directorio y se compara normalizando, en vez
/// de armar la ruta a ciegas. Es un listado por tipo de medio —tres en total—,
/// no uno por archivo: no es lo que ST-203 sacó de la carga.</para>
/// </summary>
public static class MediaRoots
{
    /// <summary>
    /// La carpeta de un tipo de medio dentro de <paramref name="libraryRoot"/>:
    /// la que ya está si hay una que se llame así en cualquiera de las dos
    /// formas, y si no, la ruta con el nombre canónico —que es la que habría que
    /// crear—.
    /// </summary>
    /// <param name="enumerateDirectories">
    /// Se inyecta para poder probar sin escribir carpetas.
    /// </param>
    public static string Directory(
        string libraryRoot,
        LibraryItemKind kind,
        Func<string, IEnumerable<string>>? enumerateDirectories = null) =>
        Directory(libraryRoot, DirectoryName(kind), enumerateDirectories);

    /// <summary>Igual, para un nombre de carpeta cualquiera de la biblioteca.</summary>
    public static string Directory(
        string libraryRoot,
        string directoryName,
        Func<string, IEnumerable<string>>? enumerateDirectories = null)
    {
        enumerateDirectories ??= SafeDirectories;
        string wanted = CatalogPath.Normalize(directoryName);

        foreach (string existing in enumerateDirectories(libraryRoot))
        {
            if (Path.GetFileName(existing) is not { Length: > 0 } name) continue;

            if (string.Equals(CatalogPath.Normalize(name), wanted, StringComparison.OrdinalIgnoreCase))
                return existing;
        }

        return Path.Combine(libraryRoot, wanted);
    }

    /// <summary>
    /// La ruta absoluta de algo que va a escribirse dentro de la biblioteca,
    /// <b>reusando cada carpeta que ya exista</b> aunque su nombre esté escrito
    /// en la otra forma Unicode (ST-244, contrato de ST-221).
    ///
    /// <para><b>Por qué componente por componente y no solo la raíz del medio.</b>
    /// La Mac <b>no puede</b> crear carpetas en NFC —Foundation descompone al
    /// bajar al sistema de archivos—, así que todo lo que ella haya creado está
    /// en NFD: <c>Música</c>, sí, pero también <c>Café Tacvba</c> y
    /// <c>Añoranza</c>. Armar la ruta a ciegas con la cadena del catálogo
    /// crearía una carpeta nueva al lado de cada una: dos "Música", dos "Café
    /// Tacvba", la biblioteca partida en dos y nadie entendiendo por qué.</para>
    ///
    /// <para><b>Y sin pagarlo en cada archivo.</b> Primero se prueba la ruta tal
    /// cual —que es el caso normal en cuanto la carpeta existe, y cuesta un
    /// <c>Exists</c>—; solo cuando no está se lista el padre para ver si hay una
    /// que se llame igual en la otra forma. O sea: un listado la primera vez que
    /// se toca cada carpeta, no uno por canción.</para>
    /// </summary>
    /// <param name="relativePath">
    /// Ruta relativa del catálogo, con <c>/</c> o con <c>\</c>
    /// (<see cref="CatalogPath"/>): leer es tolerante.
    /// </param>
    /// <param name="enumerateFiles">
    /// Qué archivos hay en una carpeta. Cuando se pasa, el <b>último</b>
    /// componente —el archivo— también se resuelve contra lo que ya está, igual
    /// que las carpetas; cuando no, se escribe con el nombre canónico.
    ///
    /// <para>Esa es toda la diferencia entre <b>buscar un archivo que ya
    /// existe</b> (ST-245, donde el nombre del archivo también puede estar en
    /// NFD porque lo escribió la Mac) y <b>elegir dónde escribir uno nuevo</b>
    /// (ST-244, donde el nombre lo ponemos nosotros y va canónico). El recorrido
    /// es el mismo y por eso vive en un solo lugar.</para>
    /// </param>
    public static string Resolve(
        string libraryRoot,
        string relativePath,
        Func<string, IEnumerable<string>>? enumerateDirectories = null,
        Func<string, bool>? directoryExists = null,
        Func<string, IEnumerable<string>>? enumerateFiles = null)
    {
        enumerateDirectories ??= SafeDirectories;
        directoryExists ??= System.IO.Directory.Exists;

        string[] parts = relativePath.Split(
            [CatalogPath.Separator, '\\'], StringSplitOptions.RemoveEmptyEntries);

        string current = libraryRoot;

        // Todos menos el último: el archivo se escribe con su nombre canónico.
        for (int i = 0; i < parts.Length - 1; i++)
        {
            string wanted = CatalogPath.Normalize(parts[i]);
            string candidate = Path.Combine(current, wanted);

            current = directoryExists(candidate)
                ? candidate
                : Directory(current, wanted, enumerateDirectories);
        }

        if (parts.Length == 0) return current;

        return enumerateFiles is null
            ? Path.Combine(current, CatalogPath.Normalize(parts[^1]))
            : Directory(current, parts[^1], enumerateFiles);
    }

    /// <summary>
    /// El nombre de la carpeta donde va cada tipo de medio.
    ///
    /// <para><c>Unsupported</c> no tiene carpeta: no se copia nada que no se
    /// sepa manejar, y devolver una carpeta cualquiera sería empezar a llenarla.
    /// </para>
    /// </summary>
    public static string DirectoryName(LibraryItemKind kind) => kind switch
    {
        LibraryItemKind.Music => PersistedLibrary.MusicDirName,
        LibraryItemKind.Photo => PersistedLibrary.ImagesDirName,
        LibraryItemKind.Video => PersistedLibrary.VideosDirName,
        _ => throw new ArgumentOutOfRangeException(nameof(kind), kind, "no tiene carpeta en la biblioteca")
    };

    /// <summary>
    /// Las carpetas que hay, o ninguna. Una biblioteca recién elegida todavía no
    /// tiene ninguna, y eso no es un error.
    /// </summary>
    private static IEnumerable<string> SafeDirectories(string path)
    {
        try
        {
            return System.IO.Directory.EnumerateDirectories(path).ToArray();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            return [];
        }
    }
}
