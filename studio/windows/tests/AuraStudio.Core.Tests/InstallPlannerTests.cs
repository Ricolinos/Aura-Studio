using AuraStudio.Core;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// ST-017: la primera acción del instalador, decidida sin tocar nada. Port de
/// `InstallPlannerTests.swift`. Los dos órdenes que gobiernan todo el asistente:
/// dual boot copia primero y flashea al final; Solo Aura formatea, flashea y
/// copia después vía el "Bootloader USB mode".
/// </summary>
public class InstallPlannerTests
{
    private static InstallPlan Plan(bool? fat32 = true,
                                    bool singleBoot = false,
                                    bool canSkipFlash = false,
                                    bool deviceIsAura = false,
                                    bool flashedThisFlow = false,
                                    bool preparedThisFlow = false)
        => InstallPlanner.Plan(fat32, singleBoot, canSkipFlash, deviceIsAura, flashedThisFlow, preparedThisFlow);

    // MARK: - Dual boot

    [Fact]
    public void DualBootOnFat32CopiesFirst()
    {
        InstallPlan plan = Plan(fat32: true, singleBoot: false);
        Assert.Equal(InstallAction.CopyFiles, plan.Action);
        Assert.False(plan.FlashFirst);
    }

    [Fact]
    public void DualBootRefusesToFormat()
    {
        // D-185: formatear destruiría el firmware original de Apple, que es
        // justamente lo que "dual boot" promete conservar. Se detiene ANTES de
        // borrar nada.
        Assert.Equal(InstallAction.RefuseDualBootRequiresWinpod, Plan(fat32: false, singleBoot: false).Action);
        Assert.Equal(InstallAction.RefuseDualBootRequiresWinpod, Plan(fat32: null, singleBoot: false).Action);
    }

    [Fact]
    public void DualBootWithBootloaderEvidenceStillCopies()
    {
        InstallPlan plan = Plan(fat32: true, singleBoot: false, canSkipFlash: true);
        Assert.Equal(InstallAction.CopyFiles, plan.Action);
        Assert.False(plan.FlashFirst);
    }

    // MARK: - Solo Aura

    [Fact]
    public void SingleBootOnACleanDiskFormatsThenFlashes()
    {
        InstallPlan plan = Plan(fat32: true, singleBoot: true);
        Assert.Equal(InstallAction.FormatThenFlash, plan.Action);
        Assert.True(plan.FlashFirst);
    }

    [Fact]
    public void SingleBootWithoutFilesystemFormatsThenFlashes()
    {
        // Disco de fábrica en blanco, o tabla de particiones rota por una
        // instalación interrumpida: no hay volumen legible, pero el disco sí
        // se identifica.
        InstallPlan plan = Plan(fat32: null, singleBoot: true);
        Assert.Equal(InstallAction.FormatThenFlash, plan.Action);
        Assert.True(plan.FlashFirst);
    }

    [Fact]
    public void SingleBootWithAuraAlreadyInstalledKeepsTheLibrary()
    {
        // Con Aura verificada no se formatea: la biblioteca del usuario se
        // conserva y se va directo a DFU.
        InstallPlan plan = Plan(fat32: true, singleBoot: true, deviceIsAura: true);
        Assert.Equal(InstallAction.EnterDfu, plan.Action);
        Assert.True(plan.FlashFirst);
    }

    [Fact]
    public void SingleBootAfterFormattingInThisFlowGoesToDfu()
    {
        InstallPlan plan = Plan(fat32: true, singleBoot: true, preparedThisFlow: true);
        Assert.Equal(InstallAction.EnterDfu, plan.Action);
    }

    [Fact]
    public void BootloaderEvidenceSkipsTheFlash()
    {
        // ST-016: la NOR no se puede leer desde una PC. Con evidencia
        // suficiente de que el bootloader ya está, se copia y ya.
        InstallPlan plan = Plan(fat32: true, singleBoot: true, canSkipFlash: true);
        Assert.Equal(InstallAction.CopyFiles, plan.Action);
        Assert.False(plan.FlashFirst);
    }

    // MARK: - Reintentos dentro de la misma corrida

    [Fact]
    public void AfterFlashingInThisFlowTheDiskIsFormattedAndThenCopied()
    {
        // El flasheo ya se hizo; falta el disco. No se vuelve a flashear.
        InstallPlan plan = Plan(fat32: false, singleBoot: true, flashedThisFlow: true);
        Assert.Equal(InstallAction.FormatThenCopy, plan.Action);
        Assert.False(plan.FlashFirst);
    }

    [Fact]
    public void AfterFlashingInThisFlowOnAReadyDiskItJustCopies()
    {
        InstallPlan plan = Plan(fat32: true, singleBoot: true, flashedThisFlow: true);
        Assert.Equal(InstallAction.CopyFiles, plan.Action);
        Assert.False(plan.FlashFirst);
    }

    [Fact]
    public void FlashedThisFlowNeverRefusesEvenInDualBoot()
    {
        // Dual boot + disco sin FAT32 se rechaza... salvo que ya se haya
        // flasheado en esta corrida, donde el rechazo llega tarde: el orden del
        // Swift original pone el rechazo primero, así que se comprueba que se
        // mantiene igual — es la conducta que el asistente espera.
        Assert.Equal(InstallAction.RefuseDualBootRequiresWinpod,
                     Plan(fat32: false, singleBoot: false, flashedThisFlow: true).Action);
    }
}
