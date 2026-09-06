using System.Runtime.CompilerServices;
using System.Security.Cryptography;

namespace AuraStudio.Core.Library;

/// <summary>
/// El resumen de una carátula (ST-208). <b>Una sola forma de calcularlo</b>,
/// porque el catálogo lo comparten las dos apps: dos formas serían dos hashes
/// distintos para la misma imagen, y cada app creyendo que la otra le cambió la
/// tapa.
///
/// <para>Definición fijada por la sesión maestra para las dos plataformas:
/// SHA-256 de los <b>bytes del archivo</b>, en hexadecimal <b>mayúsculas y sin
/// separadores</b> (64 caracteres). Es el mismo formato que
/// <see cref="CoverThumbnailKey"/> ya usaba, así que no se inventa nada nuevo:
/// se persiste el que ya estaba.</para>
/// </summary>
public static class CoverArtHash
{
    /// <summary>
    /// El resumen de cada arreglo se calcula <b>una sola vez</b> y queda atado a
    /// esa instancia (addendum de ST-208; la misma tabla que ya usaba
    /// <see cref="CoverThumbnailKey"/>).
    ///
    /// <para>Las doce pistas de un álbum comparten la misma instancia de bytes,
    /// así que guardar una biblioteca de 12 000 canciones resumía mil imágenes
    /// doce mil veces. Son 67 ms medidos —esto es higiene, no rendimiento—, pero
    /// el repo ya tenía resuelta esa trampa en un solo lugar, y tenerla resuelta
    /// de dos formas distintas es lo que hace que una de las dos se olvide.</para>
    ///
    /// <para>La tabla no impide que el arreglo se libere: cuando la carátula se
    /// va, su entrada se va con ella.</para>
    /// </summary>
    private static readonly ConditionalWeakTable<byte[], string> Digests = new();

    /// <summary>
    /// El resumen de esos bytes. <b>SHA-256 completo</b>, sin recortar: una
    /// colisión acá se ve como la carátula equivocada en la cuadrícula.
    /// </summary>
    public static string Of(byte[] data) =>
        Digests.GetValue(data, static bytes => Convert.ToHexString(SHA256.HashData(bytes)));
}
