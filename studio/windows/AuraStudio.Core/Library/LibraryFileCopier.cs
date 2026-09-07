namespace AuraStudio.Core.Library;

/// <summary>Qué pasó al meter un archivo a la biblioteca (ST-243).</summary>
/// <param name="Path">Dónde quedó. Vacío si no se copió.</param>
/// <param name="Copied"><c>false</c> cuando no se tocó nada.</param>
/// <param name="BytesWritten">Cuánto pesa lo que quedó. 0 si no se copió.</param>
/// <param name="Reason">Por qué no se copió, cuando <paramref name="Copied"/> es <c>false</c>.</param>
public readonly record struct LibraryCopyResult(
    string Path,
    bool Copied,
    long BytesWritten,
    string? Reason = null)
{
    public static LibraryCopyResult Skipped(string reason) => new("", false, 0, reason);

    /// <summary>Ya estaba adentro: el archivo del usuario ya es de la biblioteca.</summary>
    public static LibraryCopyResult AlreadyInside(string path) =>
        new(path, false, 0, "el archivo ya está dentro de la biblioteca");
}

/// <summary>
/// Mete el archivo de un elemento adentro de la biblioteca (ST-243, modo copia).
///
/// <para><b>El original del usuario no se toca nunca.</b> Ni se mueve, ni se
/// renombra, ni se le escriben etiquetas: se <b>copia</b>, y lo que queda bajo
/// nuestro mando es la copia. Es lo que promete el interruptor de Ajustes —"el
/// original queda intacto donde estaba"— y es la línea que separa una app que
/// organiza de una que arruina una biblioteca ajena.</para>
///
/// <para><b>Copia atómica</b>, igual que <see cref="LocalTagWriter"/>: se copia
/// a un temporal al lado del destino y recién ahí se renombra. Un corte a mitad
/// de copiar un archivo de cincuenta megabytes deja un <c>.aura-tmp</c> a medias
/// —basura evidente que se borra sola— y no una canción truncada que el catálogo
/// da por buena. Y el temporal <b>nunca se llama como música</b> (ST-242): un
/// <c>.aura-tmp</c> tirado es basura que nadie va a importar; un <c>.mp3</c>
/// tirado es una canción duplicada en la biblioteca del usuario.</para>
///
/// <para><b>Nunca lanza.</b> Sin espacio, sin permisos o con el disco
/// desconectado devuelve un resultado que lo explica; una importación de mil
/// archivos no se cae por uno.</para>
/// </summary>
public static class LibraryFileCopier
{
    /// <summary>El sufijo del archivo a medio copiar. El mismo que usa el escritor de etiquetas.</summary>
    public const string TemporarySuffix = ".aura-tmp";

    /// <summary>
    /// Copia <paramref name="sourcePath"/> a
    /// <paramref name="libraryRoot"/>/<paramref name="relativePath"/>.
    ///
    /// <para>Si el destino ya está ocupado por <b>otro</b> archivo, se
    /// desambigua con un número: dos canciones distintas con el mismo artista,
    /// álbum y título existen —las hay en vivo y en estudio— y la segunda no
    /// puede pisar a la primera.</para>
    /// </summary>
    public static LibraryCopyResult Copy(
        string sourcePath,
        string libraryRoot,
        string relativePath,
        ILibraryFileSystem? fileSystem = null)
    {
        ILibraryFileSystem files = fileSystem ?? LibraryFileSystem.Shared;

        if (sourcePath is not { Length: > 0 }) return LibraryCopyResult.Skipped("no hay archivo de origen");
        if (relativePath is not { Length: > 0 }) return LibraryCopyResult.Skipped("no hay ruta de destino");
        if (!files.FileExists(sourcePath)) return LibraryCopyResult.Skipped("el archivo no está");

        // Ya adentro: copiarlo sería duplicar la biblioteca del usuario dentro de
        // sí misma. Pasa al reprocesar algo que ya se copió antes.
        if (IsInside(libraryRoot, sourcePath)) return LibraryCopyResult.AlreadyInside(sourcePath);

        string destination = Available(libraryRoot, relativePath, files);
        string temporary = destination + TemporarySuffix;

        try
        {
            files.CreateDirectory(Path.GetDirectoryName(destination)!);
            files.Copy(sourcePath, temporary);

            long bytes = files.Length(temporary);
            files.Move(temporary, destination);

            return new LibraryCopyResult(destination, true, bytes);
        }
        catch (Exception ex) when (ex is not OutOfMemoryException)
        {
            return LibraryCopyResult.Skipped($"no se pudo copiar: {ex.Message}");
        }
        finally
        {
            files.TryDelete(temporary);
        }
    }

    /// <summary>
    /// Si un archivo ya cuelga de la biblioteca. Compara rutas completas y no
    /// prefijos de texto: <c>C:\Bib2</c> empieza con <c>C:\Bib</c> y no está
    /// adentro de ella.
    /// </summary>
    public static bool IsInside(string libraryRoot, string path)
    {
        if (libraryRoot is not { Length: > 0 } || path is not { Length: > 0 }) return false;

        try
        {
            string relative = Path.GetRelativePath(libraryRoot, path);

            return !Path.IsPathRooted(relative)
                   && !relative.StartsWith("..", StringComparison.Ordinal)
                   && relative != ".";
        }
        catch (ArgumentException)
        {
            return false;
        }
    }

    /// <summary>
    /// La ruta libre para <paramref name="relativePath"/>: la pedida si está
    /// libre, y si no la misma con un número. Nunca devuelve una ocupada.
    ///
    /// <para>Es pública porque lo que <b>convierte</b> un archivo a MP3 en vez de
    /// copiarlo escribe él mismo el destino, y tiene que elegirlo con esta misma
    /// regla: dos reglas para nombrar el mismo archivo es cómo una termina
    /// pisando lo que la otra escribió.</para>
    /// </summary>
    public static string Available(
        string libraryRoot, string relativePath, ILibraryFileSystem? fileSystem = null)
    {
        ILibraryFileSystem files = fileSystem ?? LibraryFileSystem.Shared;
        string candidate = Path.Combine(libraryRoot, ToNative(relativePath));
        if (!files.FileExists(candidate)) return candidate;

        string directory = Path.GetDirectoryName(candidate)!;
        string name = Path.GetFileNameWithoutExtension(candidate);
        string extension = Path.GetExtension(candidate);

        for (int counter = 2; ; counter++)
        {
            string numbered = Path.Combine(directory, $"{name} {counter}{extension}");
            if (!files.FileExists(numbered)) return numbered;
        }
    }

    private static string ToNative(string relativePath) =>
        relativePath.Replace(CatalogPath.Separator, Path.DirectorySeparatorChar);
}

/// <summary>
/// Lo que el copiador necesita del disco. Existe para poder probar la
/// desambiguación, la atomicidad y los errores <b>sin escribir gigabytes</b>, y
/// sin depender de que la máquina de pruebas tenga espacio.
/// </summary>
public interface ILibraryFileSystem
{
    bool FileExists(string path);
    void CreateDirectory(string path);
    void Copy(string source, string destination);
    void Move(string source, string destination);
    long Length(string path);
    void TryDelete(string path);
}

/// <summary>El disco de verdad.</summary>
public sealed class LibraryFileSystem : ILibraryFileSystem
{
    public static readonly LibraryFileSystem Shared = new();

    public bool FileExists(string path) => File.Exists(path);

    public void CreateDirectory(string path) => Directory.CreateDirectory(path);

    public void Copy(string source, string destination) => File.Copy(source, destination, overwrite: true);

    public void Move(string source, string destination) => File.Move(source, destination, overwrite: true);

    public long Length(string path) => new FileInfo(path).Length;

    public void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path)) File.Delete(path);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Lo que importa es que el original está bien.
        }
    }
}
