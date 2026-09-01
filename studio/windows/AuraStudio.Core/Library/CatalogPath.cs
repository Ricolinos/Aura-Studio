namespace AuraStudio.Core.Library;

/// <summary>
/// La forma <b>canónica</b> de una ruta dentro de <c>biblioteca.json</c>.
///
/// <para>El catálogo lo comparten las dos apps: el dueño apunta la misma
/// carpeta desde la Mac y desde Windows. Y el modo de falla de escribirlo mal
/// es silencioso — un elemento cuya ruta no resuelve <b>se omite</b>, así que
/// 401 rutas rotas se ven idénticas a una biblioteca vacía (ST-102, y el mismo
/// par de estados indistinguibles que costó 2408 entradas en ST-087).</para>
///
/// <para>Por eso todo lo que va al catálogo pasa por acá, y no por
/// <see cref="Path"/> directamente: <c>Path.Combine</c> y
/// <c>Path.GetRelativePath</c> producen <c>\</c> en Windows, que del otro lado
/// es <b>un solo componente con barras adentro</b>, no una ruta.</para>
/// </summary>
public static class CatalogPath
{
    /// <summary>El separador del catálogo. Es <c>/</c> en las dos plataformas.</summary>
    public const char Separator = '/';

    /// <summary>
    /// Cómo se guarda <paramref name="absolutePath"/>: relativa a la biblioteca
    /// si está adentro, y absoluta si no.
    ///
    /// <para>Con "copiar medios a la biblioteca" apagado, los archivos siguen
    /// viviendo donde el usuario los tiene, y ahí una ruta relativa no
    /// significaría nada.</para>
    /// </summary>
    public static string Store(string libraryRoot, string absolutePath)
    {
        if (string.IsNullOrEmpty(absolutePath)) return "";

        string relative = Path.GetRelativePath(libraryRoot, absolutePath);

        // Fuera de la biblioteca: se guarda tal cual, con los separadores de
        // esta máquina. Traducirlos no la haría portable —una ruta absoluta de
        // Windows no significa nada en la Mac— y sí podría romperla acá.
        bool escapes = Path.IsPathRooted(relative) || relative.StartsWith("..", StringComparison.Ordinal);

        return escapes ? absolutePath : Canonical(relative);
    }

    /// <summary>
    /// La ruta absoluta de algo guardado en el catálogo. Acepta las dos formas
    /// de separador: <b>leer es tolerante, escribir es canónico</b>.
    /// </summary>
    public static string Resolve(string libraryRoot, string storedPath) =>
        string.IsNullOrEmpty(storedPath) ? ""
        : Path.IsPathRooted(storedPath) ? storedPath
        : Path.GetFullPath(Path.Combine(libraryRoot, ToNative(storedPath)));

    /// <summary>
    /// Una ruta relativa con el separador del catálogo. Idempotente, y deja
    /// intacta una ruta absoluta.
    /// </summary>
    public static string Canonical(string? relativePath)
    {
        if (relativePath is not { Length: > 0 }) return "";

        return Path.IsPathRooted(relativePath)
            ? relativePath
            : relativePath.Replace('\\', Separator);
    }

    /// <summary>
    /// El nombre del archivo de carátula: <b>el identificador en mayúsculas y
    /// con guiones</b>, que es como lo escribe macOS.
    ///
    /// <para>Con otro formato cada app escribiría su propia carátula para la
    /// misma canción y ninguna vería la de la otra.</para>
    /// </summary>
    public static string CoverFileName(Guid id) => id.ToString("D").ToUpperInvariant() + ".jpg";

    /// <summary>
    /// Lo que se anota en el catálogo para una carátula. <b>Sale del mismo lugar
    /// que el archivo que se escribe en disco</b>: cuando eran dos lugares
    /// distintos, el archivo quedó bien y el catálogo apuntando a un nombre que
    /// no existía (ST-107).
    /// </summary>
    public static string CoverRelative(Guid id) =>
        PersistedLibrary.CoversDirName + Separator + CoverFileName(id);

    private static string ToNative(string relativePath) =>
        relativePath.Replace(Separator, Path.DirectorySeparatorChar);
}
