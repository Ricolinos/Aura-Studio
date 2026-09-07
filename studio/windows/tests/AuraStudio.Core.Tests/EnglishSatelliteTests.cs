using System.Globalization;
using System.Xml.Linq;
using AuraStudio.Core.Resources;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El inglés existe, sale de verdad, y dice lo mismo que el español (ST-247,
/// B7b).
///
/// <para><b>Que el archivo esté no prueba nada.</b> Un <c>.resx</c> con la
/// cultura en el nombre puede quedar fuera del ensamblado satélite por un
/// detalle del proyecto, y entonces la app pide inglés y recibe español sin
/// que falle nada: los textos salen, se ven bien, y están en el idioma
/// equivocado. Es un modo de falla silencioso, así que acá se pide el texto
/// <b>con la cultura puesta</b> y se comprueba que cambie.</para>
/// </summary>
public class EnglishSatelliteTests
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
    /// Con la cultura en inglés, el texto sale en inglés. Es la prueba de que
    /// el satélite se compiló, se encontró y se leyó.
    /// </summary>
    [Theory]
    [InlineData("en")]
    [InlineData("en-US")]
    [InlineData("en-GB")]
    public void ConLaCulturaEnInglesElTextoSaleEnIngles(string culture)
    {
        Assert.Equal("Settings", WithUiCulture(culture, () => Strings.Get("app-strings.nav-settings")));
        Assert.Equal("Orphaned files", WithUiCulture(culture, () => Strings.Get("orphans-title")));
    }

    /// <summary>Y en español sigue saliendo en español, que es la cultura neutra.</summary>
    [Fact]
    public void EnEspanolSigueSaliendoEnEspanol()
    {
        Assert.Equal("Ajustes", WithUiCulture("es-MX", () => Strings.Get("app-strings.nav-settings")));
        Assert.Equal("Ajustes", WithUiCulture("es", () => Strings.Get("app-strings.nav-settings")));
    }

    /// <summary>
    /// Un idioma que todavía no existe cae al español, nunca a un hueco. Es lo
    /// que hace que el español sea la cultura neutra y no un satélite más.
    /// </summary>
    [Theory]
    [InlineData("de-DE")]
    [InlineData("ja-JP")]
    public void UnIdiomaQueNoExisteTodaviaCaeAlEspanol(string culture) =>
        Assert.Equal("Ajustes", WithUiCulture(culture, () => Strings.Get("app-strings.nav-settings")));

    /// <summary>
    /// Las dos culturas tienen <b>exactamente</b> las mismas claves. Una que
    /// falte en inglés no se ve al probar —cae al español— y se descubre
    /// cuando alguien la lee en pantalla.
    /// </summary>
    [Fact]
    public void ElInglesTieneExactamenteLasMismasClavesQueElEspanol()
    {
        Dictionary<string, string> spanish = ValuesOf("Resources.resx");
        Dictionary<string, string> english = ValuesOf("Resources.en.resx");

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
    [Fact]
    public void CadaTextoEnInglesTieneLosMismosHuecosQueElEspanol()
    {
        Dictionary<string, string> spanish = ValuesOf("Resources.resx");
        Dictionary<string, string> english = ValuesOf("Resources.en.resx");

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
    [Fact]
    public void NingunaFraseLargaQuedoSinTraducir()
    {
        Dictionary<string, string> spanish = ValuesOf("Resources.resx");
        Dictionary<string, string> english = ValuesOf("Resources.en.resx");

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
