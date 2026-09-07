using System.Runtime.Versioning;
using System.Security.Principal;
using System.Text;

namespace AuraStudio.Core.Library;

/// <summary>
/// Verifica si un archivo que <see cref="WindowsRecycleBin"/> mandó a la
/// Papelera está de verdad ahí, leyendo <c>$Recycle.Bin\&lt;SID&gt;\</c>
/// directo (ST-245, addendum "espejo de A5").
///
/// <para><b>Por qué existe</b>: <c>SHFileOperationW</c> con
/// <c>FOF_WANTMAPPINGHANDLE</c> no da ningún destino para <c>FO_DELETE</c> —
/// comprobado empíricamente en esta misma VM antes de escribir esto (ver
/// DECISIONS.md): <c>hNameMappings</c> queda en <c>0</c> tras un borrado real,
/// a diferencia de lo que el nombre de la bandera sugeriría (el mapeo de
/// nombres es para resolver colisiones al copiar/mover, nunca para
/// deletes). La alternativa real —<c>IFileOperation</c> +
/// <c>IFileOperationProgressSink.PostDeleteItem</c>— es un cambio de API
/// mucho más grande que <see cref="WindowsRecycleBin"/> para un problema
/// que solo existe en pruebas, así que en vez de eso esto lee el índice que
/// la Papelera de Windows ya escribe sola.</para>
/// </summary>
[SupportedOSPlatform("windows")]
public static class RecycleBinProbe
{
    /// <summary>
    /// Busca <paramref name="originalPath"/> entre los <c>$I*</c> de la
    /// Papelera del usuario actual, en la unidad de <paramref name="originalPath"/>.
    /// </summary>
    /// <returns>
    /// La ruta del <c>$R*</c> correspondiente (los bytes de verdad) si se
    /// encuentra Y el archivo sigue ahí, o <c>null</c> si no -- un <c>$I</c>
    /// dañado o de un formato que esta función no reconoce se salta, nunca
    /// lanza.
    /// </returns>
    public static string? FindRecycledFile(string originalPath)
    {
        string normalizedTarget = Path.GetFullPath(originalPath);
        string? root = Path.GetPathRoot(normalizedTarget);
        if (root is not { Length: > 0 }) return null;

        string sid = WindowsIdentity.GetCurrent().User!.Value;
        string recycleBinDir = Path.Combine(root, "$Recycle.Bin", sid);
        if (!Directory.Exists(recycleBinDir)) return null;

        foreach (string infoFile in Directory.EnumerateFiles(recycleBinDir, "$I*"))
        {
            string? decoded = TryReadOriginalPath(infoFile);
            if (decoded is null) continue;
            if (!string.Equals(decoded, normalizedTarget, StringComparison.OrdinalIgnoreCase)) continue;

            string dataFile = Path.Combine(
                Path.GetDirectoryName(infoFile)!,
                "$R" + Path.GetFileName(infoFile)[2..]);
            if (File.Exists(dataFile)) return dataFile;
        }

        return null;
    }

    /// <summary>
    /// Formato <c>$I</c> de la Papelera de Windows 10+ (no documentado
    /// oficialmente por Microsoft -- verificado leyendo archivos <c>$I</c>
    /// reales de esta VM antes de escribir esto, ver DECISIONS.md): 8 bytes
    /// de encabezado/versión, 8 bytes de tamaño original, 8 bytes de
    /// FILETIME de borrado, 4 bytes de longitud de la ruta (caracteres
    /// UTF-16, incluido el nulo final), luego la ruta en UTF-16.
    /// </summary>
    private static string? TryReadOriginalPath(string infoFile)
    {
        try
        {
            byte[] bytes = File.ReadAllBytes(infoFile);
            if (bytes.Length < 28) return null;

            int pathLengthChars = BitConverter.ToInt32(bytes, 24);
            int byteCount = Math.Min(pathLengthChars * 2, bytes.Length - 28);
            if (byteCount <= 0) return null;

            return Encoding.Unicode.GetString(bytes, 28, byteCount).TrimEnd('\0');
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
    }
}
