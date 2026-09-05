using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using AuraStudio.Core.Installer;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// ST-165: la tercera pata de la hora del iPod. <c>DeviceSessionService</c> (al
/// conectar) y <see cref="FirmwareSwitcher.SwitchActiveFirmware"/> (al cambiar de
/// familia) ya sembraban <c>aura.cfg</c>; esto verifica que instalar o actualizar
/// el árbol de firmware (<see cref="FirmwareTreeWriter.WriteAsync"/>, el camino
/// real que usan tanto el asistente como la actualización directa) haga lo mismo,
/// sin esperar a una reconexión posterior.
/// </summary>
public sealed class FirmwareTreeWriterTests : IDisposable
{
    private readonly string _artifactsDir =
        Path.Combine(Path.GetTempPath(), "AuraFTW-artifacts-" + Guid.NewGuid().ToString("N"));
    private readonly string _volumeRoot =
        Path.Combine(Path.GetTempPath(), "AuraFTW-volumen-" + Guid.NewGuid().ToString("N"));

    public FirmwareTreeWriterTests()
    {
        Directory.CreateDirectory(_artifactsDir);
        Directory.CreateDirectory(_volumeRoot);
    }

    public void Dispose()
    {
        try { Directory.Delete(_artifactsDir, recursive: true); } catch (IOException) { }
        try { Directory.Delete(_volumeRoot, recursive: true); } catch (IOException) { }
    }

    // MARK: - Fixtures (mismo patrón que FirmwareArtifactsTests: un juego mínimo
    // que pasa la verificación de ArtifactScope.FirmwareTree).

    private static string Sha256Of(string text)
        => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text))).ToLowerInvariant();

    private void Write(string name, string contents) => File.WriteAllText(Path.Combine(_artifactsDir, name), contents);

    private void WriteHealthyArtifacts()
    {
        Write("rockbox.ipod", "IMAGEN");

        string zipPath = Path.Combine(_artifactsDir, "rockbox.zip");
        using (var zip = ZipFile.Open(zipPath, ZipArchiveMode.Create))
        {
            void Add(string entryPath)
            {
                using var w = new StreamWriter(zip.CreateEntry(entryPath).Open());
                w.Write("x");
            }
            Add(".rockbox/rockbox.ipod");
            Add(".rockbox/rocks/viewers/mpegplayer.rock");
            Add(".rockbox/codecs/mpa.codec");
            Add(".rockbox/fonts/a26-title-20.fnt"); // centinela de FirmwareFamily.Aura
        }

        Write("bootloader-ipod6g.ipod", "BOOT");

        string zipHash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(zipPath))).ToLowerInvariant();
        Write("checksums.txt",
            $"{Sha256Of("IMAGEN")}  rockbox.ipod\n" +
            $"{zipHash}  rockbox.zip\n" +
            $"{Sha256Of("BOOT")}  bootloader-ipod6g.ipod\n");
    }

    private FirmwareArtifacts Artifacts() => FirmwareArtifacts.Load(_artifactsDir, FirmwareFamily.Aura);

    private string ConfigPath => Path.Combine(_volumeRoot, ".rockbox", "aura", "aura.cfg");

    private void SeedAuraConfig(string text)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(ConfigPath)!);
        File.WriteAllText(ConfigPath, text);
    }

    // MARK: - Casos

    [Fact]
    public async Task WritingTheTreeAlsoSeedsTheClockWhenAuraConfigAlreadyExists()
    {
        // El caso real de UpdateInPlaceAsync (macOS: "un árbol que ya arrancó
        // una vez tiene su bootloader puesto"): aura.cfg ya está ahí de un
        // arranque anterior.
        WriteHealthyArtifacts();
        SeedAuraConfig("volume: -25\n");

        await FirmwareTreeWriter.WriteAsync(_volumeRoot, Artifacts(), FirmwareFamily.Aura, installedFamily: null);

        string result = File.ReadAllText(ConfigPath);
        Assert.Contains("volume: -25", result);
        Assert.Contains("rtc_sync_year:", result);
    }

    [Fact]
    public async Task WithoutAnExistingAuraConfigNothingIsCreated()
    {
        // Instalación por primera vez, antes de cualquier arranque: no hay
        // aura.cfg todavía y no es tarea de esto crearlo a medias.
        // DeviceSessionService lo siembra en la próxima conexión, ya con el
        // firmware corrido al menos una vez.
        WriteHealthyArtifacts();

        await FirmwareTreeWriter.WriteAsync(_volumeRoot, Artifacts(), FirmwareFamily.Aura, installedFamily: null);

        Assert.False(File.Exists(ConfigPath));
    }
}
