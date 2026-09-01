using AuraStudio.Core;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La frase que le dice al usuario qué firmware tiene su iPod (R3-3, ST-127).
///
/// <para>Nació de un defecto que el dueño vio comparando las dos Generales: la
/// de Windows imprimía <b>"RockboxFamily"</b> —el nombre del enum— en el
/// título, en la barra de estado y en el destino del sync. Estas pruebas
/// existen para que ningún identificador interno vuelva a llegar a pantalla, y
/// para que las combinaciones que NO son evidencia de instalación no se
/// redondeen a "instalado".</para>
/// </summary>
public sealed class DeviceFirmwareLabelTests
{
    private static IPodDiskInfo Device(
        InstalledFirmwareKind kind,
        bool hasBooted,
        RunningFirmware running,
        FirmwareFamily? declared = null,
        bool originalPresent = false) => new()
        {
            DevicePath = @"\\.\PHYSICALDRIVE2",
            VolumePath = @"E:\",
            VolumeName = "IPOD",
            Firmware = new InstalledFirmware(kind, hasBooted),
            RunningFirmware = running,
            DeclaredFamily = declared,
            OriginalFirmwarePresent = originalPresent
        };

    // MARK: - El defecto que originó todo

    [Fact]
    public void NingunaFraseImprimeElNombreInternoDeUnEnum()
    {
        RunningFirmware[] estados = [RunningFirmware.Apple, RunningFirmware.RockboxFamily, RunningFirmware.Unknown];

        foreach (InstalledFirmwareKind kind in Enum.GetValues<InstalledFirmwareKind>())
            foreach (RunningFirmware running in estados)
                foreach (bool booted in new[] { true, false })
                {
                    string label = DeviceFirmwareLabel.For(Device(kind, booted, running, FirmwareFamily.Aura));

                    Assert.DoesNotContain("RockboxFamily", label, StringComparison.Ordinal);
                    Assert.DoesNotContain("InstalledFirmwareKind", label, StringComparison.Ordinal);
                    Assert.DoesNotContain("Unknown", label, StringComparison.Ordinal);
                    Assert.NotEqual("", label);
                }
    }

    [Fact]
    public void ElNombreParaMostrarYaNoLlevaElFirmwarePegadoAtras()
    {
        IPodDiskInfo device = Device(
            InstalledFirmwareKind.Aura, hasBooted: true, RunningFirmware.RockboxFamily, FirmwareFamily.Aura);

        Assert.Equal("iPod Classic (IPOD)", device.DisplayName);
        Assert.DoesNotContain("RockboxFamily", device.DisplayName, StringComparison.Ordinal);
    }

    // MARK: - El caso normal del dueño

    [Fact]
    public void ConAuraCorriendoSeDiceQueEstaInstaladoYDesdeDondeSeConecto()
    {
        string label = DeviceFirmwareLabel.For(Device(
            InstalledFirmwareKind.Aura, hasBooted: true, RunningFirmware.RockboxFamily, FirmwareFamily.Aura));

        Assert.Equal("Firmware Aura instalado — conectado desde Aura", label);
    }

    /// <summary>
    /// ST-046: el nombre sale de lo que el firmware DECLARA. Metro-Aura escribe
    /// el mismo árbol, y llamarlo "Aura" sería mentir.
    /// </summary>
    [Fact]
    public void ElNombreSaleDeLaFamiliaDeclaradaYNoDelArbol()
    {
        string label = DeviceFirmwareLabel.For(Device(
            InstalledFirmwareKind.Aura, hasBooted: true, RunningFirmware.RockboxFamily, FirmwareFamily.Metro));

        Assert.Equal("Firmware Metro instalado — conectado desde Metro", label);
    }

    [Fact]
    public void SinFamiliaDeclaradaTodaviaNoSeArriesgaUnNombre()
    {
        // Corriendo pero sin haber escrito su configuración: no hay `aura.cfg`
        // que leer, así que se habla de la FAMILIA, no de un producto.
        string label = DeviceFirmwareLabel.For(Device(
            InstalledFirmwareKind.Aura, hasBooted: false, RunningFirmware.RockboxFamily));

        Assert.Contains("familia Aura", label, StringComparison.Ordinal);
        Assert.Contains("todavía sin escribir su configuración", label, StringComparison.Ordinal);
    }

    // MARK: - Lo que NO es evidencia de instalación

    [Fact]
    public void ArchivosSinArranqueYConAppleAtendiendoElUsbNoSonUnaInstalacion()
    {
        string label = DeviceFirmwareLabel.For(Device(
            InstalledFirmwareKind.Aura, hasBooted: false, RunningFirmware.Apple, FirmwareFamily.Aura));

        Assert.Contains("no hay evidencia de que esté instalado", label, StringComparison.Ordinal);
        Assert.DoesNotContain("instalado —", label, StringComparison.Ordinal);
    }

    [Fact]
    public void ArchivosSinArranqueYSinSaberQuienAtiendeElUsbTampoco()
    {
        string label = DeviceFirmwareLabel.For(Device(
            InstalledFirmwareKind.Aura, hasBooted: false, RunningFirmware.Unknown, FirmwareFamily.Aura));

        Assert.Contains("todavía sin arrancar", label, StringComparison.Ordinal);
        Assert.Contains("sin evidencia de que el bootloader esté instalado", label, StringComparison.Ordinal);
    }

    // MARK: - Rockbox, Apple y disco vacío

    [Fact]
    public void RockboxSeNombraYSeAclaraQueNoEsAura()
    {
        Assert.Equal("Rockbox instalado (no es Aura) — conectado desde Rockbox",
            DeviceFirmwareLabel.For(Device(InstalledFirmwareKind.Rockbox, true, RunningFirmware.RockboxFamily)));

        Assert.Equal("Rockbox instalado (no es Aura)",
            DeviceFirmwareLabel.For(Device(InstalledFirmwareKind.Rockbox, true, RunningFirmware.Unknown)));
    }

    [Fact]
    public void ElFirmwareDeAppleSeLlamaPorSuNombre() =>
        Assert.Equal("Firmware original de Apple",
            DeviceFirmwareLabel.For(Device(InstalledFirmwareKind.Stock, false, RunningFirmware.Apple)));

    /// <summary>
    /// El caso que solo se entiende sabiendo que son hechos separados: en el
    /// disco está el firmware de Apple, pero el USB lo atiende el bootloader de
    /// la familia Rockbox. Decir solo "Firmware original de Apple" escondería
    /// que hay un bootloader puesto en la NOR.
    /// </summary>
    [Fact]
    public void ElModoUsbDelBootloaderSeDiceAunqueElDiscoTengaOtraCosa()
    {
        Assert.Contains("modo USB del bootloader",
            DeviceFirmwareLabel.For(Device(InstalledFirmwareKind.Stock, false, RunningFirmware.RockboxFamily)),
            StringComparison.Ordinal);

        Assert.Contains("modo USB del bootloader",
            DeviceFirmwareLabel.For(Device(InstalledFirmwareKind.Empty, false, RunningFirmware.RockboxFamily)),
            StringComparison.Ordinal);
    }

    [Fact]
    public void ElDiscoVacioSeDiceVacio() =>
        Assert.Equal("Disco vacío, sin firmware",
            DeviceFirmwareLabel.For(Device(InstalledFirmwareKind.Empty, false, RunningFirmware.Unknown)));

    // MARK: - Dual boot

    [Fact]
    public void ElDualBootSeMencionaSoloCuandoHayEvidenciaDeLosDos()
    {
        // `iPod_Control/` presente Y evidencia de que la familia Rockbox corre.
        string dual = DeviceFirmwareLabel.For(Device(
            InstalledFirmwareKind.Aura, hasBooted: true, RunningFirmware.RockboxFamily,
            FirmwareFamily.Aura, originalPresent: true));

        Assert.EndsWith("(dual boot con Apple)", dual, StringComparison.Ordinal);

        // Sin `iPod_Control/` no hay dual boot que mencionar.
        string solo = DeviceFirmwareLabel.For(Device(
            InstalledFirmwareKind.Aura, hasBooted: true, RunningFirmware.RockboxFamily, FirmwareFamily.Aura));

        Assert.DoesNotContain("dual boot", solo, StringComparison.Ordinal);
    }
}
