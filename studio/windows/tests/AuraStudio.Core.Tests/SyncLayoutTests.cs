using System.Text;
using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Dónde va cada archivo en el iPod. **Esto es contrato**
/// (<c>docs/contracts/library-layout-v1.md</c>): lo lee el firmware, y una ruta
/// distinta significa que el aparato deja de encontrar la música, las letras o
/// las carátulas.
/// </summary>
public class SyncLayoutTests
{
    private static LibraryItem Song(
        string path = @"C:\m\a.mp3", string? title = null, string? artist = null,
        string? albumArtist = null, string? album = null, int? track = null,
        string? prepared = null)
        => new()
        {
            SourcePath = path,
            Kind = LibraryItemKind.Music,
            PreparedPath = prepared,
            Metadata = new TrackMetadata
            {
                Title = title,
                Artist = artist,
                AlbumArtist = albumArtist,
                Album = album,
                TrackNumber = track
            }
        };

    private static LibraryItem Video(
        string path, string? category = null, string? series = null,
        int? season = null, int? episode = null)
        => new()
        {
            SourcePath = path,
            Kind = LibraryItemKind.Video,
            Category = category,
            SeriesName = series,
            Season = season,
            Episode = episode
        };

    // MARK: - Música: los tres layouts

    [Fact]
    public void TheDefaultLayoutIsArtistThenAlbum()
        => Assert.Equal("Music/Soda Stereo/Signos/Persiana americana.mp3",
            SyncLayout.DestinationRelativePath(
                Song(title: "Persiana americana", artist: "Soda Stereo", album: "Signos")));

    [Fact]
    public void TheOtherTwoLayoutsDropOneFolder()
    {
        LibraryItem song = Song(title: "Amor", artist: "Soda Stereo", album: "Signos");

        Assert.Equal("Music/Signos/Amor.mp3",
            SyncLayout.DestinationRelativePath(song, MusicOrganization.Album));
        Assert.Equal("Music/Soda Stereo/Amor.mp3",
            SyncLayout.DestinationRelativePath(song, MusicOrganization.Artist));
    }

    [Fact]
    public void TheFolderArtistIsTheAlbumArtistWhenThereIsOne()
    {
        // Así una recopilación no se parte en una carpeta por invitado.
        Assert.StartsWith("Music/La Banda/",
            SyncLayout.DestinationRelativePath(
                Song(title: "x", artist: "Invitado", albumArtist: "La Banda", album: "Varios")));
    }

    [Fact]
    public void WithoutArtistOrAlbumItGoesToDesconocido()
    {
        // Nunca una carpeta vacía ni una llamada "null".
        Assert.Equal("Music/Desconocido/Desconocido/a.mp3",
            SyncLayout.DestinationRelativePath(Song(@"C:\m\a.mp3")));
    }

    [Fact]
    public void AnEmptyTagCountsAsMissingNotAsAnEmptyName()
    {
        Assert.Equal("Music/Desconocido/Desconocido/Amor.mp3",
            SyncLayout.DestinationRelativePath(Song(title: "Amor", artist: "  ", album: "")));
    }

    [Fact]
    public void WithoutATitleTheFileNameIsUsed()
        => Assert.Equal("Music/Desconocido/Desconocido/pista original.mp3",
            SyncLayout.DestinationRelativePath(Song(@"C:\m\pista original.mp3")));

    // MARK: - Música: los cuatro nombres de archivo

    [Theory]
    [InlineData(MusicFilenameFormat.TitleOnly, "Amor.mp3")]
    [InlineData(MusicFilenameFormat.TrackNumberTitle, "03 Amor.mp3")]
    [InlineData(MusicFilenameFormat.TitleArtist, "Amor - Soda Stereo.mp3")]
    [InlineData(MusicFilenameFormat.TitleAlbum, "Amor - Signos.mp3")]
    public void TheFilenameFollowsTheChosenFormat(MusicFilenameFormat format, string expected)
    {
        string path = SyncLayout.DestinationRelativePath(
            Song(title: "Amor", artist: "Soda Stereo", album: "Signos", track: 3),
            MusicOrganization.ArtistAlbum, format);

        Assert.EndsWith("/" + expected, path);
    }

    [Fact]
    public void WithoutATrackNumberThatFormatFallsBackToTheTitle()
    {
        // "00 Amor.mp3" sería mentira; el título solo es lo honesto.
        Assert.EndsWith("/Amor.mp3", SyncLayout.DestinationRelativePath(
            Song(title: "Amor", artist: "X", album: "Y"),
            MusicOrganization.ArtistAlbum, MusicFilenameFormat.TrackNumberTitle));
    }

    [Fact]
    public void TheTrackNumberIsPaddedToTwoDigits()
        => Assert.EndsWith("/03 Amor.mp3", SyncLayout.DestinationRelativePath(
            Song(title: "Amor", artist: "X", album: "Y", track: 3),
            MusicOrganization.ArtistAlbum, MusicFilenameFormat.TrackNumberTitle));

    // MARK: - Saneo FAT32

    [Fact]
    public void CharactersFat32RejectsNeverReachTheDevice()
    {
        string path = SyncLayout.DestinationRelativePath(
            Song(title: "AC/DC: ¿Qué?", artist: "A*B", album: "C<D>E"));

        foreach (char illegal in (char[])['\\', ':', '*', '?', '"', '<', '>', '|'])
            Assert.DoesNotContain(illegal, path);

        // La "/" solo separa carpetas: la del título tiene que haberse ido.
        Assert.Equal(3, path.Count(c => c == '/'));
    }

    [Fact]
    public void TheExtensionComesFromThePreparedFileWhenThereIsOne()
    {
        // Lo que viaja al iPod es lo convertido, no el original.
        Assert.EndsWith(".mp3", SyncLayout.DestinationRelativePath(
            Song(@"C:\m\a.flac", title: "Amor", artist: "X", album: "Y",
                 prepared: @"C:\lib\.preparados\a.mp3")));
    }

    // MARK: - Video plano

    [Fact]
    public void VideosGoFlatWithNoSubfolders()
        => Assert.Equal("Videos/peli.mpg",
            SyncLayout.DestinationRelativePath(Video(@"C:\v\peli.mpg", "Películas")));

    [Fact]
    public void PhotosGoFlatToo()
        => Assert.Equal("Photos/IMG_0001.jpg",
            SyncLayout.DestinationRelativePath(
                new LibraryItem { SourcePath = @"C:\f\IMG_0001.jpg", Kind = LibraryItemKind.Photo }));

    [Fact]
    public void AVideoNameNeverExceedsWhatTheFirmwareCanHold()
    {
        // 95 bytes UTF-8 con la extensión: los buffers del firmware son de 96
        // con el NUL, y pasarse trunca el nombre del otro lado sin avisar.
        string longName = new('á', 200);
        string path = SyncLayout.DestinationRelativePath(
            Video($@"C:\v\{longName}.mpg", "Películas"));

        string filename = path["Videos/".Length..];
        Assert.True(Encoding.UTF8.GetByteCount(filename) <= SyncLayout.DeviceFilenameMaxBytes,
            $"{Encoding.UTF8.GetByteCount(filename)} bytes");
    }

    // MARK: - Episodios de serie (D-318)

    [Fact]
    public void AnEpisodeTravelsWithTheSuffixTheFirmwareParses()
        => Assert.Equal("Videos/Chespirito S01E02.mpg",
            SyncLayout.DestinationRelativePath(
                Video(@"C:\v\cualquier nombre.mpg", "Series", "Chespirito", 1, 2)));

    [Fact]
    public void TheSuffixIsAlwaysTwoDigits()
        => Assert.Equal("Videos/Serie S09E10.mpg",
            SyncLayout.DestinationRelativePath(Video(@"C:\v\x.mpg", "Series", "Serie", 9, 10)));

    [Fact]
    public void ASeriesWithoutItsThreeFieldsKeepsItsFileName()
    {
        // Sin serie, temporada y episodio no hay nada que agrupar.
        Assert.Equal("Videos/capitulo suelto.mpg",
            SyncLayout.DestinationRelativePath(Video(@"C:\v\capitulo suelto.mpg", "Series")));
    }

    [Fact]
    public void TruncatingALongSeriesNameNeverEatsTheSuffix()
    {
        // Recortar desde el final mutilaría justo el SxxEyy que el firmware
        // necesita: el presupuesto se calcula antes.
        string name = SyncLayout.SeriesEpisodeFilename(new string('á', 200), 1, 2, "mpg");

        Assert.EndsWith(" S01E02.mpg", name);
        Assert.True(Encoding.UTF8.GetByteCount(name) <= SyncLayout.DeviceFilenameMaxBytes);
    }

    [Fact]
    public void TruncatingNeverSplitsACharacterOrLeavesADotAtTheEnd()
    {
        string name = SyncLayout.SeriesEpisodeFilename(new string('ñ', 100) + "...", 1, 1, "mpg");

        Assert.DoesNotContain('\uFFFD', name);
        Assert.DoesNotContain(". S", name);
    }

    [Fact]
    public void IllegalCharactersBecomeUnderscoresTheyAreNotDropped()
    {
        // El contrato dice `/ \ : * ? " < > |` → `_`. Quitarlos en vez de
        // sustituirlos cambiaría el nombre visible sin avisar.
        Assert.Equal("___ S01E01.mpg", SyncLayout.SeriesEpisodeFilename("///", 1, 1, "mpg"));
    }

    [Fact]
    public void ANameThatEndsUpEmptyStillGivesAValidFileName()
    {
        // FAT32 no admite un nombre vacío, ni terminado en punto o espacio.
        Assert.Equal("_ S01E01.mpg", SyncLayout.SeriesEpisodeFilename("  ...  ", 1, 1, "mpg"));
    }

    // MARK: - Póster de temporada (D-318)

    [Fact]
    public void TheSeasonPosterHasNoEpisodePart()
    {
        // Es un archivo por temporada, no de un episodio.
        Assert.Equal("Videos/Chespirito S01.jpg", SyncLayout.SeasonPosterRelativePath("Chespirito", 1));
    }

    [Fact]
    public void TheSeasonPosterSharesTheSanitizedNameWithItsEpisodes()
    {
        // El firmware concatena el nombre que parseó del episodio con
        // " S%02d.jpg": si el saneo difiere, no encuentra el archivo.
        const string messy = "AC/DC: en vivo";

        string episode = SyncLayout.SeriesEpisodeFilename(messy, 2, 5, "mpg");
        string poster = SyncLayout.SeasonPosterRelativePath(messy, 2);

        string episodeBase = episode[..episode.IndexOf(" S02E05", StringComparison.Ordinal)];
        string posterBase = poster["Videos/".Length..];
        posterBase = posterBase[..posterBase.IndexOf(" S02.jpg", StringComparison.Ordinal)];

        Assert.Equal(episodeBase, posterBase);
    }

    // MARK: - Hermanos: letra, póster, carátula

    [Fact]
    public void TheLyricsSitNextToTheAudioWithTheSameBaseName()
    {
        // Es la ÚNICA ruta que el firmware intenta.
        Assert.Equal("Music/A/B/01 Canción.lrc",
            SyncLayout.LyricsRelativePath("Music/A/B/01 Canción.mp3"));
    }

    [Fact]
    public void TheVideoPosterSitsNextToTheVideo()
        => Assert.Equal("Videos/Chespirito S01E02.jpg",
            SyncLayout.PosterRelativePath("Videos/Chespirito S01E02.mpg"));

    [Fact]
    public void ANameWithDotsOnlyLosesItsRealExtension()
        => Assert.Equal("Videos/Serie 1.2 final.jpg",
            SyncLayout.PosterRelativePath("Videos/Serie 1.2 final.mpg"));

    [Fact]
    public void TheAlbumCoverGoesInTheAlbumFolder()
    {
        // cover.jpg es lo que find_albumart() encuentra y lo que comparten
        // todas las pistas del álbum.
        Assert.Equal("Music/Soda Stereo/Signos/cover.jpg",
            SyncLayout.AlbumCoverRelativePath("Music/Soda Stereo/Signos/01 Amor.mp3"));
    }

    [Fact]
    public void AFileWithoutAFolderHasNoAlbumCover()
        => Assert.Null(SyncLayout.AlbumCoverRelativePath("suelto.mp3"));

    // MARK: - Listas

    [Fact]
    public void APlaylistAndItsCoverShareTheirBaseName()
    {
        Assert.Equal("Playlists/Rolas del camino.m3u8",
            SyncLayout.PlaylistRelativePath("Rolas del camino"));
        Assert.Equal("Playlists/Rolas del camino.jpg",
            SyncLayout.PlaylistCoverRelativePath("Rolas del camino"));
    }

    // MARK: - Forma general

    [Fact]
    public void EveryPathUsesForwardSlashesBecauseItIsAnIPodPath()
    {
        string path = SyncLayout.DestinationRelativePath(
            Song(title: "Amor", artist: "Soda Stereo", album: "Signos"));

        Assert.DoesNotContain('\\', path);
        Assert.False(path.StartsWith('/'), "la ruta es relativa a la raíz del volumen");
    }

    [Fact]
    public void TheFourDeviceDirectoriesAreTheOnesInTheContract()
        => Assert.Equal(["Music", "Videos", "Photos", "Playlists"], SyncLayout.DeviceDirectories);
}
