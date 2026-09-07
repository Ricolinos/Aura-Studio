using System.Xml.Linq;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El español que ve el usuario <b>no cambia ni una letra</b> al mover los
/// textos a recursos (ST-247, regla de cierre de B7a).
///
/// <para>B7a es mover, no redactar. Esta prueba compara el archivo de recursos
/// contra el borrador que la herramienta saca del código —la foto de lo que la
/// app decía antes de tocar nada— y exige el mismo conjunto de claves con los
/// mismos textos, sin excepciones.</para>
///
/// <para><b>Antes había una excepción y ya no hace falta.</b> El borrador
/// partía una frase en fragmentos (<c>…-1</c>, <c>…-2</c>) cuando el código la
/// concatena entre líneas, así que el recurso las reunía y la prueba tenía que
/// permitir esa diferencia. Reunirlas a mano salió mal —cuatro de esos pares no
/// eran fragmentos sino <b>las dos ramas de un ternario</b>, o sea dos mensajes
/// distintos, y quedaron pegados—, y la prueba no lo vio porque calculaba lo
/// esperado con la misma lógica que hacía la unión. Una prueba que reimplementa
/// el defecto no puede detectarlo.</para>
///
/// <para>La herramienta ya une las concatenaciones ella misma, que es donde se
/// puede distinguir un fragmento de una rama: mirando la sintaxis. Con eso la
/// excepción desaparece y la prueba vuelve a ser lo que tiene que ser —
/// <b>igualdad, sin lógica propia que pueda equivocarse igual que el código que
/// vigila</b>.</para>
/// </summary>
public class SpanishUnchangedTests
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

    private static Dictionary<string, string> ValuesOf(string path) =>
        XDocument.Load(path)
            .Root!
            .Elements("data")
            .ToDictionary(
                data => data.Attribute("name")!.Value,
                data => data.Element("value")?.Value ?? "");

    private static Dictionary<string, string> Resources() => ValuesOf(Path.Combine(
        RepoRoot(), "studio", "windows", "AuraStudio.Core", "Strings", "Resources.resx"));

    private static Dictionary<string, string> Draft() => ValuesOf(Path.Combine(
        RepoRoot(), "studio", "windows", "docs", "extraccion-cadenas", "Strings", "es", "Resources.resw"));

    /// <summary>
    /// Cada texto del recurso es exactamente el que la app decía antes. Una
    /// clave que sobre también falla: sería texto redactado en B7a, que es justo
    /// lo que no toca.
    /// </summary>
    [Fact]
    public void CadaTextoEsElQueLaAppDeciaAntes()
    {
        Dictionary<string, string> resources = Resources();
        Dictionary<string, string> draft = Draft();

        List<string> problems = [];

        foreach ((string key, string text) in resources)
        {
            if (!draft.TryGetValue(key, out string? original))
            {
                problems.Add($"{key}: no está en el borrador — es un texto nuevo, y B7a es mover, no redactar");
                continue;
            }

            if (original != text)
                problems.Add($"{key}: el texto cambió\n  antes: {original}\n  ahora: {text}");
        }

        Assert.True(problems.Count == 0, string.Join("\n\n", problems));
    }

    /// <summary>
    /// Y al revés: ningún texto del borrador se perdió. Un texto que desaparece
    /// del recurso es una pantalla que se queda sin su frase.
    /// </summary>
    [Fact]
    public void NingunTextoSePerdioEnElCamino()
    {
        Dictionary<string, string> resources = Resources();

        List<string> lost = [.. Draft().Keys.Where(key => !resources.ContainsKey(key))];

        Assert.True(lost.Count == 0,
            "Estos textos estaban en el borrador y no están en el recurso:\n" + string.Join("\n", lost));
    }
}
