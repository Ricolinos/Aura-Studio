using AuraStudio.Core;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// ST-143: cuándo se ofrece "Actualizar el arranque". Los mismos casos que
/// <c>BootloaderUpdateTests</c> en macOS.
/// </summary>
public class BootloaderUpdateTests
{
    [Fact]
    public void ADifferentBootloaderIsOffered()
    {
        Assert.True(BootloaderUpdate.IsAvailable("viejo", "nuevo", hasOurFirmware: true));
        Assert.Equal(BootloaderUpdate.Reason.DifferentBootloader,
                     BootloaderUpdate.ReasonFor("viejo", "nuevo", hasOurFirmware: true));
    }

    [Fact]
    public void TheSameBootloaderIsNotOffered()
    {
        Assert.False(BootloaderUpdate.IsAvailable("igual", "igual", hasOurFirmware: true));
        Assert.Null(BootloaderUpdate.ReasonFor("igual", "igual", hasOurFirmware: true));
    }

    [Fact]
    public void AnUnknownRecordIsOfferedAsUnknown()
    {
        Assert.Equal(BootloaderUpdate.Reason.UnknownBootloader,
                     BootloaderUpdate.ReasonFor(BootloaderUpdate.UnknownBootloader, "nuevo", hasOurFirmware: true));
    }

    [Fact]
    public void ADiskWeNeverVerifiedIsAlsoUnknown()
    {
        // Lo instaló otra computadora: hay firmware nuestro en el disco, pero
        // esta instalación nunca grabó ese arranque.
        Assert.Equal(BootloaderUpdate.Reason.UnknownBootloader,
                     BootloaderUpdate.ReasonFor(null, "nuevo", hasOurFirmware: true));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("viejo")]
    public void WithoutOurFirmwareNothingIsOffered(string? recorded)
    {
        // Un iPod de fábrica: lo que corresponde es instalar, no "actualizar
        // el arranque".
        Assert.False(BootloaderUpdate.IsAvailable(recorded, "nuevo", hasOurFirmware: false));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    public void WithoutAnEmbeddedBootloaderNothingIsOffered(string? embedded)
    {
        // Una build sin artefactos: no hay con qué comparar, y ofrecer
        // flashear algo que no existe sería peor que no ofrecer.
        Assert.False(BootloaderUpdate.IsAvailable("viejo", embedded, hasOurFirmware: true));
    }
}
