using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El orden y el costo de la caché de miniaturas (ST-205). Lo que se protege es
/// que el tope sea de <b>memoria</b> y no de cantidad, que se suelte lo más
/// viejo y no lo primero que se encuentre, y que nada de esto recorra la lista.
/// </summary>
public class ThumbnailCacheIndexTests
{
    private const long OneMegabyte = 1024 * 1024;

    [Fact]
    public void LoQueEntraEsta()
    {
        var index = new ThumbnailCacheIndex();

        Assert.Empty(index.Add("a", OneMegabyte));

        Assert.True(index.Contains("a"));
        Assert.Equal(1, index.Count);
        Assert.Equal(OneMegabyte, index.Cost);
    }

    [Fact]
    public void MarcarComoRecienteNoAgregaLoQueNoEstaba()
    {
        var index = new ThumbnailCacheIndex();

        // Agregarlo sin su imagen dejaría el índice diciendo que hay algo que no
        // hay, y la caché devolvería null creyendo que lo tiene.
        Assert.False(index.Touch("a"));
        Assert.Equal(0, index.Count);
    }

    [Fact]
    public void SeSueltaLoMasViejoCuandoYaNoCabe()
    {
        var index = new ThumbnailCacheIndex(costLimit: 3 * OneMegabyte);

        index.Add("a", OneMegabyte);
        index.Add("b", OneMegabyte);
        index.Add("c", OneMegabyte);

        IReadOnlyList<string> evicted = index.Add("d", OneMegabyte);

        Assert.Equal(["a"], evicted);
        Assert.False(index.Contains("a"));
        Assert.Equal(["b", "c", "d"], index.KeysOldestFirst);
        Assert.Equal(3 * OneMegabyte, index.Cost);
    }

    [Fact]
    public void UsarUnaLaSalvaDeLaProximaExpulsion()
    {
        var index = new ThumbnailCacheIndex(costLimit: 3 * OneMegabyte);

        index.Add("a", OneMegabyte);
        index.Add("b", OneMegabyte);
        index.Add("c", OneMegabyte);

        // Desplazarse hacia atrás vuelve a pedir "a": ya no es la más vieja.
        Assert.True(index.Touch("a"));

        Assert.Equal(["b"], index.Add("d", OneMegabyte));
        Assert.True(index.Contains("a"));
    }

    [Fact]
    public void ElTopeEsDeMemoriaNoDeCantidad()
    {
        var index = new ThumbnailCacheIndex(costLimit: 10 * OneMegabyte);

        // Cien miniaturas chicas caben; dos grandes, no. Un tope por cantidad no
        // sabría la diferencia.
        for (int n = 0; n < 100; n++) index.Add($"chica-{n}", 64 * 1024);

        Assert.Equal(100, index.Count);
        Assert.True(index.Cost < index.CostLimit);

        index.Add("grande-1", 6 * OneMegabyte);
        IReadOnlyList<string> evicted = index.Add("grande-2", 6 * OneMegabyte);

        Assert.Contains("grande-1", evicted);
        Assert.True(index.Cost <= index.CostLimit);
    }

    [Fact]
    public void UnaQueSolaNoCabeNoSeGuarda()
    {
        var index = new ThumbnailCacheIndex(costLimit: OneMegabyte);

        index.Add("a", 512 * 1024);
        IReadOnlyList<string> evicted = index.Add("enorme", 4 * OneMegabyte);

        // Guardarla habría vaciado la caché entera para nada.
        Assert.Equal(["enorme"], evicted);
        Assert.False(index.Contains("enorme"));
        Assert.True(index.Contains("a"));
    }

    [Fact]
    public void ReemplazarNoCuentaElCostoDosVeces()
    {
        var index = new ThumbnailCacheIndex();

        index.Add("a", OneMegabyte);
        index.Add("a", 2 * OneMegabyte);

        Assert.Equal(1, index.Count);
        Assert.Equal(2 * OneMegabyte, index.Cost);
    }

    [Fact]
    public void SacarUnaDevuelveSiEstaba()
    {
        var index = new ThumbnailCacheIndex();

        index.Add("a", OneMegabyte);

        Assert.True(index.Remove("a"));
        Assert.False(index.Remove("a"));
        Assert.Equal(0, index.Cost);
    }

    [Fact]
    public void VaciarDevuelveTodoLoQueHabiaParaSoltarlo()
    {
        var index = new ThumbnailCacheIndex();

        index.Add("a", OneMegabyte);
        index.Add("b", OneMegabyte);

        Assert.Equal(["a", "b"], index.Clear());
        Assert.Equal(0, index.Count);
        Assert.Equal(0, index.Cost);
    }

    [Fact]
    public void UnCostoAbsurdoNoRompeLaCuenta()
    {
        var index = new ThumbnailCacheIndex();

        // Una miniatura de 0x0 no existe, pero si llegara no puede dejar el
        // índice creciendo sin costo hasta llenarse de entradas gratis.
        index.Add("a", 0);
        index.Add("b", -100);

        Assert.Equal(2, index.Cost);
    }

    [Fact]
    public void ElTopePredeterminadoEsDeSesentaYCuatroMegabytes()
    {
        Assert.Equal(64L * 1024 * 1024, ThumbnailCacheIndex.DefaultCostLimit);
        Assert.Equal(ThumbnailCacheIndex.DefaultCostLimit, new ThumbnailCacheIndex().CostLimit);

        // Un tope de cero o negativo sería una caché que no guarda nada: se lee
        // como "no lo configuraron".
        Assert.Equal(ThumbnailCacheIndex.DefaultCostLimit, new ThumbnailCacheIndex(0).CostLimit);
    }

    // MARK: - La clave (ST-205 sobre ST-031)

    [Fact]
    public void LaClavePorHashNoNecesitaLosBytes()
    {
        // Es lo que hace que la caché responda sin tocar el disco: el hash ya
        // está en el catálogo desde ST-208.
        string? key = CoverThumbnailKey.ForHash("ABCDEF", 304);

        Assert.NotNull(key);
        Assert.Equal(key, CoverThumbnailKey.ForHash("ABCDEF", 304));
        Assert.NotEqual(key, CoverThumbnailKey.ForHash("ABCDEF", 96));
        Assert.NotEqual(key, CoverThumbnailKey.ForHash("FEDCBA", 304));
    }

    [Fact]
    public void SinHashNoHayClavePorHash()
    {
        Assert.Null(CoverThumbnailKey.ForHash(null, 304));
        Assert.Null(CoverThumbnailKey.ForHash("", 304));
        Assert.Null(CoverThumbnailKey.ForHash("ABCDEF", 0));
    }

    [Fact]
    public void LaClavePorRutaDistingueRutaYLado()
    {
        string? key = CoverThumbnailKey.ForPath(@"C:\fotos\a.jpg", 304);

        Assert.NotNull(key);
        Assert.Equal(key, CoverThumbnailKey.ForPath(@"C:\fotos\a.jpg", 304));
        Assert.NotEqual(key, CoverThumbnailKey.ForPath(@"C:\fotos\b.jpg", 304));
        Assert.NotEqual(key, CoverThumbnailKey.ForPath(@"C:\fotos\a.jpg", 96));
        Assert.Null(CoverThumbnailKey.ForPath(null, 304));
    }

    [Fact]
    public void LaClavePorRutaNoSeConfundeConLaDeContenido()
    {
        // Un hash y una ruta que se escribieran igual pedirían la misma
        // miniatura, y son cosas distintas.
        Assert.NotEqual(
            CoverThumbnailKey.ForHash("ABCDEF", 304),
            CoverThumbnailKey.ForPath("ABCDEF", 304));
    }
}
