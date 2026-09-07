using System.Xml.Linq;
using AuraStudio.Core.Resources;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La lista de textos críticos sirve para lo que tiene que servir (ST-247, B7c
/// preparado en B7b).
///
/// <para>Es la lista que en B7c se retrotraduce: japonés, alemán, ruso y
/// francés llegan traducidos por una máquina, nadie del proyecto los lee, y lo
/// acordado es que el mecánico los vuelva al español sin ver el original y se
/// compare el sentido. Hacer eso con seiscientas frases por cuatro idiomas no
/// es realista; con estas sí, y son donde una traducción torcida cuesta
/// archivos.</para>
/// </summary>
public class CriticalStringsTests
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

    private static List<string> Keys() =>
        [.. XDocument.Load(Path.Combine(StringsDirectory(), "Resources.resx"))
            .Root!
            .Elements("data")
            .Select(data => data.Attribute("name")!.Value)
            .Order(StringComparer.Ordinal)];

    /// <summary>
    /// Cada familia declarada alcanza al menos una clave real.
    ///
    /// <para>Un prefijo que no alcanza nada es un renglón que alguien escribió
    /// creyendo que protegía algo. Pasa al renombrar una clave: la lista sigue
    /// ahí, se ve completa, y ya no cubre lo que decía cubrir.</para>
    /// </summary>
    [Fact]
    public void CadaFamiliaDeclaradaAlcanzaAlgunaClave()
    {
        List<string> keys = Keys();

        List<string> empty =
        [
            .. CriticalStrings.Families
                .Where(family => !keys.Any(key => key.StartsWith(family.Prefix, StringComparison.Ordinal)))
                .Select(family => $"{family.Prefix} — «{family.Reason}»")
                .Order(StringComparer.Ordinal)
        ];

        Assert.True(empty.Count == 0,
            "Estos prefijos no alcanzan ninguna clave: o la clave se renombró, o el renglón sobra.\n"
            + string.Join("\n", empty));
    }

    /// <summary>
    /// Lo que borra, formatea o migra <b>está</b> en la lista.
    ///
    /// <para>Un puñado de claves concretas, escritas a mano y a propósito: si
    /// esta prueba derivara la respuesta de los mismos prefijos que vigila,
    /// pasaría siempre y no comprobaría nada. Son las pantallas donde el
    /// usuario aprieta "sí" y algo desaparece.</para>
    /// </summary>
    [Theory]
    [InlineData("app-strings.delete-confirm-title.one")]
    [InlineData("app-strings.delete-confirm-copy.other")]
    [InlineData("app-strings.installer-format-confirm")]
    [InlineData("app-strings.installer-welcome-warning")]
    [InlineData("app-strings.installer-flash-confirm")]
    [InlineData("app-strings.bootloader-update-flash-confirm")]
    [InlineData("app-strings.orphans-confirm-title.one")]
    [InlineData("orphans-confirm-message")]
    [InlineData("storage-copy-explainer")]
    [InlineData("storage-reference-explainer")]
    [InlineData("device-safety-validator.hay-mas-ipod-candidato-por-seguridad")]
    [InlineData("similar-items-view-model.items-removed.other")]
    [InlineData("library-view-model.migration-tagged.one")]
    [InlineData("settings-page.migrar-biblioteca")]
    public void LoQueBorraFormateaOMigraEsCritico(string key) =>
        Assert.True(CriticalStrings.IsCritical(key),
            $"{key} decide qué le pasa a los archivos de alguien y no está marcada como crítica");

    /// <summary>
    /// Y lo que es solo decoración <b>no</b> lo está: una lista que marca todo
    /// no prioriza nada, y entonces la retrotraducción de B7c vuelve a ser
    /// impracticable.
    /// </summary>
    [Theory]
    [InlineData("app-strings.nav-albums")]
    [InlineData("app-strings.theme-dark")]
    [InlineData("conteo.canciones.one")]
    [InlineData("extras-page.juegos")]
    [InlineData("themes-page.autor")]
    [InlineData("app-strings.settings-appearance")]
    public void LoQueEsDecoracionNoEsCritico(string key) =>
        Assert.False(CriticalStrings.IsCritical(key),
            $"{key} no decide nada sobre los archivos de nadie: marcarla diluye la lista");

    /// <summary>
    /// La lista cubre una parte del total, no casi todo ni casi nada. Los dos
    /// extremos la vuelven inútil, y el número exacto importa menos que el
    /// hecho de que alguien lo mire cuando cambie.
    /// </summary>
    [Fact]
    public void LaListaCubreUnaParteYNoElTodo()
    {
        List<string> keys = Keys();
        int critical = keys.Count(CriticalStrings.IsCritical);

        Assert.InRange(critical, 60, keys.Count / 2);
    }
}
