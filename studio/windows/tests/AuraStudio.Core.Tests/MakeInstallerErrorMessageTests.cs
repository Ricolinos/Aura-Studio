using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// ST-248 (B8): cuando el publish sale incompleto por falta de un artefacto
/// de firmware (todo lo que <c>Make-Installer.ps1</c> busca bajo
/// <c>artifacts\</c>), el mensaje tiene que decir exactamente qué correr --
/// <c>FirmwareFetch.ps1</c> -- en vez de dejar a quien lo lee a adivinar por
/// qué faltan ocho archivos de golpe. Solo el mensaje cambia: el flujo
/// (publicar, comprobar, empaquetar) sigue igual.
///
/// <para>Mismo patrón que <c>SatelliteCulturesTests</c>: lee el script como
/// texto, porque correrlo de verdad exigiría un publish real (minutos, y
/// necesita el SDK de Windows instalado) que no le corresponde a esta
/// batería.</para>
/// </summary>
public class MakeInstallerErrorMessageTests
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

    /// <summary>El bloque que arma el mensaje de "publish incompleto" tiene que citar FirmwareFetch.ps1 y su modo -FromDir.</summary>
    [Fact]
    public void ElAvisoDeArtefactoDeFirmwareFaltanteMencionaFirmwareFetch()
    {
        string script = InstallerScript();

        int block = script.IndexOf("El publish está incompleto", StringComparison.Ordinal);
        Assert.True(block >= 0, "no se encontró el mensaje de publish incompleto en Make-Installer.ps1");

        string rest = script[block..];
        int nextSection = rest.IndexOf("# ---", StringComparison.Ordinal);
        if (nextSection > 0) rest = rest[..nextSection];

        Assert.Contains("FirmwareFetch.ps1", rest, StringComparison.Ordinal);
        Assert.Contains("-FromDir", rest, StringComparison.Ordinal);
    }

    /// <summary>
    /// Un binario propio de la app (no bajo <c>artifacts\</c>) no tiene por
    /// qué mandar a FirmwareFetch.ps1 -- ese script no lo puede arreglar, y
    /// decir que sí solo manda a alguien a correr algo que no ayuda.
    /// </summary>
    [Fact]
    public void ElAvisoDistingueBinarioDeAppDeArtefactoDeFirmware()
    {
        string script = InstallerScript();

        int block = script.IndexOf("El publish está incompleto", StringComparison.Ordinal);
        Assert.True(block >= 0);

        string rest = script[block..];
        int nextSection = rest.IndexOf("# ---", StringComparison.Ordinal);
        if (nextSection > 0) rest = rest[..nextSection];

        Assert.Contains("faltanApp", rest, StringComparison.Ordinal);
        Assert.Contains("faltanFirmware", rest, StringComparison.Ordinal);
    }
}
