using System.Globalization;
using System.Xml.Linq;
using AuraStudio.Core.Resources;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Cada idioma existe, sale de verdad, y dice lo mismo que el español
/// (ST-247, B7b para el inglés; B7c para los otros cuatro).
///
/// <para><b>Que el archivo esté no prueba nada.</b> Un <c>.resx</c> con la
/// cultura en el nombre puede quedar fuera del ensamblado satélite por un
/// detalle del proyecto, y entonces la app pide inglés y recibe español sin
/// que falle nada: los textos salen, se ven bien, y están en el idioma
/// equivocado. Es un modo de falla silencioso, así que acá se pide el texto
/// <b>con la cultura puesta</b> y se comprueba que cambie.</para>
/// </summary>
public class SatelliteResourcesTests
{
    private static string StringsDirectory()
    {
        DirectoryInfo? directory = new(AppContext.BaseDirectory);

        while (directory is not null)
        {
            string candidate = Path.Combine(directory.FullName, "studio", "windows", "AuraStudio.Core", "Strings");
            if (Directory.Exists(candidate)) return candidate;

            directory = directory.Parent;
        }

        throw new InvalidOperationException("No se encontró la carpeta de recursos desde el directorio de pruebas.");
    }

    private static Dictionary<string, string> ValuesOf(string file) =>
        XDocument.Load(Path.Combine(StringsDirectory(), file))
            .Root!
            .Elements("data")
            .ToDictionary(
                data => data.Attribute("name")!.Value,
                data => data.Element("value")?.Value ?? "");

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

    /// <summary>
    /// Con la cultura puesta, el texto sale en ese idioma. Es la prueba de que
    /// el satélite se compiló, se encontró y se leyó — que el archivo exista no
    /// prueba ninguna de las tres.
    ///
    /// <para>Se comprueba contra el <c>.resx</c> del idioma y no contra una
    /// frase escrita acá: una traducción que cambie tendría que venir a
    /// arreglar la prueba, y lo único que esta prueba sabe es que el texto que
    /// sale es el que está en el archivo de ese idioma.</para>
    /// </summary>
    [Theory]
    [InlineData("en")]
    [InlineData("en-US")]
    [InlineData("en-GB")]
    [InlineData("de")]
    [InlineData("de-DE")]
    [InlineData("de-AT")]
    [InlineData("fr")]
    [InlineData("fr-FR")]
    [InlineData("fr-CA")]
    public void ConLaCulturaPuestaElTextoSaleEnEseIdioma(string culture)
    {
        string language = culture.Split('-')[0];
        Dictionary<string, string> expected = ValuesOf($"Resources.{language}.resx");

        foreach (string key in new[] { "app-strings.nav-settings", "orphans-title", "app-strings.installer-title" })
            Assert.Equal(expected[key], WithUiCulture(culture, () => Strings.Get(key)));
    }

    /// <summary>
    /// Y cada idioma que la app dice ofrecer tiene su archivo. Ofrecer uno sin
    /// archivo es prometer algo que al elegirlo no pasa: cae al español y no
    /// falla nada.
    /// </summary>
    [Fact]
    public void CadaIdiomaOfrecidoTieneSuArchivo()
    {
        List<string> missing =
        [
            .. AppLanguages.RequiredSatelliteCultures
                .Where(culture => !File.Exists(Path.Combine(StringsDirectory(), $"Resources.{culture}.resx")))
        ];

        Assert.True(missing.Count == 0,
            "Estos idiomas se ofrecen y no tienen archivo:\n" + string.Join("\n", missing));
    }

    /// <summary>Y en español sigue saliendo en español, que es la cultura neutra.</summary>
    [Fact]
    public void EnEspanolSigueSaliendoEnEspanol()
    {
        Assert.Equal("Ajustes", WithUiCulture("es-MX", () => Strings.Get("app-strings.nav-settings")));
        Assert.Equal("Ajustes", WithUiCulture("es", () => Strings.Get("app-strings.nav-settings")));
    }

    /// <summary>
    /// Un idioma que la app no ofrece cae al español, nunca a un hueco. Es lo
    /// que hace que el español sea la cultura neutra y no un satélite más — y
    /// se comprueban las dos mitades: que no se ofrezca, y que el texto salga
    /// igual.
    /// </summary>
    [Theory]
    [InlineData("pt-BR")]
    [InlineData("it-IT")]
    public void UnIdiomaQueNoSeOfreceCaeAlEspanol(string culture)
    {
        Assert.Null(AppLanguages.For(new CultureInfo(culture)));
        Assert.Equal("Ajustes", WithUiCulture(culture, () => Strings.Get("app-strings.nav-settings")));
    }

    /// <summary>
    /// Las dos culturas tienen <b>exactamente</b> las mismas claves. Una que
    /// falte en inglés no se ve al probar —cae al español— y se descubre
    /// cuando alguien la lee en pantalla.
    /// </summary>
    [Theory]
    [InlineData("en")]
    [InlineData("de")]
    [InlineData("fr")]
    public void CadaIdiomaTieneExactamenteLasMismasClavesQueElEspanol(string culture)
    {
        Dictionary<string, string> spanish = ValuesOf("Resources.resx");
        Dictionary<string, string> english = ValuesOf($"Resources.{culture}.resx");

        List<string> missing = [.. spanish.Keys.Where(key => !english.ContainsKey(key)).Order(StringComparer.Ordinal)];
        List<string> extra = [.. english.Keys.Where(key => !spanish.ContainsKey(key)).Order(StringComparer.Ordinal)];

        Assert.True(missing.Count == 0, "Sin traducir al inglés:\n" + string.Join("\n", missing));
        Assert.True(extra.Count == 0, "En inglés y no en español:\n" + string.Join("\n", extra));
    }

    /// <summary>
    /// Y los mismos huecos. Uno que falte deja un dato fuera de la frase —"se
    /// copiaron archivos" sin decir cuántos— y uno de más hace reventar
    /// <c>string.Format</c> en tiempo de ejecución, en el idioma que casi nadie
    /// prueba.
    /// </summary>
    [Theory]
    [InlineData("en")]
    [InlineData("de")]
    [InlineData("fr")]
    public void CadaTextoTraducidoTieneLosMismosHuecosQueElEspanol(string culture)
    {
        Dictionary<string, string> spanish = ValuesOf("Resources.resx");
        Dictionary<string, string> english = ValuesOf($"Resources.{culture}.resx");

        static string Holes(string text) =>
            string.Join(",", System.Text.RegularExpressions.Regex
                .Matches(text, @"\{(\d+)\}")
                .Select(match => match.Groups[1].Value)
                .Distinct()
                .Order(StringComparer.Ordinal));

        List<string> problems =
        [
            .. spanish
                .Where(entry => english.ContainsKey(entry.Key))
                .Where(entry => Holes(entry.Value) != Holes(english[entry.Key]))
                .Select(entry =>
                    $"{entry.Key}: español usa {{{Holes(entry.Value)}}} y el inglés {{{Holes(english[entry.Key])}}}")
                .Order(StringComparer.Ordinal)
        ];

        Assert.True(problems.Count == 0, string.Join("\n", problems));
    }

    /// <summary>Textos que son iguales en los dos idiomas a propósito.</summary>
    private static readonly string[] SameInBothLanguages =
    [
        // Nombre de producto y licencia: "TagLib# 2.3.0 — LGPL v2.1" no se
        // traduce en ningún idioma, y tiene cuatro palabras por casualidad.
        "app-strings.licenses-tag-lib-name",
    ];

    /// <summary>
    /// Ningún texto en inglés quedó en español por olvido.
    ///
    /// <para>No se puede pedir que todo sea distinto: "Aura Studio", "ffmpeg",
    /// "Deezer", "{0}, {1}" y las flechas son iguales en los dos idiomas y
    /// tienen que serlo. Lo que sí se puede pedir es que un texto largo —una
    /// frase, no una etiqueta— no sea idéntico: ahí la coincidencia ya no es
    /// una palabra que se escribe igual, es una traducción que falta.</para>
    /// </summary>
    [Theory]
    [InlineData("en")]
    [InlineData("de")]
    [InlineData("fr")]
    public void NingunaFraseLargaQuedoSinTraducir(string culture)
    {
        Dictionary<string, string> spanish = ValuesOf("Resources.resx");
        Dictionary<string, string> english = ValuesOf($"Resources.{culture}.resx");

        List<string> untranslated =
        [
            .. spanish
                .Where(entry => english.TryGetValue(entry.Key, out string? value) && value == entry.Value)
                .Where(entry => entry.Value.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length >= 4)
                .Where(entry => !SameInBothLanguages.Contains(entry.Key))
                .Select(entry => $"{entry.Key}: {entry.Value}")
                .Order(StringComparer.Ordinal)
        ];

        Assert.True(untranslated.Count == 0,
            "Estas frases dicen exactamente lo mismo en los dos idiomas, así que probablemente "
            + "quedaron sin traducir:\n" + string.Join("\n", untranslated));
    }
}
