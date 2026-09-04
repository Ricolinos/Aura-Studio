using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Los mismos casos, con los mismos números, que
/// <c>Tests/AuraStudioTests/SquareCropPlanTests.swift</c> en macOS. Si una de
/// las dos plataformas cambia de criterio, esta pareja de archivos es donde se
/// nota.
/// </summary>
public class SquareCropPlanTests
{
    [Fact]
    public void ASquareSourceIsNotCroppedAtAll()
    {
        var plan = SquareCropPlan.For(500, 500, 320);
        Assert.Equal(0, plan.CropX);
        Assert.Equal(0, plan.CropY);
        Assert.Equal(500, plan.CropSide);
        Assert.Equal(320, plan.OutputSide);
        Assert.False(plan.NeedsCrop);   // no hay nada que tirar
        Assert.True(plan.NeedsResize);  // pero sí que reducir
    }

    [Fact]
    public void AFourThreeCoverLosesTheSidesInEqualHalves()
    {
        var plan = SquareCropPlan.For(1600, 1200, 320);
        Assert.Equal(200, plan.CropX);   // (1600-1200)/2
        Assert.Equal(0, plan.CropY);
        Assert.Equal(1200, plan.CropSide);
        Assert.Equal(320, plan.OutputSide);
        Assert.True(plan.NeedsCrop);
    }

    [Fact]
    public void ASixteenNineCoverLosesMuchMoreOfTheSides()
    {
        var plan = SquareCropPlan.For(1920, 1080, 320);
        Assert.Equal(420, plan.CropX);   // (1920-1080)/2
        Assert.Equal(0, plan.CropY);
        Assert.Equal(1080, plan.CropSide);
        Assert.Equal(320, plan.OutputSide);
    }

    [Fact]
    public void AVeryTallSourceIsCroppedTopAndBottom()
    {
        // 1:4 — el recorte va por arriba y por abajo, no por los lados.
        var plan = SquareCropPlan.For(200, 800, 128);
        Assert.Equal(0, plan.CropX);
        Assert.Equal(300, plan.CropY);   // (800-200)/2
        Assert.Equal(200, plan.CropSide);
        Assert.Equal(128, plan.OutputSide);
    }

    [Fact]
    public void TheLeftoverPixelIsAlwaysDiscardedFromTheRight()
    {
        // 401 de ancho: sobran 101 columnas, 50 a la izquierda y 51 a la
        // derecha. Determinista a propósito — las dos plataformas tienen que
        // recortar exactamente el mismo píxel.
        var plan = SquareCropPlan.For(401, 300, 1000);
        Assert.Equal(50, plan.CropX);
        Assert.Equal(300, plan.CropSide);
        Assert.Equal(51, plan.SourceWidth - (plan.CropX + plan.CropSide));
    }

    [Fact]
    public void TheLeftoverPixelIsAlwaysDiscardedFromTheBottom()
    {
        var plan = SquareCropPlan.For(300, 401, 1000);
        Assert.Equal(50, plan.CropY);
        Assert.Equal(300, plan.CropSide);
        Assert.Equal(51, plan.SourceHeight - (plan.CropY + plan.CropSide));
    }

    [Fact]
    public void ASourceSmallerThanAskedIsNeverBlownUp()
    {
        // Agrandarla solo agrega peso y se ve peor — el mismo criterio que
        // ImageResizePlan.TargetSize.
        var plan = SquareCropPlan.For(200, 200, 320);
        Assert.Equal(200, plan.OutputSide);
        Assert.False(plan.NeedsResize);
        Assert.False(plan.NeedsCrop);
    }

    [Fact]
    public void TheSmallestPossibleImageStillGivesAValidPlan()
    {
        var plan = SquareCropPlan.For(1, 1, 320);
        Assert.Equal(1, plan.CropSide);
        Assert.Equal(1, plan.OutputSide);
        Assert.False(plan.IsEmpty);
        Assert.False(plan.NeedsCrop);
        Assert.False(plan.NeedsResize);
    }

    [Fact]
    public void TheCanonicalSidesOfTheContract()
    {
        // v18: cover.jpg 320x320 y artists/*.jpg 128x128 desde una copia local
        // cuadrada de 1000 — sobre una fuente ya cuadrada el plan es solo un
        // reescalado.
        var cover = SquareCropPlan.For(1000, 1000, 320);
        Assert.Equal(320, cover.OutputSide);
        Assert.False(cover.NeedsCrop);
        Assert.True(cover.NeedsResize);

        Assert.Equal(128, SquareCropPlan.For(1000, 1000, 128).OutputSide);
    }

    [Theory]
    [InlineData(0, 100, 320)]
    [InlineData(100, 0, 320)]
    [InlineData(-5, 100, 320)]
    [InlineData(100, 100, 0)]
    public void ADegenerateSizeGivesNothingInsteadOfGarbage(int width, int height, int maxSide)
    {
        var plan = SquareCropPlan.For(width, height, maxSide);
        Assert.True(plan.IsEmpty);
        Assert.Equal(SquareCropPlan.Empty, plan);
        Assert.False(plan.NeedsCrop);
        Assert.False(plan.NeedsResize);
    }
}
