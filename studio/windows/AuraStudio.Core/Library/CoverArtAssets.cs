using System.Text.RegularExpressions;

namespace AuraStudio.Core.Library;

/// <summary>
/// Lo que un conjunto de archivos (el arrastre expandido, o la biblioteca)
/// aporta como CONTEXTO para decidir si una imagen es carátula.
///
/// **Solo el audio define "carpeta de álbum"**: una carpeta de fotos de un
/// viaje puede traer clips `.mov` y sus fotos siguen siendo fotos.
/// </summary>
public sealed class CoverArtDropContext
{
    public HashSet<string> AudioDirectories { get; } = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>"&lt;directorio&gt;\&lt;nombre base&gt;" de cada video del conjunto.</summary>
    public HashSet<string> VideoBaseNames { get; } = new(StringComparer.OrdinalIgnoreCase);

    public CoverArtDropContext(IEnumerable<string> paths)
    {
        foreach (string path in paths)
        {
            if (CoverArtAssets.IsAudio(path))
            {
                string? dir = Path.GetDirectoryName(path);
                if (dir is { Length: > 0 }) AudioDirectories.Add(Path.TrimEndingDirectorySeparator(dir));
            }
            else if (CoverArtAssets.IsVideo(path))
            {
                VideoBaseNames.Add(CoverArtAssets.PathWithoutExtension(path));
            }
        }
    }
}

/// <summary>
/// ST-012 / `docs/contracts/library-layout-v1.md` §2: las carátulas son
/// **assets** asociados a sus entradas de Música o Video, **nunca entradas
/// propias del módulo de Imágenes**. Port de `CoverArtAssets.swift`.
///
/// Contesta dos preguntas, sin tocar la biblioteca:
/// <list type="bullet">
/// <item>al importar: ¿este JPEG/PNG que venía en el arrastre es una carátula
/// (y por lo tanto NO se agrega a Imágenes)?</item>
/// <item>al leer una canción: ¿hay una carátula de carpeta al lado
/// (`cover.jpg`, `folder.jpg`…) que sirva de portada?</item>
/// </list>
///
/// Los nombres reconocidos son los mismos que busca el firmware
/// (`apps/recorder/albumart.c`) más los sinónimos que traen los rippers y
/// tiendas habituales.
/// </summary>
public static class CoverArtAssets
{
    public static readonly HashSet<string> ImageExtensions =
        new(["jpg", "jpeg", "png", "gif", "bmp", "heic", "tiff"], StringComparer.OrdinalIgnoreCase);

    public static readonly HashSet<string> AudioExtensions =
        new(["flac", "mp3", "m4a", "wav", "aiff", "aif"], StringComparer.OrdinalIgnoreCase);

    public static readonly HashSet<string> VideoExtensions =
        new(["mp4", "mov", "m4v", "avi", "mkv", "mpg", "mpeg"], StringComparer.OrdinalIgnoreCase);

    /// <summary>Nombres base que casi siempre son una carátula y no una foto personal.</summary>
    public static readonly HashSet<string> CoverBaseNames = new(
    [
        "cover", "folder", "front", "back", "album", "albumart", "albumartsmall",
        "artwork", "art", "thumb", "thumbnail", "booklet", "cd", "disc", "inlay",
        "poster"
    ], StringComparer.OrdinalIgnoreCase);

    /// <summary>Orden de preferencia para elegir LA portada de una carpeta.</summary>
    public static readonly string[] PreferredCoverBaseNames =
        ["cover", "folder", "front", "album", "albumart", "artwork"];

    private static readonly Regex SeparatorRun = new(@"[\s_\-()]+", RegexOptions.Compiled);

    public static bool IsImage(string path) => HasExtension(path, ImageExtensions);
    public static bool IsAudio(string path) => HasExtension(path, AudioExtensions);
    public static bool IsVideo(string path) => HasExtension(path, VideoExtensions);
    public static bool IsAudioOrVideo(string path) => IsAudio(path) || IsVideo(path);

    private static bool HasExtension(string path, HashSet<string> extensions)
    {
        if (string.IsNullOrWhiteSpace(path)) return false;
        string ext = Path.GetExtension(path);
        return ext.Length > 1 && extensions.Contains(ext[1..]);
    }

    /// <summary>Ruta sin extensión, para comparar un video con su póster hermano.</summary>
    public static string PathWithoutExtension(string path)
    {
        string? dir = Path.GetDirectoryName(path);
        string name = Path.GetFileNameWithoutExtension(path);
        return dir is { Length: > 0 } ? Path.Combine(dir, name) : name;
    }

    /// <summary>
    /// `cover.jpg`, `Folder.PNG`, `front-1.jpg`, `cover (1).jpeg`,
    /// `AlbumArt_{…}_Large.jpg` (Windows Media Player)…
    /// </summary>
    public static bool HasCoverLikeName(string path)
    {
        if (!IsImage(path)) return false;
        string baseName = Path.GetFileNameWithoutExtension(path).ToLowerInvariant();
        if (CoverBaseNames.Contains(baseName)) return true;

        // Sufijos numéricos y separadores: "cover 2", "front-1", "cover_small".
        string[] parts = SeparatorRun.Replace(baseName, " ").Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length > 0 && CoverBaseNames.Contains(parts[0])) return true;

        return baseName.StartsWith("albumart", StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// Decisión de importación. Una imagen es carátula o póster (y no foto) si:
    /// <list type="bullet">
    /// <item>vive en un directorio que en el MISMO conjunto trae audio (un álbum
    /// soltado entero con su `cover.jpg`, se llame como se llame), o</item>
    /// <item>es el póster de un video del conjunto (mismo nombre base), o</item>
    /// <item>tiene nombre de carátula y el arrastre NO fue dirigido al módulo de
    /// Imágenes — **soltarla a propósito en Fotos gana**: ahí el usuario dijo
    /// "esto es una foto", o</item>
    /// <item>tiene nombre de carátula y en disco convive con audio (evidencia
    /// fuera del arrastre).</item>
    /// </list>
    /// </summary>
    public static bool IsCoverAsset(string path, CoverArtDropContext context, bool droppedIntoPhotos)
    {
        if (!IsImage(path)) return false;

        string? dir = Path.GetDirectoryName(path);
        if (dir is { Length: > 0 } && context.AudioDirectories.Contains(Path.TrimEndingDirectorySeparator(dir)))
        {
            return true;
        }
        if (context.VideoBaseNames.Contains(PathWithoutExtension(path))) return true;
        if (!HasCoverLikeName(path)) return false;
        if (!droppedIntoPhotos) return true;

        return dir is { Length: > 0 } && DirectoryContainsAudio(dir);
    }

    public static bool DirectoryContainsAudio(string directory)
    {
        try
        {
            return Directory.Exists(directory)
                && Directory.EnumerateFiles(directory).Any(IsAudio);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    /// <summary>
    /// La carátula de carpeta de una canción, si existe: mismo criterio de
    /// nombres que el firmware, en orden de preferencia.
    /// </summary>
    public static string? FolderCover(string audioPath)
    {
        string? directory = Path.GetDirectoryName(audioPath);
        if (directory is not { Length: > 0 }) return null;

        List<string> images;
        try
        {
            if (!Directory.Exists(directory)) return null;
            images = Directory.EnumerateFiles(directory).Where(IsImage).ToList();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return null;
        }
        if (images.Count == 0) return null;

        foreach (string preferred in PreferredCoverBaseNames)
        {
            string? match = images.FirstOrDefault(image =>
                Path.GetFileNameWithoutExtension(image).Equals(preferred, StringComparison.OrdinalIgnoreCase));
            if (match is not null) return match;
        }

        // `<álbum>.jpg` u otro nombre de carátula reconocido.
        return images.FirstOrDefault(HasCoverLikeName);
    }
}
