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
    /// El resumen de esos bytes. <b>SHA-256 completo</b>, sin recortar: una
    /// colisión acá se ve como la carátula equivocada en la cuadrícula.
    /// </summary>
    public static string Of(byte[] data) => Convert.ToHexString(SHA256.HashData(data));
}
