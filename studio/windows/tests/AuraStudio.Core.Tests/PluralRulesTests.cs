using System.Globalization;
using AuraStudio.Core.Resources;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Las reglas de plural por idioma (ST-247).
///
/// <para>La app tenía cincuenta y un ternarios
/// <c>count == 1 ? "1 canción" : $"{count} canciones"</c>. Eso no es una
/// condición: es la regla del plural del español escrita a mano, cincuenta y
/// una veces. Cada uno sería un texto mal escrito en cuanto la app hable otro
/// idioma — y no un error de compilación, sino algo que alguien lee mal en su
/// pantalla.</para>
///
/// <para>Lo que se protege acá es <b>la tabla</b> —qué forma le toca a qué
/// número en cada familia de idiomas—, que es lo que hay que acertar y lo único
/// que un humano puede revisar leyendo. Se llama a
/// <see cref="PluralRules"/> directamente: las reglas viven en Core desde que
/// los recursos se mudaron ahí, así que la prueba corre contra el código que
/// corre en la app y no contra una copia suya.</para>
/// </summary>
public class PluralRulesTests
{
    // MARK: - Español e inglés: dos formas

    [Theory]
    [InlineData(1, ".one")]
    [InlineData(0, ".other")]
    [InlineData(2, ".other")]
    [InlineData(21, ".other")]
    [InlineData(100, ".other")]
    public void EspanolDistingueUnoDelResto(int count, string expected) =>
        Assert.Equal(expected, SuffixFor(count, "es-MX"));

    [Theory]
    [InlineData(1, ".one")]
    [InlineData(0, ".other")]
    [InlineData(11, ".other")]
    public void InglesTambien(int count, string expected) =>
        Assert.Equal(expected, SuffixFor(count, "en-US"));

    /// <summary>
    /// El cero va en plural en español —"0 canciones"— y esa es justamente la
    /// razón por la que la regla no es "count > 1".
    /// </summary>
    [Fact]
    public void ElCeroVaEnPlural() => Assert.Equal(".other", SuffixFor(0, "es-MX"));

    // MARK: - Japonés: una sola forma

    [Theory]
    [InlineData(0)]
    [InlineData(1)]
    [InlineData(2)]
    [InlineData(11)]
    public void ElJaponesNoDistingueNumero(int count) =>
        Assert.Equal(".other", SuffixFor(count, "ja-JP"));

    // MARK: - Ruso: tres formas, con la trampa de los adolescentes

    [Theory]
    [InlineData(1, ".one")]
    [InlineData(21, ".one")]
    [InlineData(101, ".one")]
    [InlineData(2, ".few")]
    [InlineData(4, ".few")]
    [InlineData(22, ".few")]
    [InlineData(5, ".many")]
    [InlineData(0, ".many")]
    [InlineData(100, ".many")]
    public void ElRusoUsaTresFormas(int count, string expected) =>
        Assert.Equal(expected, SuffixFor(count, "ru-RU"));

    /// <summary>
    /// La trampa: 11, 12, 13 y 14 <b>no</b> siguen a 1, 2, 3 y 4 — van todos a
    /// "muchos". Es el error clásico de quien implementa el plural ruso mirando
    /// solo el último dígito.
    /// </summary>
    [Theory]
    [InlineData(11)]
    [InlineData(12)]
    [InlineData(13)]
    [InlineData(14)]
    [InlineData(111)]
    [InlineData(112)]
    public void LosOnceAlCatorceNoSiguenAlUltimoDigito(int count) =>
        Assert.Equal(".many", SuffixFor(count, "ru-RU"));

    /// <summary>El país no cambia el plural: <c>es-MX</c> y <c>es-ES</c> pluralizan igual.</summary>
    [Fact]
    public void ElPaisNoCambiaElPlural()
    {
        Assert.Equal(SuffixFor(1, "es-MX"), SuffixFor(1, "es-ES"));
        Assert.Equal(SuffixFor(3, "es-MX"), SuffixFor(3, "es-419"));
    }


    // MARK: - Francés: el cero va en singular

    /// <summary>
    /// La trampa de suponer que "dos formas" significa la misma regla en todos
    /// los idiomas: en francés el <b>cero</b> va en singular ("0 chanson"),
    /// mientras que en español va en plural ("0 canciones").
    /// </summary>
    [Theory]
    [InlineData(0, ".one")]
    [InlineData(1, ".one")]
    [InlineData(2, ".other")]
    public void ElFrancesPoneElCeroEnSingular(int count, string expected) =>
        Assert.Equal(expected, SuffixFor(count, "fr-FR"));

    [Fact]
    public void YEspanolNo() => Assert.Equal(".other", SuffixFor(0, "es-MX"));
    // MARK: - Las reglas de verdad

    /// <summary>
    /// Se llama a las reglas de verdad, no a una copia. Al mudar los recursos a
    /// Core (ST-247) esta prueba dejó de tener que reimplementar la tabla: lo
    /// que se prueba es el código que corre en la app, que es de lo que sirve
    /// una prueba.
    /// </summary>
    private static string SuffixFor(int count, string culture) =>
        PluralRules.SuffixFor(count, new CultureInfo(culture));
}
