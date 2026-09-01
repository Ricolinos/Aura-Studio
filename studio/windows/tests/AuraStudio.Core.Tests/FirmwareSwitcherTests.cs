using AuraStudio.Core;
using AuraStudio.Core.Installer;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// ST-056 / contrato v10: cambiar de familia **estaciona** el árbol saliente,
/// no lo borra. Es la promesa que el instalador le hace al usuario en pantalla
/// ("se guarda completo, con sus ajustes, y puedes volver a él"), así que estos
/// casos son lo que sostiene esa frase.
///
/// Todo contra un volumen simulado en un directorio temporal: no hace falta un
/// iPod para verificar que no se pierde nada.
/// </summary>
public class FirmwareSwitcherTests : IDisposable
{
    private readonly string _root;

    public FirmwareSwitcherTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "AuraSwitch-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ }
    }

    private void WriteFile(string relative, string contents = "x")
    {
        string path = Path.Combine(_root, relative.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, contents);
    }

    private bool Exists(string relative)
    {
        string path = Path.Combine(_root, relative.Replace('/', Path.DirectorySeparatorChar));
        return File.Exists(path) || Directory.Exists(path);
    }

    private string Read(string relative)
        => File.ReadAllText(Path.Combine(_root, relative.Replace('/', Path.DirectorySeparatorChar)));

    /// <summary>Un árbol activo con un ajuste dentro, para poder comprobar que sobrevive.</summary>
    private void GiveActiveTree(string settingValue)
    {
        WriteFile(".rockbox/rockbox.ipod", "binario-" + settingValue);
        WriteFile(".rockbox/config.cfg", settingValue);
        WriteFile(".rockbox/aura/aura.cfg", "sync_marker_supported: 1");
    }

    // MARK: - Estacionar

    [Fact]
    public void ParkingKeepsTheWholeTreeWithItsSettings()
    {
        GiveActiveTree("volumen: 30");

        FirmwareSwitcher.ParkActiveTree(FirmwareFamily.Moonlit, _root);

        Assert.False(Exists(".rockbox"));
        Assert.True(Exists(".firmware-moonlit/rockbox.ipod"));
        // Los ajustes viajan con su árbol: eso es lo que promete la interfaz.
        Assert.Equal("volumen: 30", Read(".firmware-moonlit/config.cfg"));
        Assert.True(Exists(".firmware-moonlit/aura/aura.cfg"));
    }

    [Fact]
    public void ParkingReplacesAnOlderDormantOfTheSameFamily()
    {
        // Nunca dos dormidos de la misma familia.
        WriteFile(".firmware-moonlit/viejo.txt", "anterior");
        GiveActiveTree("nuevo");

        FirmwareSwitcher.ParkActiveTree(FirmwareFamily.Moonlit, _root);

        Assert.False(Exists(".firmware-moonlit/viejo.txt"));
        Assert.Equal("nuevo", Read(".firmware-moonlit/config.cfg"));
    }

    [Fact]
    public void ParkingWithoutAnActiveTreeDoesNothing()
    {
        FirmwareSwitcher.ParkActiveTree(FirmwareFamily.Aura, _root);
        Assert.False(Exists(".firmware-aura"));
    }

    [Fact]
    public void TheUsersMusicIsNeverTouchedWhenParking()
    {
        WriteFile("Music/Artista/cancion.mp3", "audio");
        WriteFile("Photos/foto.jpg", "imagen");
        GiveActiveTree("x");

        FirmwareSwitcher.ParkActiveTree(FirmwareFamily.Metro, _root);

        Assert.Equal("audio", Read("Music/Artista/cancion.mp3"));
        Assert.Equal("imagen", Read("Photos/foto.jpg"));
    }

    // MARK: - Inventario de dormidos

    [Fact]
    public void DormantFamiliesListsOnlyWhatIsThere()
    {
        Assert.Empty(FirmwareSwitcher.DormantFamilies(_root));

        WriteFile(".firmware-metro/x", "1");
        WriteFile(".firmware-moonlit/x", "1");

        List<string> dormant = FirmwareSwitcher.DormantFamilies(_root).Select(f => f.DisplayName).ToList();
        Assert.Equal(2, dormant.Count);
        Assert.Contains("Metro", dormant);
        Assert.Contains("moonlit.aura", dormant);
        Assert.DoesNotContain("Aura", dormant);
    }

    [Fact]
    public void HasActiveTreeSeesTheActiveOne()
    {
        Assert.False(FirmwareSwitcher.HasActiveTree(_root));
        GiveActiveTree("x");
        Assert.True(FirmwareSwitcher.HasActiveTree(_root));
    }

    // MARK: - El cambio

    [Fact]
    public void SwitchingSwapsBothTreesAndKeepsEachOnesSettings()
    {
        // Activo: Aura con sus ajustes. Dormido: Metro con los suyos.
        GiveActiveTree("ajustes-de-aura");
        WriteFile(".firmware-metro/config.cfg", "ajustes-de-metro");
        WriteFile(".firmware-metro/rockbox.ipod", "binario-de-metro");

        FirmwareSwitcher.SwitchActiveFirmware(FirmwareFamily.Metro, FirmwareFamily.Aura, _root);

        // Metro pasa a ser el activo, con SUS ajustes intactos.
        Assert.Equal("ajustes-de-metro", Read(".rockbox/config.cfg"));
        // Aura queda estacionada, con LOS SUYOS.
        Assert.Equal("ajustes-de-aura", Read(".firmware-aura/config.cfg"));
        // Y ya no queda un dormido de la familia que acaba de despertar.
        Assert.False(Exists(".firmware-metro"));
    }

    [Fact]
    public void SwitchingRefreshesTheRootBinaryFromTheIncomingTree()
    {
        // El bootloader arranca /rockbox.ipod de la raíz: si no se actualiza,
        // se despierta el árbol de una familia y arranca el binario de la otra.
        GiveActiveTree("aura");
        WriteFile("rockbox.ipod", "binario-de-aura");
        WriteFile(".firmware-metro/rockbox.ipod", "binario-de-metro");
        WriteFile(".firmware-metro/config.cfg", "metro");

        FirmwareSwitcher.SwitchActiveFirmware(FirmwareFamily.Metro, FirmwareFamily.Aura, _root);

        Assert.Equal("binario-de-metro", Read("rockbox.ipod"));
    }

    [Fact]
    public void SwitchingToTheAlreadyActiveFamilyIsRefused()
    {
        GiveActiveTree("x");
        var ex = Assert.Throws<FirmwareSwitcher.SwitchException>(
            () => FirmwareSwitcher.SwitchActiveFirmware(FirmwareFamily.Aura, FirmwareFamily.Aura, _root));
        Assert.Equal(FirmwareSwitcher.SwitchFailure.AlreadyActive, ex.Failure);
    }

    [Fact]
    public void SwitchingWithoutADormantTreeIsRefused()
    {
        GiveActiveTree("x");
        var ex = Assert.Throws<FirmwareSwitcher.SwitchException>(
            () => FirmwareSwitcher.SwitchActiveFirmware(FirmwareFamily.Metro, FirmwareFamily.Aura, _root));
        Assert.Equal(FirmwareSwitcher.SwitchFailure.DormantTreeMissing, ex.Failure);
        // Y nada se movió.
        Assert.True(Exists(".rockbox/config.cfg"));
    }

    [Fact]
    public void AnUnknownFamilyCannotBeParkedOrWoken()
    {
        FirmwareFamily unknown = FirmwareFamily.Parse("una-familia-que-no-existe");
        Assert.Null(unknown.DormantTreeName);

        GiveActiveTree("x");
        Assert.Throws<FirmwareSwitcher.SwitchException>(
            () => FirmwareSwitcher.ParkActiveTree(unknown, _root));
    }

    // MARK: - Quitar un dormido

    [Fact]
    public void RemovingADormantTreeOnlyRemovesThatOne()
    {
        WriteFile(".firmware-metro/x", "1");
        WriteFile(".firmware-moonlit/x", "1");
        GiveActiveTree("x");

        FirmwareSwitcher.RemoveDormantTree(FirmwareFamily.Metro, _root);

        Assert.False(Exists(".firmware-metro"));
        Assert.True(Exists(".firmware-moonlit"));
        Assert.True(Exists(".rockbox"));
    }

    [Fact]
    public void RemovingADormantTreeThatIsNotThereIsHarmless()
    {
        FirmwareSwitcher.RemoveDormantTree(FirmwareFamily.Metro, _root);
        Assert.False(Exists(".firmware-metro"));
    }

    // MARK: - Sello de biblioteca (contrato v12)

    [Fact]
    public void TheLibraryStampIsAStableOrderedString()
    {
        string earlier = FirmwareSwitcher.MakeLibraryStamp(new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero));
        string later = FirmwareSwitcher.MakeLibraryStamp(new DateTimeOffset(2026, 8, 31, 0, 0, 0, TimeSpan.Zero));

        Assert.NotEqual(earlier, later);
        Assert.True(string.CompareOrdinal(earlier, later) < 0);
    }

    [Fact]
    public void BumpingTheStampWritesItWhereTheContractSays()
    {
        FirmwareSwitcher.BumpLibraryStamp(_root);
        Assert.True(Exists(FirmwareSwitcher.LibraryStampRelativePath));
        Assert.NotEmpty(Read(FirmwareSwitcher.LibraryStampRelativePath).Trim());
    }
}
