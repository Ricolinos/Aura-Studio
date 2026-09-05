using AuraStudio.Core;
using AuraStudio.Core.Installer;
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

    // MARK: - La ayuda de último recurso en la pantalla de DFU (ST-169)

    [Fact]
    public void BeforeTheDelayTheHelpDoesNotExist()
    {
        // El caso normal tiene que seguir siendo de cero permisos: la ayuda no
        // puede estar desde el principio.
        Assert.False(BootloaderUpdate.ShouldOfferServicePause(
            InstallerMode.UpdateBootloader, secondsWaiting: 19,
            isDfuDetected: false, alreadyPaused: false));
    }

    [Fact]
    public void AtTwentySecondsItIsOffered()
    {
        Assert.True(BootloaderUpdate.ShouldOfferServicePause(
            InstallerMode.UpdateBootloader, secondsWaiting: 20,
            isDfuDetected: false, alreadyPaused: false));
    }

    [Fact]
    public void TwelveSecondsIsStillTheUserHoldingTheButtons()
    {
        // La combinación tarda doce: ofrecer antes sería interrumpir a alguien
        // que está haciendo bien las cosas.
        Assert.Equal(20, BootloaderUpdate.AssistDelaySeconds);
        Assert.False(BootloaderUpdate.ShouldOfferServicePause(
            InstallerMode.UpdateBootloader, secondsWaiting: 12,
            isDfuDetected: false, alreadyPaused: false));
    }

    [Fact]
    public void WithTheIPodAlreadyDetectedThereIsNothingToHelpWith()
    {
        Assert.False(BootloaderUpdate.ShouldOfferServicePause(
            InstallerMode.UpdateBootloader, secondsWaiting: 60,
            isDfuDetected: true, alreadyPaused: false));
    }

    [Fact]
    public void HavingPausedAlreadyItIsNotOfferedAgain()
    {
        // Ya se pidió permiso una vez y no alcanzó: volver a ofrecer lo mismo
        // no arregla nada y pide otro permiso.
        Assert.False(BootloaderUpdate.ShouldOfferServicePause(
            InstallerMode.UpdateBootloader, secondsWaiting: 60,
            isDfuDetected: false, alreadyPaused: true));
    }

    [Fact]
    public void TheFullInstallerNeverOffersItHere()
    {
        // Ese flujo ya lo propone antes de llegar al DFU; pedir permiso dos
        // veces por lo mismo es peor que no ofrecerlo.
        Assert.False(BootloaderUpdate.ShouldOfferServicePause(
            InstallerMode.Install, secondsWaiting: 60,
            isDfuDetected: false, alreadyPaused: false));
    }

    [Fact]
    public void RestoringNeverOffersItEither()
    {
        Assert.False(BootloaderUpdate.ShouldOfferServicePause(
            InstallerMode.Restore, secondsWaiting: 60,
            isDfuDetected: false, alreadyPaused: false));
    }
}
