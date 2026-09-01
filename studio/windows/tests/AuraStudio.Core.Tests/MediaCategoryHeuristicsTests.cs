using AuraStudio.Core;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// D-192/D-228: heurísticas puras de categorización de fotos/video — sin tocar
/// disco, la lectura real de EXIF/duración vive en `MediaCategoryClassifier`
/// (no testeado acá, necesita archivos reales).
/// </summary>
public class MediaCategoryHeuristicsTests
{
    // MARK: - Fotos

    [Fact]
    public void PhotoWithKnownAISoftwareTagIsAIGenerated()
    {
        // Equivalente a testPhotoWithKnownAISoftwareTagIsAIGenerated
        Assert.Equal("IA", MediaCategoryHeuristics.ClassifyPhoto("Midjourney v6", hasCameraExif: false));
        Assert.Equal("IA", MediaCategoryHeuristics.ClassifyPhoto("Adobe Firefly", hasCameraExif: true));
    }

    [Fact]
    public void PhotoWithCameraExifAndNoAITagIsPhoto()
    {
        // Equivalente a testPhotoWithCameraExifAndNoAITagIsPhoto
        Assert.Equal("Fotos", MediaCategoryHeuristics.ClassifyPhoto(null, hasCameraExif: true));
    }

    [Fact]
    public void PhotoWithNoCameraExifAndNoAITagIsImage()
    {
        // Equivalente a testPhotoWithNoCameraExifAndNoAITagIsImage
        Assert.Equal("Imágenes", MediaCategoryHeuristics.ClassifyPhoto(null, hasCameraExif: false));
    }

    [Fact]
    public void PhotoSoftwareTagMatchIsCaseInsensitive()
    {
        // Equivalente a testPhotoSoftwareTagMatchIsCaseInsensitive
        Assert.Equal("IA", MediaCategoryHeuristics.ClassifyPhoto("STABLE DIFFUSION XL", hasCameraExif: false));
    }

    [Fact]
    public void UnrelatedSoftwareTagDoesNotTriggerAIGenerated()
    {
        // Equivalente a testUnrelatedSoftwareTagDoesNotTriggerAIGenerated
        Assert.Equal("Fotos", MediaCategoryHeuristics.ClassifyPhoto("Adobe Photoshop 25.0", hasCameraExif: true));
    }

    // MARK: - Videos

    // D-228: se eliminó el corte de "casero" (<= 3 min) — ya no hay heurística
    // automática para "Series", el usuario la asigna a mano. Un video corto ahora
    // cae en el default (.videos), igual que cualquier duración que no sea
    // claramente una película.
    [Theory]
    [InlineData(45)]
    [InlineData(180)]
    public void ShortVideoIsVideos(double durationSeconds)
    {
        // Equivalente a testShortVideoIsVideos
        Assert.Equal(MediaCategory.Videos, MediaCategoryHeuristics.ClassifyVideo(durationSeconds));
    }

    [Fact]
    public void MediumVideoIsVideos()
    {
        // Equivalente a testMediumVideoIsVideos
        Assert.Equal(MediaCategory.Videos, MediaCategoryHeuristics.ClassifyVideo(600));
    }

    [Fact]
    public void LongVideoIsMovie()
    {
        // Equivalente a testLongVideoIsMovie — el corte es > 2400 s (40 min)
        Assert.Equal(MediaCategory.Movies, MediaCategoryHeuristics.ClassifyVideo(5400));
    }

    [Fact]
    public void UnknownDurationFallsBackToVideos()
    {
        // Equivalente a testUnknownDurationFallsBackToVideos
        Assert.Equal(MediaCategory.Videos, MediaCategoryHeuristics.ClassifyVideo(null));
        Assert.Equal(MediaCategory.Videos, MediaCategoryHeuristics.ClassifyVideo(0));
    }
}
