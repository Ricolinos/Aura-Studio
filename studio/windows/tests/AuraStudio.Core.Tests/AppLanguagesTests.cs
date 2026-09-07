using System.Globalization;
using AuraStudio.Core.Resources;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La lista de idiomas, que es una sola y manda sobre todo lo demás (ST-247,
/// B7b).
///
/// <para>De <see cref="AppLanguages"/> salen tres cosas que antes habrían
/// estado escritas en tres lados: qué ofrece el selector, qué carpetas de
/// satélite tiene que traer el publish, y qué idiomas exige el instalador. Una
/// lista copiada es una lista que se desincroniza, y el síntoma sería el peor
/// posible — la app ofrece un idioma que no está y cae al español sin decir
/// nada.</para>
/// </summary>
public class AppLanguagesTests
{
    /// <summary>
    /// El español es la cultura neutra y por eso <b>no</b> es un satélite: va
    /// dentro del ensamblado para que la app nunca se quede sin texto.
    /// </summary>
    [Fact]
    public void ElEspanolNoEsUnSatelite()
    {
        Assert.Equal("es", AppLanguages.NeutralCulture);
        Assert.DoesNotContain(AppLanguages.NeutralCulture, AppLanguages.RequiredSatelliteCultures);
        Assert.Contains(AppLanguages.Available, language => language.Culture == "es");
    }

    /// <summary>
    /// Cada idioma que se ofrece tiene su archivo, y cada archivo que existe se
    /// ofrece. La lista y el disco dicen lo mismo.
    /// </summary>
    [Fact]
    public void LoQueSeOfreceEsExactamenteLoQueTieneArchivo()
    {
        Assert.Equal(
            AppLanguages.All.Where(language => language.Ships).Select(language => language.Culture),
            AppLanguages.Available.Select(language => language.Culture));

        Assert.Equal(
            AppLanguages.Available.Where(language => language.Culture != AppLanguages.NeutralCulture)
                .Select(language => language.Culture),
            AppLanguages.RequiredSatelliteCultures);
    }

    /// <summary>
    /// Solo el español y el inglés están revisados por una persona.
    ///
    /// <para>Los otros cuatro se ofrecen <b>sin</b> revisar, y eso es una
    /// decisión, no un descuido: la app los marca "(beta)" y dice que son
    /// traducción automática. Lo que esta prueba fija es que nadie los declare
    /// revisados sin que un revisor humano haya pasado — un <c>true</c> de más
    /// acá apaga el aviso en pantalla y nadie lo notaría.</para>
    /// </summary>
    [Fact]
    public void SoloElEspanolYElInglesEstanRevisadosPorUnaPersona() =>
        Assert.Equal(
            ["es", "en"],
            AppLanguages.All.Where(language => language.ReviewedByHumans).Select(language => language.Culture));

    /// <summary>
    /// El nombre de cada idioma está <b>en ese idioma</b>. Un selector que
    /// traduce los nombres no le sirve a la única persona que lo necesita: la
    /// que abrió la app en un idioma que no lee.
    /// </summary>
    [Fact]
    public void CadaIdiomaSeLlamaComoSeLlamaEnSuPropioIdioma()
    {
        Assert.Equal("Español", AppLanguages.All.Single(l => l.Culture == "es").Endonym);
        Assert.Equal("English", AppLanguages.All.Single(l => l.Culture == "en").Endonym);
        Assert.Equal("Deutsch", AppLanguages.All.Single(l => l.Culture == "de").Endonym);
        Assert.Equal("Français", AppLanguages.All.Single(l => l.Culture == "fr").Endonym);
        Assert.Equal("日本語", AppLanguages.All.Single(l => l.Culture == "ja").Endonym);
        Assert.Equal("Русский", AppLanguages.All.Single(l => l.Culture == "ru").Endonym);
    }

    /// <summary>
    /// El país no decide el idioma: quien tiene Windows en <c>en-GB</c> quiere
    /// inglés, no español porque no exista una entrada <c>en-GB</c>.
    /// </summary>
    [Theory]
    [InlineData("en-US", "en")]
    [InlineData("en-GB", "en")]
    [InlineData("es-MX", "es")]
    [InlineData("es-419", "es")]
    public void ElPaisNoDecideElIdioma(string culture, string expected) =>
        Assert.Equal(expected, AppLanguages.For(new CultureInfo(culture))?.Culture);

    /// <summary>Y un idioma que no se ofrece todavía no resuelve a nada.</summary>
    [Theory]
    [InlineData("pt-BR")]
    [InlineData("it-IT")]
    public void UnIdiomaQueNoSeOfreceNoResuelveANada(string culture) =>
        Assert.Null(AppLanguages.For(new CultureInfo(culture)));

    /// <summary>
    /// Ninguna cultura declarada dos veces, y todas válidas para .NET. Una
    /// cadena mal escrita acá no falla al compilar: falla al construir la
    /// <c>CultureInfo</c>, en el arranque, con la app ya abierta.
    /// </summary>
    [Fact]
    public void CadaCulturaEsValidaYApareceUnaSolaVez()
    {
        Assert.Equal(
            AppLanguages.All.Select(language => language.Culture).Distinct().Count(),
            AppLanguages.All.Count);

        Assert.All(AppLanguages.All, language =>
        {
            CultureInfo culture = new(language.Culture);
            Assert.Equal(language.Culture, culture.Name);
        });
    }
}
