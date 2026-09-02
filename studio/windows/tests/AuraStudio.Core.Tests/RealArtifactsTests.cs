using AuraStudio.Core;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Verificación contra el árbol <b>real</b> de <c>artifacts/</c> del repo, no
/// contra fixtures.
///
/// <para>Existe por un fallo que ninguna prueba de fixtures podía encontrar: el
/// dueño instaló Aura sin problema y Metro y moonlit.aura se negaban con «Los
/// archivos del firmware no se pudieron verificar». La causa estaba en los
/// datos, no en la lógica — los Releases publican `mks5lboot` (POSIX) por
/// familia y el `.exe` de Windows vive solo en la raíz, así que las carpetas
/// hermanas no lo tienen y nunca lo van a tener (ST-136). Los fixtures escribían
/// siempre un juego completo, así que pasaban.</para>
///
/// <para><b>Las tres familias se prueban igual.</b> Que Aura funcione no dice
/// nada de sus hermanas: es la que vive en la raíz, y la raíz es justo el caso
/// afortunado.</para>
/// </summary>
public class RealArtifactsTests
{
    /// <summary>
    /// Sube desde el directorio de la prueba hasta encontrar `studio\windows`,
    /// para no depender de cuántos niveles tenga la ruta de compilación.
    /// </summary>
    private static string? FindArtifactsRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null)
        {
            string candidate = Path.Combine(dir.FullName, "artifacts");
            if (Directory.Exists(candidate) && File.Exists(Path.Combine(candidate, "rockbox.ipod")))
            {
                return dir.FullName;
            }
            dir = dir.Parent;
        }
        return null;
    }

    /// <summary>
    /// `artifacts/` está gitignorado: lo puebla `scripts\FirmwareFetch.ps1`. En
    /// un árbol recién clonado no está, y esta prueba no tiene nada que decir.
    /// Estas pruebas se saltan solas ahí, y este miembro deja dicho por qué.
    /// </summary>
    public static bool ArtifactsPresent => FindArtifactsRoot() is not null;

    [Theory]
    [MemberData(nameof(EveryInstallableFamily))]
    public void EveryFamilyVerifiesWithTheArtifactsThatShip(FirmwareFamily family)
    {
        string? root = FindArtifactsRoot();
        // Sin artifacts/ no hay nada que verificar: ver ArtifactsPresent.
        if (root is null) return;

        FirmwareArtifacts artifacts = FirmwareArtifacts.Load(
            FirmwareArtifacts.DirectoryFor(root!, family), family);

        ArtifactVerificationResult result = FirmwareArtifactVerifier.Verify(artifacts);

        Assert.True(result.IsValid,
            $"{family.DisplayName} no verifica con los artefactos reales:\n  " +
            string.Join("\n  ", result.Errors));
    }

    /// <summary>
    /// La herramienta que se va a ejecutar existe de verdad y su procedencia se
    /// puede acreditar. `Unverified` sería «no sé qué binario voy a correr
    /// contra el iPod de alguien», que es lo único inaceptable acá.
    /// </summary>
    [Theory]
    [MemberData(nameof(EveryInstallableFamily))]
    public void TheFlashingToolIsFoundAndAccountedForInEveryFamily(FirmwareFamily family)
    {
        string? root = FindArtifactsRoot();
        // Sin artifacts/ no hay nada que verificar: ver ArtifactsPresent.
        if (root is null) return;

        FirmwareArtifacts artifacts = FirmwareArtifacts.Load(
            FirmwareArtifacts.DirectoryFor(root!, family), family);

        FirmwareArtifacts.ToolLocation tool = artifacts.ResolveTool();
        Assert.True(tool.Exists, $"{family.DisplayName}: no se encontró {tool.OwnPath} ni el respaldo de la raíz.");
        Assert.True(File.Exists(tool.Path));

        ArtifactVerificationResult result =
            FirmwareArtifactVerifier.Verify(artifacts, ArtifactScope.Flashing);
        Assert.NotEqual(ToolProvenance.Unverified, result.Provenance);
        Assert.NotEqual(ToolProvenance.Missing, result.Provenance);
    }

    public static TheoryData<FirmwareFamily> EveryInstallableFamily
    {
        get
        {
            var data = new TheoryData<FirmwareFamily>();
            foreach (FirmwareFamily family in FirmwareFamily.Installable) data.Add(family);
            return data;
        }
    }
}
