using System.Runtime.CompilerServices;
using System.Security.Cryptography;

namespace AuraStudio.Core.Library;

/// <summary>
/// La clave con la que se guarda la miniatura de una carátula.
///
/// <para>Es por <b>contenido</b>, no por canción: un álbum de 14 pistas tiene la
/// misma carátula 14 veces, y con una clave por canción se decodificarían y
/// guardarían 14 miniaturas idénticas.</para>
/// </summary>
public static class CoverThumbnailKey
{
    /// <summary>
    /// El resumen de cada arreglo se calcula <b>una sola vez</b> y queda atado a
    /// esa instancia. Sin esto habría que volver a resumir el megabyte de la
    /// carátula en cada celda que aparece al hacer scroll, que es justo el costo
    /// que la caché existe para evitar. La tabla no impide que el arreglo se
    /// libere: cuando la carátula se va, su entrada se va con ella.
    /// </summary>
    private static readonly ConditionalWeakTable<byte[], string> Digests = new();

    /// <summary>
    /// <c>null</c> si no hay carátula — no hay nada que guardar ni que buscar.
    /// </summary>
    public static string? For(byte[]? data, int side)
    {
        if (data is null || data.Length == 0 || side <= 0) return null;
        return $"{Digest(data)}-{side}";
    }

    private static string Digest(byte[] data) =>
        Digests.GetValue(data, static bytes =>
            // SHA-256 completo: una colisión acá se ve como la carátula
            // equivocada en la cuadrícula, así que no se recorta el resumen ni
            // se resume solo una parte del archivo.
            Convert.ToHexString(SHA256.HashData(bytes)));
}
