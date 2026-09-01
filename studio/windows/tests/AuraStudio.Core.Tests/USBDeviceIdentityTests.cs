using AuraStudio.Core;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// ST-016: la única lectura real de "qué firmware corre" es lo que el propio
/// firmware anuncia por USB. Estos tests fijan la clasificación contra los
/// descriptores reales (iPod del dueño en modo disco de Apple y los de
/// Rockbox).
/// </summary>
public class USBDeviceIdentityTests
{
    [Fact]
    public void AppleDiskMode_IsClassifiedAsApple()
    {
        Assert.Equal(RunningFirmware.Apple, RunningFirmware.Classify("Apple Inc.", "iPod"));
    }

    [Fact]
    public void RockboxDescriptors_AreClassifiedAsRockboxFamily()
    {
        Assert.Equal(RunningFirmware.RockboxFamily, RunningFirmware.Classify("Rockbox.org", "Rockbox media player"));
        // Basta con que una de las dos cadenas lo diga.
        Assert.Equal(RunningFirmware.RockboxFamily, RunningFirmware.Classify("", "Rockbox media player"));
    }

    [Fact]
    public void AnythingElse_IsUnknownNeverGuessed()
    {
        Assert.Equal(RunningFirmware.Unknown, RunningFirmware.Classify("", ""));
        Assert.Equal(RunningFirmware.Unknown, RunningFirmware.Classify("Apple Inc.", "iPad"));
        Assert.Equal(RunningFirmware.Unknown, RunningFirmware.Classify("Ugreen", "USB3 Hub"));
    }

    [Fact]
    public void IPodClassicVIDPID_IsRecognised()
    {
        var ipod = new USBDeviceIdentity("Apple Inc.", "iPod", "000A270013923F13", 0x05AC, 0x1261);
        Assert.True(ipod.IsIPodClassicUSB);
        Assert.Equal(RunningFirmware.Apple, ipod.RunningFirmware);
    }

    /// Un iPad también es 0x05AC — el PID es lo que decide.
    [Fact]
    public void OtherAppleDevices_AreNotIPodClassic()
    {
        var ipad = new USBDeviceIdentity("Apple Inc.", "iPad", null, 0x05AC, 0x12AB);
        Assert.False(ipad.IsIPodClassicUSB);
    }

    [Fact]
    public void RockboxKeepsAppleVIDPID_SoIdentityStillMatches()
    {
        var running = new USBDeviceIdentity("Rockbox.org", "Rockbox media player", null, 0x05AC, 0x1261);
        Assert.True(running.IsIPodClassicUSB);
        Assert.Equal(RunningFirmware.RockboxFamily, running.RunningFirmware);
    }
}
