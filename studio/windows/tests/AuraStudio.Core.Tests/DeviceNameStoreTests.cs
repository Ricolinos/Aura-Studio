using System.Text;
using AuraStudio.Core;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El nombre del iPod (<c>CONTRATO-dispositivo.md</c> v2). Dos cosas importan
/// más que el resto: que el nombre <b>sobreviva al firmware</b> —que reescribe
/// <c>aura.cfg</c> entero, por eso esto vive en su propio archivo— y que
/// <b>solo la instalación que lo nombró</b> lo pueda cambiar.
/// </summary>
public sealed class DeviceNameStoreTests : IDisposable
{
    private readonly string _volume = Path.Combine(Path.GetTempPath(), "aura-dev-" + Guid.NewGuid().ToString("N"));

    private const string Mac = "0A1B2C3D-4E5F-4A6B-8C7D-9E0F1A2B3C4D";
    private const string Windows = "8B1F0C4E-0000-4000-8000-000000000001";

    public DeviceNameStoreTests() => Directory.CreateDirectory(_volume);

    public void Dispose()
    {
        try { Directory.Delete(_volume, recursive: true); } catch (IOException) { }
    }

    private string ConfigPath => Path.Combine(_volume, ".rockbox", "aura", "device.cfg");

    private void WriteRaw(string text)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(ConfigPath)!);
        File.WriteAllText(ConfigPath, text);
    }

    // MARK: - Nombrar

    [Fact]
    public void AnUnnamedIPodGetsItsNameAndItsOwner()
    {
        DeviceConfig config = DeviceNameStore.Save(_volume, "iPod de Ricardo", Windows);

        Assert.Equal("iPod de Ricardo", config.Name);
        Assert.Equal(Windows, config.Owner);
        Assert.Equal(2, config.ContractVersion);
        Assert.NotNull(config.DeviceId);
        Assert.Equal("iPod de Ricardo", DeviceNameStore.Read(_volume).Name);
    }

    [Fact]
    public void TheIdSurvivesARename()
    {
        string? first = DeviceNameStore.Save(_volume, "Uno", Windows).DeviceId;

        Assert.Equal(first, DeviceNameStore.Save(_volume, "Dos", Windows).DeviceId);
    }

    [Fact]
    public void NamingOnlyHappensIfItHasNoNameYet()
    {
        DeviceNameStore.Save(_volume, "El que puso el usuario", Windows);
        DeviceNameStore.EnsureNamed(_volume, "iPod de alguien", Windows);

        Assert.Equal("El que puso el usuario", DeviceNameStore.Read(_volume).Name);
    }

    // MARK: - Propiedad del nombre (§C bis)

    [Fact]
    public void AnotherInstallationCannotRenameIt()
    {
        DeviceNameStore.Save(_volume, "iPod de la Mac", Mac);

        DeviceConfig result = DeviceNameStore.Save(_volume, "iPod de Windows", Windows);

        Assert.Equal("iPod de la Mac", result.Name);
        Assert.Equal(Mac, result.Owner);
        Assert.Equal("iPod de la Mac", DeviceNameStore.Read(_volume).Name);
    }

    [Fact]
    public void AnotherInstallationSeesTheNameAndTheExplanation()
    {
        DeviceNameStore.Save(_volume, "iPod de la Mac", Mac);
        DeviceConfig config = DeviceNameStore.Read(_volume);

        Assert.Equal("iPod de la Mac", config.Name);
        Assert.False(DeviceNameStore.CanEdit(config, Windows));
        Assert.True(DeviceNameStore.CanEdit(config, Mac));
        Assert.Contains("otra computadora", DeviceNameStore.NotOwnerExplanation);
    }

    [Fact]
    public void AV1FileIsClaimedOnTheNextSaveAndNotBefore()
    {
        // Nunca se reescribe el archivo solo para reclamarlo: solo cuando de
        // todas formas se iba a guardar.
        WriteRaw("device_id: 6F2C1B4A\ndevice_name: iPod viejo\n");

        DeviceConfig before = DeviceNameStore.Read(_volume);
        Assert.Null(before.Owner);
        Assert.Equal(1, before.ContractVersion);
        Assert.True(DeviceNameStore.CanEdit(before, Windows));

        DeviceConfig after = DeviceNameStore.Save(_volume, "iPod nuevo", Windows);

        Assert.Equal(Windows, after.Owner);
        Assert.Equal(2, after.ContractVersion);
        Assert.Equal("6F2C1B4A", after.DeviceId);
    }

    // MARK: - Formato

    [Fact]
    public void TheFileHasTheFiveKeysOfTheContract()
    {
        DeviceNameStore.Save(_volume, "iPod de Ricardo", Windows);
        string text = File.ReadAllText(ConfigPath);

        Assert.Contains("contract_version: 2\n", text);
        Assert.Contains("device_name: iPod de Ricardo\n", text);
        Assert.Contains($"device_owner: {Windows}\n", text);
        Assert.Contains("device_id: ", text);
        Assert.Contains("device_name_updated_at: ", text);
    }

    [Fact]
    public void EveryLineFitsInTheFirmwareBuffer()
    {
        // El lector de .cfg del firmware corta en 63 bytes: una línea más larga
        // llegaría truncada del otro lado.
        DeviceNameStore.Save(_volume, new string('á', 40), Windows);

        foreach (string line in File.ReadAllText(ConfigPath).Split('\n'))
            Assert.True(Encoding.UTF8.GetByteCount(line) <= 63, line);
    }

    [Fact]
    public void UnknownKeysAreIgnoredInsteadOfBreakingTheFile()
    {
        WriteRaw("contract_version: 2\ndevice_name: iPod\nclave_del_futuro: algo\n");

        Assert.Equal("iPod", DeviceNameStore.Read(_volume).Name);
    }

    [Fact]
    public void NoFileIsNotAnError()
    {
        Assert.Null(DeviceNameStore.Read(_volume).Name);
        Assert.True(DeviceNameStore.CanEdit(DeviceNameStore.Read(_volume), Windows));
    }

    // MARK: - Validación del nombre (§C)

    [Theory]
    [InlineData("  iPod de Ricardo  ", "iPod de Ricardo")]
    [InlineData("iPod    de   Ricardo", "iPod de Ricardo")]
    public void TheNameIsAlwaysOneCleanLine(string input, string expected)
    {
        Assert.Equal(expected, DeviceNameStore.SanitizeName(input));
    }

    [Fact]
    public void AControlCharacterIsDroppedNotTurnedIntoASpace()
    {
        // Mismo criterio que la app de macOS y que el saneo del firmware: los
        // caracteres de control se descartan enteros. Un tabulador entre
        // palabras las pega, y está bien — el nombre es siempre una sola línea.
        Assert.Equal("iPoddeRicardo", DeviceNameStore.SanitizeName("iPod\tde\nRicardo"));
    }

    [Fact]
    public void EmojiAreDroppedBecauseTheIPodHasNoGlyphForThem()
    {
        // Recortarlos dejaría cajas vacías en pantalla.
        Assert.Equal("iPod de Ricardo", DeviceNameStore.SanitizeName("iPod 🎵 de Ricardo 🎧"));
    }

    [Fact]
    public void AccentsCountDoubleAgainstTheByteLimit()
    {
        string name = DeviceNameStore.SanitizeName(new string('ñ', 40));

        Assert.Equal(24, name.Length);
        Assert.Equal(48, Encoding.UTF8.GetByteCount(name));
    }

    [Fact]
    public void ALongNameIsCutAtThirtyTwoCharacters()
    {
        Assert.Equal(32, DeviceNameStore.SanitizeName(new string('a', 60)).Length);
    }

    [Fact]
    public void CuttingNeverLeavesATrailingSpace()
    {
        Assert.Equal("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            DeviceNameStore.SanitizeName(new string('a', 31) + " y más"));
    }

    [Fact]
    public void ANameThatIsOnlyNoiseDoesNotEraseTheOneThatWasThere()
    {
        // El usuario escribió algo que el iPod no puede mostrar; no pidió
        // quitarle el nombre.
        DeviceNameStore.Save(_volume, "iPod de Ricardo", Windows);

        Assert.Equal("iPod de Ricardo", DeviceNameStore.Save(_volume, "   🎵   ", Windows).Name);
    }
}
