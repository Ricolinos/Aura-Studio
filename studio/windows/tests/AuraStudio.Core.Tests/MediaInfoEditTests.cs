using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La hoja de "Más información". Lo que se prueba acá es lo que decide: qué
/// cuenta como completo y qué se guarda — la vista solo dibuja campos.
/// </summary>
public class MediaInfoEditTests
{
    private static LibraryItem Song(TrackMetadata? metadata = null) => new()
    {
        SourcePath = @"C:\m\a.mp3",
        Kind = LibraryItemKind.Music,
        Metadata = metadata
    };

    // MARK: - Lo que se carga en la hoja

    [Fact]
    public void TheSheetOpensWithWhatTheItemAlreadyHas()
    {
        MediaInfoDraft draft = MediaInfoDraft.From(Song(new TrackMetadata
        {
            Title = "Persiana americana",
            Artist = "Soda Stereo",
            Album = "Signos",
            TrackNumber = 3,
            Rating = 4,
            SyncedLyrics = "[00:01.00] hola"
        }));

        Assert.Equal("Persiana americana", draft.Title);
        Assert.Equal("3", draft.TrackNumber);
        Assert.Equal(4, draft.Rating);
        Assert.Equal("[00:01.00] hola", draft.Lyrics);
    }

    [Fact]
    public void AnItemWithoutMetadataOpensWithEverythingEmpty()
    {
        MediaInfoDraft draft = MediaInfoDraft.From(Song());

        Assert.Equal("", draft.Title);
        Assert.Equal("", draft.TrackNumber);
        Assert.Equal(0, draft.Rating);
    }

    [Fact]
    public void AVideoOpensWithItsSeriesFields()
    {
        var episode = new LibraryItem
        {
            SourcePath = @"C:\v\a.mkv",
            Kind = LibraryItemKind.Video,
            Category = "Series",
            SeriesName = "Chespirito",
            Season = 1,
            Episode = 2,
            Metadata = new TrackMetadata { Title = "El capítulo" }
        };

        MediaInfoDraft draft = MediaInfoDraft.From(episode);

        Assert.Equal("El capítulo", draft.VideoTitle);
        Assert.Equal("Chespirito", draft.SeriesName);
        Assert.Equal("1", draft.Season);
        Assert.Equal("2", draft.Episode);
    }

    // MARK: - Qué cuenta como completo

    [Fact]
    public void ASongNeedsTitleArtistAndAlbum()
    {
        // Sin ellos, en el iPod cae en "Desconocido".
        var complete = new MediaInfoDraft { Title = "a", Artist = "b", Album = "c" };
        Assert.True(MediaInfoEdit.IsCompleteForSync(complete, LibraryItemKind.Music));

        Assert.False(MediaInfoEdit.IsCompleteForSync(
            complete with { Album = "" }, LibraryItemKind.Music));
        Assert.False(MediaInfoEdit.IsCompleteForSync(
            complete with { Artist = "   " }, LibraryItemKind.Music));
    }

    [Fact]
    public void APhotoOrAVideoHasNothingMandatory()
    {
        var empty = new MediaInfoDraft();

        Assert.True(MediaInfoEdit.IsCompleteForSync(empty, LibraryItemKind.Photo));
        Assert.True(MediaInfoEdit.IsCompleteForSync(empty, LibraryItemKind.Video));
    }

    [Fact]
    public void TheReasonIsSaidOutLoudNotJustImplied()
    {
        // Un botón gris sin explicación es un error de diseño, no una decisión.
        Assert.Contains("obligatorios", MediaInfoEdit.IncompleteReason);
    }

    // MARK: - Qué se guarda

    [Fact]
    public void AnEmptyFieldIsSavedAsAbsentNotAsAnEmptyString()
    {
        // Una cadena vacía se vería en el iPod como un artista llamado "".
        TrackMetadata metadata = MediaInfoEdit.ToMetadata(
            new MediaInfoDraft { Title = "Amor", Artist = "  ", Genre = "" }, null);

        Assert.Equal("Amor", metadata.Title);
        Assert.Null(metadata.Artist);
        Assert.Null(metadata.Genre);
    }

    [Fact]
    public void TheCoverAndTheMusicBrainzLinksSurviveAnEdit()
    {
        // La hoja no los edita, así que no puede borrarlos por omisión.
        var existing = new TrackMetadata
        {
            CoverArtData = [1, 2, 3],
            MusicBrainzRecordingId = "83c68fe1-9660-4e4a-ad7b-f27815730606",
            DurationSeconds = 214.5
        };

        TrackMetadata metadata = MediaInfoEdit.ToMetadata(
            new MediaInfoDraft { Title = "Amor", Artist = "X", Album = "Y" }, existing);

        Assert.Equal([1, 2, 3], metadata.CoverArtData);
        Assert.Equal("83c68fe1-9660-4e4a-ad7b-f27815730606", metadata.MusicBrainzRecordingId);
        Assert.Equal(214.5, metadata.DurationSeconds);
    }

    [Fact]
    public void TheLyricsKeepTheirFormattingButBlankOnesAreNotSaved()
    {
        // Los espacios y saltos de un LRC son parte del formato.
        const string lrc = "[00:01.00] hola\n[00:05.00]   mundo  ";

        Assert.Equal(lrc, MediaInfoEdit.ToMetadata(new MediaInfoDraft { Lyrics = lrc }, null).SyncedLyrics);
        Assert.Null(MediaInfoEdit.ToMetadata(new MediaInfoDraft { Lyrics = "  \n  " }, null).SyncedLyrics);
    }

    [Fact]
    public void ZeroStarsMeansUnratedNotARatingOfZero()
    {
        Assert.Null(MediaInfoEdit.ToMetadata(new MediaInfoDraft { Rating = 0 }, null).Rating);
        Assert.Equal(4, MediaInfoEdit.ToMetadata(new MediaInfoDraft { Rating = 4 }, null).Rating);
    }

    [Fact]
    public void ATrackNumberThatIsNotANumberIsJustAbsent()
    {
        Assert.Null(MediaInfoEdit.ToMetadata(new MediaInfoDraft { TrackNumber = "" }, null).TrackNumber);
        Assert.Equal(12, MediaInfoEdit.ToMetadata(new MediaInfoDraft { TrackNumber = "12" }, null).TrackNumber);
    }

    // MARK: - Lo que se puede escribir

    [Theory]
    [InlineData("12", "12")]
    [InlineData("a1b2", "12")]
    [InlineData("1234", "123")]
    [InlineData("", "")]
    [InlineData("abc", "")]
    public void OnlyDigitsAndAtMostThree(string typed, string expected)
        => Assert.Equal(expected, MediaInfoEdit.DigitsOnly(typed));

    // MARK: - Video

    [Fact]
    public void AVideoThatIsNotASeriesOnlySavesItsTitle()
    {
        // Los campos de serie ni siquiera se muestran, y tampoco se guardan por
        // detrás si quedaron escritos de antes.
        var draft = new MediaInfoDraft
        {
            VideoTitle = "La Peli",
            SeriesName = "Sobra",
            Season = "9",
            Episode = "9"
        };

        var (title, series, season, episode) = MediaInfoEdit.ToVideoInfo(draft, isSeries: false);

        Assert.Equal("La Peli", title);
        Assert.Null(series);
        Assert.Null(season);
        Assert.Null(episode);
    }

    [Fact]
    public void ASeriesEpisodeSavesTheThreeFieldsThatArmItsNameOnTheIPod()
    {
        var draft = new MediaInfoDraft
        {
            VideoTitle = "El capítulo",
            SeriesName = "Chespirito",
            Season = "1",
            Episode = "2"
        };

        var (title, series, season, episode) = MediaInfoEdit.ToVideoInfo(draft, isSeries: true);

        Assert.Equal("El capítulo", title);
        Assert.Equal("Chespirito", series);
        Assert.Equal(1, season);
        Assert.Equal(2, episode);
    }

    // MARK: - Estrellas

    [Fact]
    public void TappingTheActiveStarClearsTheRating()
    {
        // El mismo gesto que Música.app.
        Assert.Equal(0, MediaInfoEdit.RatingAfterTapping(current: 4, star: 4));
        Assert.Equal(2, MediaInfoEdit.RatingAfterTapping(current: 4, star: 2));
        Assert.Equal(5, MediaInfoEdit.RatingAfterTapping(current: 0, star: 5));
    }
}
