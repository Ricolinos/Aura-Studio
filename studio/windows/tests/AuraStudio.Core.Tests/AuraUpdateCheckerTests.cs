using System.Security.Cryptography;
using System.Text;
using AuraStudio.Core;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Port de `AuraUpdateChecker` de macOS: tag primero, hash del binario como
/// respaldo, y **nunca** comparar contra el binario de otra familia (ST-046).
/// </summary>
public class AuraUpdateCheckerTests : IDisposable
{
    private readonly string _volume;
    private readonly string _artifactsDir;

    public AuraUpdateCheckerTests()
    {
        string root = Path.Combine(Path.GetTempPath(), "AuraUpdate-" + Guid.NewGuid().ToString("N"));
        _volume = Path.Combine(root, "volumen");
        _artifactsDir = Path.Combine(root, "artefactos");
        Directory.CreateDirectory(_volume);
        Directory.CreateDirectory(_artifactsDir);
    }

    public void Dispose()
    {
        try { Directory.Delete(Path.GetDirectoryName(_volume)!, recursive: true); } catch { /* best effort */ }
    }

    private void WriteOnVolume(string relative, string contents)
    {
        string path = Path.Combine(_volume, relative.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, contents);
    }

    private FirmwareArtifacts WriteArtifacts(string image, string? tag = null)
    {
        File.WriteAllText(Path.Combine(_artifactsDir, "rockbox.ipod"), image);
        if (tag is not null) File.WriteAllText(Path.Combine(_artifactsDir, "firmware-version.txt"), tag);
        return FirmwareArtifacts.Load(_artifactsDir, FirmwareFamily.Aura);
    }

    // MARK: - version.txt

    [Fact]
    public void ReadsTheInstalledTag()
    {
        WriteOnVolume(".rockbox/aura/version.txt", "v0.4.3-beta\n");
        Assert.Equal("v0.4.3-beta", AuraUpdateChecker.InstalledVersionTag(_volume));
    }

    [Fact]
    public void AnEmptyOrMissingTagIsNull()
    {
        Assert.Null(AuraUpdateChecker.InstalledVersionTag(_volume));
        WriteOnVolume(".rockbox/aura/version.txt", "   \n");
        Assert.Null(AuraUpdateChecker.InstalledVersionTag(_volume));
        Assert.Null(AuraUpdateChecker.InstalledVersionTag(""));
    }

    [Fact]
    public void AnOlderTagMeansThereIsAnUpdate()
    {
        WriteOnVolume(".rockbox/aura/version.txt", "v0.4.3-beta");
        FirmwareArtifacts artifacts = WriteArtifacts("IMAGEN");

        UpdateVerdict verdict = AuraUpdateChecker.Check(_volume, artifacts, latestKnownTag: "v0.4.4-beta");
        Assert.True(verdict.UpdateAvailable);
        Assert.Equal(UpdateVerdictReason.VersionTag, verdict.Reason);
        Assert.Equal("v0.4.4-beta", verdict.LatestTag);
    }

    [Fact]
    public void TheSameTagMeansThereIsNoUpdate()
    {
        WriteOnVolume(".rockbox/aura/version.txt", "v0.4.4-beta");
        WriteOnVolume(".rockbox/rockbox.ipod", "VIEJO");   // el hash diría que sí; el tag manda
        FirmwareArtifacts artifacts = WriteArtifacts("NUEVO");

        UpdateVerdict verdict = AuraUpdateChecker.Check(_volume, artifacts, latestKnownTag: "v0.4.4-beta");
        Assert.False(verdict.UpdateAvailable);
        Assert.Equal(UpdateVerdictReason.VersionTag, verdict.Reason);
    }

    [Fact]
    public void AnUnparseableTagFallsBackToTheHash()
    {
        WriteOnVolume(".rockbox/aura/version.txt", "no-es-una-version");
        WriteOnVolume(".rockbox/rockbox.ipod", "VIEJO");
        FirmwareArtifacts artifacts = WriteArtifacts("NUEVO");

        UpdateVerdict verdict = AuraUpdateChecker.Check(_volume, artifacts, latestKnownTag: "v0.4.4-beta");
        Assert.Equal(UpdateVerdictReason.BinaryHash, verdict.Reason);
        Assert.True(verdict.UpdateAvailable);
    }

    [Fact]
    public void WithoutAKnownLatestTagItGoesStraightToTheHash()
    {
        // Sin red y sin caché: comparar binarios es mejor que reportar "al día".
        WriteOnVolume(".rockbox/aura/version.txt", "v0.4.3-beta");
        WriteOnVolume(".rockbox/rockbox.ipod", "IGUAL");
        FirmwareArtifacts artifacts = WriteArtifacts("IGUAL");

        UpdateVerdict verdict = AuraUpdateChecker.Check(_volume, artifacts, latestKnownTag: null);
        Assert.Equal(UpdateVerdictReason.BinaryHash, verdict.Reason);
        Assert.False(verdict.UpdateAvailable);
    }

    // MARK: - Respaldo por hash

    [Fact]
    public void IdenticalBinariesMeanNoUpdate()
    {
        WriteOnVolume(".rockbox/rockbox.ipod", "MISMO CONTENIDO");
        UpdateVerdict verdict = AuraUpdateChecker.CompareBinaries(_volume, WriteArtifacts("MISMO CONTENIDO"));
        Assert.False(verdict.UpdateAvailable);
        Assert.Equal(UpdateVerdictReason.BinaryHash, verdict.Reason);
    }

    [Fact]
    public void DifferentBinariesMeanUpdate()
    {
        WriteOnVolume(".rockbox/rockbox.ipod", "INSTALADO");
        Assert.True(AuraUpdateChecker.CompareBinaries(_volume, WriteArtifacts("LOCAL")).UpdateAvailable);
    }

    [Fact]
    public void TheTreeCopyWinsOverTheRootCopy()
    {
        // El que arranca el bootloader es el del árbol (D-178); el de la raíz es
        // la copia histórica. Si difieren, manda el del árbol.
        WriteOnVolume(".rockbox/rockbox.ipod", "EL BUENO");
        WriteOnVolume("rockbox.ipod", "EL VIEJO");

        Assert.False(AuraUpdateChecker.CompareBinaries(_volume, WriteArtifacts("EL BUENO")).UpdateAvailable);
        Assert.EndsWith(Path.Combine(".rockbox", "rockbox.ipod"),
                        AuraUpdateChecker.InstalledFirmwareBinary(_volume));
    }

    [Fact]
    public void TheRootCopyIsUsedWhenTheTreeHasNone()
    {
        WriteOnVolume("rockbox.ipod", "SOLO RAIZ");
        Assert.False(AuraUpdateChecker.CompareBinaries(_volume, WriteArtifacts("SOLO RAIZ")).UpdateAvailable);
    }

    [Fact]
    public void AHalfCopiedTreeCountsAsUpdateAvailable()
    {
        // Familia detectada pero sin binario a la vista: reinstalar lo arregla.
        UpdateVerdict verdict = AuraUpdateChecker.CompareBinaries(_volume, WriteArtifacts("LOCAL"));
        Assert.True(verdict.UpdateAvailable);
        Assert.Equal(UpdateVerdictReason.InstalledBinaryMissing, verdict.Reason);
    }

    [Fact]
    public void WithoutLocalArtifactsNothingIsConcluded()
    {
        // ST-046: sin binario propio de esa familia con qué comparar, no
        // comparar es mejor que comparar mal — comparar contra otra familia
        // daría "hay actualización" para siempre y ofrecería sobrescribirla.
        WriteOnVolume(".rockbox/rockbox.ipod", "INSTALADO");

        Assert.Equal(UpdateVerdictReason.Unknown, AuraUpdateChecker.CompareBinaries(_volume, null).Reason);
        Assert.False(AuraUpdateChecker.CompareBinaries(_volume, null).UpdateAvailable);

        var sinBinario = FirmwareArtifacts.Load(_artifactsDir, FirmwareFamily.Metro);
        Assert.Equal(UpdateVerdictReason.Unknown, AuraUpdateChecker.CompareBinaries(_volume, sinBinario).Reason);
    }

    [Fact]
    public void AVolumeThatIsGoneConcludesNothing()
    {
        UpdateVerdict verdict = AuraUpdateChecker.Check(Path.Combine(_volume, "no-existe"), WriteArtifacts("X"));
        Assert.Equal(UpdateVerdictReason.Unknown, verdict.Reason);
        Assert.False(verdict.UpdateAvailable);
    }
}
