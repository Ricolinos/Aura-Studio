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
    /// <para>Mientras duró B7c las dos listas <b>diferían</b> —los cuatro
    /// viajaban dentro del instalador sin que el selector los mostrara— y esto
    /// se comprobaba mirando la tabla. Al encenderlos, en el cierre de B7d,
    /// dejaron de diferir, y ahí la prueba se volvió peligrosa: comparar dos
    /// listas que hoy coinciden no dice de cuál se derivó la otra. El comentario
    /// que estaba acá lo anticipaba —"si un día no existiera, estaría comparando
    /// dos veces la misma lista sin que nadie lo note"— y ese día llegó.</para>
    ///
    /// <para>Así que la diferencia ya no se busca en la tabla: se construye. Un
    /// idioma compilado y no ofrecido tiene que seguir siendo un satélite
    /// exigido, porque apagar uno del selector no puede sacarlo del instalador;
    /// si lo sacara, volver a encenderlo dejaría de ser una línea.</para>
    /// </summary>
    [Fact]
    public void ElInstaladorExigeLoQueSeGeneraYNoLoQueSeOfrece()
    {
        Assert.Equal(
            AppLanguages.Translated.Where(language => language.Culture != AppLanguages.NeutralCulture)
                .Select(language => language.Culture),
            AppLanguages.RequiredSatelliteCultures);

        AppLanguage[] table =
        [
            new("es", "Español", Built: true, Offered: true, ReviewedByHumans: true),
            new("de", "Deutsch", Built: true, Offered: false, ReviewedByHumans: false),
        ];

        Assert.Equal(
            ["de"],
            table.Where(language => language.Built && language.Culture != AppLanguages.NeutralCulture)
                .Select(language => language.Culture));

        Assert.DoesNotContain(table.Where(language => language.Offered),
            language => language.Culture == "de");
    }

    /// <summary>
    /// Se ofrecen los seis, y los cuatro de B7c sin revisar.
    ///
    /// <para>Durante B7c estuvieron traducidos, compilados y viajando, y aun así
    /// apagados: la extracción de B7a estaba en los seis idiomas, pero unas
    /// trescientas frases habían quedado fuera —instalador, errores de disco,
    /// permisos— y seguían en español. Ofrecer alemán así habría sido prometer
    /// una app en alemán que a mitad del formateo cambia de idioma. B7d sacó
    /// esas frases y por eso se encienden.</para>
    ///
    /// <para>Lo que <b>no</b> cambió es <c>ReviewedByHumans</c>: nadie en el
    /// proyecto lee estos cuatro idiomas, así que salen marcados. Encender el
    /// selector y dar por revisada la traducción son dos decisiones distintas y
    /// esta prueba las mantiene separadas.</para>
    /// </summary>
    [Fact]
    public void SeOfrecenLosSeisYLosCuatroDeB7cSiguenSinRevisar()
    {
        Assert.DoesNotContain(AppLanguages.Translated, language => !language.Offered);

        // Sobre `All` y no sobre `Available`: lo que esta prueba fija es la
        // TABLA —quién está revisado y quién no—, y eso no cambia con la
        // propiedad de compilación. Lo que sí cambia, qué se ofrece, lo
        // comprueban LanguageSelectorTests y OfferMachineTranslationsTests.
        Assert.Equal(
            ["de", "fr", "ja", "ru"],
            AppLanguages.All.Where(language => !language.ReviewedByHumans)
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
    /// Y un idioma que no se ofrece no resuelve a nada.
    ///
    /// <para>Hasta el cierre de B7d acá estaban también <c>de-DE</c>,
    /// <c>fr-FR</c>, <c>ja-JP</c> y <c>ru-RU</c>: traducidos y compilados, así
    /// que arrancar en ellos "habría funcionado", y justamente no debía —
    /// alguien con Windows en alemán habría abierto la app en alemán sin
    /// pedirlo, sin que el selector ofreciera ese idioma y con el instalador
    /// todavía en español. Ahora se ofrecen, y pasaron al caso de abajo.</para>
    /// </summary>
    [Theory]
    [InlineData("pt-BR")]
    [InlineData("it-IT")]
    [InlineData("zh-CN")]
    public void UnIdiomaQueNoSeOfreceNoResuelveANada(string culture) =>
        Assert.Null(AppLanguages.For(new CultureInfo(culture)));

    /// <summary>
    /// Los cuatro de B7c resuelven —si esta compilación los ofrece— por su
    /// idioma y no por su país: quien tiene Windows en <c>de-AT</c> o en
    /// <c>fr-CA</c> quiere su idioma, no el español porque no exista una entrada
    /// para su región.
    ///
    /// <para>Y si <c>OfferMachineTranslations</c> está apagado, no resuelven a
    /// nada. Esa mitad importa tanto como la otra: apagar la lista que se dibuja
    /// y olvidar la resolución automática dejaría a alguien con Windows en
    /// alemán usando la app en alemán, en un paquete que decidió no ofrecer
    /// alemán y cuyo selector muestra dos idiomas.</para>
    /// </summary>
    [Theory]
    [InlineData("de-DE", "de")]
    [InlineData("de-AT", "de")]
    [InlineData("fr-FR", "fr")]
    [InlineData("fr-CA", "fr")]
    [InlineData("ja-JP", "ja")]
    [InlineData("ru-RU", "ru")]
    public void LosCuatroDeB7cResuelvenSiEstaCompilacionLosOfrece(string culture, string expected) =>
        Assert.Equal(
            AppLanguages.OffersMachineTranslations ? expected : null,
            AppLanguages.For(new CultureInfo(culture))?.Culture);

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
