using System.Xml.Linq;
using AuraStudio.Core.Resources;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Cuando una frase manda al usuario a una sección de la app, la nombra igual
/// que la etiqueta de esa sección — en el mismo idioma (ST-247, B7c).
///
/// <para>"Expulsa el iPod desde <b>General</b>" y "puedes volver a él desde
/// <b>Extras</b>" no son texto libre: son referencias a una pestaña que el
/// usuario tiene que encontrar. Si la etiqueta se traduce y la frase no —o al
/// revés, o cada una a su manera— la app manda a un sitio que no existe con ese
/// nombre. En japonés la pestaña dice 「その他」; una frase que dijera "Extras"
/// no lleva a ninguna parte.</para>
///
/// <para>Es un fallo que no rompe nada y que solo se ve leyendo las dos cosas a
/// la vez, en un idioma que además casi nadie del equipo lee. Por eso se
/// comprueba y no se confía.</para>
/// </summary>
public class SectionNamesTests
{
    /// <summary>
    /// Cada frase y la etiqueta de la sección a la que manda.
    /// </summary>
    private static readonly (string Sentence, string Label)[] References =
    [
        ("app-strings.installer-done-detail", "app-strings.nav-general"),
        ("app-strings.installer-family-change", "app-strings.nav-extras"),
    ];

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

    private static Dictionary<string, string> ValuesOf(string culture)
    {
        string file = culture == AppLanguages.NeutralCulture ? "Resources.resx" : $"Resources.{culture}.resx";

        return XDocument.Load(Path.Combine(StringsDirectory(), file))
            .Root!
            .Elements("data")
            .ToDictionary(
                data => data.Attribute("name")!.Value,
                data => data.Element("value")?.Value ?? "");
    }

    public static TheoryData<string> Cultures()
    {
        TheoryData<string> data = [];
        foreach (AppLanguage language in AppLanguages.Available) data.Add(language.Culture);
        return data;
    }

    [Theory]
    [MemberData(nameof(Cultures))]
    public void CadaFraseNombraLaSeccionComoSuEtiquetaEnEseIdioma(string culture)
    {
        Dictionary<string, string> resources = ValuesOf(culture);

        List<string> problems = [];

        foreach ((string sentence, string label) in References)
        {
            string text = resources[sentence];
            string name = resources[label];

            if (!text.Contains(name, StringComparison.Ordinal))
                problems.Add($"{sentence} manda a «{name}» ({label}) y no lo nombra así:\n  {text}");
        }

        Assert.True(problems.Count == 0,
            $"En {culture} una frase manda a una sección con un nombre que esa sección no tiene:\n"
            + string.Join("\n\n", problems));
    }
}
