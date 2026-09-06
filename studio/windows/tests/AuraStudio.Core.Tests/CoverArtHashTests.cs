using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El resumen de una carátula (ST-208, memoizado en su addendum). Lo que se
/// protege es lo que el catálogo comparten las dos apps —el formato exacto— y
/// que la misma instancia de bytes no se resuma dos veces.
/// </summary>
public class CoverArtHashTests
{
    [Fact]
    public void ElFormatoEsElQueFijoLaMaestra()
    {
        string hash = CoverArtHash.Of([1, 2, 3]);

        // 64 caracteres, hexadecimal en MAYÚSCULAS, sin separadores: es lo que
        // se persiste en `coverHash` y lo que la Mac espera leer.
        Assert.Equal(64, hash.Length);
        Assert.Equal(hash.ToUpperInvariant(), hash);
        Assert.All(hash, c => Assert.Contains(c, "0123456789ABCDEF"));
    }

    [Fact]
    public void LosMismosBytesDanElMismoResumenAunqueSeanOtroArreglo()
    {
        // Dos copias de la misma carátula son la misma carátula: si dieran
        // resúmenes distintos, cada app creería que la otra le cambió la tapa.
        byte[] uno = [4, 5, 6];
        byte[] otro = [4, 5, 6];

        Assert.Equal(CoverArtHash.Of(uno), CoverArtHash.Of(otro));
    }

    [Fact]
    public void BytesDistintosDanResumenesDistintos()
    {
        Assert.NotEqual(CoverArtHash.Of([1]), CoverArtHash.Of([2]));
    }

    [Fact]
    public void LaMismaInstanciaNoSeResumeDosVeces()
    {
        // Addendum de ST-208: las doce pistas de un álbum comparten la misma
        // instancia de bytes. Sin memoizar, guardar 12 000 canciones resumía mil
        // imágenes doce mil veces.
        //
        // Se comprueba por identidad de la cadena devuelta: `string.Intern` no
        // interviene acá —el hexadecimal se arma en tiempo de ejecución—, así
        // que dos llamadas que devuelven LA MISMA instancia solo pueden venir de
        // la tabla.
        byte[] cover = [7, 7, 7, 7];

        string first = CoverArtHash.Of(cover);
        string second = CoverArtHash.Of(cover);

        Assert.Same(first, second);
    }

    [Fact]
    public void DosArreglosIgualesNoCompartenLaEntrada()
    {
        // La memoización es por INSTANCIA, no por contenido: la tabla es débil y
        // no puede comparar megabytes para buscar. Que el resumen coincida ya lo
        // dice otra prueba; acá se fija que son entradas distintas, que es lo que
        // permite que cada arreglo se libere con su carátula.
        byte[] uno = [8, 8];
        byte[] otro = [8, 8];

        Assert.NotSame(CoverArtHash.Of(uno), CoverArtHash.Of(otro));
        Assert.Equal(CoverArtHash.Of(uno), CoverArtHash.Of(otro));
    }

    [Fact]
    public void UnArregloVacioTieneResumenIgual()
    {
        // No se usa —sin bytes no hay carátula que resumir— pero no puede tirar
        // una excepción desde el camino de guardado.
        Assert.Equal(64, CoverArtHash.Of([]).Length);
    }
}
