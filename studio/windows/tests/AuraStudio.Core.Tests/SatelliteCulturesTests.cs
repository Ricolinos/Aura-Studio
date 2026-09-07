using System.Text.RegularExpressions;
using AuraStudio.Core.Resources;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La lista de idiomas del instalador es la misma que la de la app (ST-247,
/// B7b).
///
/// <para><b>Por qué hay dos y no una.</b> <c>Make-Installer.ps1</c> corre en
/// PowerShell y no puede leer una lista de C#, así que las culturas de satélite
/// están escritas también ahí. Eso es una copia, y una copia se desincroniza —
/// con el peor síntoma posible: el instalador deja de exigir un idioma, el
/// satélite no viaja, y la app ofrece ese idioma y se queda en español sin
/// decir nada. Nadie ve un error; alguien ve la pantalla en el idioma
/// equivocado, meses después.</para>
///
/// <para>Así que la copia existe pero no puede divergir: esta prueba lee el
/// script y compara. Si B7c agrega cuatro idiomas y olvida el instalador, falla
/// acá y no en la máquina de alguien.</para>
/// </summary>
public class SatelliteCulturesTests
{
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

    private static string InstallerScript() =>
        File.ReadAllText(Path.Combine(WindowsRoot(), "scripts", "Make-Installer.ps1"));

    /// <summary>
    /// Las culturas que el script exige son exactamente las que la app declara
    /// como necesarias.
    /// </summary>
    [Fact]
    public void ElInstaladorExigeExactamenteLosIdiomasQueLaAppDeclara()
    {
        Match declaration = Regex.Match(InstallerScript(), @"\$culturasSatelite\s*=\s*@\(([^)]*)\)");

        Assert.True(declaration.Success,
            "No se encontró $culturasSatelite en Make-Installer.ps1 — ¿se renombró? "
            + "Si el instalador dejó de comprobar los idiomas, hay que saberlo acá.");

        List<string> inScript =
        [
            .. Regex.Matches(declaration.Groups[1].Value, @"'([^']+)'")
                .Select(match => match.Groups[1].Value)
                .Order(StringComparer.Ordinal)
        ];

        List<string> declared = [.. AppLanguages.RequiredSatelliteCultures.Order(StringComparer.Ordinal)];

        Assert.Equal(declared, inScript);
    }

    /// <summary>
    /// Y el script <b>aborta</b> cuando falta uno, no solo avisa. Un aviso en
    /// la salida de una compilación de cinco minutos no lo lee nadie; lo que se
    /// lee es que no salió el instalador.
    /// </summary>
    [Fact]
    public void CuandoFaltaUnIdiomaElInstaladorSeDetiene()
    {
        string script = InstallerScript();

        int block = script.IndexOf("$culturasSatelite", StringComparison.Ordinal);
        Assert.True(block >= 0, "no se encontró el bloque de idiomas");

        string rest = script[block..];
        int nextSection = rest.IndexOf("# ---", StringComparison.Ordinal);
        if (nextSection > 0) rest = rest[..nextSection];

        Assert.Contains("throw", rest, StringComparison.Ordinal);
    }

    /// <summary>
    /// El español no se exige como carpeta: si alguien lo agregara a la lista,
    /// el instalador buscaría un satélite que por diseño no existe y fallaría
    /// siempre.
    /// </summary>
    [Fact]
    public void ElEspanolNoSeExigeComoCarpeta()
    {
        Match declaration = Regex.Match(InstallerScript(), @"\$culturasSatelite\s*=\s*@\(([^)]*)\)");

        Assert.DoesNotContain($"'{AppLanguages.NeutralCulture}'", declaration.Groups[1].Value, StringComparison.Ordinal);
    }
}
