using System.Text;
using AuraStudio.Core;
using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Lo que se escribe después de copiar: letras, carátulas, listas, pósters y
/// los índices que el firmware lee para armar sus pantallas.
///
/// <para>La regla que más se prueba acá es la misma en todos: se escribe el
/// estado completo, y <b>sin nada que escribir el archivo se borra</b>. Un
/// índice viejo apuntando a archivos que ya no están hace que el firmware
/// muestre entradas que no se pueden abrir.</para>
/// </summary>
public sealed class LibrarySyncFinalizerTests : IDisposable
{
    private readonly string _volume = Path.Combine(Path.GetTempPath(), "aura-fin-" + Guid.NewGuid().ToString("N"));
    private readonly string _library = Path.Combine(Path.GetTempPath(), "aura-finlib-" + Guid.NewGuid().ToString("N"));

    public LibrarySyncFinalizerTests()
    {
        Directory.CreateDirectory(_volume);
        Directory.CreateDirectory(_library);
    }

    public void Dispose()
    {
        foreach (string directory in (string[])[_volume, _library])
            try { Directory.Delete(directory, recursive: true); } catch (IOException) { }
    }

    // MARK: - Ayudas

    private string OnDevice(string relative) => Path.Combine(_volume, relative.Replace('/', Path.DirectorySeparatorChar));

    private void PutOnDevice(string relative, string contents = "x")
    {
        string path = OnDevice(relative);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, contents);
    }

    private static LibraryItem Song(string title, string? lyrics = null, byte[]? cover = null,
        int? rating = null, string artist = "Soda Stereo", string album = "Signos") =>
        new()
        {
            Kind = LibraryItemKind.Music,
            SourcePath = $@"C:\lib\{title}.mp3",
            Status = LibraryItemStatus.Ready,
            Metadata = new TrackMetadata
            {
                Title = title, Artist = artist, Album = album,
                SyncedLyrics = lyrics, CoverArtData = cover, Rating = rating
            }
        };

    private static LibraryItem Video(string category, string? series = null, int? season = null, int? episode = null,
        byte[]? cover = null) =>
        new()
        {
            Kind = LibraryItemKind.Video,
            SourcePath = @"C:\lib\v.mpg",
            Status = LibraryItemStatus.Ready,
            Category = category,
            SeriesName = series,
            Season = season,
            Episode = episode,
            Metadata = cover is null ? null : new TrackMetadata { CoverArtData = cover }
        };

    private static LibraryItem Photo(string category) =>
        new() { Kind = LibraryItemKind.Photo, SourcePath = @"C:\lib\f.jpg", Status = LibraryItemStatus.Ready, Category = category };

    /// <summary>
    /// El recorte cuadrado de mentira: deja los bytes originales con el lado
    /// pedido al frente, para que cada prueba pueda comprobar CON QUÉ LADO se
    /// recortó (320 la carátula, 128 la foto de artista) sin decodificar nada.
    /// </summary>
    private static byte[] Squared(byte[] source, int side) => [.. Encoding.UTF8.GetBytes($"{side}:"), .. source];

    private SyncFinalizeResult Run(IReadOnlyList<LibraryItem> items, IReadOnlyDictionary<Guid, string> destinations,
        IReadOnlyList<Playlist>? playlists = null, Func<byte[], int, byte[]?>? downscale = null,
        Func<IReadOnlyList<byte[]>, byte[]?>? playlistArt = null,
        Func<byte[], int, byte[]?>? squareCrop = null) =>
        LibrarySyncFinalizer.Run(_volume, new SyncFinalizeInput
        {
            Items = items,
            DestinationByItemId = destinations,
            Playlists = playlists ?? [],
            LibraryRoot = _library,
            Downscale = downscale,
            PlaylistArt = playlistArt,
            SquareCrop = squareCrop ?? Squared
        });

    // MARK: - Letras (contrato §3)

    [Fact]
    public void TheLyricsLandNextToTheAudioWithTheSameBaseName()
    {
        // Es la única ruta que el firmware intenta: ni /Lyrics/, ni por
        // etiquetas, ni .txt.
        LibraryItem song = Song("Persiana Americana", lyrics: "[00:01.00]Un tomate");
        PutOnDevice("Music/Soda Stereo/Signos/Persiana Americana.mp3");

        Run([song], new Dictionary<Guid, string> { [song.Id] = "Music/Soda Stereo/Signos/Persiana Americana.mp3" });

        Assert.Equal("[00:01.00]Un tomate\n",
            File.ReadAllText(OnDevice("Music/Soda Stereo/Signos/Persiana Americana.lrc")));
    }

    [Fact]
    public void ALyricThatArrivedAfterTheSongWasAlreadyOnTheDeviceStillTravels()
    {
        // Por eso se escribe el estado completo en cada pasada y no solo lo
        // recién copiado.
        LibraryItem song = Song("Canción", lyrics: "letra nueva");
        PutOnDevice("Music/A/B/Canción.mp3");

        Run([song], new Dictionary<Guid, string> { [song.Id] = "Music/A/B/Canción.mp3" });

        Assert.True(File.Exists(OnDevice("Music/A/B/Canción.lrc")));
    }

    [Fact]
    public void ALyricRemovedInStudioLeavesTheDevice()
    {
        LibraryItem song = Song("Canción");
        PutOnDevice("Music/A/B/Canción.mp3");
        PutOnDevice("Music/A/B/Canción.lrc", "letra vieja");

        Run([song], new Dictionary<Guid, string> { [song.Id] = "Music/A/B/Canción.mp3" });

        Assert.False(File.Exists(OnDevice("Music/A/B/Canción.lrc")));
    }

    [Fact]
    public void NoLyricIsWrittenForASongThatIsNotOnTheDevice()
    {
        // Un .lrc suelto es un huérfano; el contrato §3 no los admite.
        LibraryItem song = Song("Canción", lyrics: "letra");

        Run([song], new Dictionary<Guid, string> { [song.Id] = "Music/A/B/Canción.mp3" });

        Assert.False(File.Exists(OnDevice("Music/A/B/Canción.lrc")));
    }

    [Fact]
    public void AnUnchangedLyricIsNotRewritten()
    {
        // Sobre USB 2.0, rehacer miles de archivos idénticos cuesta minutos.
        LibraryItem song = Song("Canción", lyrics: "misma letra");
        PutOnDevice("Music/A/B/Canción.mp3");
        var destinations = new Dictionary<Guid, string> { [song.Id] = "Music/A/B/Canción.mp3" };

        Run([song], destinations);
        DateTime first = File.GetLastWriteTimeUtc(OnDevice("Music/A/B/Canción.lrc"));

        Run([song], destinations);

        Assert.Equal(first, File.GetLastWriteTimeUtc(OnDevice("Music/A/B/Canción.lrc")));
    }

    // MARK: - Carátulas de álbum (contrato §2)

    [Fact]
    public void TheAlbumCoverGoesOnceIntoTheAlbumFolder()
    {
        byte[] cover = [1, 2, 3];
        LibraryItem a = Song("A", cover: cover);
        LibraryItem b = Song("B", cover: cover);
        PutOnDevice("Music/Soda Stereo/Signos/A.mp3");
        PutOnDevice("Music/Soda Stereo/Signos/B.mp3");

        Run([a, b], new Dictionary<Guid, string>
        {
            [a.Id] = "Music/Soda Stereo/Signos/A.mp3",
            [b.Id] = "Music/Soda Stereo/Signos/B.mp3"
        });

        // v18: llega recortada a 320x320, no cruda.
        Assert.Equal(Squared(cover, LibrarySyncFinalizer.DeviceCoverSide),
                     File.ReadAllBytes(OnDevice("Music/Soda Stereo/Signos/cover.jpg")));
    }

    [Fact]
    public void AnUnchangedCoverIsNotRewritten()
    {
        // Desde v18 el mtime de cover.jpg forma parte de la clave de la caché
        // maestra del firmware: reescribirla igual en cada sync le tiraría toda
        // su caché de carátulas sin que nada hubiera cambiado.
        LibraryItem song = Song("A", cover: [1, 2, 3]);
        PutOnDevice("Music/A/B/A.mp3");
        var destinations = new Dictionary<Guid, string> { [song.Id] = "Music/A/B/A.mp3" };

        Run([song], destinations);
        DateTime first = File.GetLastWriteTimeUtc(OnDevice("Music/A/B/cover.jpg"));

        Run([song], destinations);

        Assert.Equal(first, File.GetLastWriteTimeUtc(OnDevice("Music/A/B/cover.jpg")));
    }

    [Fact]
    public void ACoverThatChangedDoesTravelAgain()
    {
        LibraryItem song = Song("A", cover: [1, 2, 3]);
        PutOnDevice("Music/A/B/A.mp3");
        var destinations = new Dictionary<Guid, string> { [song.Id] = "Music/A/B/A.mp3" };
        Run([song], destinations);

        song.Metadata!.CoverArtData = [9, 9, 9];
        Run([song], destinations);

        Assert.Equal(Squared([9, 9, 9], LibrarySyncFinalizer.DeviceCoverSide),
                     File.ReadAllBytes(OnDevice("Music/A/B/cover.jpg")));
    }

    [Fact]
    public void ASyncThatOnlyChangedTheCoverStillReportsIt()
    {
        // Desde v18 el firmware rehace su caché maestra por una clave que
        // incluye el mtime de `cover.jpg`: un sync que no copió ni una canción
        // pero cambió la carátula SÍ tocó Música, y quien llama tiene que
        // poder decirlo en el marcador.
        LibraryItem song = Song("A", cover: [1, 2, 3]);
        PutOnDevice("Music/A/B/A.mp3");
        var destinations = new Dictionary<Guid, string> { [song.Id] = "Music/A/B/A.mp3" };

        Assert.True(Run([song], destinations).AlbumCoversChanged);

        // Y la segunda pasada, con todo idéntico, ya no anuncia nada.
        Assert.False(Run([song], destinations).AlbumCoversChanged);
    }

    [Fact]
    public void WithoutASquareCropNoCoverIsWritten()
    {
        // Antes que mandarle al iPod algo que incumple el contrato (una
        // carátula con la proporción que sea), no se manda nada.
        LibraryItem song = Song("A", cover: [1, 2, 3]);
        PutOnDevice("Music/A/B/A.mp3");

        LibrarySyncFinalizer.Run(_volume, new SyncFinalizeInput
        {
            Items = [song],
            DestinationByItemId = new Dictionary<Guid, string> { [song.Id] = "Music/A/B/A.mp3" },
            LibraryRoot = _library
        });

        Assert.False(File.Exists(OnDevice("Music/A/B/cover.jpg")));
    }

    [Fact]
    public void WithTheCoverPerTrackPolicyNoAlbumCoverIsWritten()
    {
        LibraryItem song = Song("A", cover: [1]);
        PutOnDevice("Music/A/B/A.mp3");

        LibrarySyncFinalizer.Run(_volume, new SyncFinalizeInput
        {
            Items = [song],
            DestinationByItemId = new Dictionary<Guid, string> { [song.Id] = "Music/A/B/A.mp3" },
            CoverArtPolicy = CoverArtPolicy.PerTrack
        });

        Assert.False(File.Exists(OnDevice("Music/A/B/cover.jpg")));
    }

    // MARK: - Listas

    [Fact]
    public void APlaylistTravelsWithItsTracksResolvedToDevicePaths()
    {
        LibraryItem song = Song("Canción");
        PutOnDevice("Music/A/B/Canción.mp3");
        var playlist = new Playlist { Name = "De noche", TrackItemIds = [song.Id] };

        SyncFinalizeResult result = Run([song],
            new Dictionary<Guid, string> { [song.Id] = "Music/A/B/Canción.mp3" }, [playlist]);

        Assert.Equal(1, result.PlaylistsWritten);
        Assert.Contains("Music/A/B/Canción.mp3",
            File.ReadAllText(Path.Combine(_volume, "Playlists", PlaylistExporter.FileName("De noche"))));
    }

    [Fact]
    public void APlaylistWhoseTracksAreNotOnTheDeviceIsNotWritten()
    {
        var playlist = new Playlist { Name = "Vacía", TrackItemIds = [Guid.NewGuid()] };

        Assert.Equal(0, Run([], new Dictionary<Guid, string>(), [playlist]).PlaylistsWritten);
    }

    [Fact]
    public void APlaylistGetsItsArtNextToItWithTheSameBaseName()
    {
        LibraryItem song = Song("Canción", cover: [9, 9]);
        PutOnDevice("Music/A/B/Canción.mp3");
        var playlist = new Playlist { Name = "De noche", TrackItemIds = [song.Id] };

        Run([song], new Dictionary<Guid, string> { [song.Id] = "Music/A/B/Canción.mp3" }, [playlist],
            playlistArt: covers => covers.Count == 0 ? null : [7]);

        Assert.Equal<byte[]>([7],
            File.ReadAllBytes(Path.Combine(_volume, "Playlists", PlaylistExporter.ImageFileName("De noche"))));
    }

    [Fact]
    public void ACustomPlaylistImageWinsOverTheGeneratedOne()
    {
        LibraryItem song = Song("Canción", cover: [9]);
        PutOnDevice("Music/A/B/Canción.mp3");
        Directory.CreateDirectory(Path.Combine(_library, ".portadas"));
        File.WriteAllBytes(Path.Combine(_library, ".portadas", "playlist.jpg"), [42]);

        var playlist = new Playlist
        {
            Name = "De noche", TrackItemIds = [song.Id], ImageRelativePath = ".portadas/playlist.jpg"
        };

        Run([song], new Dictionary<Guid, string> { [song.Id] = "Music/A/B/Canción.mp3" }, [playlist],
            playlistArt: _ => [7]);

        Assert.Equal<byte[]>([42],
            File.ReadAllBytes(Path.Combine(_volume, "Playlists", PlaylistExporter.ImageFileName("De noche"))));
    }

    // MARK: - Pósters de temporada (D-318)

    [Fact]
    public void EachSeasonGetsItsPosterWhereTheFirmwareLooksForIt()
    {
        // El firmware concatena el nombre de programa que ya parseó con
        // " S%02d.jpg": el archivo tiene que llamarse exactamente así.
        LibraryItem uno = Video("Series", "Los Simpson", 3, 1, cover: [1]);
        LibraryItem dos = Video("Series", "Los Simpson", 3, 2, cover: [2]);

        Run([dos, uno], new Dictionary<Guid, string>
        {
            [uno.Id] = "Videos/Los Simpson S03E01.mpg",
            [dos.Id] = "Videos/Los Simpson S03E02.mpg"
        });

        // El del PRIMER episodio, no el que vino primero en la lista.
        Assert.Equal<byte[]>([1], File.ReadAllBytes(OnDevice("Videos/Los Simpson S03.jpg")));
    }

    [Fact]
    public void AMovieDoesNotGetASeasonPoster()
    {
        LibraryItem movie = Video("Películas", cover: [1]);

        Run([movie], new Dictionary<Guid, string> { [movie.Id] = "Videos/Peli.mpg" });

        Assert.False(Directory.Exists(Path.Combine(_volume, "Videos")));
    }

    // MARK: - Resumen para "Acerca de" (D-283)

    [Fact]
    public void TheSummaryCountsWhatReallyEndedUpOnTheDevice()
    {
        LibraryItem song = Song("A");
        LibraryItem movie = Video("Películas");
        LibraryItem photo = Photo("IA");
        PutOnDevice("Music/A/B/A.mp3", "1234567890");

        Run([song, movie, photo], new Dictionary<Guid, string>
        {
            [song.Id] = "Music/A/B/A.mp3",
            [movie.Id] = "Videos/Peli.mpg",
            [photo.Id] = "Photos/f.jpg"
        });

        CatalogSummary summary = CatalogSummaryReader.Parse(
            File.ReadAllText(OnDevice(LibrarySyncFinalizer.SummaryRelativePath)));

        Assert.Equal(1, summary.Music.Count);
        Assert.Equal(10, summary.Music.Bytes);
        Assert.Equal(1, summary.VideoMovies);
        Assert.Equal(1, summary.PhotoAI);
    }

    // MARK: - Calificaciones (D-199/D-200)

    [Fact]
    public void TheRatingTravelsInRockboxScaleWithTheAbsoluteDevicePath()
    {
        // Sin este sidecar, cualquier calificación se perdería en cuanto el
        // firmware reconstruya su índice.
        LibraryItem song = Song("A", rating: 4);

        Run([song], new Dictionary<Guid, string> { [song.Id] = "Music/A/B/A.mp3" });

        Assert.Equal("/Music/A/B/A.mp3: 8\n",
            File.ReadAllText(OnDevice(LibrarySyncFinalizer.RatingsRelativePath)));
    }

    [Fact]
    public void WithoutRatingsTheFileIsRemovedInsteadOfLeftStale()
    {
        PutOnDevice(LibrarySyncFinalizer.RatingsRelativePath, "/Music/viejo.mp3: 10\n");

        Run([Song("A")], new Dictionary<Guid, string>());

        Assert.False(File.Exists(OnDevice(LibrarySyncFinalizer.RatingsRelativePath)));
    }

    // MARK: - Índices de categoría (contrato §D.2)

    [Fact]
    public void EachVideoAndPhotoIsFiledUnderItsCategory()
    {
        LibraryItem movie = Video("Películas");
        LibraryItem episode = Video("Series", "Serie", 1, 1);
        LibraryItem photo = Photo("Fotos");

        Run([movie, episode, photo], new Dictionary<Guid, string>
        {
            [movie.Id] = "Videos/Peli.mpg",
            [episode.Id] = "Videos/Serie S01E01.mpg",
            [photo.Id] = "Photos/f.jpg"
        });

        string videos = File.ReadAllText(OnDevice(LibrarySyncFinalizer.VideoCategoriesRelativePath));
        Assert.StartsWith("# aura-video-categories v1\n", videos);
        Assert.Contains("Peli.mpg: movie\n", videos);
        Assert.Contains("Serie S01E01.mpg: series\n", videos);

        // La clave es el nombre de archivo, no la ruta: es con lo que el
        // firmware compara.
        Assert.Contains("f.jpg: photo\n", File.ReadAllText(OnDevice(LibrarySyncFinalizer.PhotoCategoriesRelativePath)));
    }

    [Fact]
    public void AnIndexWithNothingToSayIsDeleted()
    {
        PutOnDevice(LibrarySyncFinalizer.VideoCategoriesRelativePath, "# aura-video-categories v1\nviejo.mpg: movie\n");

        Run([], new Dictionary<Guid, string>());

        Assert.False(File.Exists(OnDevice(LibrarySyncFinalizer.VideoCategoriesRelativePath)));
    }

    // MARK: - Fotos de artista (contrato §D.3)

    [Fact]
    public void TheArtistPhotoTravelsReducedWithOneLinePerRawTagValue()
    {
        // El firmware compara byte a byte contra la etiqueta real, así que el
        // índice lleva el valor crudo, no el normalizado.
        var store = new ArtistImageStore(_library);
        store.Save(LibraryGrouping.ArtistKeyOf(Song("A")), [1, 2, 3, 4]);

        LibraryItem a = Song("A", artist: "Soda Stereo");
        LibraryItem b = Song("B", artist: "soda stereo");

        SyncFinalizeResult result = Run([a, b],
            new Dictionary<Guid, string> { [a.Id] = "Music/A/A.mp3", [b.Id] = "Music/A/B.mp3" },
            downscale: (data, _) => data);

        Assert.True(result.ArtistImagesChanged);

        string index = File.ReadAllText(OnDevice(LibrarySyncFinalizer.ArtistImagesIndexRelativePath));
        string fileName = ArtistImageStore.FileName(LibraryGrouping.ArtistKeyOf(a));
        Assert.StartsWith("# aura-artist-images v1\n", index);
        Assert.Contains($"{fileName}: Soda Stereo\n", index);
        Assert.Contains($"{fileName}: soda stereo\n", index);
        // §D.3: cuadrada de 128, no el lado mayor a 128 con la proporción
        // original, que es lo que Studio mandaba hasta v18.
        Assert.Equal(Squared([1, 2, 3, 4], LibrarySyncFinalizer.ArtistImageMaxDimension),
                     File.ReadAllBytes(Path.Combine(_volume, ".rockbox", "aura", "artists", fileName)));
    }

    [Fact]
    public void WithoutArtistPhotosTheIndexIsRemoved()
    {
        PutOnDevice(LibrarySyncFinalizer.ArtistImagesIndexRelativePath, "# aura-artist-images v1\nviejo.jpg: Alguien\n");

        LibraryItem song = Song("A");
        SyncFinalizeResult result = Run([song],
            new Dictionary<Guid, string> { [song.Id] = "Music/A/A.mp3" }, downscale: (data, _) => data);

        Assert.True(result.ArtistImagesChanged);
        Assert.False(File.Exists(OnDevice(LibrarySyncFinalizer.ArtistImagesIndexRelativePath)));
    }

    // MARK: - Nombres de archivo compartidos con la Mac

    [Fact]
    public void TheArtistFileNameIsTheSameOneTheMacWouldWrite()
    {
        // Las dos apps escriben en la misma biblioteca: si el nombre no
        // coincidiera, cada artista terminaría con dos fotos.
        Assert.Equal("soda-stereo.jpg", ArtistImageStore.FileName("soda stereo"));
        Assert.Equal("_e9xito.jpg", ArtistImageStore.FileName("éxito"));
        Assert.Equal("artista.jpg", ArtistImageStore.FileName(""));
    }
}
