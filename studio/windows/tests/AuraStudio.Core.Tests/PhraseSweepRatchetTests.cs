using System.Diagnostics;
using System.Text;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El trinquete de verdad: <b>ningún literal con pinta de frase entra al árbol
/// sin que alguien diga qué es</b> (ST-247, cierre de B7d, a pedido de la
/// Maestra).
///
/// <para><b>De dónde sale.</b> Al cerrar B7d la barrida no señalaba ninguna
/// frase de pantalla. Pero ese cero era el resultado de <i>una corrida</i>, no
/// una propiedad del árbol: se llegó a él tres veces seguidas, y las tres veces
/// la corrida siguiente destapó frases nuevas que nadie había visto —cuatro
/// sueltas, dos ramas de un aviso de catálogo, el cuerpo del diálogo de "algo
/// salió mal"—. Un cero que hay que volver a ganar cada vez que alguien mira no
/// es un cero: es una foto.</para>
///
/// <para><b>Qué hace.</b> <see cref="PhraseSweep"/> barre el árbol y el
/// resultado se compara contra <c>barrida-inventario.tsv</c>, commiteado, donde
/// cada literal está clasificado como INTERNO, DATO o DOC. Un literal nuevo que
/// no esté en la lista pone esto en rojo y obliga a decidir qué es; si es de
/// PANTALLA, no hay clase que lo admita y el único camino es sacarlo a recurso.
/// La comparación es simétrica: una entrada del inventario que ya no existe
/// también se pone roja, para que la lista no envejezca acumulando fantasmas —
/// una lista con basura adentro deja de leerse, y una lista que no se lee no
/// protege nada.</para>
///
/// <para><b>Se cuentan las repeticiones.</b> Un mismo texto aparece varias veces
/// en un archivo —los motivos del detector de parecidos viven en tres bloques—,
/// así que se comparan multiconjuntos y no conjuntos. Fue exactamente ahí donde
/// una tanda de sustituciones sin <c>/g</c> convirtió la primera aparición y
/// dejó las otras dos: con conjuntos, eso pasaba en verde.</para>
///
/// <para><b>Por archivo y texto, no por renglón.</b> El inventario no guarda
/// números de línea a propósito: mover código haría fallar el trinquete sin que
/// nada de fondo hubiera cambiado, y un trinquete que grita por nada se termina
/// apagando. Cuando hay algo que reportar, el mensaje trae el renglón de hoy,
/// que es cuando de verdad hace falta.</para>
/// </summary>
public class PhraseSweepRatchetTests
{
    private const string InventoryPath = "docs/extraccion-cadenas/barrida-inventario.tsv";

    /// <summary>Las clases que admite el inventario. PANTALLA no está, y esa es toda la idea.</summary>
    private static readonly string[] Classes = ["INTERNO", "DATO", "DOC"];

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

    private readonly record struct Entry(string Class, string File, string Text);

    private static List<Entry> Inventory()
    {
        string path = Path.Combine(WindowsRoot(), InventoryPath.Replace('/', Path.DirectorySeparatorChar));

        Assert.True(File.Exists(path),
            $"Falta {InventoryPath}. Es la lista contra la que se compara la barrida; sin ella "
            + "esta prueba no comprueba nada y el árbol vuelve a quedar sin vigilancia.");

        List<Entry> entries = [];

        foreach (string line in File.ReadAllLines(path, Encoding.UTF8))
        {
            if (line.Length == 0) continue;

            string[] fields = line.Split('\t');
            Assert.True(fields.Length == 3,
                $"Renglón mal formado en {InventoryPath} (se esperan clase, archivo y texto separados por tabulador):\n  {line}");

            entries.Add(new Entry(fields[0], fields[1], fields[2]));
        }

        return entries;
    }

    /// <summary>Cuántas veces aparece cada (archivo, texto).</summary>
    private static Dictionary<(string File, string Text), int> Counted(IEnumerable<(string File, string Text)> items)
    {
        Dictionary<(string File, string Text), int> counts = [];
        foreach ((string file, string text) in items)
        {
            counts.TryGetValue((file, text), out int n);
            counts[(file, text)] = n + 1;
        }
        return counts;
    }

    /// <summary>
    /// Lo que hay en el árbol y lo que dice el inventario son lo mismo, con
    /// repeticiones y en las dos direcciones.
    /// </summary>
    [Fact]
    public void NingunLiteralConPintaDeFraseEntraSinClasificar()
    {
        string root = WindowsRoot();
        IReadOnlyList<SweptPhrase> swept = PhraseSweep.Run(root);

        Dictionary<(string File, string Text), int> inTree =
            Counted(swept.Select(phrase => (phrase.File, phrase.Text)));

        Dictionary<(string File, string Text), int> declared =
            Counted(Inventory().Select(entry => (entry.File, entry.Text)));

        // Dónde está hoy cada texto, para que el mensaje sirva sin buscar a mano.
        Dictionary<(string File, string Text), int> line = [];
        foreach (SweptPhrase phrase in swept) line.TryAdd((phrase.File, phrase.Text), phrase.Line);

        List<string> newcomers = [];
        foreach ((var key, int count) in inTree.OrderBy(pair => pair.Key))
        {
            declared.TryGetValue(key, out int known);
            if (count > known)
                newcomers.Add($"  {key.File}:{line[key]}  ({count - known} sin declarar)  {key.Text}");
        }

        List<string> ghosts = [];
        foreach ((var key, int count) in declared.OrderBy(pair => pair.Key))
        {
            inTree.TryGetValue(key, out int present);
            if (count > present) ghosts.Add($"  {key.File}  ({count - present} de más)  {key.Text}");
        }

        Assert.True(newcomers.Count == 0,
            $"Hay {newcomers.Count} literales con pinta de frase que no están en {InventoryPath}:\n"
            + string.Join("\n", newcomers)
            + "\n\nDecidí qué son y agrégalos con su clase:\n"
            + "  INTERNO — bitácora, traza de diagnóstico o mensaje de excepción que nadie lee como texto\n"
            + "            (quien lo atrapa mira el TIPO, no el mensaje: compruébalo siguiendo al que lo atrapa)\n"
            + "  DATO    — lo interpreta otro sistema, se guarda y se compara, o es el nombre propio de algo\n"
            + "  DOC     — documentación en el código, no texto de la app\n\n"
            + "Si es texto que el usuario lee, NO hay clase para eso: sácalo a Resources.resx "
            + "en los seis idiomas y no vuelve a aparecer acá.");

        Assert.True(ghosts.Count == 0,
            $"{InventoryPath} declara {ghosts.Count} literales que ya no están en el árbol:\n"
            + string.Join("\n", ghosts)
            + "\n\nQuítalos. Un inventario que acumula fantasmas deja de leerse, y uno que no se lee no protege nada.");
    }

    /// <summary>
    /// Toda entrada lleva una de las tres clases. <b>PANTALLA no es una de
    /// ellas</b>: no hay forma de declarar texto de pantalla como aceptable, que
    /// es justo lo que la Maestra pidió dejar amarrado.
    /// </summary>
    [Fact]
    public void NoHayClaseParaElTextoDePantalla()
    {
        List<Entry> entries = Inventory();

        List<string> wrong =
        [
            .. entries.Where(entry => !Classes.Contains(entry.Class, StringComparer.Ordinal))
                .Select(entry => $"  «{entry.Class}» en {entry.File}: {entry.Text}")
        ];

        Assert.True(wrong.Count == 0,
            $"Clases que {InventoryPath} no admite (solo {string.Join(", ", Classes)}):\n"
            + string.Join("\n", wrong)
            + "\n\nSi lo que apareció es texto de pantalla, la salida no es inventarle una clase: es sacarlo a recurso.");

        Assert.True(entries.Count > 0, $"{InventoryPath} está vacío: el trinquete no estaría comparando nada.");
    }

    /// <summary>
    /// El guion en perl y esta implementación ven lo mismo.
    ///
    /// <para>El guion se sigue usando a mano —imprime archivo y renglón, que es
    /// lo que sirve para leer— y la detección está escrita dos veces. Dos copias
    /// de una regla se separan solas; lo único que lo impide es esta prueba.</para>
    ///
    /// <para>Se salta si no hay perl, y puede saltarse sin peligro: el trinquete
    /// de arriba no lo necesita. Esa es toda la razón de haber portado la
    /// detección — la prueba anterior corría el guion y se saltaba sola cuando
    /// no había perl, y ahí un trinquete habría pasado en verde sin mirar
    /// nada.</para>
    /// </summary>
    [Fact]
    public void ElGuionEnPerlYEstaImplementacionVenLoMismo()
    {
        string root = WindowsRoot();

        var start = new ProcessStartInfo("perl", "docs/extraccion-cadenas/barrida-frases.pl")
        {
            WorkingDirectory = root,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            StandardOutputEncoding = Encoding.UTF8,
        };

        Process? process;
        try
        {
            process = Process.Start(start);
        }
        catch (System.ComponentModel.Win32Exception)
        {
            return;   // sin perl acá; el trinquete de arriba corre igual
        }

        Assert.NotNull(process);
        string output = process.StandardOutput.ReadToEnd();
        process.WaitForExit();

        Assert.True(process.ExitCode == 0, "La barrida terminó con error:\n" + process.StandardError.ReadToEnd());

        // El guion imprime el archivo en su propio renglón y debajo, indentados,
        // "<línea>  <texto>".
        List<(string File, string Text)> fromPerl = [];
        string? file = null;

        foreach (string line in output.Split('\n').Select(l => l.TrimEnd('\r')))
        {
            if (line.Length == 0 || line.StartsWith("---", StringComparison.Ordinal)) continue;

            if (!line.StartsWith(' ')) { file = line; continue; }

            int separator = line.IndexOf("  ", StringComparison.Ordinal);
            string rest = line.TrimStart();
            separator = rest.IndexOf("  ", StringComparison.Ordinal);
            if (separator < 0 || file is null) continue;

            fromPerl.Add((file, rest[(separator + 2)..]));
        }

        Assert.True(fromPerl.Count > 0,
            "No se pudo leer la salida del guion: cambió su formato y esta comparación quedó mirando al vacío.");

        Dictionary<(string File, string Text), int> perl = Counted(fromPerl);
        Dictionary<(string File, string Text), int> csharp =
            Counted(PhraseSweep.Run(root).Select(phrase => (phrase.File, phrase.Text)));

        List<string> differences = [];

        foreach ((var key, int count) in perl.OrderBy(pair => pair.Key))
        {
            csharp.TryGetValue(key, out int mine);
            if (mine != count) differences.Add($"  perl {count} / C# {mine}  {key.Item1}: {key.Item2}");
        }

        foreach ((var key, int count) in csharp.OrderBy(pair => pair.Key))
        {
            if (!perl.ContainsKey(key)) differences.Add($"  perl 0 / C# {count}  {key.Item1}: {key.Item2}");
        }

        Assert.True(differences.Count == 0,
            "El guion en perl y PhraseSweep dejaron de ver lo mismo:\n" + string.Join("\n", differences)
            + "\n\nSon la misma regla escrita dos veces; si una cambió, la otra tiene que cambiar igual.");
    }
}
