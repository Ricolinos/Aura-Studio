using AuraStudio.Core;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Las cadenas son las que emite de verdad el `mks5lboot.exe` que trae el port
/// (leídas del binario, no inventadas). Este parser es la razón por la que el
/// instalador puede distinguir "el iPod está en DFU" de "no está".
/// </summary>
public class Mks5lbootOutputTests
{
    [Fact]
    public void ReadsTheDfuState()
    {
        Assert.Equal(2, Mks5lbootOutput.ParseDfuState("[INFO] DFU device state: 2\n"));
        Assert.Equal(10, Mks5lbootOutput.ParseDfuState("ruido antes\n[INFO] DFU device state: 10\nruido después\n"));
    }

    [Fact]
    public void LookingForTheWordDfuWouldBeWrong()
    {
        // El bug que este parser evita: cuando NO hay dispositivo, la salida
        // también contiene "DFU". Buscar la palabra daba siempre "presente".
        const string noDevice = "[INFO] mks5lboot: no DFU devices found\n";
        Assert.Contains("DFU", noDevice, StringComparison.Ordinal);
        Assert.Null(Mks5lbootOutput.ParseDfuState(noDevice));
        Assert.True(Mks5lbootOutput.ReportsNoDevice(noDevice));
    }

    [Fact]
    public void AnEmptyOrUnrelatedOutputHasNoState()
    {
        Assert.Null(Mks5lbootOutput.ParseDfuState(""));
        Assert.Null(Mks5lbootOutput.ParseDfuState("[ERR] Could not reset USB device: DeviceIoControl()\n"));
        Assert.Null(Mks5lbootOutput.ParseDfuState("DFU device state: no-es-un-numero\n"));
    }

    [Fact]
    public void TrailingTextAfterTheNumberDoesNotBreakIt()
    {
        Assert.Equal(2, Mks5lbootOutput.ParseDfuState("[INFO] DFU device state: 2 (idle)\n"));
    }

    [Fact]
    public void CrLfOutputIsParsedToo()
    {
        Assert.Equal(3, Mks5lbootOutput.ParseDfuState("[INFO] DFU device state: 3\r\n"));
    }

    [Fact]
    public void NotFoundIsDistinguishedFromUnreadable()
    {
        // Distinguirlos permite decir "falta el iPod" vs "falta el driver".
        Assert.True(Mks5lbootOutput.ReportsNoDevice("DFU device not found"));
        Assert.False(Mks5lbootOutput.ReportsNoDevice("[ERR] DFU request failed: WriteFile()"));
    }
}
