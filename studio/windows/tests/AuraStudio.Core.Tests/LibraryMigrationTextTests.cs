using System.Globalization;
using System.Xml.Linq;
using AuraStudio.Core.Library;
using AuraStudio.Core.Resources;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La frase que resume una migración se lee entera, en cada idioma (ST-247,
/// B7c).
///
/// <para><b>El defecto que encontró la retrotraducción alemana.</b> Esta frase
/// se arma de pedazos, y estaba <b>a medio traducir</b>: B7a sacó a recursos el
/// fragmento de las etiquetas —tenía un ternario de plural y el extractor lo
/// vio— y dejó los otros siete como literales. Con la app en alemán salía una
/// sola oración con las dos lenguas adentro:</para>
///
/// <para><c>"Biblioteca migrada: die Tags von 3 Titeln wurden geschrieben, se
/// ordenaron 2 preparados."</c></para>
///
/// <para>Ninguna prueba de las que había podía verlo: todas miraban cadenas
/// <b>sueltas</b>, y cada pedazo por separado estaba bien. El defecto solo
/// existe en la unión.</para>
///
/// <para>Por eso esta prueba arma la oración completa —en los cuatro idiomas y
/// en los cuatro caminos que tiene el método— y comprueba que cada pedazo salió
/// del recurso de ESE idioma. Es una prueba de composición, no de traducción:
/// no sabe alemán, sabe que no puede haber mezcla.</para>
/// </summary>
public class LibraryMigrationTextTests
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

    private static Dictionary<string, string> ValuesOf(string culture)
    {
        string file = culture == "es" ? "Resources.resx" : $"Resources.{culture}.resx";

        return XDocument.Load(Path.Combine(StringsDirectory(), file))
            .Root!
            .Elements("data")
            .ToDictionary(
                data => data.Attribute("name")!.Value,
                data => data.Element("value")?.Value ?? "");
    }

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

    /// <summary>`Touched` es la suma de los cuatro, no un campo aparte.</summary>
    private static LibraryMigrationSummary Summary(
        int tagged = 0, int renamed = 0, int built = 0, int orphans = 0,
        int failed = 0, bool cancelled = false) =>
        new(tagged, renamed, built, orphans, failed, [], cancelled);

    /// <summary>
    /// Con todos los pedazos presentes, la oración entera está en el idioma
    /// pedido: cabecera, cada fragmento y el cierre.
    ///
    /// <para>Se comprueba pieza por pieza contra el <c>.resx</c> de ese idioma,
    /// no contra una frase escrita acá: la prueba no sabe alemán y no tiene por
    /// qué. Lo que sabe es que <b>todo</b> pedazo tiene que venir del mismo
    /// archivo.</para>
    /// </summary>
    [Theory]
    [InlineData("es")]
    [InlineData("en")]
    [InlineData("de")]
    [InlineData("fr")]
    public void LaOracionCompletaSaleEnteraEnElIdiomaPedido(string culture)
    {
        Dictionary<string, string> resources = ValuesOf(culture);

        string sentence = WithUiCulture(culture, () => LibraryMigrationText.Summarize(
            Summary(tagged: 3, renamed: 2, built: 4, orphans: 5)));

        Assert.Contains(resources["library-migration.head-done"], sentence, StringComparison.Ordinal);

        // Cada fragmento, ya formateado con su número: comparar la plantilla
        // con el hueco quitado dejaría dos espacios donde hay uno y no calzaría
        // por un motivo que no tiene nada que ver con el idioma.
        (string Key, int Count)[] fragments =
        [
            ("library-view-model.migration-tagged.other", 3),
            ("library-migration.prepared-renamed.other", 2),
            ("library-migration.prepared-built.other", 4),
            ("library-migration.orphans-deleted.other", 5)
        ];

        foreach ((string key, int count) in fragments)
        {
            string fragment = string.Format(
                new CultureInfo(culture), resources[key], count);

            Assert.Contains(fragment, sentence, StringComparison.Ordinal);
        }
    }

    /// <summary>
    /// Y no queda ni un pedazo en español cuando el idioma es otro.
    ///
    /// <para>Ésta es la que habría fallado antes del arreglo. Busca en la
    /// oración los fragmentos <b>españoles</b> que el código traía escritos, y
    /// exige que no aparezcan: si alguno vuelve al código como literal, esta
    /// prueba lo dice.</para>
    /// </summary>
    [Theory]
    [InlineData("en")]
    [InlineData("de")]
    [InlineData("fr")]
    public void NoQuedaNingunPedazoEnEspanol(string culture)
    {
        Dictionary<string, string> spanish = ValuesOf("es");

        string sentence = WithUiCulture(culture, () => LibraryMigrationText.Summarize(
            Summary(tagged: 3, renamed: 2, built: 4, orphans: 5, failed: 1)));

        // Con los MISMOS números que la oración: formatear el español con otro
        // número haría que no calzara nunca y la prueba no podría fallar jamás.
        (string Key, int Count)[] spanishFragments =
        [
            ("library-migration.head-done", 0),
            ("library-migration.prepared-renamed.other", 2),
            ("library-migration.prepared-built.other", 4),
            ("library-migration.orphans-deleted.other", 5),
            ("library-migration.failed.one", 1)
        ];

        List<string> leaked =
        [
            .. spanishFragments
                .Select(entry => string.Format(new CultureInfo("es"), spanish[entry.Key], entry.Count))
                .Where(fragment => sentence.Contains(fragment, StringComparison.Ordinal))
        ];

        Assert.True(leaked.Count == 0,
            $"En {culture} quedaron pedazos en español dentro de la oración:\n"
            + string.Join("\n", leaked) + "\n\nLa oración fue:\n" + sentence);
    }

    /// <summary>
    /// El aviso de "esta biblioteca viene de antes" también sale entero en el
    /// idioma pedido, y sin ningún pedazo en español.
    ///
    /// <para>Tenía el mismo defecto que el resumen y lo encontró la barrida que
    /// se hizo justo después de arreglarlo: los conteos venían del recurso y la
    /// oración que los envuelve estaba escrita en el código, con su "y" incluida.
    /// </para>
    /// </summary>
    [Theory]
    [InlineData("en")]
    [InlineData("de")]
    [InlineData("fr")]
    [InlineData("ru")]
    [InlineData("ja")]
    public void ElAvisoDeMigracionPendienteTampocoMezclaIdiomas(string culture)
    {
        Dictionary<string, string> spanish = ValuesOf("es");
        Dictionary<string, string> resources = ValuesOf(culture);

        string sentence = WithUiCulture(culture,
            () => LibraryMigrationText.Needed(new LibraryMigrationNeed(3, 2)));

        Assert.Contains(resources["library-migration.needed-detail"], sentence, StringComparison.Ordinal);
        Assert.Contains(resources["library-migration.needed-joiner"], sentence, StringComparison.Ordinal);

        foreach (string key in new[] { "library-migration.needed-detail", "library-migration.needed-joiner" })
            Assert.DoesNotContain(spanish[key], sentence, StringComparison.Ordinal);
    }

    /// <summary>Sin nada que migrar, el aviso no dice nada: no se muestra.</summary>
    [Fact]
    public void SinNadaQueMigrarElAvisoEstaVacio() =>
        Assert.Equal("", LibraryMigrationText.Needed(LibraryMigrationNeed.None));

    /// <summary>
    /// Los cuatro caminos del método dan una oración con contenido: nada vacío,
    /// nada con la clave entre corchetes.
    /// </summary>
    [Theory]
    [InlineData("es")]
    [InlineData("en")]
    [InlineData("de")]
    [InlineData("fr")]
    public void NingunCaminoDejaLaOracionVaciaNiConClavesSinResolver(string culture)
    {
        LibraryMigrationSummary[] cases =
        [
            Summary(cancelled: true),
            Summary(),
            Summary(tagged: 3),
            Summary(tagged: 3, failed: 2, cancelled: true)
        ];

        foreach (LibraryMigrationSummary summary in cases)
        {
            string sentence = WithUiCulture(culture, () => LibraryMigrationText.Summarize(summary));

            Assert.False(string.IsNullOrWhiteSpace(sentence));
            Assert.DoesNotContain('⟦', sentence);
        }
    }
}
