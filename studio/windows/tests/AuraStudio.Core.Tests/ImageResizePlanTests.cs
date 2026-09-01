using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

public class ImageResizePlanTests
{
    [Fact]
    public void ALandscapePhotoFitsItsLongSideAndKeepsTheAspect()
    {
        (int w, int h) = ImageResizePlan.TargetSize(1600, 1200, 320);
        Assert.Equal(320, w);
        Assert.Equal(240, h);   // 4:3 intacto, la resolución del LCD
    }

    [Fact]
    public void APortraitPhotoFitsItsLongSideToo()
    {
        (int w, int h) = ImageResizePlan.TargetSize(1200, 1600, 320);
        Assert.Equal(240, w);
        Assert.Equal(320, h);
    }

    [Fact]
    public void ASmallPhotoIsLeftAlone()
    {
        // Escalar hacia arriba solo agrega peso y se ve peor.
        Assert.Equal((100, 80), ImageResizePlan.TargetSize(100, 80, 320));
        Assert.Equal((320, 240), ImageResizePlan.TargetSize(320, 240, 320));
    }

    [Fact]
    public void AVeryElongatedPhotoNeverCollapsesToZero()
    {
        // 4000x3 redondearía su lado corto a 0 y el codificador fallaría.
        (int w, int h) = ImageResizePlan.TargetSize(4000, 3, 320);
        Assert.Equal(320, w);
        Assert.Equal(1, h);
    }

    [Fact]
    public void TheHighQualityPreferenceUsesTheFirmwareMaximum()
    {
        Assert.Equal(640, ImageResizePlan.FirmwareMaxDimension);
        Assert.Equal((640, 480), ImageResizePlan.TargetSize(3200, 2400, ImageResizePlan.FirmwareMaxDimension));
    }

    [Theory]
    [InlineData(0, 100)]
    [InlineData(100, 0)]
    [InlineData(-5, 100)]
    public void ADegenerateSizeGivesNothingInsteadOfGarbage(int width, int height)
        => Assert.Equal((0, 0), ImageResizePlan.TargetSize(width, height, 320));
}

/// <summary>
/// D-291: el visor del firmware solo decodifica JPEG baseline. Un progresivo
/// llega al iPod y aparece como "Formato no soportado", así que reconocerlo
/// tiene que ser exacto.
/// </summary>
public class JpegMarkersTests
{
    /// <summary>SOI + un APP0 de relleno + el SOF que se quiere probar + EOI.</summary>
    private static byte[] Jpeg(byte startOfFrame) =>
    [
        0xFF, 0xD8,
        0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00,      // APP0 con longitud 4
        0xFF, startOfFrame, 0x00, 0x0B,          // SOF con longitud 11
        0x08, 0x00, 0x10, 0x00, 0x10, 0x01, 0x00, 0x11, 0x00,
        0xFF, 0xD9
    ];

    [Fact]
    public void ABaselineJpegIsAccepted() => Assert.True(JpegMarkers.IsBaseline(Jpeg(0xC0)));

    [Fact]
    public void AnExtendedSequentialJpegIsAccepted()
        => Assert.True(JpegMarkers.IsBaseline(Jpeg(0xC1)));

    [Fact]
    public void AProgressiveJpegIsRejected() => Assert.False(JpegMarkers.IsBaseline(Jpeg(0xC2)));

    [Fact]
    public void AnArithmeticProgressiveJpegIsRejected()
        => Assert.False(JpegMarkers.IsBaseline(Jpeg(0xCA)));

    [Fact]
    public void SomethingThatIsNotAJpegIsRejected()
    {
        Assert.False(JpegMarkers.IsBaseline("PNG\r\n"u8));
        Assert.False(JpegMarkers.IsBaseline([]));
    }

    [Fact]
    public void AFileThatEndsBeforeItsSofIsRejected()
    {
        // Ante la duda no se declara apto: mandarlo al iPod sin saberlo es
        // exactamente lo que produce el "Formato no soportado".
        Assert.False(JpegMarkers.IsBaseline([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00]));
    }

    [Fact]
    public void ADefinitionSegmentBeforeTheSofDoesNotConfuseIt()
    {
        // Una tabla de cuantización (DQT, 0xDB) antes del SOF es lo normal.
        byte[] jpeg =
        [
            0xFF, 0xD8,
            0xFF, 0xDB, 0x00, 0x05, 0x00, 0x01, 0x02,
            0xFF, 0xC2, 0x00, 0x04, 0x00, 0x00,      // progresivo detrás del DQT
            0xFF, 0xD9
        ];
        Assert.False(JpegMarkers.IsBaseline(jpeg));
    }
}
