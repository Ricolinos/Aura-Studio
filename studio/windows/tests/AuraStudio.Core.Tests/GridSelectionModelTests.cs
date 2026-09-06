using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La selección como lógica pura (ST-201). Lo que se prueba es lo que la vista
/// usa para no tocar más tarjetas de las que cambiaron: <b>el delta</b>. Un
/// delta de más es un recorrido de 1 091 tarjetas; un delta de menos es una
/// casilla que se queda marcada mintiendo.
/// </summary>
public class GridSelectionModelTests
{
    [Fact]
    public void EmpiezaVacia()
    {
        var selection = new GridSelectionModel();

        Assert.Equal(0, selection.Count);
        Assert.False(selection.Any);
        Assert.False(selection.Contains("a"));
    }

    [Fact]
    public void LaCasillaSumaYQuitaSinTocarElResto()
    {
        var selection = new GridSelectionModel();

        SelectionDelta suma = selection.Toggle("a");
        Assert.Equal(["a"], suma.Selected);
        Assert.Empty(suma.Deselected);

        selection.Toggle("b");
        Assert.Equal(2, selection.Count);

        SelectionDelta quita = selection.Toggle("a");
        Assert.Empty(quita.Selected);
        Assert.Equal(["a"], quita.Deselected);
        Assert.True(selection.Contains("b"));
    }

    [Fact]
    public void ElClicReemplazaYSoloAvisaDeLoQueCambio()
    {
        var selection = new GridSelectionModel();
        selection.SelectAll(["a", "b", "c"]);

        SelectionDelta delta = selection.SelectOnly("b");

        // "b" ya estaba marcado: no cambia, así que no viaja en el delta.
        Assert.Empty(delta.Selected);
        Assert.Equal(["a", "c"], [.. delta.Deselected.Order(StringComparer.Ordinal)]);
        Assert.Equal(1, selection.Count);
        Assert.True(selection.Contains("b"));
    }

    [Fact]
    public void ElClicSobreElUnicoYaMarcadoNoCambiaNada()
    {
        // Es el caso más frecuente de todos —volver a hacer clic donde ya se
        // estaba—, y es el que tiene que costar cero.
        var selection = new GridSelectionModel();
        selection.SelectOnly("a");

        Assert.True(selection.SelectOnly("a").IsEmpty);
    }

    [Fact]
    public void ElClicSobreOtroMarcaElNuevoYDesmarcaElAnterior()
    {
        var selection = new GridSelectionModel();
        selection.SelectOnly("a");

        SelectionDelta delta = selection.SelectOnly("b");

        Assert.Equal(["b"], delta.Selected);
        Assert.Equal(["a"], delta.Deselected);
    }

    [Fact]
    public void VaciarUnaSeleccionVaciaNoAvisa()
    {
        var selection = new GridSelectionModel();

        Assert.True(selection.Clear().IsEmpty);
    }

    [Fact]
    public void VaciarDevuelveTodoLoQueEstabaMarcado()
    {
        var selection = new GridSelectionModel();
        selection.SelectAll(["a", "b"]);

        SelectionDelta delta = selection.Clear();

        Assert.Equal(["a", "b"], [.. delta.Deselected.Order(StringComparer.Ordinal)]);
        Assert.False(selection.Any);
    }

    [Fact]
    public void SeleccionarTodoSoloAvisaDeLosQueFaltaban()
    {
        var selection = new GridSelectionModel();
        selection.Toggle("b");

        SelectionDelta delta = selection.SelectAll(["a", "b", "c"]);

        Assert.Equal(["a", "c"], [.. delta.Selected.Order(StringComparer.Ordinal)]);
        Assert.Empty(delta.Deselected);
        Assert.Equal(3, selection.Count);
    }

    [Fact]
    public void SeleccionarTodoConTodoYaMarcadoNoAvisa()
    {
        var selection = new GridSelectionModel();
        selection.SelectAll(["a", "b"]);

        Assert.True(selection.SelectAll(["a", "b"]).IsEmpty);
    }

    [Fact]
    public void ReemplazarDejaExactamenteEsaSeleccion()
    {
        var selection = new GridSelectionModel();
        selection.SelectAll(["a", "b"]);

        SelectionDelta delta = selection.Replace(["b", "c"]);

        Assert.Equal(["c"], delta.Selected);
        Assert.Equal(["a"], delta.Deselected);
        Assert.Equal(["b", "c"], [.. selection.Ids.Order(StringComparer.Ordinal)]);
    }

    [Fact]
    public void ReemplazarPorLoMismoNoAvisa()
    {
        // Lo va a usar W2 cada vez que el control publique su SelectedItems:
        // sin esto, sincronizarse con el control sería un aviso por evento.
        var selection = new GridSelectionModel();
        selection.SelectAll(["a", "b"]);

        Assert.True(selection.Replace(["b", "a"]).IsEmpty);
    }

    [Fact]
    public void TrasRefrescarSeQuedanSoloLosQueSiguenExistiendo()
    {
        var selection = new GridSelectionModel();
        selection.SelectAll(["a", "b", "c"]);

        SelectionDelta delta = selection.Retain(["a", "c"]);

        Assert.Equal(["b"], delta.Deselected);
        Assert.Equal(["a", "c"], [.. selection.Ids.Order(StringComparer.Ordinal)]);
    }

    [Fact]
    public void ConservarTodoLoQueSigueNoAvisa()
    {
        var selection = new GridSelectionModel();
        selection.SelectAll(["a", "b"]);

        Assert.True(selection.Retain(["a", "b", "c"]).IsEmpty);
    }

    [Fact]
    public void ConservarSobreUnaSeleccionVaciaNoRecorreNada()
    {
        var selection = new GridSelectionModel();

        Assert.True(selection.Retain(["a", "b"]).IsEmpty);
    }

    [Fact]
    public void MarcarLoQueYaEstabaMarcadoNoAvisa()
    {
        var selection = new GridSelectionModel();
        selection.Set("a", true);

        Assert.True(selection.Set("a", true).IsEmpty);
        Assert.True(selection.Set("b", false).IsEmpty);
    }

    [Fact]
    public void LosIdentificadoresDistinguenMayusculas()
    {
        // Las claves de álbum ya vienen normalizadas de LibraryGrouping; volver a
        // igualar mayúsculas acá fusionaría dos grupos que la cuadrícula muestra
        // separados.
        var selection = new GridSelectionModel();
        selection.Toggle("Kid A");

        Assert.False(selection.Contains("kid a"));
    }
}
