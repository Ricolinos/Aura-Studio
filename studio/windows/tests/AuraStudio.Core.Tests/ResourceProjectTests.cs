using System.Xml.Linq;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Cada archivo de idioma está declarado en el proyecto, con su nombre lógico
/// escrito (ST-247, B7c).
///
/// <para><b>Por qué existe esta prueba.</b> En B7b la entrada del inglés se
/// perdió del <c>.csproj</c> —una restauración desde una copia vieja se la
/// llevó— y <b>nadie lo notó</b>: el satélite se siguió generando, las pruebas
/// de cultura siguieron pasando, y el instalador siguió encontrando la carpeta.
/// El motivo es que el SDK incluye los <c>.resx</c> por su cuenta e infiere la
/// cultura del nombre, y el nombre lógico que le toca por convención resulta
/// ser el mismo que busca el <c>ResourceManager</c>.</para>
///
/// <para>Eso es una coincidencia, no un acuerdo. Y si algún día deja de
/// coincidir —otra carpeta, otro espacio de nombres, otra versión del SDK—, el
/// síntoma es que la app pide un idioma, no lo encuentra y cae al español
/// <b>sin fallar nada</b>. Es el mismo modo de falla silencioso contra el que
/// están escritas las otras comprobaciones de este bloque, y la única razón por
/// la que se descubrió fue que alguien leyó el diff.</para>
///
/// <para>Así que el emparejamiento se escribe y esta prueba exige que esté
/// escrito: agregar un idioma es agregar su <c>.resx</c> <i>y</i> su entrada, y
/// olvidarse de la segunda ya no pasa desapercibido.</para>
/// </summary>
public class ResourceProjectTests
{
    private const string NeutralLogicalName = "AuraStudio.Core.Strings.Resources.resources";

    private static string CoreDirectory()
    {
        DirectoryInfo? directory = new(AppContext.BaseDirectory);

        while (directory is not null)
        {
            string candidate = Path.Combine(directory.FullName, "studio", "windows", "AuraStudio.Core");
            if (File.Exists(Path.Combine(candidate, "AuraStudio.Core.csproj"))) return candidate;

            directory = directory.Parent;
        }

        throw new InvalidOperationException("No se encontró AuraStudio.Core desde el directorio de pruebas.");
    }

    /// <summary>Las entradas declaradas: ruta → nombre lógico.</summary>
    private static Dictionary<string, string> DeclaredResources()
    {
        XDocument project = XDocument.Load(Path.Combine(CoreDirectory(), "AuraStudio.Core.csproj"));

        return project
            .Descendants("EmbeddedResource")
            .Where(element => element.Attribute("Update")?.Value.StartsWith("Strings", StringComparison.Ordinal) == true)
            .ToDictionary(
                element => Path.GetFileName(element.Attribute("Update")!.Value.Replace('\\', '/')),
                element => element.Element("LogicalName")?.Value ?? "");
    }

    private static List<string> ResourceFilesOnDisk() =>
        [.. Directory.EnumerateFiles(Path.Combine(CoreDirectory(), "Strings"), "Resources*.resx")
            .Select(Path.GetFileName)
            .OfType<string>()
            .Order(StringComparer.Ordinal)];

    /// <summary>
    /// Todo <c>.resx</c> que está en disco está declarado en el proyecto.
    /// </summary>
    [Fact]
    public void CadaArchivoDeIdiomaTieneSuEntradaEnElProyecto()
    {
        Dictionary<string, string> declared = DeclaredResources();

        List<string> undeclared = [.. ResourceFilesOnDisk().Where(file => !declared.ContainsKey(file))];

        Assert.True(undeclared.Count == 0,
            "Estos archivos de idioma existen y el .csproj no los nombra. Hoy funcionarían igual "
            + "—el SDK los incluye solo— pero eso es una coincidencia que se puede romper en "
            + "silencio:\n" + string.Join("\n", undeclared));
    }

    /// <summary>
    /// Y toda entrada declarada tiene un archivo: una que apunte a nada es un
    /// renglón que dice proteger algo que ya no está.
    /// </summary>
    [Fact]
    public void NingunaEntradaApuntaAUnArchivoQueNoExiste()
    {
        List<string> onDisk = ResourceFilesOnDisk();

        List<string> missing = [.. DeclaredResources().Keys.Where(file => !onDisk.Contains(file))];

        Assert.True(missing.Count == 0,
            "El .csproj declara estos archivos y no están en disco:\n" + string.Join("\n", missing));
    }

    /// <summary>
    /// Cada entrada trae su <c>LogicalName</c> escrito, y el de cada idioma es
    /// el del neutro con la cultura metida antes de <c>.resources</c>. Ese es el
    /// nombre que el <c>ResourceManager</c> va a pedir; escribirlo distinto es
    /// un satélite que existe y no se encuentra.
    /// </summary>
    [Fact]
    public void CadaEntradaTraeSuNombreLogicoYSigueElPatronDelNeutro()
    {
        List<string> problems = [];

        foreach ((string file, string logicalName) in DeclaredResources())
        {
            if (logicalName.Length == 0)
            {
                problems.Add($"{file}: sin LogicalName — quedaría al criterio de la convención");
                continue;
            }

            // "Resources.resx" → neutro; "Resources.en.resx" → cultura "en".
            string[] parts = file.Split('.');
            string expected = parts.Length == 2
                ? NeutralLogicalName
                : NeutralLogicalName.Replace(".resources", $".{parts[1]}.resources", StringComparison.Ordinal);

            if (logicalName != expected)
                problems.Add($"{file}: dice «{logicalName}» y tendría que decir «{expected}»");
        }

        Assert.True(problems.Count == 0, string.Join("\n", problems));
    }
}
