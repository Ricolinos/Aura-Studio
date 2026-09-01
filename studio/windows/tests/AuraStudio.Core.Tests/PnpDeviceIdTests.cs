using AuraStudio.Core;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Parser de los IDs Plug&amp;Play de Windows que identifican los discos USB.
/// Estas cadenas son la lectura real de qué firmware atiende el USB (ST-016):
/// el INQUIRY SCSI dice "Apple"/"iPod" en modo disco de Apple y
/// "Rockbox"/"media player" cuando corre Rockbox/Aura.
/// </summary>
public class PnpDeviceIdTests
{
    [Fact]
    public void AppleDiskModeUsbStorageId_ParsesVendorProductSerial()
    {
        bool ok = PnpDeviceId.TryParseUsbStorageId(
            @"USBSTOR\Disk&Ven_Apple&Prod_iPod&Rev_2.70\000A270013923F13&0",
            out var id);

        Assert.True(ok);
        Assert.Equal("Apple", id.Vendor);
        Assert.Equal("iPod", id.Product);
        Assert.Equal("000A270013923F13", id.Serial);
    }

    [Fact]
    public void RockboxUsbStorageId_ParsesVendorProduct()
    {
        bool ok = PnpDeviceId.TryParseUsbStorageId(
            @"USBSTOR\Disk&Ven_Rockbox&Prod_media_player&Rev_0.01\000A270013923F13&0",
            out var id);

        Assert.True(ok);
        Assert.Equal("Rockbox", id.Vendor);
        Assert.Equal("media player", id.Product); // '_' → espacio
        Assert.Equal("000A270013923F13", id.Serial);
    }

    [Fact]
    public void UsbStorageId_WithoutSerial_ReturnsNullSerial()
    {
        bool ok = PnpDeviceId.TryParseUsbStorageId(
            @"USBSTOR\Disk&Ven_Apple&Prod_iPod&Rev_2.70",
            out var id);

        Assert.True(ok);
        Assert.Equal("Apple", id.Vendor);
        Assert.Equal("iPod", id.Product);
        Assert.Null(id.Serial);
    }

    [Fact]
    public void UsbStorageId_DecodesUnderscoresToSpaces()
    {
        bool ok = PnpDeviceId.TryParseUsbStorageId(
            @"USBSTOR\Disk&Ven_Kingston&Prod_DataTraveler_3.0&Rev_1.00\SERIAL&0",
            out var id);

        Assert.True(ok);
        Assert.Equal("DataTraveler 3.0", id.Product);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData(@"SCSI\Disk&Ven_Apple&Prod_iPod\123")]   // no es USBSTOR
    [InlineData(@"USBSTOR\Disk")]                         // falta Ven_/Prod_
    [InlineData(@"USBSTOR")]                              // sin segmentos
    public void MalformedUsbStorageId_ReturnsFalse(string? input)
    {
        Assert.False(PnpDeviceId.TryParseUsbStorageId(input, out _));
    }

    [Fact]
    public void AppleIPodUsbDeviceId_ParsesVidPidSerial()
    {
        bool ok = PnpDeviceId.TryParseUsbDeviceId(
            @"USB\VID_05AC&PID_1261\000A270013923F13",
            out int vid, out int pid, out string? serial);

        Assert.True(ok);
        Assert.Equal(0x05AC, vid);
        Assert.Equal(0x1261, pid);
        Assert.Equal("000A270013923F13", serial);
    }

    [Fact]
    public void UsbDeviceId_IsCaseInsensitiveOnVidPid()
    {
        bool ok = PnpDeviceId.TryParseUsbDeviceId(
            @"USB\vid_05ac&pid_1261\ABC",
            out int vid, out int pid, out _);

        Assert.True(ok);
        Assert.Equal(0x05AC, vid);
        Assert.Equal(0x1261, pid);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData(@"HID\VID_05AC&PID_1261\ABC")]   // no es nodo USB
    [InlineData(@"USB\VID_05AC\ABC")]            // falta PID
    [InlineData(@"USB\VID_ZZZZ&PID_1261\ABC")]   // VID no hexadecimal
    public void MalformedUsbDeviceId_ReturnsFalse(string? input)
    {
        Assert.False(PnpDeviceId.TryParseUsbDeviceId(input, out _, out _, out _));
    }

    [Fact]
    public void UsbDeviceId_WithoutSerial_ReturnsNullSerial()
    {
        bool ok = PnpDeviceId.TryParseUsbDeviceId(
            @"USB\VID_05AC&PID_1261",
            out _, out _, out string? serial);

        Assert.True(ok);
        Assert.Null(serial);
    }
}
