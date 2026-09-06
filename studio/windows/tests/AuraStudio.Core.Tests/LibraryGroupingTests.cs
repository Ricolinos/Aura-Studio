using AuraStudio.Core;
using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Las cuadrículas de Álbumes, Artistas, Películas, Series y álbumes de fotos
/// (ST-031). Son grupos <b>en memoria</b>: nada de esto crea carpetas ni cambia
/// la organización en disco.
/// </summary>
public class LibraryGroupingTests
{
    private static LibraryItem Song(
        string path, string? title = null, string? artist = null, string? albumArtist = null,
        string? album = null, string? genre = null, string? year = null,
        int? track = null, int? disc = null, byte[]? cover = null, bool favorite = false,
        double? duration = null)
        => new()
        {
            SourcePath = path,
            Kind = LibraryItemKind.Music,
            Metadata = new TrackMetadata
            {
                Title = title,
                Artist = artist,
                AlbumArtist = albumArtist,
                Album = album,
                Genre = genre,
                Year = year,
                TrackNumber = track,
                DiscNumber = disc,
                CoverArtData = cover,
                IsFavorite = favorite,
                DurationSeconds = duration
            }
        };

    private static LibraryItem Video(
        string path, string category, string? title = null, string? series = null,
        int? season = null, int? episode = null, string? year = null, byte[]? poster = null)
        => new()
        {
            SourcePath = path,
            Kind = LibraryItemKind.Video,
            Category = category,
            SeriesName = series,
            Season = season,
            Episode = episode,
            Metadata = new TrackMetadata { Title = title, Year = year, CoverArtData = poster }
        };

    private static LibraryItem Photo(string path, string category, string? album = null) =>
        new() { SourcePath = path, Kind = LibraryItemKind.Photo, Category = category, PhotoAlbum = album };

    // MARK: - Normalización

    [Fact]
    public void TwoWaysOfWritingTheSameAlbumLandInOneGroup()
    {
        // "Álbum" y "album " son el mismo álbum; si no, la cuadrícula mostraría
        // el mismo disco dos veces.
        IReadOnlyList<AlbumGroup> albums = LibraryGrouping.Albums(
        [
            Song(@"C:\m\1.mp3", album: "Signos", artist: "Soda Stereo"),
            Song(@"C:\m\2.mp3", album: "signos ", artist: "soda stereo")
        ]);

        AlbumGroup album = Assert.Single(albums);
        Assert.Equal(2, album.TrackCount);
    }

    [Fact]
    public void TheSpellingShownIsTheOneOfTheFirstTrackThatCameIn()
    {
        // Así una grafía descuidada que llegue después no le cambia el nombre al
        // álbum entero.
        IReadOnlyList<AlbumGroup> albums = LibraryGrouping.Albums(
        [
            Song(@"C:\m\1.mp3", album: "Signos", artist: "Soda Stereo"),
            Song(@"C:\m\2.mp3", album: "SIGNOS", artist: "Soda Stereo")
        ]);

        Assert.Equal("Signos", albums[0].Title);
    }

    [Fact]
    public void AnAlbumIsGroupedByItsAlbumArtistNotByEachTracksArtist()
    {
        // Misma precedencia que la ruta de sincronización: lo que se ve acá
        // tiene que coincidir con las carpetas del iPod.
        IReadOnlyList<AlbumGroup> albums = LibraryGrouping.Albums(
        [
            Song(@"C:\m\1.mp3", album: "Varios", artist: "Invitado 1", albumArtist: "La Banda"),
            Song(@"C:\m\2.mp3", album: "Varios", artist: "Invitado 2", albumArtist: "La Banda")
        ]);

        AlbumGroup album = Assert.Single(albums);
        Assert.Equal("La Banda", album.Artist);
    }

    // MARK: - Álbumes

    [Fact]
    public void AlbumsWithoutATitleGoIntoSinAlbumAtTheEnd()
    {
        IReadOnlyList<AlbumGroup> albums = LibraryGrouping.Albums(
        [
            Song(@"C:\m\1.mp3", artist: "Soda Stereo"),
            Song(@"C:\m\2.mp3", album: "Signos", artist: "Soda Stereo")
        ]);

        Assert.Equal("Signos", albums[0].Title);
        Assert.Equal(LibraryGrouping.UnknownAlbumTitle, albums[^1].Title);
        Assert.True(albums[^1].IsUnknown);
    }

    [Fact]
    public void TheInitialArticleIsIgnoredWhenOrdering()
    {
        // Como Music.app: "Los Fabulosos Cadillacs" va en la F.
        IReadOnlyList<AlbumGroup> albums = LibraryGrouping.Albums(
        [
            Song(@"C:\m\1.mp3", album: "Zamba", artist: "X"),
            Song(@"C:\m\2.mp3", album: "El Amor", artist: "X"),
            Song(@"C:\m\3.mp3", album: "Bailando", artist: "X")
        ]);

        Assert.Equal(["El Amor", "Bailando", "Zamba"], albums.Select(a => a.Title));
    }

    [Theory]
    [InlineData("The Wall", "Wall")]
    [InlineData("Los Fabulosos", "Fabulosos")]
    [InlineData("…Little Broken Hearts", "Little Broken Hearts")]
    [InlineData("(What's the Story)", "What's the Story)")]
    [InlineData("El", "El")]                // el artículo solo NO se vacía
    [InlineData("...", "...")]              // puro signo tampoco
    public void TheSortNameDropsArticlesAndLeadingPunctuation(string name, string expected)
        => Assert.Equal(expected, LibraryGrouping.SortName(name));

    [Fact]
    public void TheAlbumCoverIsTheFirstTrackThatHasOne()
    {
        byte[] cover = [1, 2, 3];
        IReadOnlyList<AlbumGroup> albums = LibraryGrouping.Albums(
        [
            Song(@"C:\m\1.mp3", album: "Signos", artist: "X", track: 1),
            Song(@"C:\m\2.mp3", album: "Signos", artist: "X", track: 2, cover: cover)
        ]);

        // ST-208: el grupo apunta a la PISTA que tiene la tapa, no a sus bytes.
        Assert.Equal(cover, albums[0].CoverItem?.Metadata?.CoverArtData);
    }

    [Fact]
    public void TheCardSaysHowManySongsAndFromWhatYear()
    {
        IReadOnlyList<AlbumGroup> albums = LibraryGrouping.Albums(
        [
            Song(@"C:\m\1.mp3", album: "Signos", artist: "X", year: "1986"),
            Song(@"C:\m\2.mp3", album: "Signos", artist: "X", year: "1986")
        ]);

        Assert.Equal("2 canciones · 1986", albums[0].SubtitleDetail);
    }

    [Fact]
    public void ASingleSongIsWrittenInTheSingular()
    {
        IReadOnlyList<AlbumGroup> albums = LibraryGrouping.Albums(
            [Song(@"C:\m\1.mp3", album: "Sencillo", artist: "X")]);

        Assert.Equal("1 canción", albums[0].SubtitleDetail);
    }

    [Fact]
    public void AnAlbumIsFavoriteIfAnyOfItsSongsIs()
    {
        IReadOnlyList<AlbumGroup> albums = LibraryGrouping.Albums(
        [
            Song(@"C:\m\1.mp3", album: "Signos", artist: "X"),
            Song(@"C:\m\2.mp3", album: "Signos", artist: "X", favorite: true)
        ]);

        Assert.True(albums[0].IsFavorite);
    }

    // MARK: - Orden de las pistas

    [Fact]
    public void TracksAreOrderedByDiscThenTrackThenTitle()
    {
        IReadOnlyList<LibraryItem> tracks = LibraryGrouping.SortedTracks(
        [
            Song(@"C:\m\d2t1.mp3", title: "D2T1", disc: 2, track: 1),
            Song(@"C:\m\d1t2.mp3", title: "D1T2", disc: 1, track: 2),
            Song(@"C:\m\d1t1.mp3", title: "D1T1", disc: 1, track: 1)
        ]);

        Assert.Equal(["D1T1", "D1T2", "D2T1"], tracks.Select(t => t.DisplayTitle));
    }

    [Fact]
    public void ATrackWithoutADiscNumberCountsAsDiscOne()
    {
        // Como Music.app: sin ese dato no puede quedar antes de TODO el disco 1.
        IReadOnlyList<LibraryItem> tracks = LibraryGrouping.SortedTracks(
        [
            Song(@"C:\m\a.mp3", title: "sin disco", track: 5),
            Song(@"C:\m\b.mp3", title: "disco 1", disc: 1, track: 1),
            Song(@"C:\m\c.mp3", title: "disco 2", disc: 2, track: 1)
        ]);

        Assert.Equal(["disco 1", "sin disco", "disco 2"], tracks.Select(t => t.DisplayTitle));
    }

    [Fact]
    public void ATrackWithoutATrackNumberGoesToTheEndOfItsDisc()
    {
        // Ahí no hay un valor razonable que suponer, a diferencia del disco.
        IReadOnlyList<LibraryItem> tracks = LibraryGrouping.SortedTracks(
        [
            Song(@"C:\m\a.mp3", title: "sin número"),
            Song(@"C:\m\b.mp3", title: "pista 9", track: 9)
        ]);

        Assert.Equal(["pista 9", "sin número"], tracks.Select(t => t.DisplayTitle));
    }

    // MARK: - Artistas

    [Fact]
    public void AnArtistCollectsItsAlbumsAndCountsItsSongs()
    {
        IReadOnlyList<ArtistGroup> artists = LibraryGrouping.Artists(
        [
            Song(@"C:\m\1.mp3", album: "Signos", artist: "Soda Stereo"),
            Song(@"C:\m\2.mp3", album: "Signos", artist: "Soda Stereo"),
            Song(@"C:\m\3.mp3", album: "Nada Personal", artist: "Soda Stereo")
        ]);

        ArtistGroup artist = Assert.Single(artists);
        Assert.Equal(2, artist.Albums.Count);
        Assert.Equal(3, artist.TrackCount);
        Assert.Equal("2 álbumes, 3 canciones", artist.Summary);
    }

    [Fact]
    public void AnArtistWithOnlyLooseSongsIsSummarizedWithoutAlbums()
    {
        IReadOnlyList<ArtistGroup> artists = LibraryGrouping.Artists(
            [Song(@"C:\m\1.mp3", artist: "Soda Stereo")]);

        Assert.Equal("1 canción", artists[0].Summary);
    }

    [Fact]
    public void SongsWithoutAnArtistEndUpInArtistaDesconocidoAtTheEnd()
    {
        IReadOnlyList<ArtistGroup> artists = LibraryGrouping.Artists(
        [
            Song(@"C:\m\1.mp3", album: "Suelto"),
            Song(@"C:\m\2.mp3", album: "Signos", artist: "Soda Stereo")
        ]);

        Assert.Equal("Soda Stereo", artists[0].Name);
        Assert.Equal(LibraryGrouping.UnknownArtistName, artists[^1].Name);
        Assert.True(artists[^1].IsUnknown);
    }

    [Fact]
    public void AnArtistFallsBackToTheCoverOfItsFirstAlbumThatHasOne()
    {
        byte[] cover = [9, 9];
        IReadOnlyList<ArtistGroup> artists = LibraryGrouping.Artists(
        [
            Song(@"C:\m\1.mp3", album: "A", artist: "X"),
            Song(@"C:\m\2.mp3", album: "B", artist: "X", cover: cover)
        ]);

        Assert.Equal(cover, artists[0].FallbackCoverItem?.Metadata?.CoverArtData);
    }

    // MARK: - Películas y series

    [Fact]
    public void EveryEpisodeOfASeriesIsOneGroupNotOnePerFile()
    {
        IReadOnlyList<VideoCollectionGroup> collections = LibraryGrouping.VideoCollections(
        [
            Video(@"C:\v\1.mkv", "Series", series: "Chespirito", season: 1, episode: 1),
            Video(@"C:\v\2.mkv", "Series", series: "Chespirito", season: 1, episode: 2),
            Video(@"C:\v\3.mkv", "Series", series: "Chespirito", season: 2, episode: 1)
        ]);

        VideoCollectionGroup series = Assert.Single(collections);
        Assert.True(series.IsSeries);
        Assert.Equal("Chespirito", series.Title);
        Assert.Equal(3, series.EpisodeCount);
        Assert.Equal(2, series.Seasons.Count);
    }

    [Fact]
    public void EpisodesWithoutASeasonGoIntoTheirOwnDrawerAtTheEnd()
    {
        IReadOnlyList<VideoCollectionGroup> collections = LibraryGrouping.VideoCollections(
        [
            Video(@"C:\v\x.mkv", "Series", series: "Chespirito", episode: 1),
            Video(@"C:\v\1.mkv", "Series", series: "Chespirito", season: 1, episode: 1)
        ]);

        IReadOnlyList<SeasonGroup> seasons = collections[0].Seasons;
        Assert.Equal(1, seasons[0].Number);
        Assert.Equal(VideoCollectionGroup.NoSeasonNumber, seasons[^1].Number);
    }

    [Fact]
    public void EpisodesInsideASeasonAreOrderedByNumber()
    {
        IReadOnlyList<VideoCollectionGroup> collections = LibraryGrouping.VideoCollections(
        [
            Video(@"C:\v\3.mkv", "Series", title: "tres", series: "S", season: 1, episode: 3),
            Video(@"C:\v\1.mkv", "Series", title: "uno", series: "S", season: 1, episode: 1)
        ]);

        Assert.Equal(["uno", "tres"], collections[0].Seasons[0].Items.Select(i => i.DisplayTitle));
    }

    [Fact]
    public void AMovieDoesNotGetSeasons()
    {
        IReadOnlyList<VideoCollectionGroup> collections = LibraryGrouping.VideoCollections(
            [Video(@"C:\v\peli.mp4", "Películas", title: "La Peli", year: "1999")]);

        Assert.False(collections[0].IsSeries);
        Assert.Empty(collections[0].Seasons);
        Assert.Equal("La Peli", collections[0].Title);
    }

    [Fact]
    public void TwoImportsOfTheSameMovieAreOneGroup()
    {
        IReadOnlyList<VideoCollectionGroup> collections = LibraryGrouping.VideoCollections(
        [
            Video(@"C:\v\a.mp4", "Películas", title: "La Peli"),
            Video(@"C:\v\b.mkv", "Películas", title: "la peli ")
        ]);

        Assert.Equal(2, Assert.Single(collections).EpisodeCount);
    }

    [Fact]
    public void TwoMoviesWithoutATitleNeverGetMergedTogether()
    {
        // Sin título se agrupan por su propio id: mezclarlas sería peor que
        // mostrarlas separadas.
        IReadOnlyList<VideoCollectionGroup> collections = LibraryGrouping.VideoCollections(
        [
            Video(@"C:\v\a.mp4", "Películas"),
            Video(@"C:\v\b.mp4", "Películas")
        ]);

        Assert.Equal(2, collections.Count);
    }

    [Fact]
    public void ACatalogWrittenInEnglishIsStillRecognized()
    {
        // D-228: la categoría se guarda como nombre visible, y la app de macOS
        // en inglés escribe "Movies". Tratarlo como desconocido dejaría esas
        // películas fuera de la vista.
        Assert.Single(LibraryGrouping.VideoCollections(
            [Video(@"C:\v\a.mp4", "Movies", title: "La Peli")]));

        Assert.True(MediaCategoryNames.IsSeriesCategory("Series"));
        Assert.False(MediaCategoryNames.IsSeriesCategory("Videos"));
    }

    [Fact]
    public void APlainVideoIsNotAMovieNorASeries()
    {
        // La vista de Películas/Series no muestra los videos sueltos.
        Assert.Empty(LibraryGrouping.VideoCollections(
            [Video(@"C:\v\clip.mp4", "Videos", title: "Un clip")]));
    }

    // MARK: - Álbumes de fotos

    [Fact]
    public void PhotoAlbumsLiveInsideOneCollectionAtATime()
    {
        // La categoría entra en la clave: "Fotos" e "Imágenes" pueden tener cada
        // una un álbum llamado igual sin que se mezclen.
        LibraryItem[] items =
        [
            Photo(@"C:\f\1.jpg", "Fotos", "Viaje"),
            Photo(@"C:\f\2.jpg", "Imágenes", "Viaje")
        ];

        Assert.Single(Assert.Single(LibraryGrouping.PhotoAlbums(items, "Fotos")).Items);
        Assert.Single(Assert.Single(LibraryGrouping.PhotoAlbums(items, "Imágenes")).Items);
    }

    [Fact]
    public void PhotosWithoutAnAlbumEndUpInSinAlbumAtTheEnd()
    {
        IReadOnlyList<PhotoAlbumGroup> albums = LibraryGrouping.PhotoAlbums(
        [
            Photo(@"C:\f\1.jpg", "Fotos"),
            Photo(@"C:\f\2.jpg", "Fotos", "Viaje")
        ], "Fotos");

        Assert.Equal("Viaje", albums[0].Title);
        Assert.Equal(LibraryGrouping.UnknownPhotoAlbumTitle, albums[^1].Title);
        Assert.True(albums[^1].IsUnknown);
    }

    [Fact]
    public void TheCardShowsUpToFourPhotosForItsMosaic()
    {
        IReadOnlyList<PhotoAlbumGroup> albums = LibraryGrouping.PhotoAlbums(
            [.. Enumerable.Range(1, 6).Select(i => Photo($@"C:\f\{i}.jpg", "Fotos", "Viaje"))],
            "Fotos");

        Assert.Equal(6, albums[0].Count);
        Assert.Equal(4, albums[0].PreviewPaths.Count);
    }

    [Fact]
    public void TheMosaicPrefersThePreparedFileOverTheOriginal()
    {
        var photo = Photo(@"C:\f\1.heic", "Fotos", "Viaje");
        photo.PreparedPath = @"C:\biblioteca\.preparados\1.jpg";

        IReadOnlyList<PhotoAlbumGroup> albums = LibraryGrouping.PhotoAlbums([photo], "Fotos");

        Assert.Equal(@"C:\biblioteca\.preparados\1.jpg", albums[0].PreviewPaths[0]);
    }

    // MARK: - Alcance

    [Fact]
    public void AnEmptyLibraryGroupsIntoNothing()
    {
        Assert.Empty(LibraryGrouping.Albums([]));
        Assert.Empty(LibraryGrouping.Artists([]));
        Assert.Empty(LibraryGrouping.VideoCollections([]));
        Assert.Empty(LibraryGrouping.PhotoAlbums([], "Fotos"));
    }

    [Fact]
    public void AlbumsOnlyLookAtMusic()
    {
        Assert.Empty(LibraryGrouping.Albums(
            [Photo(@"C:\f\1.jpg", "Fotos"), Video(@"C:\v\1.mp4", "Películas", title: "x")]));
    }
}
