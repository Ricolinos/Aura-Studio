using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

public class CoverThumbnailKeyTests
{
    private static byte[] Cover(byte seed, int length = 2048)
    {
        byte[] data = new byte[length];
        for (int i = 0; i < length; i++) data[i] = (byte)(seed + i);
        return data;
    }

    [Fact]
    public void TheSameCoverInTwoSongsSharesOneThumbnail()
    {
        // Un álbum de 14 pistas tiene la misma carátula 14 veces; con una clave
        // por canción se decodificarían 14 miniaturas idénticas.
        Assert.Equal(CoverThumbnailKey.For(Cover(7), 96), CoverThumbnailKey.For(Cover(7), 96));
    }

    [Fact]
    public void TwoDifferentCoversNeverShareAKey()
        => Assert.NotEqual(CoverThumbnailKey.For(Cover(1), 96), CoverThumbnailKey.For(Cover(2), 96));

    [Fact]
    public void TwoCoversOfTheSameLengthStillDiffer()
    {
        // El largo solo no alcanza: dos portadas distintas pesan casi siempre
        // parecido, y confundirlas se ve como el disco equivocado en pantalla.
        byte[] a = Cover(0), b = Cover(0);
        b[^1] ^= 0xFF;
        Assert.Equal(a.Length, b.Length);
        Assert.NotEqual(CoverThumbnailKey.For(a, 96), CoverThumbnailKey.For(b, 96));
    }

    [Fact]
    public void EachSizeGetsItsOwnEntry()
    {
        // La misma carátula en la cuadrícula chica y en la grande son dos
        // miniaturas distintas.
        Assert.NotEqual(CoverThumbnailKey.For(Cover(3), 96), CoverThumbnailKey.For(Cover(3), 160));
    }

    [Fact]
    public void WithoutACoverThereIsNothingToCache()
    {
        Assert.Null(CoverThumbnailKey.For(null, 96));
        Assert.Null(CoverThumbnailKey.For([], 96));
        Assert.Null(CoverThumbnailKey.For(Cover(1), 0));
    }

    [Fact]
    public void TheKeyIsStableAcrossCalls()
    {
        // Se memoriza por instancia del arreglo; el valor no puede cambiar
        // entre la primera llamada y la segunda.
        byte[] cover = Cover(9);
        string? first = CoverThumbnailKey.For(cover, 96);
        Assert.Equal(first, CoverThumbnailKey.For(cover, 96));
        Assert.Equal(first, CoverThumbnailKey.For(Cover(9), 96));
    }
}
