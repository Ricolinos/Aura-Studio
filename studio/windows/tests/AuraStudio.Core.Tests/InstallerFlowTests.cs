using AuraStudio.Core.Installer;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// ST-167: qué pasos recorre el asistente según lo que venga a hacer.
///
/// <para>La primera mitad de estas pruebas <b>no describe nada nuevo</b>: fija
/// el recorrido que el instalador de Windows ya hacía, leído de sus
/// transiciones, para poder introducirle modos sin cambiarlo sin querer. Si una
/// de ellas se pone roja, lo que cambió es el flujo de instalar — y eso no es
/// parte de "Actualizar el arranque".</para>
/// </summary>
public class InstallerFlowTests
{
    // MARK: - El flujo que YA existía (ST-017, ST-050, D-222)

    [Fact]
    public void InstallingWalksTheNineStepsItAlreadyWalked()
    {
        // Copiado de las transiciones de InstallerViewModel: Begin →
        // AcknowledgePermissions → RunFormat(dryRun) → RunFormat → FlashAsync
        // → espera del "Bootloader USB mode" → CopyFiles.
        Assert.Equal(
        [
            InstallerStep.Welcome,
            InstallerStep.Permissions,
            InstallerStep.DetectDevice,
            InstallerStep.PreparingDisk,
            InstallerStep.EnterDfu,
            InstallerStep.Installing,
            InstallerStep.AwaitingBootloaderUsb,
            InstallerStep.CopyingFiles,
            InstallerStep.Done
        ], InstallerFlow.StepsFor(InstallerMode.Install));
    }

    [Fact]
    public void InstallingGoesFromWelcomeToPermissions()
    {
        Assert.Equal(InstallerStep.Permissions, InstallerFlow.AfterWelcome(InstallerMode.Install));
    }

    [Fact]
    public void InstallingFlashesWithSingleWhichDestroysApplesBootloader()
    {
        // ST-050: la instalación es siempre Solo firmware.
        Assert.True(InstallerFlow.FlashesSingle(InstallerMode.Install));
    }

    [Fact]
    public void InstallingTouchesTheDiskAndNeedsAdministrator()
    {
        Assert.True(InstallerFlow.TouchesDisk(InstallerMode.Install));
        Assert.True(InstallerFlow.NeedsPrivilegesInNormalPath(InstallerMode.Install));
    }

    [Fact]
    public void TheDirectUpdateOnlyCopiesFiles()
    {
        // D-222: con Aura ya instalado el arranque ya está en la NOR, así que
        // actualizar es reemplazar archivos. Ni bienvenida, ni permisos, ni
        // formateo, ni DFU.
        Assert.Equal(
        [
            InstallerStep.CopyingFiles,
            InstallerStep.Done
        ], InstallerFlow.StepsFor(InstallerMode.Install, automaticUpdate: true));
    }

    [Theory]
    [InlineData(InstallerStep.Welcome)]
    [InlineData(InstallerStep.Permissions)]
    [InlineData(InstallerStep.PreparingDisk)]
    [InlineData(InstallerStep.EnterDfu)]
    [InlineData(InstallerStep.Installing)]
    public void TheDirectUpdateSkipsEverythingElse(InstallerStep step)
    {
        Assert.False(InstallerFlow.Visits(InstallerMode.Install, step, automaticUpdate: true));
    }

    [Fact]
    public void NoFlowEverVisitsChooseBootMode()
    {
        // ST-050 lo dejó sin visitar y el caso se conservó para no renumerar.
        // Que siga sin visitarse es parte de "instalar es siempre Solo firmware".
        Assert.False(InstallerFlow.Visits(InstallerMode.Install, InstallerStep.ChooseBootMode));
        Assert.False(InstallerFlow.Visits(InstallerMode.Install, InstallerStep.ChooseBootMode,
                                          automaticUpdate: true));
        Assert.False(InstallerFlow.Visits(InstallerMode.UpdateBootloader, InstallerStep.ChooseBootMode));
    }

    [Fact]
    public void FailingIsNotAStepOfAnyFlow()
    {
        // Se llega desde cualquier lado: es la interrupción del camino, no un
        // tramo suyo.
        Assert.False(InstallerFlow.Visits(InstallerMode.Install, InstallerStep.Failed));
        Assert.False(InstallerFlow.Visits(InstallerMode.UpdateBootloader, InstallerStep.Failed));
    }

    // MARK: - El flujo nuevo: cuatro pasos y ninguna contraseña (ST-143)

    [Fact]
    public void UpdatingTheBootloaderIsFourStepsAndNoMore()
    {
        Assert.Equal(
        [
            InstallerStep.Welcome,
            InstallerStep.EnterDfu,
            InstallerStep.Installing,
            InstallerStep.Done
        ], InstallerFlow.StepsFor(InstallerMode.UpdateBootloader));
    }

    [Fact]
    public void UpdatingTheBootloaderGoesFromItsOwnScreenStraightToDfu()
    {
        // Saltarse Permisos no es un atajo: es que no hay nada privilegiado
        // que pedir, y la pantalla se lo promete al usuario por escrito.
        Assert.Equal(InstallerStep.EnterDfu, InstallerFlow.AfterWelcome(InstallerMode.UpdateBootloader));
    }

    [Fact]
    public void UpdatingTheBootloaderNeverAsksForAPassword()
    {
        Assert.False(InstallerFlow.NeedsPrivilegesInNormalPath(InstallerMode.UpdateBootloader));
        Assert.False(InstallerFlow.Visits(InstallerMode.UpdateBootloader, InstallerStep.Permissions));
    }

    [Fact]
    public void UpdatingTheBootloaderNeverPreparesTheDisk()
    {
        Assert.False(InstallerFlow.Visits(InstallerMode.UpdateBootloader, InstallerStep.PreparingDisk));
    }

    [Fact]
    public void UpdatingTheBootloaderNeverCopiesFiles()
    {
        Assert.False(InstallerFlow.Visits(InstallerMode.UpdateBootloader, InstallerStep.CopyingFiles));
    }

    [Fact]
    public void UpdatingTheBootloaderDoesNotTouchTheDiskAtAll()
    {
        // Las tres de arriba dicen esto mismo por partes; ésta es la promesa
        // entera, que es la que se le hace al usuario en pantalla: su música,
        // sus fotos, sus listas y sus ajustes se quedan como están.
        Assert.False(InstallerFlow.TouchesDisk(InstallerMode.UpdateBootloader));
    }

    [Fact]
    public void UpdatingTheBootloaderDoesNotWaitForBootloaderUsbMode()
    {
        // Ese paso existe porque tras instalar faltan los archivos. Acá no
        // falta nada: el iPod reinicia y ya está.
        Assert.False(InstallerFlow.Visits(InstallerMode.UpdateBootloader,
                                          InstallerStep.AwaitingBootloaderUsb));
    }

    [Fact]
    public void UpdatingTheBootloaderDoesNotFlashWithSingle()
    {
        // ST-143: --single borra el arranque de Apple, y actualizar no puede
        // destruir más de lo que ya estaba destruido.
        Assert.False(InstallerFlow.FlashesSingle(InstallerMode.UpdateBootloader));
    }

    // MARK: - Restaurar no está en Windows

    [Fact]
    public void RestoringSaysOutLoudThatItIsNotImplementedOnWindows()
    {
        // El caso existe en el enum para no renumerar (viene del Swift), pero
        // nadie lo recorre acá. Devolver una lista vacía dibujaría un asistente
        // sin pasos; fallar dice qué pasa.
        Assert.Throws<NotSupportedException>(() => InstallerFlow.StepsFor(InstallerMode.Restore));
        Assert.Throws<NotSupportedException>(() => InstallerFlow.FlashesSingle(InstallerMode.Restore));
    }
}
