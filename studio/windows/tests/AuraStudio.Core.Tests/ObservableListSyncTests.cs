using System.Collections.ObjectModel;
using System.Collections.Specialized;
using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El refresco diferencial de las cuadrículas (ST-201).
///
/// <para>Lo que importa no es solo que la colección quede bien: es <b>cuántos
/// avisos</b> costó dejarla bien. Cada aviso hace que el control rehaga
/// contenedores y vuelva a decodificar portadas, y el caso frecuente —refrescar
/// sin que haya cambiado nada— tiene que costar cero.</para>
/// </summary>
public class ObservableListSyncTests
{
    /// <summary>Una tarjeta de mentira: lo único que hace falta es su identidad.</summary>
    private sealed class Card(string name)
    {
        public string Name { get; } = name;
        public override string ToString() => Name;
    }

    private static (ObservableCollection<Card> Target, List<NotifyCollectionChangedAction> Events) Watched(
        params Card[] initial)
    {
        var target = new ObservableCollection<Card>(initial);
        List<NotifyCollectionChangedAction> events = [];
        target.CollectionChanged += (_, e) => events.Add(e.Action);
        return (target, events);
    }

    [Fact]
    public void SinCambiosNoTocaLaColeccion()
    {
        Card a = new("a"), b = new("b");
        (ObservableCollection<Card> target, List<NotifyCollectionChangedAction> events) = Watched(a, b);

        Assert.Equal(0, ObservableListSync.Apply(target, [a, b]));
        Assert.Empty(events);
    }

    [Fact]
    public void NoVuelveASuscribirLoQueNoCambio()
    {
        Card a = new("a"), b = new("b");
        var target = new ObservableCollection<Card>([a, b]);
        List<Card> added = [], removed = [];

        ObservableListSync.Apply(target, [a, b], added.Add, removed.Add);

        Assert.Empty(added);
        Assert.Empty(removed);
    }

    [Fact]
    public void AgregaAlFinal()
    {
        Card a = new("a"), b = new("b");
        (ObservableCollection<Card> target, List<NotifyCollectionChangedAction> events) = Watched(a);
        List<Card> added = [];

        ObservableListSync.Apply(target, [a, b], added.Add);

        Assert.Equal([a, b], target);
        Assert.Equal([b], added);
        Assert.Equal([NotifyCollectionChangedAction.Add], events);
    }

    [Fact]
    public void InsertaEnMedioSinTocarElResto()
    {
        Card a = new("a"), b = new("b"), c = new("c");
        (ObservableCollection<Card> target, List<NotifyCollectionChangedAction> events) = Watched(a, c);

        ObservableListSync.Apply(target, [a, b, c]);

        Assert.Equal([a, b, c], target);
        Assert.Equal([NotifyCollectionChangedAction.Add], events);
    }

    [Fact]
    public void QuitaLoQueYaNoEstaYAvisaDeSuBaja()
    {
        Card a = new("a"), b = new("b"), c = new("c");
        var target = new ObservableCollection<Card>([a, b, c]);
        List<Card> removed = [];

        ObservableListSync.Apply(target, [a, c], onRemoved: removed.Add);

        Assert.Equal([a, c], target);
        Assert.Equal([b], removed);
    }

    [Fact]
    public void ReemplazarUnaSolaTarjetaNoRehaceLasDemas()
    {
        // Es lo que pasa al aplicarle una tapa a un álbum: cambia esa tarjeta y
        // ninguna otra.
        Card a = new("a"), b = new("b"), c = new("c"), nuevaB = new("b");
        var target = new ObservableCollection<Card>([a, b, c]);
        List<Card> added = [], removed = [];

        ObservableListSync.Apply(target, [a, nuevaB, c], added.Add, removed.Add);

        Assert.Equal([a, nuevaB, c], target);
        Assert.Equal([nuevaB], added);
        Assert.Equal([b], removed);
    }

    [Fact]
    public void ReordenarUsaMovimientosYNoRehaceNingunaTarjeta()
    {
        Card a = new("a"), b = new("b"), c = new("c");
        var target = new ObservableCollection<Card>([a, b, c]);
        List<Card> added = [], removed = [];

        ObservableListSync.Apply(target, [c, b, a], added.Add, removed.Add);

        Assert.Equal([c, b, a], target);
        Assert.Empty(added);
        Assert.Empty(removed);
    }

    [Fact]
    public void VaciarLaDejaVacia()
    {
        Card a = new("a"), b = new("b");
        var target = new ObservableCollection<Card>([a, b]);
        List<Card> removed = [];

        ObservableListSync.Apply(target, [], onRemoved: removed.Add);

        Assert.Empty(target);
        Assert.Equal(2, removed.Count);
    }

    [Fact]
    public void LlenarUnaColeccionVaciaSuscribeTodo()
    {
        Card a = new("a"), b = new("b");
        var target = new ObservableCollection<Card>();
        List<Card> added = [];

        ObservableListSync.Apply(target, [a, b], added.Add);

        Assert.Equal([a, b], target);
        Assert.Equal([a, b], added);
    }

    [Fact]
    public void UnCambioCompletoDejaExactamenteLoPedido()
    {
        Card a = new("a"), b = new("b"), x = new("x"), y = new("y");
        var target = new ObservableCollection<Card>([a, b]);

        ObservableListSync.Apply(target, [x, y]);

        Assert.Equal([x, y], target);
    }

    [Fact]
    public void CualquierMezclaTerminaIgualALoPedido()
    {
        // Barrido: lo que importa de un algoritmo de diferencias es que NUNCA
        // deje la colección distinta de lo pedido. Se prueban todas las
        // combinaciones de un alfabeto chico en vez de tres casos elegidos.
        Card[] alfabeto = [new("a"), new("b"), new("c"), new("d")];
        var random = new Random(20260906);

        for (int intento = 0; intento < 400; intento++)
        {
            var target = new ObservableCollection<Card>(Subconjunto(alfabeto, random));
            List<Card> desired = Subconjunto(alfabeto, random);

            ObservableListSync.Apply(target, desired);

            Assert.Equal(desired, target);
        }
    }

    private static List<Card> Subconjunto(Card[] alfabeto, Random random) =>
        [.. alfabeto.Where(_ => random.Next(2) == 0).OrderBy(_ => random.Next())];
}
