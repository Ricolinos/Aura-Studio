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
    /// Nada se ofrece sin tener archivo. Es la única de las dos direcciones que
    /// vale siempre: ofrecer un idioma cuyo texto no existe es la falla
    /// silenciosa de siempre —el usuario lo elige, la app cae al español y nada
    /// avisa—. Al revés sí se puede, y hoy pasa.
    /// </summary>
    [Fact]
    public void NadaSeOfreceSinTenerArchivo() =>
        Assert.All(AppLanguages.Available, language => Assert.True(language.Built,
            $"«{language.Culture}» se ofrece y no tiene archivo: al elegirlo la app cae al español sin decir nada."));

    /// <summary>
    /// El instalador exige lo que se <b>genera</b>, no lo que se ofrece.
    ///
    /// <para>Y hoy no son lo mismo, que es justo lo que hace que valga la pena
    /// la prueba: los cuatro de B7c viajan dentro del instalador sin que el
    /// selector los muestre. Si a alguien le pareciera "más limpio" exigir solo
    /// los ofrecidos, los cuatro satélites dejarían de comprobarse, y el día que
    /// B7d los encienda podrían no estar.</para>
    /// </summary>
    [Fact]
    public void ElInstaladorExigeLoQueSeGeneraYNoLoQueSeOfrece()
    {
        Assert.Equal(
            AppLanguages.Translated.Where(language => language.Culture != AppLanguages.NeutralCulture)
                .Select(language => language.Culture),
            AppLanguages.RequiredSatelliteCultures);

        // La diferencia existe de verdad; si un día no existiera, esta prueba
        // estaría comparando dos veces la misma lista sin que nadie lo note.
        Assert.Contains(AppLanguages.RequiredSatelliteCultures,
            culture => AppLanguages.Available.All(language => language.Culture != culture));
    }

    /// <summary>
    /// Hoy se ofrecen español e inglés, y nada más.
    ///
    /// <para>Los cuatro de B7c están traducidos, compilados y viajando, y aun
    /// así apagados: la extracción de B7a está en los seis idiomas, pero unas
    /// trescientas frases quedaron fuera de esa extracción —instalador, errores
    /// de disco, permisos— y siguen en español. Ofrecer alemán así es prometer
    /// una app en alemán que a mitad del formateo cambia de idioma.</para>
    ///
    /// <para>Encenderlos es cambiar <c>Offered</c> y esta prueba: dos ediciones
    /// deliberadas, que es lo que se quiere para una decisión de este tamaño.
    /// Lo hace B7d cuando termine con esas trescientas.</para>
    /// </summary>
    [Fact]
    public void HoySeOfrecenElEspanolYElIngles()
    {
        Assert.Equal(["es", "en"], AppLanguages.Available.Select(language => language.Culture));

        Assert.Equal(
            ["de", "fr", "ja", "ru"],
            AppLanguages.Translated.Where(language => !language.Offered)
                .Select(language => language.Culture).Order(StringComparer.Ordinal));
    }

    /// <summary>
    /// Solo el español y el inglés están revisados por una persona.
    ///
    /// <para>Lo que fija esta prueba es que nadie declare revisado un idioma sin
    /// que un revisor humano haya pasado. Cuando B7d encienda los cuatro, lo
    /// harán con este <c>false</c> intacto y el selector los marcará "(beta)"
    /// diciendo que son traducción automática; un <c>true</c> de más acá apaga
    /// ese aviso y nadie lo notaría.</para>
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

    /// <summary>
    /// Y un idioma que no se ofrece no resuelve a nada, aunque su archivo
    /// exista.
    ///
    /// <para>Los cuatro últimos casos son los de B7c: están traducidos y
    /// compilados, así que arrancar en ellos "funcionaría". No tiene que
    /// hacerlo. Alguien con Windows en alemán abriría la app en alemán sin
    /// haberlo pedido y sin que el selector siquiera ofrezca ese idioma — y con
    /// las pantallas del instalador todavía en español.</para>
    /// </summary>
    [Theory]
    [InlineData("pt-BR")]
    [InlineData("it-IT")]
    [InlineData("de-DE")]
    [InlineData("fr-FR")]
    [InlineData("ja-JP")]
    [InlineData("ru-RU")]
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
