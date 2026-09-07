using AuraStudio.Tools.ExtraerCadenasWindows;
using Xunit;

namespace ExtraerCadenasWindows.Tests;

/// <summary>
/// Coordinador (ítem 2 del addendum sobre huecos): la misma expresión
/// interpolada repetida en un mismo texto tiene que reusar el índice, no
/// numerar uno nuevo cada vez -- caso real: <c>app-strings.installer-family-change</c>,
/// <c>{installed}</c> aparece dos veces.
/// </summary>
public class InterpolationHolesTests
{
    [Fact]
    public void LaMismaExpresionRepetidaReusaElMismoIndice()
    {
        (string converted, bool hasInterpolation) = InterpolationHoles.Convert(
            "Este iPod tiene {installed} instalado y vas a instalar {target}. " +
            "{installed} se guarda completo.");

        Assert.True(hasInterpolation);
        Assert.Equal(
            "Este iPod tiene {0} instalado y vas a instalar {1}. {0} se guarda completo.",
            converted);
    }

    [Fact]
    public void ExpresionesDistintasNumeranEnOrdenDeAparicion()
    {
        (string converted, bool hasInterpolation) = InterpolationHoles.Convert(
            "{a} y {b} y {c}");

        Assert.True(hasInterpolation);
        Assert.Equal("{0} y {1} y {2}", converted);
    }

    [Fact]
    public void MismaVariableConFormatoDistintoNoComparteIndice()
    {
        // El especificador de formato es parte de la expresión completa: si
        // cambia, no es "el mismo dato" para el traductor -- se trata como
        // hueco distinto.
        (string converted, bool hasInterpolation) = InterpolationHoles.Convert(
            "{count} de {count:0.0}");

        Assert.True(hasInterpolation);
        Assert.Equal("{0} de {1}", converted);
    }

    [Fact]
    public void SinHuecosDevuelveElTextoTalCual()
    {
        (string converted, bool hasInterpolation) = InterpolationHoles.Convert("Sin huecos aquí");

        Assert.False(hasInterpolation);
        Assert.Equal("Sin huecos aquí", converted);
    }
}
