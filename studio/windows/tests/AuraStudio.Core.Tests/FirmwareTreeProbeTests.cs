using AuraStudio.Core;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// ST-016: qué firmware hay EN EL DISCO, leído solo de archivos. Port de la
/// mitad de `AuraDeviceProbe.probe` que clasifica el árbol (macOS), más la
/// tabla de verdad de `IPodDiskInfo.SupportsAuraContract` — la regla que
/// habilita biblioteca, sync, temas y nombre, y que nunca puede salir de
/// archivos solos.
/// </summary>
public class FirmwareTreeProbeTests : IDisposable
{
    private readonly string _root;

    public FirmwareTreeProbeTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "FakeIPod-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ }
    }

    private void MakeDir(string relative) =>
        Directory.CreateDirectory(Path.Combine(_root, relative.Replace('/', Path.DirectorySeparatorChar)));

    private void MakeFile(string relative, string contents = "")
    {
        string full = Path.Combine(_root, relative.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        File.WriteAllText(full, contents);
    }

    // MARK: - Clasificación del árbol

    [Fact]
    public void EmptyVolumeIsEmpty()
    {
        var facts = FirmwareTreeProbe.Probe(_root);
        Assert.Equal(InstalledFirmwareKind.Empty, facts.Firmware.Kind);
        Assert.False(facts.Firmware.HasBooted);
        Assert.False(facts.OriginalFirmwarePresent);
    }

    [Fact]
    public void IPodControlAloneIsStock()
    {
        MakeDir("iPod_Control");
        var facts = FirmwareTreeProbe.Probe(_root);
        Assert.Equal(InstalledFirmwareKind.Stock, facts.Firmware.Kind);
        Assert.True(facts.OriginalFirmwarePresent);
    }

    [Fact]
    public void RockboxWithoutAuraIsPlainRockbox()
    {
        MakeDir(".rockbox");
        var facts = FirmwareTreeProbe.Probe(_root);
        Assert.Equal(InstalledFirmwareKind.Rockbox, facts.Firmware.Kind);
        Assert.False(facts.Firmware.HasBooted);
    }

    [Fact]
    public void RockboxResumeIsBootEvidence()
    {
        MakeDir(".rockbox");
        MakeFile(".rockbox/.resume.cfg");
        Assert.True(FirmwareTreeProbe.Probe(_root).Firmware.HasBooted);
    }

    [Fact]
    public void RockboxConfigIsBootEvidence()
    {
        MakeDir(".rockbox");
        MakeFile(".rockbox/config.cfg");
        Assert.True(FirmwareTreeProbe.Probe(_root).Firmware.HasBooted);
    }

    [Fact]
    public void AuraIconsMarkTheTreeEvenBeforeFirstBoot()
    {
        // El marcador que deja el instalador (D-178) existe desde la copia;
        // `.rockbox/aura/` lo crea el firmware al arrancar.
        MakeDir(".rockbox/icons/aura");
        var facts = FirmwareTreeProbe.Probe(_root);
        Assert.Equal(InstalledFirmwareKind.Aura, facts.Firmware.Kind);
        Assert.False(facts.Firmware.HasBooted);
    }

    [Fact]
    public void AuraConfigIsBootEvidence()
    {
        MakeDir(".rockbox/aura");
        MakeFile(".rockbox/aura/aura.cfg", "sync_marker_supported: 1\n");
        var facts = FirmwareTreeProbe.Probe(_root);
        Assert.Equal(InstalledFirmwareKind.Aura, facts.Firmware.Kind);
        Assert.True(facts.Firmware.HasBooted);
    }

    [Fact]
    public void FirmwareBinaryAloneIsAuraNotBooted()
    {
        MakeFile("rockbox.ipod");
        var facts = FirmwareTreeProbe.Probe(_root);
        Assert.Equal(InstalledFirmwareKind.Aura, facts.Firmware.Kind);
        Assert.False(facts.Firmware.HasBooted);
    }

    [Fact]
    public void AuraAndOriginalCoexist()
    {
        MakeDir("iPod_Control");
        MakeDir(".rockbox/aura");
        MakeFile(".rockbox/aura/aura.cfg");
        var facts = FirmwareTreeProbe.Probe(_root);
        Assert.Equal(InstalledFirmwareKind.Aura, facts.Firmware.Kind);
        Assert.True(facts.OriginalFirmwarePresent);
    }

    [Fact]
    public void EmptyPathNeverProbesTheProcessDirectory()
    {
        // D-070: una ruta vacía terminó apuntando al disco de arranque.
        Assert.Equal(FirmwareTreeFacts.None, FirmwareTreeProbe.Probe(""));
        Assert.Equal(FirmwareTreeFacts.None, FirmwareTreeProbe.Probe("   "));
    }

    [Fact]
    public void MissingDirectoryIsNone()
    {
        Assert.Equal(FirmwareTreeFacts.None,
                     FirmwareTreeProbe.Probe(Path.Combine(_root, "no-existe")));
    }

    // MARK: - SupportsAuraContract (ST-016 / ST-046)

    private static IPodDiskInfo Device(InstalledFirmwareKind kind, bool hasBooted,
                                       RunningFirmware running, FirmwareFamily? family = null) =>
        new()
        {
            VolumePath = "E:\\",
            Firmware = new InstalledFirmware(kind, hasBooted),
            RunningFirmware = running,
            DeclaredFamily = family
        };

    [Fact]
    public void CopiedFilesWithoutBootEvidenceDoNotSupportTheContract()
    {
        // Una carpeta `.rockbox` copiada a mano sobre un iPod con el firmware
        // de Apple corriendo NO es "Aura instalado" (ST-016).
        var device = Device(InstalledFirmwareKind.Aura, hasBooted: false, RunningFirmware.Apple);
        Assert.False(device.SupportsAuraContract);
        Assert.False(device.IsAuraFirmware);
    }

    [Fact]
    public void RunningOnUsbIsEnoughEvenWithoutBootTrace()
    {
        var device = Device(InstalledFirmwareKind.Aura, hasBooted: false, RunningFirmware.RockboxFamily);
        Assert.True(device.SupportsAuraContract);
        Assert.True(device.RockboxFamilyVerified);
    }

    [Fact]
    public void BootTraceIsEnoughEvenInAppleDiskMode()
    {
        var device = Device(InstalledFirmwareKind.Aura, hasBooted: true, RunningFirmware.Apple);
        Assert.True(device.SupportsAuraContract);
    }

    [Fact]
    public void PlainRockboxNeverSupportsTheContract()
    {
        var device = Device(InstalledFirmwareKind.Rockbox, hasBooted: true, RunningFirmware.RockboxFamily);
        Assert.False(device.SupportsAuraContract);
    }

    [Fact]
    public void MetroSupportsTheContractButIsNotAura()
    {
        // ST-046: capacidad ≠ identidad. Metro habla el mismo §D del contrato.
        var device = Device(InstalledFirmwareKind.Aura, hasBooted: true,
                            RunningFirmware.RockboxFamily, FirmwareFamily.Metro);
        Assert.True(device.SupportsAuraContract);
        Assert.False(device.IsAuraFirmware);
    }

    /// <summary>
    /// ST-146 / maestro §B: `SupportsAuraContract` es lo que decide si
    /// <c>DeviceSessionService</c> sincroniza la hora al conectar -- tiene que
    /// dar <c>true</c> para moonlit igual que para Metro y Aura, no solo para
    /// quien no declara familia (que es Aura por default).
    /// </summary>
    [Fact]
    public void MoonlitAlsoSupportsTheContract()
    {
        var device = Device(InstalledFirmwareKind.Aura, hasBooted: true,
                            RunningFirmware.RockboxFamily, FirmwareFamily.Moonlit);
        Assert.True(device.SupportsAuraContract);
        Assert.False(device.IsAuraFirmware);
    }

    [Fact]
    public void AuraDeclaredIsAuraFirmware()
    {
        var device = Device(InstalledFirmwareKind.Aura, hasBooted: true,
                            RunningFirmware.RockboxFamily, FirmwareFamily.Aura);
        Assert.True(device.IsAuraFirmware);
    }

    [Fact]
    public void DualBootNeedsBootEvidenceNotJustFiles()
    {
        var copied = Device(InstalledFirmwareKind.Aura, hasBooted: false, RunningFirmware.Apple)
            with { OriginalFirmwarePresent = true };
        Assert.False(copied.IsDualBoot);

        var real = Device(InstalledFirmwareKind.Aura, hasBooted: true, RunningFirmware.Apple)
            with { OriginalFirmwarePresent = true };
        Assert.True(real.IsDualBoot);
    }

    [Fact]
    public void ThemeFormatSupportedOnlyWhenTheKeyIsPublished()
    {
        var withThemes = Device(InstalledFirmwareKind.Aura, true, RunningFirmware.RockboxFamily)
            with { SupportedThemeFormat = 1 };
        var withoutThemes = Device(InstalledFirmwareKind.Aura, true, RunningFirmware.RockboxFamily);
        Assert.True(withThemes.ThemeFormatSupported);
        Assert.False(withoutThemes.ThemeFormatSupported);
    }
}
