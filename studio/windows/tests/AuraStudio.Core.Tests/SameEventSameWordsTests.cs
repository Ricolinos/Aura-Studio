using System.Xml.Linq;
using AuraStudio.Core.Resources;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Dos claves que describen el mismo suceso dicen lo mismo, en todos los
/// idiomas (ST-247, B7d).
///
/// <para><b>El caso.</b> Cancelar el diálogo de UAC se reportaba con dos
/// mensajes distintos según por dónde pasara: uno decía «Cancelaste la
/// autorización» y el otro «Cancelaste el permiso de administrador». El mismo
/// clic del usuario, dos frases. En español se notaba poco; al traducir, cada
/// idioma eligió su propia raíz para cada una y la app terminó con cuatro
/// formas de contar una cosa.</para>
///
/// <para><b>Por qué siguen siendo dos claves.</b> Lo natural sería una sola.
/// Las dos ya salieron en la ronda de retrotraducción a ciegas con su
/// identificador —<c>mapa2-criticas.csv</c>—, y borrar una dejaría un id
/// huérfano en un expediente ya cerrado. Se quedan las dos, y esta prueba se
/// encarga de que no vuelvan a separarse.</para>
/// </summary>
public class SameEventSameWordsTests
{
    /// <summary>
    /// Grupos de claves que tienen que decir exactamente lo mismo, con el
    /// suceso que describen.
    /// </summary>
    private static readonly (string Event, string[] Keys)[] SameWords =
    [
        ("el usuario cerró el diálogo de UAC",
        [
            "installer-error.authorization-cancelled",
            "privileged.authorization-cancelled",
        ]),
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
        foreach (AppLanguage language in AppLanguages.Translated) data.Add(language.Culture);
        return data;
    }

    [Theory]
    [MemberData(nameof(Cultures))]
    public void ElMismoSucesoSeCuentaConLasMismasPalabras(string culture)
    {
        Dictionary<string, string> resources = ValuesOf(culture);

        List<string> problems = [];

        foreach ((string happening, string[] keys) in SameWords)
        {
            string first = resources[keys[0]];

            foreach (string key in keys.Skip(1))
            {
                if (resources[key] == first) continue;

                problems.Add($"«{happening}» se cuenta de dos formas:\n  {keys[0]}: {first}\n  {key}: {resources[key]}");
            }
        }

        Assert.True(problems.Count == 0, $"En {culture}:\n" + string.Join("\n\n", problems));
    }
}
