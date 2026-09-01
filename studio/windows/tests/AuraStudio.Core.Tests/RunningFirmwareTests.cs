using AuraStudio.Core;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Qué firmware atiende el USB (ST-016) — el hecho del que cuelgan biblioteca,
/// sincronización, temas y nombre del iPod.
///
/// <para>Las cadenas de acá <b>no son inventadas</b>: salen del iPod real del
/// dueño, con su adaptador iFlash, leído el 2026-09-01 (R3-1). Es la diferencia
/// que costó el "no me deja sincronizar": el aparato reporta por el bus
/// "Rockbox media player", mientras que las cadenas SCSI del disco reportan el
/// adaptador.</para>
/// </summary>
public sealed class RunningFirmwareTests
{
    [Theory]
    // Lo que reporta el nodo USB del iPod del dueño con Aura corriendo.
    [InlineData("Apple", "Rockbox media player")]
    // Y lo que reporta Rockbox de fábrica, con su propio fabricante.
    [InlineData("Rockbox.org", "Rockbox media player")]
    // Sin fabricante legible sigue alcanzando con el producto.
    [InlineData("", "Rockbox media player")]
    public void UnFirmwareDeLaFamiliaRockboxSeReconocePorLoQueReportaElAparato(
        string vendor, string product) =>
        Assert.Equal(RunningFirmware.RockboxFamily, RunningFirmware.Classify(vendor, product));

    [Theory]
    [InlineData("Apple Inc.", "iPod")]
    [InlineData("Apple", "iPod")]
    [InlineData("", "iPod")]
    public void ElModoDiscoDeAppleSeReconocePorSuProducto(string vendor, string product) =>
        Assert.Equal(RunningFirmware.Apple, RunningFirmware.Classify(vendor, product));

    /// <summary>
    /// <b>El caso que originó R3-1.</b> Con un adaptador iFlash, las cadenas
    /// SCSI del disco describen el ADAPTADOR: "iFlash-P" / "latform iPod Ada"
    /// (el nombre viene partido por los 8 y 16 caracteres del formato SCSI).
    /// Contienen "ipod", así que invitan a concluir "modo disco de Apple" —
    /// justo lo que no hay que hacer.
    ///
    /// <para>La clasificación correcta de esas cadenas es <b>desconocido</b>: no
    /// dicen qué firmware corre. Y por eso la fuente ya no son ellas, sino lo
    /// que el aparato reporta por el bus.</para>
    /// </summary>
    [Fact]
    public void LasCadenasSCSIDeUnAdaptadorIFlashNoSonEvidenciaDeNada() =>
        Assert.Equal(RunningFirmware.Unknown, RunningFirmware.Classify("iFlash-P", "latform iPod Ada"));

    [Theory]
    [InlineData("", "")]
    [InlineData("Generic", "USB Mass Storage Device")]   // el nodo de interfaz, que no dice nada
    [InlineData("SanDisk", "Cruzer")]
    public void LoQueNoEsNingunaDeLasDosEsDesconocidoYNoSeAdivina(string vendor, string product) =>
        Assert.Equal(RunningFirmware.Unknown, RunningFirmware.Classify(vendor, product));

    /// <summary>
    /// La identidad USB clasifica con lo que ella misma trae, y el par VID/PID
    /// sigue identificando al aparato aunque el firmware sea otro: son dos
    /// hechos distintos y ninguno reemplaza al otro.
    /// </summary>
    [Fact]
    public void LaIdentidadUSBSeparaQuienEsElAparatoDeQueFirmwareCorre()
    {
        var conAura = new USBDeviceIdentity("Apple", "Rockbox media player", "91000E593", 0x05AC, 0x1261);

        Assert.True(conAura.IsIPodClassicUSB);
        Assert.Equal(RunningFirmware.RockboxFamily, conAura.RunningFirmware);

        var conApple = new USBDeviceIdentity("Apple Inc.", "iPod", "91000E593", 0x05AC, 0x1261);

        Assert.True(conApple.IsIPodClassicUSB);
        Assert.Equal(RunningFirmware.Apple, conApple.RunningFirmware);
    }
}
