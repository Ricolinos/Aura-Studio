using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El almacén de la selección de la vista activa (ST-202). Lo que se protege es
/// <b>cuándo avisa</b>: un aviso de más vuelve a poner a toda la biblioteca en
/// el camino de cada clic, que es de lo que ST-202 la sacó.
/// </summary>
public class SelectionStoreTests
{
    private static Guid[] Ids(int count) => [.. Enumerable.Range(0, count).Select(_ => Guid.NewGuid())];

    [Fact]
    public void EmpiezaVacio()
    {
        var store = new SelectionStore();

        Assert.Empty(store.Selected);
        Assert.Equal(0, store.Count);
        Assert.False(store.Any);
    }

    [Fact]
    public void PublicarAlgoNuevoAvisaUnaVez()
    {
        var store = new SelectionStore();
        Guid[] ids = Ids(3);
        int avisos = 0;
        store.Changed += (_, _) => avisos++;

        Assert.True(store.Replace(ids));

        Assert.Equal(1, avisos);
        Assert.Equal(3, store.Count);
        Assert.True(store.Contains(ids[0]));
    }

    [Fact]
    public void PublicarLoMismoNoAvisa()
    {
        // Es el aviso que cerraba el ciclo de ST-161: refrescar publica la
        // selección, publicar avisa, el aviso vuelve a refrescar.
        var store = new SelectionStore();
        Guid[] ids = Ids(3);
        store.Replace(ids);

        int avisos = 0;
        store.Changed += (_, _) => avisos++;

        Assert.False(store.Replace(ids));
        Assert.Equal(0, avisos);
    }

    [Fact]
    public void PublicarLoMismoEnOtroOrdenTampocoAvisa()
    {
        // Es un CONJUNTO: ni el orden ni las repeticiones cambian a qué llega
        // «Solo la selección», así que tampoco pueden contar como un cambio.
        var store = new SelectionStore();
        Guid[] ids = Ids(3);
        store.Replace(ids);

        int avisos = 0;
        store.Changed += (_, _) => avisos++;

        Assert.False(store.Replace([ids[2], ids[0], ids[1], ids[0]]));
        Assert.Equal(0, avisos);
    }

    [Fact]
    public void UnaListaNuevaConLosMismosIdentificadoresNoAvisa()
    {
        // Cada refresco de una cuadrícula arma una lista nueva: comparar
        // referencias diría "cambió" siempre.
        var store = new SelectionStore();
        Guid[] ids = Ids(2);
        store.Replace(ids);

        int avisos = 0;
        store.Changed += (_, _) => avisos++;

        Assert.False(store.Replace(new List<Guid>(ids)));
        Assert.Equal(0, avisos);
    }

    [Fact]
    public void VaciarAvisaUnaVezYSoloSiHabiaAlgo()
    {
        var store = new SelectionStore();
        int avisos = 0;
        store.Changed += (_, _) => avisos++;

        Assert.False(store.Clear());
        Assert.Equal(0, avisos);

        store.Replace(Ids(2));
        avisos = 0;

        Assert.True(store.Clear());
        Assert.Equal(1, avisos);
        Assert.False(store.Any);
    }

    [Fact]
    public void PublicarVacioSobreAlgoEsVaciar()
    {
        var store = new SelectionStore();
        store.Replace(Ids(2));

        Assert.True(store.Replace([]));
        Assert.Equal(0, store.Count);
    }

    [Fact]
    public void QuitarUnoDeLaSeleccionAvisa()
    {
        var store = new SelectionStore();
        Guid[] ids = Ids(3);
        store.Replace(ids);

        int avisos = 0;
        store.Changed += (_, _) => avisos++;

        Assert.True(store.Replace([ids[0], ids[1]]));
        Assert.Equal(1, avisos);
        Assert.False(store.Contains(ids[2]));
    }

    [Fact]
    public void LoPublicadoNoCambiaSiQuienLoPublicoMutaSuLista()
    {
        // El almacén se queda con una copia: si conservara la lista de quien
        // publicó, la selección cambiaría a sus espaldas y sin aviso.
        var store = new SelectionStore();
        Guid[] ids = Ids(2);
        List<Guid> mutable = [.. ids];

        store.Replace(mutable);
        mutable.Add(Guid.NewGuid());

        Assert.Equal(2, store.Count);
    }
}
