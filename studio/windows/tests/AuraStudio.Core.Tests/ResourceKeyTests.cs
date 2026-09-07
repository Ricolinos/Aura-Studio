using System.Text.RegularExpressions;
using System.Xml.Linq;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Que toda clave que el código pide exista en el archivo de recursos
/// (ST-247).
///
/// <para><b>Esto es lo que reemplaza a la verificación del compilador.</b>
/// ST-079 eligió una tabla estática de C# en vez de recursos con un argumento
/// que sigue siendo bueno: una clave mal escrita no falla al compilar, devuelve
/// un texto vacío y el usuario ve un hueco. Al mover los textos a un
/// <c>.resx</c> ese riesgo vuelve, y esta prueba es la que lo cierra: si
/// alguien escribe <c>Strings.Get("ajustes.titulo")</c> y esa clave no está,
/// falla acá y no en la pantalla de alguien.</para>
///
/// <para>Se hace <b>por archivos</b> —el código fuente y el <c>.resx</c>— y no
/// cargando la app: el proyecto de pruebas es <c>net10.0</c> y el de la app
/// <c>net10.0-windows</c> con WinUI, así que no se puede referenciar. Que el
/// recurso además quedó embebido con el nombre correcto se comprueba en el
/// arnés, que sí corre código de la app.</para>
/// </summary>
public class ResourceKeyTests
{
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

    private static string AppDirectory() =>
        Path.Combine(RepoRoot(), "studio", "windows", "AuraStudio.App");

    private static string ResourcesPath() =>
        Path.Combine(AppDirectory(), "Strings", "Resources.resx");

    /// <summary>Las claves que el archivo de recursos trae.</summary>
    private static HashSet<string> KeysInResources() =>
    [
        .. XDocument.Load(ResourcesPath())
            .Root!
            .Elements("data")
            .Select(data => data.Attribute("name")!.Value)
    ];

    /// <summary>Cada uso de <c>Strings.Get/Format/Plural</c> del código de la app.</summary>
    private static IEnumerable<(string Key, string File, string Method)> KeysUsedInCode()
    {
        var pattern = new Regex(@"Strings\.(Get|Format|Plural)\(\s*""([^""]+)""");

        foreach (string file in Directory.EnumerateFiles(AppDirectory(), "*.cs", SearchOption.AllDirectories))
        {
            if (file.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")
                || file.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}"))
            {
                continue;
            }

            foreach (Match match in pattern.Matches(File.ReadAllText(file)))
                yield return (match.Groups[2].Value, Path.GetFileName(file), match.Groups[1].Value);
        }
    }

    [Fact]
    public void TodaClaveQueElCodigoPideExiste()
    {
        HashSet<string> available = KeysInResources();

        List<string> missing =
        [
            .. KeysUsedInCode()
                .Where(use => use.Method != "Plural")
                .Where(use => !available.Contains(use.Key))
                .Select(use => $"{use.File}: {use.Key}")
        ];

        Assert.True(missing.Count == 0,
            "Estas claves se piden y no están en Resources.resx —el usuario vería ⟦la.clave⟧—:\n"
            + string.Join("\n", missing));
    }

    /// <summary>
    /// Una clave plural necesita <b>todas</b> las formas de la cultura, no solo
    /// una: la que falte no se nota hasta que alguien cuenta justo ese número.
    /// En español son <c>.one</c> y <c>.other</c>.
    /// </summary>
    [Fact]
    public void TodaClavePluralTraeSusDosFormasEnEspanol()
    {
        HashSet<string> available = KeysInResources();

        List<string> missing =
        [
            .. KeysUsedInCode()
                .Where(use => use.Method == "Plural")
                .SelectMany(use => new[] { use.Key + ".one", use.Key + ".other" }
                    .Where(form => !available.Contains(form))
                    .Select(form => $"{use.File}: {form}"))
        ];

        Assert.True(missing.Count == 0,
            "Faltan formas de plural en Resources.resx:\n" + string.Join("\n", missing));
    }

    /// <summary>
    /// Ninguna clave con valor vacío. Un <c>&lt;value&gt;&lt;/value&gt;</c> es un
    /// hueco en la pantalla que además <b>no</b> dispara el aviso de clave
    /// ausente: se ve exactamente igual que un texto que se olvidaron de
    /// escribir, y no lo delata nadie.
    /// </summary>
    [Fact]
    public void NingunaClaveEstaVacia()
    {
        List<string> empty =
        [
            .. XDocument.Load(ResourcesPath())
                .Root!
                .Elements("data")
                .Where(data => string.IsNullOrWhiteSpace(data.Element("value")?.Value))
                .Select(data => data.Attribute("name")!.Value)
        ];

        Assert.True(empty.Count == 0,
            "Estas claves están vacías en Resources.resx:\n" + string.Join("\n", empty));
    }
}
