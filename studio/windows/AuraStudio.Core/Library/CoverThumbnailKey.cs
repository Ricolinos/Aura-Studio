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

    /// <summary>
    /// La misma clave, pero desde el <b>hash que ya está en el catálogo</b>
    /// (ST-205, con el <c>coverHash</c> de ST-208): si el elemento lo trae, no
    /// hace falta leer el archivo ni resumirlo para saber qué miniatura pedir —
    /// que es lo que permite responder desde la caché <b>sin tocar el
    /// disco</b>.
    ///
    /// <para><c>null</c> si no se sabe el hash: entonces hay que leer los bytes,
    /// y de ahí sale con la otra sobrecarga.</para>
    /// </summary>
    public static string? ForHash(string? coverHash, int side) =>
        coverHash is { Length: > 0 } && side > 0 ? $"{coverHash}-{side}" : null;

    /// <summary>
    /// La clave de una imagen que se identifica por su <b>ruta</b> y no por su
    /// contenido: las fotos y las portadas de lista, que no tienen
    /// <c>coverHash</c> porque no son carátulas del catálogo.
    ///
    /// <para>Lo que se acepta a cambio: si alguien reemplaza ese archivo por
    /// fuera sin que cambie la ruta, la miniatura vieja sigue hasta que se
    /// recargue la biblioteca —que vacía la caché—. Preguntarle al disco por
    /// cada tarjeta para descartarlo sería justo el trabajo que esto evita.</para>
    /// </summary>
    public static string? ForPath(string? path, int side) =>
        path is { Length: > 0 } && side > 0 ? $"ruta:{path}-{side}" : null;
}
