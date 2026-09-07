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
    /// Hoy se ofrecen dos y hace falta un satélite: el inglés. Cuando B7c suba
    /// los otros cuatro, esta prueba cambia con ellos — y que haya que venir a
    /// cambiarla es parte del punto.
    /// </summary>
    [Fact]
    public void HoySeOfrecenDosIdiomasYHaceFaltaUnSatelite()
    {
        Assert.Equal(["es", "en"], AppLanguages.Available.Select(language => language.Culture));
        Assert.Equal(["en"], AppLanguages.RequiredSatelliteCultures);
    }

    /// <summary>
    /// Lo que se ofrece está revisado por una persona. Es la regla que separa
    /// B7b de B7c: un idioma sin revisar puede estar en la lista, pero no se
    /// ofrece hasta que la app pueda decir que no lo está.
    /// </summary>
    [Fact]
    public void TodoLoQueSeOfreceHoyEstaRevisadoPorUnaPersona() =>
        Assert.All(AppLanguages.Available, language => Assert.True(
            language.ReviewedByHumans,
            $"{language.Culture} se ofrece sin estar revisado: o se marca la revisión, o se muestra con su aviso"));

    /// <summary>
    /// Los cuatro de B7c están declarados, sin archivo y sin revisar. Vivir en
    /// la lista desde ya es lo que evita que el día que lleguen alguien tenga
    /// que buscar en cuántos lugares estaba escrita.
    /// </summary>
    [Theory]
    [InlineData("de")]
    [InlineData("fr")]
    [InlineData("ja")]
    [InlineData("ru")]
    public void LosCuatroDeB7cEstanDeclaradosYTodaviaNoSeOfrecen(string culture)
    {
        AppLanguage language = Assert.Single(AppLanguages.All, entry => entry.Culture == culture);

        Assert.False(language.Ships, $"{culture} dice que ya tiene archivo: si es cierto, hay que ofrecerlo");
        Assert.False(language.ReviewedByHumans);
        Assert.DoesNotContain(language, AppLanguages.Available);
    }

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
    [InlineData("de-DE")]
    [InlineData("ja-JP")]
    [InlineData("pt-BR")]
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
