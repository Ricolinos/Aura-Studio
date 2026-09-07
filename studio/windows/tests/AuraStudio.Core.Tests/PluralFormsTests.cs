using System.Xml.Linq;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Cómo tiene que estar escrita una forma de plural en el archivo de recursos
/// (ST-247).
///
/// <para><b>El número va DENTRO de la frase.</b> Nunca un sustantivo suelto
/// —"canciones"— que la app pegue al número por fuera. En ruso la concordancia
/// del sustantivo depende del número <i>y</i> del caso, en árabe hay seis
/// formas, y en varios idiomas el número no va delante: partir "3 canciones" en
/// "3" + "canciones" deja al que traduce sin la frase, solo con la mitad que no
/// puede acomodar. Es la lección que la Mac aprendió en A7a y aplica igual
/// acá.</para>
///
/// <para>Esto no lo puede atrapar el compilador: un recurso que dice
/// "canciones" compila igual de bien que uno que dice "{0} canciones". Lo
/// atrapa esta prueba, mirando el archivo.</para>
/// </summary>
public class PluralFormsTests
{
    /// <summary>
    /// Las únicas formas que <b>no</b> llevan número, porque la frase que
    /// reemplazan tampoco lo decía. Ponerles un <c>{0}</c> sería redactar, y
    /// B7a mueve.
    /// </summary>
    private static readonly string[] WithoutNumber =
    [
        // Etiquetas de menú: cambian de número pero nunca dicen cuántos.
        // "Quitar foto del artista" / "Quitar fotos de los artistas".
        "context-menu.quitar-foto-artista.one",
        "context-menu.quitar-foto-artista.other",

        // "Buscando carátula…" con una sola; con varias sí dice cuántos
        // álbumes, y esa forma lleva su {0}.
        "library-view-model.searching-covers.one",
    ];

    private static string RepoRoot()
    {
        DirectoryInfo? directory = new(AppContext.BaseDirectory);

        while (directory is not null)
        {
            if (File.Exists(Path.Combine(directory.FullName, "studio", "windows", "AuraStudio.Windows.slnx")))
                return directory.FullName;

            directory = directory.Parent;
        }

        throw new InvalidOperationException("No se encontró la raíz del repo desde el directorio de pruebas.");
    }

    private static Dictionary<string, string> Resources() =>
        XDocument.Load(Path.Combine(
                RepoRoot(), "studio", "windows", "AuraStudio.Core", "Strings", "Resources.resx"))
            .Root!
            .Elements("data")
            .ToDictionary(
                data => data.Attribute("name")!.Value,
                data => data.Element("value")?.Value ?? "");

    private static readonly string[] Suffixes = [".one", ".few", ".many", ".other"];

    private static IEnumerable<KeyValuePair<string, string>> PluralForms(Dictionary<string, string> resources) =>
        resources.Where(entry => Suffixes.Any(suffix => entry.Key.EndsWith(suffix, StringComparison.Ordinal)));

    /// <summary>Toda forma de plural lleva su número adentro.</summary>
    [Fact]
    public void TodaFormaDePluralLlevaSuNumeroAdentro()
    {
        List<string> without =
        [
            .. PluralForms(Resources())
                .Where(entry => !entry.Value.Contains("{0}", StringComparison.Ordinal))
                .Select(entry => entry.Key)
                .Where(key => !WithoutNumber.Contains(key))
                .Order(StringComparer.Ordinal)
        ];

        Assert.True(without.Count == 0,
            "Estas formas de plural no dicen el número, así que alguien lo está pegando por fuera —\n"
            + "y eso es lo que no se puede traducir. Si de verdad la frase no lleva número,\n"
            + "declárala en WithoutNumber con su razón:\n" + string.Join("\n", without));
    }

    /// <summary>
    /// Toda clave con formas tiene al menos <c>.other</c>: es la forma a la que
    /// <c>Strings.Plural</c> se cae cuando la cultura no trae la que toca, así
    /// que sin ella el respaldo no existe.
    /// </summary>
    [Fact]
    public void TodaClaveConPluralTieneLaFormaOther()
    {
        Dictionary<string, string> resources = Resources();

        HashSet<string> bases =
        [
            .. PluralForms(resources)
                .Select(entry => entry.Key[..entry.Key.LastIndexOf('.')])
        ];

        List<string> missing = [.. bases.Where(key => !resources.ContainsKey(key + ".other")).Order(StringComparer.Ordinal)];

        Assert.True(missing.Count == 0,
            "Estas claves tienen formas de plural pero no la de respaldo (.other):\n" + string.Join("\n", missing));
    }

    /// <summary>
    /// Y ninguna clave de plural existe también como clave suelta: sería el
    /// mismo texto por dos caminos, y uno de los dos se quedaría sin traducir.
    /// </summary>
    [Fact]
    public void NingunaClaveDePluralExisteTambienSuelta()
    {
        Dictionary<string, string> resources = Resources();

        List<string> both =
        [
            .. PluralForms(resources)
                .Select(entry => entry.Key[..entry.Key.LastIndexOf('.')])
                .Distinct(StringComparer.Ordinal)
                .Where(resources.ContainsKey)
                .Order(StringComparer.Ordinal)
        ];

        Assert.True(both.Count == 0,
            "Estas claves están a la vez con formas de plural y sueltas:\n" + string.Join("\n", both));
    }
}
