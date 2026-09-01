using System.Text;

namespace AuraStudio.Core;

/// <summary>
/// Fase 24 (PLAN-UX.md): saneo de un único componente de ruta (nombre de
/// artista/álbum/título/playlist) para que sea válido como nombre de
/// archivo/carpeta en el FAT32 del iPod — los metadatos reales traen con
/// frecuencia caracteres que ese sistema de archivos no acepta
/// ("AC/DC", "Sigur Ros: ()" con dos puntos, etc).
/// </summary>
public static class PathSanitizer
{
    private static readonly char[] IllegalCharacters = ['/', '\\', ':', '*', '?', '"', '<', '>', '|'];

    /// <summary>
    /// PLAN-sync-media-hardening.md PARTE 1A: visto en producción, un único
    /// componente de ruta (el tag de artista, en ese caso) puede traer
    /// metadata real de decenas de caracteres — un crédito de composición
    /// completo pegado ahí ("Los Aguas Aguas, Luis Felipe Balderas Lopez,
    /// ..."), sin ningún límite. `Music/&lt;ese componente&gt;/&lt;album&gt;/&lt;archivo&gt;.mp3.aura-tmp`
    /// (el sufijo temporal de `copyFileTransactionally`) terminó excediendo
    /// lo que el driver msdosfs de macOS acepta — Cocoa lo reporta como "el
    /// nombre de archivo es inválido", sin mencionar que la causa real es el
    /// largo acumulado. 120 caracteres por componente es holgado para nombres
    /// reales (artista/álbum/título) y deja margen de sobra bajo cualquier
    /// límite práctico de FAT32/msdosfs para la ruta completa.
    /// </summary>
    public const int DefaultMaxLength = 120;

    /// <summary>
    /// Sanea un componente de ruta reemplazando los caracteres ilegales de
    /// FAT32 por "_", recortando el exceso de longitud y limpiando los
    /// puntos/espacios finales.
    /// </summary>
    public static string Sanitize(string s, int maxLength = DefaultMaxLength)
    {
        var sb = new StringBuilder(s.Length);
        foreach (char c in s)
        {
            sb.Append(Array.IndexOf(IllegalCharacters, c) >= 0 ? '_' : c);
        }

        var result = sb.ToString().Trim();

        if (result.Length > maxLength)
        {
            result = result[..maxLength];
        }
        // FAT32/Windows no permite que un nombre termine en "." o espacio
        // — se revisa DESPUÉS de truncar, por si el corte dejó alguno.
        while (result.Length > 0 && (result[^1] == '.' || result[^1] == ' '))
        {
            result = result[..^1];
        }

        return result.Length == 0 ? "_" : result;
    }

    /// <summary>
    /// PLAN-sync-media-hardening.md PARTE 2A: `/Photos/` y `/Videos/` son
    /// planos en el iPod — el nombre de archivo final (con extensión) es lo
    /// único que el firmware ve, y su límite real es un buffer C de tamaño
    /// fijo (`PHOTO_NAME_LEN`/`VIDEO_NAME_LEN`, 96 con el NUL —
    /// docs/contracts/library-layout-v1.md §1: "≤ 95 bytes UTF-8 incluyendo
    /// la extensión"). Un nombre con acentos/ñ puede tener MENOS caracteres
    /// que bytes — capar por caracteres (como `sanitize(_:maxLength:)`,
    /// pensado para componentes de ruta de música, donde el firmware no tiene
    /// ese límite exacto) seguía pudiendo exceder el límite real en bytes
    /// para un nombre muy acentuado. Recorta un `Character` (nunca a mitad de
    /// una secuencia UTF-8 multibyte) a la vez desde el final de la base,
    /// conservando la extensión completa.
    /// </summary>
    public static string SanitizeFilename(string raw, int maxBytes)
    {
        string ext = Path.GetExtension(raw);
        string baseName = Sanitize(
            raw[..^ext.Length],
            maxLength: int.MaxValue);
        string suffix = ext.Length == 0 ? "" : ext;

        while (Encoding.UTF8.GetByteCount(baseName + suffix) > maxBytes && baseName.Length > 0)
        {
            baseName = baseName[..^1];
        }
        while (baseName.Length > 0 && (baseName[^1] == '.' || baseName[^1] == ' '))
        {
            baseName = baseName[..^1];
        }
        string result = baseName + suffix;
        return result.Length == 0 ? "_" + suffix : result;
    }
}
