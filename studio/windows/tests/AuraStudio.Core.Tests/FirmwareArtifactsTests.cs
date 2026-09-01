using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using AuraStudio.Core;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Contrato §A: nada se escribe en el iPod ni se ejecuta para flashear sin
/// verificar antes. Port de `BundledArtifacts.verifyAll` de macOS, más el caso
/// que solo existe en Windows: `mks5lboot.exe` **no viene del Release** (§A
/// publica `mks5lboot`, Unix), así que su procedencia se reporta aparte.
/// </summary>
public class FirmwareArtifactsTests : IDisposable
{
    private readonly string _dir;

    public FirmwareArtifactsTests()
    {
        _dir = Path.Combine(Path.GetTempPath(), "AuraArtifacts-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_dir);
    }

    public void Dispose()
    {
        try { Directory.Delete(_dir, recursive: true); } catch { /* best effort */ }
    }

    // MARK: - Fixtures

    private string Write(string name, string contents)
    {
        string path = Path.Combine(_dir, name);
        File.WriteAllText(path, contents);
        return path;
    }

    private static string Sha256Of(string text)
        => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text))).ToLowerInvariant();

    /// <summary>`rockbox.zip` con las entradas que D-297/D-298 exigen comprobar.</summary>
    private void WriteArchive(bool complete = true, string? unsafeEntry = null)
    {
        string path = Path.Combine(_dir, "rockbox.zip");
        using var zip = ZipFile.Open(path, ZipArchiveMode.Create);
        void Add(string entryPath)
        {
            using var w = new StreamWriter(zip.CreateEntry(entryPath).Open());
            w.Write("x");
        }
        Add(".rockbox/rockbox.ipod");
        if (complete)
        {
            Add(".rockbox/rocks/viewers/mpegplayer.rock");
            Add(".rockbox/codecs/mpa.codec");
        }
        if (unsafeEntry is not null) Add(unsafeEntry);
    }

    /// <summary>Deja un juego completo y verificable de artefactos.</summary>
    private void WriteHealthySet(bool withTool = true, bool withToolOrigin = true)
    {
        Write("rockbox.ipod", "IMAGEN");
        WriteArchive();
        Write("bootloader-ipod6g.ipod", "BOOT");
        if (withTool) Write("mks5lboot.exe", "HERRAMIENTA");

        string zipHash = Convert.ToHexString(
            SHA256.HashData(File.ReadAllBytes(Path.Combine(_dir, "rockbox.zip")))).ToLowerInvariant();

        Write("checksums.txt",
            $"{Sha256Of("IMAGEN")}  rockbox.ipod\n" +
            $"{zipHash}  rockbox.zip\n" +
            $"{Sha256Of("BOOT")}  bootloader-ipod6g.ipod\n");

        if (withTool && withToolOrigin)
        {
            Write(ToolOrigin.FileName, $"sha256={Sha256Of("HERRAMIENTA")}\ntag=desconocido\n");
        }
    }

    private FirmwareArtifacts Artifacts() => FirmwareArtifacts.Load(_dir, FirmwareFamily.Aura);

    // MARK: - Tag del Release

    [Fact]
    public void TheTagComesFromTheVersionMarkerNeverInvented()
    {
        Assert.Null(Artifacts().ReleaseTag);
        Assert.False(Artifacts().IsRelease);

        Write("firmware-version.txt", "v0.4.4-beta\n");
        Assert.Equal("v0.4.4-beta", Artifacts().ReleaseTag);
        Assert.True(Artifacts().IsRelease);
    }

    [Fact]
    public void LocalDevIsNotARelease()
    {
        // Lo escribe FirmwareFetch.ps1 -FromDir: un dist armado a mano, no un
        // Release etiquetado. La pantalla de Licencias tiene que poder decirlo.
        Write("firmware-version.txt", "local-dev");
        Assert.Equal("local-dev", Artifacts().ReleaseTag);
        Assert.False(Artifacts().IsRelease);
    }

    // MARK: - Verificación del árbol

    [Fact]
    public void AHealthySetVerifies()
    {
        WriteHealthySet();
        ArtifactVerificationResult result = FirmwareArtifactVerifier.Verify(Artifacts());
        Assert.True(result.IsValid, string.Join(" | ", result.Errors));
    }

    [Fact]
    public void AChangedFileFailsItsChecksum()
    {
        WriteHealthySet();
        Write("rockbox.ipod", "OTRA COSA");

        ArtifactVerificationResult result = FirmwareArtifactVerifier.Verify(Artifacts(), ArtifactScope.FirmwareTree);
        Assert.False(result.IsValid);
        Assert.Contains(result.Errors, e => e.Contains("rockbox.ipod", StringComparison.Ordinal));
    }

    [Fact]
    public void AZipWithoutCodecsOrPluginsIsRejectedEvenWithARightChecksum()
    {
        // D-297/D-298: el bug real. El checksum coincidía con lo que el Release
        // publicaba; lo que estaba mal era el contenido publicado.
        Write("rockbox.ipod", "IMAGEN");
        WriteArchive(complete: false);
        Write("bootloader-ipod6g.ipod", "BOOT");
        string zipHash = Convert.ToHexString(
            SHA256.HashData(File.ReadAllBytes(Path.Combine(_dir, "rockbox.zip")))).ToLowerInvariant();
        Write("checksums.txt",
            $"{Sha256Of("IMAGEN")}  rockbox.ipod\n{zipHash}  rockbox.zip\n{Sha256Of("BOOT")}  bootloader-ipod6g.ipod\n");

        ArtifactVerificationResult result = FirmwareArtifactVerifier.Verify(Artifacts(), ArtifactScope.FirmwareTree);
        Assert.False(result.IsValid);
        Assert.Contains(result.Errors, e => e.Contains("incompleto", StringComparison.Ordinal));
        Assert.Contains(result.Errors, e => e.Contains("mpegplayer.rock", StringComparison.Ordinal));
    }

    [Fact]
    public void AnUnsafePathInsideTheZipIsRejected()
    {
        Write("rockbox.ipod", "IMAGEN");
        WriteArchive(unsafeEntry: "../fuera.txt");
        Write("bootloader-ipod6g.ipod", "BOOT");
        string zipHash = Convert.ToHexString(
            SHA256.HashData(File.ReadAllBytes(Path.Combine(_dir, "rockbox.zip")))).ToLowerInvariant();
        Write("checksums.txt",
            $"{Sha256Of("IMAGEN")}  rockbox.ipod\n{zipHash}  rockbox.zip\n{Sha256Of("BOOT")}  bootloader-ipod6g.ipod\n");

        ArtifactVerificationResult result = FirmwareArtifactVerifier.Verify(Artifacts(), ArtifactScope.FirmwareTree);
        Assert.False(result.IsValid);
        Assert.Contains(result.Errors, e => e.Contains("insegura", StringComparison.Ordinal));
    }

    [Fact]
    public void WithoutChecksumsNothingIsTrusted()
    {
        Write("rockbox.ipod", "IMAGEN");
        WriteArchive();
        ArtifactVerificationResult result = FirmwareArtifactVerifier.Verify(Artifacts(), ArtifactScope.FirmwareTree);
        Assert.False(result.IsValid);
        Assert.Contains(result.Errors, e => e.Contains("checksums.txt", StringComparison.Ordinal));
    }

    [Fact]
    public void AMissingDirectoryIsReportedNotThrown()
    {
        var artifacts = new FirmwareArtifacts(FirmwareFamily.Aura, Path.Combine(_dir, "no-existe"), null, false);
        ArtifactVerificationResult result = FirmwareArtifactVerifier.Verify(artifacts);
        Assert.False(result.IsValid);
        Assert.Single(result.Errors);
    }

    // MARK: - Alcance

    [Fact]
    public void TheTreeScopeDoesNotRequireTheFlashingTool()
    {
        // Dual boot sobre un iPod con el bootloader ya grabado solo copia
        // archivos: no hace falta mks5lboot para eso.
        WriteHealthySet(withTool: false);
        Assert.True(FirmwareArtifactVerifier.Verify(Artifacts(), ArtifactScope.FirmwareTree).IsValid);
        Assert.False(FirmwareArtifactVerifier.Verify(Artifacts(), ArtifactScope.Flashing).IsValid);
    }

    [Fact]
    public void TheFlashingScopeRequiresTheBootloader()
    {
        WriteHealthySet();
        File.Delete(Path.Combine(_dir, "bootloader-ipod6g.ipod"));

        ArtifactVerificationResult result = FirmwareArtifactVerifier.Verify(Artifacts(), ArtifactScope.Flashing);
        Assert.False(result.IsValid);
        Assert.Contains(result.Errors, e => e.Contains("bootloader", StringComparison.Ordinal));
    }

    // MARK: - Procedencia de mks5lboot.exe (solo Windows)

    [Fact]
    public void WithoutAnyHashTheToolIsUnverified()
    {
        WriteHealthySet(withToolOrigin: false);
        ArtifactVerificationResult result = FirmwareArtifactVerifier.Verify(Artifacts(), ArtifactScope.Flashing);

        Assert.False(result.IsValid);
        Assert.Equal(ToolProvenance.Unverified, result.Provenance);
    }

    [Fact]
    public void ALocalPinDetectsAReplacedTool()
    {
        WriteHealthySet();
        Write("mks5lboot.exe", "OTRA HERRAMIENTA");

        ArtifactVerificationResult result = FirmwareArtifactVerifier.Verify(Artifacts(), ArtifactScope.Flashing);
        Assert.False(result.IsValid);
        Assert.Equal(ToolProvenance.Unverified, result.Provenance);
        Assert.Contains(result.Errors, e => e.Contains(ToolOrigin.FileName, StringComparison.Ordinal));
    }

    [Fact]
    public void ALocalPinThatMatchesIsAcceptedButLabeledAsSuch()
    {
        WriteHealthySet();
        ArtifactVerificationResult result = FirmwareArtifactVerifier.Verify(Artifacts(), ArtifactScope.Flashing);

        Assert.True(result.IsValid, string.Join(" | ", result.Errors));
        // Detecta corrupción o reemplazo; NO acredita de qué fuente salió.
        Assert.Equal(ToolProvenance.LocalPin, result.Provenance);
        Assert.Equal("desconocido", result.ToolOriginTag);
    }

    [Fact]
    public void AReleaseThatPublishesTheExeWins()
    {
        // El día que el Release publique mks5lboot.exe, su checksum manda sobre
        // el fijado localmente y la procedencia sube de nivel sola.
        WriteHealthySet();
        Write("firmware-version.txt", "v0.4.4-beta");
        string checksums = File.ReadAllText(Path.Combine(_dir, "checksums.txt"));
        Write("checksums.txt", checksums + $"{Sha256Of("HERRAMIENTA")}  mks5lboot.exe\n");

        ArtifactVerificationResult result = FirmwareArtifactVerifier.Verify(Artifacts(), ArtifactScope.Flashing);
        Assert.True(result.IsValid, string.Join(" | ", result.Errors));
        Assert.Equal(ToolProvenance.ReleaseChecksums, result.Provenance);
        Assert.Equal("v0.4.4-beta", result.ToolOriginTag);
    }

    [Fact]
    public void AMissingToolIsReportedAsMissing()
    {
        WriteHealthySet(withTool: false, withToolOrigin: false);
        ArtifactVerificationResult result = FirmwareArtifactVerifier.Verify(Artifacts(), ArtifactScope.Flashing);
        Assert.Equal(ToolProvenance.Missing, result.Provenance);
    }

    [Fact]
    public void ToolOriginParsesKeysAndIgnoresComments()
    {
        ToolOrigin? origin = ToolOrigin.Parse("# comentario\n\nsha256=ABCDEF\n  tag = v1.0.0 \n");
        Assert.NotNull(origin);
        Assert.Equal("ABCDEF", origin!.Sha256);
        Assert.Equal("v1.0.0", origin.Tag);
        Assert.Null(ToolOrigin.Parse("nada que ver"));
    }

    // MARK: - checksums.txt

    [Fact]
    public void ChecksumsWithUnsafeOrMalformedLinesAreReported()
    {
        Write("checksums.txt",
            $"{Sha256Of("A")}  ok.bin\n" +
            "nohex  malo.bin\n" +
            $"{Sha256Of("B")}  ../fuera.bin\n" +
            $"{Sha256Of("C")}  *asterisco.bin\n");

        var errors = new List<string>();
        Dictionary<string, string> map = FirmwareArtifactVerifier.ReadChecksums(
            Path.Combine(_dir, "checksums.txt"), errors);

        Assert.True(map.ContainsKey("ok.bin"));
        // El asterisco del modo binario de shasum no forma parte del nombre.
        Assert.True(map.ContainsKey("asterisco.bin"));
        Assert.False(map.ContainsKey("../fuera.bin"));
        Assert.Equal(2, errors.Count);
    }

    [Fact]
    public void DirectoryForPutsEachFamilyWhereTheContractSays()
    {
        // §A bis: Aura en la raíz, cada hermana en su subdirectorio.
        Assert.Equal(Path.Combine("C:\\app", "artifacts"),
                     FirmwareArtifacts.DirectoryFor("C:\\app", FirmwareFamily.Aura));
        Assert.Equal(Path.Combine("C:\\app", "artifacts", "metro"),
                     FirmwareArtifacts.DirectoryFor("C:\\app", FirmwareFamily.Metro));
        Assert.Equal(Path.Combine("C:\\app", "artifacts", "moonlit"),
                     FirmwareArtifacts.DirectoryFor("C:\\app", FirmwareFamily.Moonlit));
    }
}

/// <summary>
/// Resolver el directorio de artefactos (ST-130). El NRE que tumbó la copia de
/// firmware del dueño entraba por acá con la familia en nulo — la escribía un
/// selector de la interfaz al refrescar su lista.
/// </summary>
public sealed class FirmwareArtifactsDirectoryTests
{
    [Fact]
    public void AuraViveEnLaRaizYCadaHermanaEnSuSubdirectorio()
    {
        Assert.Equal(Path.Combine(@"C:\app", "artifacts"),
            FirmwareArtifacts.DirectoryFor(@"C:\app", FirmwareFamily.Aura));

        Assert.Equal(Path.Combine(@"C:\app", "artifacts", "metro"),
            FirmwareArtifacts.DirectoryFor(@"C:\app", FirmwareFamily.Metro));
    }

    [Fact]
    public void SinRaizSeCaeALaDelEjecutable()
    {
        string expected = Path.Combine(AppContext.BaseDirectory, "artifacts");

        Assert.Equal(expected, FirmwareArtifacts.DirectoryFor(null!, FirmwareFamily.Aura));
        Assert.Equal(expected, FirmwareArtifacts.DirectoryFor("   ", FirmwareFamily.Aura));
    }

    /// <summary>
    /// Sin familia se LANZA, no se elige una. Resolver el directorio de un
    /// firmware que el usuario no pidió, cuando el que llama está a punto de
    /// copiarlo al iPod, es peor que fallar (ST-046).
    /// </summary>
    [Fact]
    public void SinFamiliaSeLanzaConNombreEnVezDeAdivinar() =>
        Assert.Throws<ArgumentNullException>(() => FirmwareArtifacts.DirectoryFor(@"C:\app", null!));
}
