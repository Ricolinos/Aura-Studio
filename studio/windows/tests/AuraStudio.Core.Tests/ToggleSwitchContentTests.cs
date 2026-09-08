using System.Text.RegularExpressions;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Ningún <c>ToggleSwitch</c> se queda con las etiquetas que pone WinUI
/// (ST-247, hallazgo de las capturas del mecánico).
///
/// <para><b>El caso que la trajo, y por qué es peor de lo que parece.</b> Un
/// <c>ToggleSwitch</c> sin <c>OnContent</c>/<c>OffContent</c> dice «Activado» y
/// «Desactivado» por su cuenta — y los toma del <b>idioma de Windows</b>, no del
/// idioma de la app. Con Windows en español y Aura Studio en inglés, los cinco
/// interruptores de Ajustes decían «Activado». No es una traducción que falta:
/// es texto que viene de otro lado y que ninguna prueba de recursos podía ver,
/// porque en el árbol no hay ninguna cadena que revisar.</para>
///
/// <para>Por eso esta prueba mira el <b>XAML</b> y no los <c>.resx</c>: lo que
/// hay que comprobar no es que exista una traducción, sino que alguien haya
/// pedido usarla. Un control que no la pide se ve idéntico a uno que sí, hasta
/// que se abre la app en otro idioma del que tiene el sistema — y nadie prueba
/// esa combinación por casualidad.</para>
///
/// <para>Los valores siguen la convención de cada Windows y no una traducción
/// literal («Вкл.» en ruso, «Ein» en alemán), que es la misma regla que la
/// Maestra fijó para «Отмена»: las etiquetas estándar del sistema se dicen como
/// las dice esa plataforma.</para>
/// </summary>
public class ToggleSwitchContentTests
{
    private static string AppRoot()
    {
        DirectoryInfo? directory = new(AppContext.BaseDirectory);

        while (directory is not null)
        {
            string candidate = Path.Combine(directory.FullName, "studio", "windows");
            if (File.Exists(Path.Combine(candidate, "AuraStudio.Windows.slnx")))
                return Path.Combine(candidate, "AuraStudio.App");

            directory = directory.Parent;
        }

        throw new InvalidOperationException("No se encontró la raíz del repo desde el directorio de pruebas.");
    }

    /// <summary>
    /// Cada apertura de <c>&lt;ToggleSwitch</c> con todo lo que la sigue hasta
    /// cerrar la etiqueta. Se toma así, y no renglón por renglón, porque los
    /// atributos se reparten en varias líneas y uno de los cinco tenía el
    /// <c>IsOn</c> pegado al <c>Header</c> en el mismo renglón.
    /// </summary>
    private static readonly Regex Element = new(@"<ToggleSwitch\b[^>]*?/?>", RegexOptions.Compiled | RegexOptions.Singleline);

    [Fact]
    public void TodoToggleSwitchDiceLoSuyoEnElIdiomaDeLaApp()
    {
        string appRoot = AppRoot();

        List<string> problems = [];
        int seen = 0;

        IEnumerable<string> files = Directory
            .EnumerateFiles(appRoot, "*.xaml", SearchOption.AllDirectories)
            .Where(path => !Path.GetRelativePath(appRoot, path)
                .Split(['/', '\\'])
                .Any(segment => segment is "bin" or "obj"))
            .Order(StringComparer.Ordinal);

        foreach (string path in files)
        {
            string relative = Path.GetRelativePath(appRoot, path).Replace('\\', '/');
            string text = File.ReadAllText(path);

            foreach (Match match in Element.Matches(text))
            {
                seen++;

                List<string> missing =
                [
                    .. new[] { "OnContent", "OffContent" }
                        .Where(attribute => !match.Value.Contains(attribute + "=", StringComparison.Ordinal))
                ];

                if (missing.Count == 0) continue;

                int line = text[..match.Index].Count(c => c == '\n') + 1;
                problems.Add($"  {relative}:{line}  le falta {string.Join(" y ", missing)}");
            }
        }

        Assert.True(seen > 0,
            "No se encontró ningún ToggleSwitch en el XAML. O se quitaron todos, o el patrón dejó de "
            + "reconocerlos — y en ese caso esta prueba estaría pasando sin mirar nada.");

        Assert.True(problems.Count == 0,
            $"Hay {problems.Count} ToggleSwitch (de {seen}) sin sus etiquetas propias:\n"
            + string.Join("\n", problems)
            + "\n\nSin OnContent/OffContent, WinUI pone «Activado»/«Desactivado» EN EL IDIOMA DE "
            + "WINDOWS, no en el de la app: con Windows en español y Aura Studio en inglés se lee "
            + "«Activado». Agrégalos:\n"
            + "  OnContent=\"{x:Bind str:Strings.Get('toggle.on')}\"\n"
            + "  OffContent=\"{x:Bind str:Strings.Get('toggle.off')}\"");
    }

    /// <summary>
    /// Y las dos claves existen en los seis idiomas. Pedirlas y que no estén
    /// dejaría el interruptor con las etiquetas en blanco, que es peor que
    /// tenerlas en el idioma equivocado.
    /// </summary>
    [Theory]
    [InlineData("toggle.on")]
    [InlineData("toggle.off")]
    public void LasEtiquetasExistenEnLosSeisIdiomas(string key)
    {
        foreach (AuraStudio.Core.Resources.AppLanguage language in AuraStudio.Core.Resources.AppLanguages.Translated)
        {
            string file = language.Culture == AuraStudio.Core.Resources.AppLanguages.NeutralCulture
                ? "Resources.resx"
                : $"Resources.{language.Culture}.resx";

            string path = Path.Combine(
                Directory.GetParent(AppRoot())!.FullName, "AuraStudio.Core", "Strings", file);

            Assert.Contains($"name=\"{key}\"", File.ReadAllText(path), StringComparison.Ordinal);
        }
    }
}
