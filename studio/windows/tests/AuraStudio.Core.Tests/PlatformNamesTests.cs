using System.Text;
using System.Xml.Linq;
using AuraStudio.Core.Resources;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Cuando la app le dice al usuario que instale algo, lo nombra con el nombre
/// que ese algo tiene en su idioma (ST-247, B7c).
///
/// <para><b>El caso que la trajo.</b> El japonés decía 「Apple デバイス」 y la
/// ficha de la Microsoft Store en japonés se llama 「Appleデバイス」, sin
/// espacio. Nada falla: la frase se lee bien, la retrotraducción la dio por
/// correcta —dice justo lo que tiene que decir— y el glosario la traía como
/// buena. Lo único que pasa es que el usuario escribe en el buscador de la
/// tienda lo que la app le puso entre comillas y no encuentra la app; y sin ese
/// controlador no hay instalación en Windows. Un espacio.</para>
///
/// <para><b>Por qué no lo ve ninguna otra prueba.</b> Las demás miran una
/// cadena contra sí misma: que exista, que tenga sus formas de plural, que no
/// esté en español. Esta mira una cadena contra un hecho de afuera —cómo se
/// llama esa ficha en esa tienda— y ese hecho no está en el código. Está en el
/// glosario, con su fuente anotada, y de ahí lo lee esta prueba: si mañana
/// alguien corrige el glosario porque Microsoft renombró la ficha, la prueba
/// señala las cadenas que quedaron viejas en vez de dejarlas envejecer.</para>
///
/// <para>Por eso la tabla de abajo es corta a propósito: solo nombres de cosas
/// que el usuario va a <b>buscar</b> o <b>escribir</b> en otro programa. Un
/// término del glosario que solo se lee no necesita esta vigilancia; meterlo
/// aquí daría falsos positivos —una frase puede hablar del Explorador sin
/// nombrarlo— y una prueba que grita de más se termina apagando.</para>
/// </summary>
public class PlatformNamesTests
{
    /// <summary>
    /// Término del glosario (columna española) y claves donde el usuario lo va
    /// a copiar a un buscador.
    /// </summary>
    private static readonly (string Term, string[] Keys)[] MustBeNamedExactly =
    [
        ("Dispositivos Apple",
        [
            "app-strings.dfu-driver-missing",
            "app-strings.dfu-driver-package-missing",
        ]),
    ];

    private static string WindowsRoot()
    {
        DirectoryInfo? directory = new(AppContext.BaseDirectory);

        while (directory is not null)
        {
            string candidate = Path.Combine(directory.FullName, "studio", "windows");
            if (File.Exists(Path.Combine(candidate, "AuraStudio.Windows.slnx"))) return candidate;

            directory = directory.Parent;
        }

        throw new InvalidOperationException("No se encontró la raíz del repo desde el directorio de pruebas.");
    }

    /// <summary>
    /// Un CSV con comas dentro de las comillas —la columna de la fuente las
    /// tiene— no se parte con Split. Esto es lo mínimo que hace falta: comillas
    /// dobles para escapar una comilla, comas fuera de comillas para separar.
    /// </summary>
    private static string[] Fields(string line)
    {
        List<string> fields = [];
        StringBuilder current = new();
        bool quoted = false;

        for (int index = 0; index < line.Length; index++)
        {
            char character = line[index];

            if (quoted)
            {
                if (character != '"') { current.Append(character); continue; }

                if (index + 1 < line.Length && line[index + 1] == '"') { current.Append('"'); index++; continue; }

                quoted = false;
                continue;
            }

            if (character == '"') { quoted = true; continue; }
            if (character == ',') { fields.Add(current.ToString()); current.Clear(); continue; }

            current.Append(character);
        }

        fields.Add(current.ToString());
        return [.. fields];
    }

    /// <summary>
    /// El glosario indexado por término español: cultura → nombre en esa
    /// lengua. Las columnas salen del encabezado, no de posiciones escritas
    /// aquí, para que agregar un idioma al glosario no obligue a tocar esto.
    /// </summary>
    private static Dictionary<string, Dictionary<string, string>> Glossary()
    {
        string path = Path.Combine(WindowsRoot(), "docs", "extraccion-cadenas", "glosario-plataforma.csv");
        string[] lines = File.ReadAllLines(path);

        string[] header = Fields(lines[0]);
        // La primera columna se titula "termino es" y es la española; el resto
        // son culturas, salvo la última, que es la fuente.
        Dictionary<int, string> cultures = new() { [0] = AppLanguages.NeutralCulture };
        for (int column = 1; column < header.Length - 1; column++) cultures[column] = header[column];

        Dictionary<string, Dictionary<string, string>> glossary = [];

        foreach (string line in lines.Skip(1))
        {
            if (line.Length == 0) continue;

            string[] fields = Fields(line);
            Dictionary<string, string> names = [];
            foreach ((int column, string culture) in cultures)
                if (column < fields.Length) names[culture] = fields[column];

            glossary[fields[0]] = names;
        }

        return glossary;
    }

    private static Dictionary<string, string> ValuesOf(string culture)
    {
        string file = culture == AppLanguages.NeutralCulture ? "Resources.resx" : $"Resources.{culture}.resx";
        string path = Path.Combine(WindowsRoot(), "AuraStudio.Core", "Strings", file);

        return XDocument.Load(path)
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
    public void CadaFraseNombraLoQueHayQueBuscarComoSeLlamaEnEseIdioma(string culture)
    {
        Dictionary<string, Dictionary<string, string>> glossary = Glossary();
        Dictionary<string, string> resources = ValuesOf(culture);

        List<string> problems = [];

        foreach ((string term, string[] keys) in MustBeNamedExactly)
        {
            Assert.True(glossary.ContainsKey(term),
                $"«{term}» ya no está en el glosario y esta prueba lo necesita para saber cómo se llama en cada idioma.");

            string name = glossary[term][culture];

            foreach (string key in keys)
            {
                if (!resources[key].Contains(name, StringComparison.Ordinal))
                    problems.Add($"{key} tendría que nombrar «{name}» y dice:\n  {resources[key]}");
            }
        }

        Assert.True(problems.Count == 0,
            $"En {culture} la app manda a buscar algo con un nombre que ahí no tiene "
            + "(el usuario lo escribe en la tienda y no lo encuentra):\n"
            + string.Join("\n\n", problems));
    }
}
