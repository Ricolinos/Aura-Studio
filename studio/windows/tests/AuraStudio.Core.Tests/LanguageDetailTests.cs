using System.Globalization;
using AuraStudio.Core.Resources;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Lo que la explicación del selector promete es lo que la app hace hoy
/// (ST-247, addendum de 0.4.1).
///
/// <para><b>El caso que la trajo.</b> El texto decía que «el español y el inglés
/// los revisó una persona; los demás <b>llegan después</b>». Era cierto mientras
/// se ofrecían dos idiomas, y dejó de serlo el día que se encendieron los
/// cuatro: seguían apareciendo, ya habían llegado, y la app le decía al usuario
/// que estaban por venir. En japonés era todavía más literal —
/// 「ほかの言語は後から届きます」, «los demás idiomas llegarán más tarde»— y así
/// salió en las capturas.</para>
///
/// <para><b>Una frase que describe a la app envejece cuando la app cambia</b>, y
/// no hay compilador que avise. Ya había pasado con
/// <c>settings-language-detail</c> en B7b, cuando decía que Windows no tenía
/// selector de idioma; está anotado en <c>SpanishUnchangedTests.Redacted</c>
/// como cambio deliberado y volvió a pasar por lo mismo.</para>
///
/// <para><b>Por qué el texto nuevo no enumera los cuatro.</b> Nombrar «alemán,
/// francés, japonés y ruso» habría creado una lista escrita a mano al lado de la
/// lista de verdad, que es exactamente cómo se separaron los separadores de
/// colaboraciones. Dice «los demás»: mientras los revisados sean español e
/// inglés —y eso lo fija <c>AppLanguagesTests</c>— la frase no puede quedar
/// vieja por mucho que cambie el resto de la tabla.</para>
/// </summary>
public class LanguageDetailTests
{
    private static T WithUiCulture<T>(string culture, Func<T> body)
    {
        CultureInfo before = CultureInfo.CurrentUICulture;
        try
        {
            CultureInfo.CurrentUICulture = new CultureInfo(culture);
            return body();
        }
        finally
        {
            CultureInfo.CurrentUICulture = before;
        }
    }

    public static TheoryData<string> Cultures()
    {
        TheoryData<string> data = [];
        foreach (AppLanguage language in AppLanguages.Translated) data.Add(language.Culture);
        return data;
    }

    /// <summary>
    /// La explicación cita la marca <b>tal como la escribe ese idioma</b>.
    ///
    /// <para>Es lo que ata las dos cadenas: si alguien cambia «(beta)» por otra
    /// cosa en un idioma, la explicación de ese idioma queda hablando de una
    /// marca que el selector ya no pone, y esto se pone rojo. Sin esta prueba
    /// serían dos textos sueltos que casualmente coinciden hoy.</para>
    /// </summary>
    [Theory]
    [MemberData(nameof(Cultures))]
    public void LaExplicacionCitaLaMarcaDeEseIdioma(string culture)
    {
        (string detail, string mark) = WithUiCulture(culture, () => (
            Strings.Get("app-strings.settings-language-detail"),
            Strings.Get(LanguageBadge.MarkKey)));

        Assert.False(string.IsNullOrWhiteSpace(mark), $"la marca está vacía en {culture}");

        Assert.Contains(mark, detail, StringComparison.Ordinal);
    }

    /// <summary>
    /// Y ya no promete que falten idiomas por llegar.
    ///
    /// <para>Se buscan las formas concretas que tenía cada idioma, no una idea
    /// general: es una prueba contra <b>esta</b> frase vieja, la que estuvo en
    /// pantalla. Una comprobación difusa —«que no diga nada sobre el futuro»— no
    /// se puede escribir sin inventarse un criterio, y lo que hay que impedir es
    /// que alguien restaure el texto anterior por error.</para>
    /// </summary>
    [Theory]
    [InlineData("es", "llegan después")]
    [InlineData("en", "arrive later")]
    [InlineData("de", "kommen später")]
    [InlineData("fr", "arrivent plus tard")]
    [InlineData("ja", "後から届きます")]
    [InlineData("ru", "придут позже")]
    public void YaNoPrometeQueFaltenIdiomasPorLlegar(string culture, string promise) =>
        Assert.DoesNotContain(
            promise,
            WithUiCulture(culture, () => Strings.Get("app-strings.settings-language-detail")),
            StringComparison.Ordinal);

    /// <summary>
    /// En ruso, «canción» es <b>трек</b>, que es lo que fijó el glosario
    /// (<c>glosario-plataforma.csv</c>: es el término dominante en los
    /// reproductores). La barra lateral decía «Композиции».
    ///
    /// <para>Se comprueban las dos mitades. <b>Композитор</b> es «compositor»,
    /// otra palabra, y se queda; y «текст песни» es la colocación fija de
    /// «letra» en ruso —no es una forma alternativa de decir canción— así que
    /// también se queda. Una prueba que solo prohibiera la raíz habría barrido
    /// las dos y nadie habría entendido por qué.</para>
    /// </summary>
    [Fact]
    public void EnRusoUnaCancionEsUnTrek()
    {
        string sidebar = WithUiCulture("ru", () => Strings.Get("app-strings.nav-songs"));
        Assert.Equal("Треки", sidebar);

        string playlists = WithUiCulture("ru",
            () => Strings.Get("playlists-page.crea-nueva-o-importa-archivo-m3u"));
        Assert.StartsWith("Создайте", playlists, StringComparison.Ordinal);
        Assert.Contains("Треки", playlists, StringComparison.Ordinal);
        Assert.DoesNotContain("Композиции", playlists, StringComparison.Ordinal);

        // Y lo que NO se toca, para que quede escrito por qué.
        Assert.Contains("Композитор",
            WithUiCulture("ru", () => Strings.Get("music-column.composer")),
            StringComparison.Ordinal);
    }
}
