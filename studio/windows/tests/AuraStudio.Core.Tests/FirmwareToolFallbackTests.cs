using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using AuraStudio.Core;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// ST-136: `mks5lboot.exe` se comparte desde la raíz de `artifacts/` cuando la
/// familia no lo trae.
///
/// <para>Esto no es una comodidad: los Releases publican `mks5lboot` (binario
/// POSIX) por familia, con tres hashes distintos, y el `.exe` de Windows es un
/// cross-compile nuestro que vive solo en la raíz. Sin el respaldo, Metro y
/// moonlit.aura fallaban la verificación —y por lo tanto no se instalaban— por
/// faltarles un archivo que en Windows nunca van a traer. Lo reportó el dueño
/// probando la app instalada.</para>
///
/// <para>Se puede compartir porque la herramienta habla DFU con el hardware y
/// recibe el bootloader como argumento: <b>ese</b> sí es de cada familia, sí
/// viene del Release y se sigue verificando contra su propio `checksums.txt`.
/// Estas pruebas cuidan las dos mitades.</para>
/// </summary>
public class FirmwareToolFallbackTests : IDisposable
{
    private readonly string _root;

    public FirmwareToolFallbackTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "AuraTool-" + Guid.NewGuid().ToString("N"), "artifacts");
        Directory.CreateDirectory(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(Path.GetDirectoryName(_root)!, recursive: true); } catch { /* best effort */ }
    }

    // MARK: - Fixtures

    private static string Sha256Of(string text)
        => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text))).ToLowerInvariant();

    private string DirOf(FirmwareFamily family)
    {
        string dir = family.ConfigValue is { Length: > 0 } sub ? Path.Combine(_root, sub) : _root;
        Directory.CreateDirectory(dir);
        return dir;
    }

    /// <summary>El árbol de una familia, sin la herramienta: como lo deja un Release.</summary>
    private void WriteFamily(FirmwareFamily family, string flavor = "X")
    {
        string dir = DirOf(family);
        File.WriteAllText(Path.Combine(dir, "rockbox.ipod"), "IMAGEN" + flavor);
        File.WriteAllText(Path.Combine(dir, "bootloader-ipod6g.ipod"), "BOOT" + flavor);

        string zipPath = Path.Combine(dir, "rockbox.zip");
        using (var zip = ZipFile.Open(zipPath, ZipArchiveMode.Create))
        {
            foreach (string entry in new[]
                     {
                         ".rockbox/rockbox.ipod",
                         ".rockbox/rocks/viewers/mpegplayer.rock",
                         ".rockbox/codecs/mpa.codec"
                     })
            {
                using var w = new StreamWriter(zip.CreateEntry(entry).Open());
                w.Write(flavor);
            }
        }

        string zipHash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(zipPath))).ToLowerInvariant();
        File.WriteAllText(Path.Combine(dir, "checksums.txt"),
            $"{Sha256Of("IMAGEN" + flavor)}  rockbox.ipod\n" +
            $"{zipHash}  rockbox.zip\n" +
            $"{Sha256Of("BOOT" + flavor)}  bootloader-ipod6g.ipod\n");
    }

    /// <summary>El `.exe` cross-compilado y su `.origin`, solo en la raíz.</summary>
    private void WriteSharedTool(string contents = "HERRAMIENTA")
    {
        File.WriteAllText(Path.Combine(_root, FirmwareArtifacts.Mks5lbootFileName), contents);
        File.WriteAllText(Path.Combine(_root, ToolOrigin.FileName),
            $"sha256={Sha256Of(contents)}\ntag=desconocido\n");
    }

    private FirmwareArtifacts Load(FirmwareFamily family)
        => FirmwareArtifacts.Load(
               FirmwareArtifacts.DirectoryFor(Path.GetDirectoryName(_root)!, family), family);

    // MARK: - El respaldo

    [Theory]
    [MemberData(nameof(SisterFamilies))]
    public void ASisterFamilyUsesTheToolFromTheRoot(FirmwareFamily family)
    {
        WriteFamily(family);
        WriteSharedTool();

        FirmwareArtifacts.ToolLocation tool = Load(family).ResolveTool();

        Assert.True(tool.Exists);
        Assert.True(tool.Shared);
        Assert.Equal(Path.Combine(_root, FirmwareArtifacts.Mks5lbootFileName), tool.Path);
    }

    [Theory]
    [MemberData(nameof(SisterFamilies))]
    public void ASisterFamilyVerifiesCompletelyWithTheSharedTool(FirmwareFamily family)
    {
        WriteFamily(family);
        WriteSharedTool();

        ArtifactVerificationResult result = FirmwareArtifactVerifier.Verify(Load(family));

        Assert.True(result.IsValid, string.Join(" | ", result.Errors));
        // El `.origin` que vale es el que está junto al binario que se va a
        // ejecutar — el de la raíz, no uno de la carpeta de la familia.
        Assert.Equal(ToolProvenance.LocalPin, result.Provenance);
    }

    [Fact]
    public void AuraKeepsUsingItsOwnToolAndNeverReportsItAsShared()
    {
        WriteFamily(FirmwareFamily.Aura);
        WriteSharedTool();

        FirmwareArtifacts.ToolLocation tool = Load(FirmwareFamily.Aura).ResolveTool();

        Assert.True(tool.Exists);
        Assert.False(tool.Shared);   // para Aura la raíz ES su carpeta
    }

    [Fact]
    public void AFamilyThatBringsItsOwnToolPrefersIt()
    {
        WriteFamily(FirmwareFamily.Metro);
        WriteSharedTool("DE LA RAIZ");

        string own = Path.Combine(DirOf(FirmwareFamily.Metro), FirmwareArtifacts.Mks5lbootFileName);
        File.WriteAllText(own, "PROPIA");
        File.WriteAllText(Path.Combine(DirOf(FirmwareFamily.Metro), ToolOrigin.FileName),
            $"sha256={Sha256Of("PROPIA")}\ntag=desconocido\n");

        FirmwareArtifacts.ToolLocation tool = Load(FirmwareFamily.Metro).ResolveTool();

        Assert.Equal(own, tool.Path);
        Assert.False(tool.Shared);
    }

    /// <summary>
    /// El respaldo comparte la herramienta, **no** relaja la verificación: el
    /// bootloader sigue siendo de cada familia y sigue teniendo que cuadrar.
    /// </summary>
    [Fact]
    public void TheSharedToolDoesNotExcuseABadBootloader()
    {
        WriteFamily(FirmwareFamily.Metro);
        WriteSharedTool();
        File.WriteAllText(
            Path.Combine(DirOf(FirmwareFamily.Metro), "bootloader-ipod6g.ipod"), "OTRA COSA");

        ArtifactVerificationResult result = FirmwareArtifactVerifier.Verify(Load(FirmwareFamily.Metro));

        Assert.False(result.IsValid);
        Assert.Contains(result.Errors, e => e.Contains("bootloader-ipod6g.ipod", StringComparison.Ordinal));
    }

    /// <summary>
    /// Un `.exe` reemplazado o corrupto en la raíz rompe a **todas** las
    /// familias que dependen de él. Es lo correcto, y por eso el mensaje tiene
    /// que señalar el archivo de la raíz, no uno de la familia que no existe.
    /// </summary>
    [Fact]
    public void ATamperedSharedToolFailsTheSisterFamilyToo()
    {
        WriteFamily(FirmwareFamily.Moonlit);
        WriteSharedTool();
        File.WriteAllText(Path.Combine(_root, FirmwareArtifacts.Mks5lbootFileName), "REEMPLAZADA");

        ArtifactVerificationResult result = FirmwareArtifactVerifier.Verify(Load(FirmwareFamily.Moonlit));

        Assert.False(result.IsValid);
        Assert.Equal(ToolProvenance.Unverified, result.Provenance);
        Assert.Contains(result.Errors, e =>
            e.Contains(@"artifacts\mks5lboot.exe", StringComparison.Ordinal)
            && e.Contains(ToolOrigin.FileName, StringComparison.Ordinal));
    }

    // MARK: - Los mensajes nombran archivo y motivo

    [Fact]
    public void AMissingToolNamesBothPlacesItLookedIn()
    {
        WriteFamily(FirmwareFamily.Metro);
        // Sin herramienta en ningún lado.

        ArtifactVerificationResult result = FirmwareArtifactVerifier.Verify(Load(FirmwareFamily.Metro));

        Assert.False(result.IsValid);
        string error = Assert.Single(result.Errors, e => e.Contains("mks5lboot", StringComparison.Ordinal));
        Assert.Contains(@"artifacts\metro\mks5lboot.exe", error, StringComparison.Ordinal);
        Assert.Contains(@"artifacts\mks5lboot.exe", error, StringComparison.Ordinal);
    }

    [Fact]
    public void AChecksumMismatchNamesTheFileAndBothHashes()
    {
        WriteFamily(FirmwareFamily.Metro);
        WriteSharedTool();
        File.WriteAllText(Path.Combine(DirOf(FirmwareFamily.Metro), "rockbox.ipod"), "CORRUPTO");

        ArtifactVerificationResult result = FirmwareArtifactVerifier.Verify(Load(FirmwareFamily.Metro));

        string error = Assert.Single(result.Errors, e => e.Contains("rockbox.ipod", StringComparison.Ordinal));
        Assert.Contains(@"artifacts\metro\rockbox.ipod", error, StringComparison.Ordinal);
        Assert.Contains("esperado", error, StringComparison.Ordinal);
        Assert.Contains("calculado", error, StringComparison.Ordinal);
        // Ocho caracteres del hash, no los sesenta y cuatro.
        Assert.Contains(Sha256Of("IMAGENX")[..8], error, StringComparison.Ordinal);
        Assert.DoesNotContain(Sha256Of("IMAGENX"), error, StringComparison.Ordinal);
    }

    [Fact]
    public void AMissingDirectoryNamesTheFamilyAndTheFolder()
    {
        // Nunca se pobló metro/.
        ArtifactVerificationResult result = FirmwareArtifactVerifier.Verify(Load(FirmwareFamily.Metro));

        Assert.False(result.IsValid);
        string error = Assert.Single(result.Errors);
        Assert.Contains(@"artifacts\metro", error, StringComparison.Ordinal);
        Assert.Contains(FirmwareFamily.Metro.DisplayName, error, StringComparison.Ordinal);
    }

    [Fact]
    public void DisplayPathTrimsEverythingAboveArtifacts()
    {
        Assert.Equal(@"artifacts\metro\mks5lboot.exe",
            FirmwareArtifacts.DisplayPath(
                @"C:\Users\alguien\Programs\Aura Studio\artifacts\metro\mks5lboot.exe"));

        // Sin `artifacts` en la ruta se devuelve entera: es preferible una ruta
        // larga a un mensaje que no dice de qué archivo habla.
        Assert.Equal(@"C:\otro\sitio\x.bin", FirmwareArtifacts.DisplayPath(@"C:\otro\sitio\x.bin"));
    }

    public static TheoryData<FirmwareFamily> SisterFamilies =>
        new() { FirmwareFamily.Metro, FirmwareFamily.Moonlit };
}
