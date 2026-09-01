using AuraStudio.Core.Library;
using AuraStudio.Core.Media;
using AuraStudio.Core.Networking;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Los archivos de video reales no se llaman como la película. Sin limpiar el
/// nombre, la biblioteca muestra <c>The.Matrix.1999.1080p.BluRay.x264</c> y la
/// búsqueda de póster no encuentra nada.
/// </summary>
public class VideoTitleParserTests
{
    [Theory]
    [InlineData("The.Matrix.1999.1080p.BluRay.x264.mkv", "The Matrix", "1999")]
    [InlineData("Blade Runner 2049 (2017) [1080p] [Latino]", "Blade Runner 2049", "2017")]
    [InlineData("Amelie", "Amelie", null)]
    public void AMovieKeepsItsNameAndItsYear(string raw, string title, string? year)
    {
        VideoTitleParser.Parsed parsed = VideoTitleParser.Parse(raw);

        Assert.Equal(title, parsed.Title);
        Assert.Equal(year, parsed.Year);
        Assert.False(parsed.IsEpisode);
    }

    [Fact]
    public void AMovieNamedAfterAYearDoesNotLoseItsName()
    {
        // "2012" es el título, no el año.
        VideoTitleParser.Parsed parsed = VideoTitleParser.Parse("2012");

        Assert.Equal("2012", parsed.Title);
        Assert.Null(parsed.Year);
    }

    [Fact]
    public void OfTwoYearsTheLastOneIsTheYear()
    {
        VideoTitleParser.Parsed parsed = VideoTitleParser.Parse("1917 (2019) 1080p");

        Assert.Equal("1917", parsed.Title);
        Assert.Equal("2019", parsed.Year);
    }

    [Theory]
    [InlineData("Breaking Bad - S01E02 - Cat's in the Bag.mp4", "Breaking Bad", 1, 2)]
    [InlineData("Los.Simpson.s3e15.mkv", "Los Simpson", 3, 15)]
    [InlineData("Friends 1x02 The One With the Sonogram.avi", "Friends", 1, 2)]
    public void AnEpisodeGivesUpItsSeriesSeasonAndNumber(string raw, string series, int season, int episode)
    {
        VideoTitleParser.Parsed parsed = VideoTitleParser.Parse(raw);

        Assert.True(parsed.IsEpisode);
        Assert.Equal(series, parsed.SeriesName);
        Assert.Equal(season, parsed.Season);
        Assert.Equal(episode, parsed.Episode);
    }

    [Fact]
    public void WhatFollowsTheFirstNoiseTokenIsAlsoNoise()
    {
        Assert.Equal("Interstellar", VideoTitleParser.CleanTitle("Interstellar 1080p BluRay Grupo-XYZ"));
    }

    [Fact]
    public void ANameThatIsOnlyNoiseComesBackEmpty()
    {
        // Igual que en macOS. No es un descuido: quien llama usa el nombre del
        // archivo cuando esto viene vacío, y así el título nunca queda hecho de
        // puro ruido.
        Assert.Equal("", VideoTitleParser.Parse("1080p").Title);
    }

    [Fact]
    public void TheParsedEpisodeIsExactlyWhatTheDeviceFilenameNeeds()
    {
        // Lo que sale de acá alimenta el `SxxEyy` que el firmware agrupa por
        // temporada: si no calzaran, el episodio quedaría suelto en Movie Flow.
        VideoTitleParser.Parsed parsed = VideoTitleParser.Parse("Breaking Bad - S01E02.mp4");

        Assert.Equal("Breaking Bad S01E02.mpg",
            SyncLayout.SeriesEpisodeFilename(parsed.SeriesName!, parsed.Season!.Value, parsed.Episode!.Value, "mpg"));
    }
}

/// <summary>
/// <c>.preparados/</c> es plano: dos archivos distintos con el mismo nombre
/// —justo el caso de los duplicados— compartirían el preparado, y borrar uno
/// dejaría al otro apuntando a un archivo que no existe.
/// </summary>
public class StagingPathsTests
{
    private const string Staging = @"C:\lib\.preparados";

    [Fact]
    public void SomethingNewGetsTheNameOfItsSource()
    {
        Assert.Equal(@"C:\lib\.preparados\canción.mpg",
            StagingPaths.Resolve(Staging, "canción", "mpg", exists: _ => false));
    }

    [Fact]
    public void ASecondFileWithTheSameNameDoesNotStealTheFirstOne()
    {
        Assert.Equal(@"C:\lib\.preparados\canción 2.mpg",
            StagingPaths.Resolve(Staging, "canción", "mpg",
                exists: path => path == @"C:\lib\.preparados\canción.mpg"));
    }

    [Fact]
    public void ReprocessingSomethingReusesItsPreparedFileInsteadOfAbandoningIt()
    {
        Assert.Equal(@"C:\lib\.preparados\ya estaba.mpg",
            StagingPaths.Resolve(Staging, "canción", "mpg",
                existingPrepared: @"C:\lib\.preparados\ya estaba.mpg",
                exists: path => path == @"C:\lib\.preparados\ya estaba.mpg"));
    }

    [Fact]
    public void APreparedFileThatIsNoLongerThereIsNotReused()
    {
        Assert.Equal(@"C:\lib\.preparados\canción.mpg",
            StagingPaths.Resolve(Staging, "canción", "mpg",
                existingPrepared: @"C:\lib\.preparados\borrado.mpg", exists: _ => false));
    }
}
