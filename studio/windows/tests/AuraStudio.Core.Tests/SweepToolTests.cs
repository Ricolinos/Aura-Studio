using System.Diagnostics;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La segunda barrida corre y encuentra algo (ST-247, B7d).
///
/// <para><b>Por qué existe la barrida.</b> El trinquete de
/// <see cref="HardcodedSpanishTests"/> decide qué es español con una lista de
/// palabras —«archivo», «canción», «álbum»…—, así que no ve «Formatos
/// distintos» ni «El árbol de X en el iPod está incompleto». El triaje de B7c
/// salió de ese detector y heredó su ceguera: las «303» eran un subconteo.</para>
///
/// <para>La barrida usa otra señal —literales de dos o más palabras que no
/// parezcan ruta, identificador ni clave— y por eso encuentra lo que el léxico
/// no alcanza. Da más ruido a propósito: <b>es para leer, no para contar.</b>
/// Ningún número suyo entra en un trinquete.</para>
///
/// <para><b>Y por eso esta prueba es tan corta.</b> No comprueba cuántas
/// encuentra —ese número baja y sube con cada tanda, y fijarlo convertiría una
/// herramienta de lectura en otro contador—. Comprueba lo único que puede
/// pudrirse en silencio: que el guion siga estando y siga corriendo. Una
/// herramienta que dejó de ejecutarse se ve igual que una que no encontró
/// nada.</para>
/// </summary>
public class SweepToolTests
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

    [Fact]
    public void LaBarridaEstaEnElRepo()
    {
        string script = Path.Combine(
            WindowsRoot(), "docs", "extraccion-cadenas", "barrida-frases.pl");

        Assert.True(File.Exists(script),
            "Falta docs/extraccion-cadenas/barrida-frases.pl. Es la herramienta que encontró lo que el "
            + "trinquete no ve; sin ella, la próxima tanda vuelve a confiar solo en el léxico.");
    }

    /// <summary>
    /// Y corre. Si no hay perl en esta máquina la prueba no falla: no todos los
    /// que compilan el proyecto tienen que tenerlo, y una prueba que exige una
    /// herramienta ajena para pasar termina desactivada.
    /// </summary>
    [Fact]
    public void LaBarridaCorreYEncuentraAlgo()
    {
        var start = new ProcessStartInfo("perl", "docs/extraccion-cadenas/barrida-frases.pl")
        {
            WorkingDirectory = WindowsRoot(),
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };

        Process? process;
        try
        {
            process = Process.Start(start);
        }
        catch (Exception exception) when (exception is System.ComponentModel.Win32Exception)
        {
            return;   // sin perl acá; ya se comprobó que el guion existe
        }

        Assert.NotNull(process);

        string output = process.StandardOutput.ReadToEnd();
        process.WaitForExit();

        Assert.True(process.ExitCode == 0,
            "La barrida terminó con error:\n" + process.StandardError.ReadToEnd());

        Assert.Contains("literales con pinta de frase", output, StringComparison.Ordinal);
    }
}
