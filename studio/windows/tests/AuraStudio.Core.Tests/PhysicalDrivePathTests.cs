using AuraStudio.Core;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Ese número es lo que recibe la operación privilegiada de formateo: si se
/// parsea mal, se formatea otro disco.
/// </summary>
public class PhysicalDrivePathTests
{
    [Theory]
    [InlineData(@"\\.\PHYSICALDRIVE0", 0)]
    [InlineData(@"\\.\PhysicalDrive2", 2)]
    [InlineData(@"\\.\physicaldrive11", 11)]
    [InlineData(@"  \\.\PHYSICALDRIVE7  ", 7)]
    public void ReadsTheNumber(string path, int expected)
    {
        Assert.True(PhysicalDrivePath.TryGetNumber(path, out int number));
        Assert.Equal(expected, number);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData(@"\\.\PHYSICALDRIVE")]          // sin número
    [InlineData(@"\\.\PHYSICALDRIVE2a")]        // basura pegada
    [InlineData(@"\\.\PHYSICALDRIVE-1")]        // negativo
    [InlineData(@"\\.\PHYSICALDRIVE 2")]        // espacio en medio
    [InlineData(@"E:\")]                        // no es una ruta de disco
    [InlineData("/dev/disk2")]                  // la forma de macOS
    [InlineData(@"\\.\CdRom0")]
    public void AnythingElseIsRejected(string? path)
    {
        // Nunca se adivina un número a partir de una ruta que no se entiende.
        Assert.False(PhysicalDrivePath.TryGetNumber(path, out int number));
        Assert.Equal(-1, number);
    }

    [Fact]
    public void AnAbsurdNumberIsRejected()
    {
        Assert.False(PhysicalDrivePath.TryGetNumber(@"\\.\PHYSICALDRIVE100", out _));
        Assert.False(PhysicalDrivePath.TryGetNumber(@"\\.\PHYSICALDRIVE999999999999", out _));
    }
}
