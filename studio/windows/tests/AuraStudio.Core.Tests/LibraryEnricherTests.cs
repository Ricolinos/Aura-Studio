using System.Net;
using AuraStudio.Core.Library;
using AuraStudio.Core.Networking;
using Xunit;

namespace AuraStudio.Core.Tests;

public class FilenameGuesserTests
{
    [Fact]
    public void TheCommonPatternIsArtistDashTitle()
    {
        FilenameGuesser.Guess guess = FilenameGuesser.For(@"C:\m\Soda Stereo - Persiana Americana.mp3");
        Assert.Equal("Soda Stereo", guess.Artist);
        Assert.Equal("Persiana Americana", guess.Title);
    }

    [Fact]
    public void ATitleThatItselfContainsADashIsNotCutInHalf()
    {
        FilenameGuesser.Guess guess = FilenameGuesser.For(@"C:\m\Artista - Canción - Parte 2.mp3");
        Assert.Equal("Artista", guess.Artist);
        Assert.Equal("Canción - Parte 2", guess.Title);
    }

    [Fact]
    public void WithoutTheDashTheWholeNameIsTheTitle()
    {
        FilenameGuesser.Guess guess = FilenameGuesser.For(@"C:\m\Persiana Americana.mp3");
        Assert.Null(guess.Artist);
        Assert.Equal("Persiana Americana", guess.Title);
    }

    [Fact]
    public void ATrackNumberIsNeverMistakenForTheArtist()
    {
        // El bug de producción: decenas de canciones sin etiqueta terminaron en
        // carpetas del iPod llamadas "1".."20", una por número de pista,
        // mezclando artistas distintos.
        FilenameGuesser.Guess guess = FilenameGuesser.For(@"C:\m\1 - Título.m4a");
        Assert.Null(guess.Artist);
        Assert.Equal("1 - Título", guess.Title);
    }

    [Theory]
    [InlineData("1")]
    [InlineData("01")]
    [InlineData("007")]
    [InlineData("01 Lil Dub Chefin")]
    [InlineData("12 algo")]
    public void ASegmentThatLooksLikeATrackNumberIsRejected(string segment)
        => Assert.True(FilenameGuesser.LooksLikeTrackNumberPrefix(segment));

    [Theory]
    [InlineData("Soda Stereo")]
    [InlineData("U2")]
    [InlineData("3Teeth")]
    [InlineData("1234 Algo")]     // 4 dígitos: ya no parece número de pista
    [InlineData("")]
    public void ARealArtistNameIsNotRejected(string segment)
        => Assert.False(FilenameGuesser.LooksLikeTrackNumberPrefix(segment));

    [Fact]
    public void AnImperfectionThatIsDeliberate()
    {
        // "21 Savage" cae en "sin artista" en vez de en su nombre. Se acepta a
        // conciencia: es muchísimo mejor que agrupar decenas de artistas bajo
        // una carpeta llamada "21".
        Assert.True(FilenameGuesser.LooksLikeTrackNumberPrefix("21 Savage"));
        Assert.Null(FilenameGuesser.For(@"C:\m\21 Savage - Canción.mp3").Artist);
    }
}

/// <summary>
/// Devuelve respuestas preparadas según la URL. Sin red: lo que se prueba es la
/// orquestación del enriquecedor, no los clientes (que tienen lo suyo).
/// </summary>
internal sealed class StubHttpHandler(Func<string, (HttpStatusCode Status, string Body)> respond)
    : HttpMessageHandler
{
    public List<string> Requests { get; } = [];

    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        string url = request.RequestUri!.ToString();
        Requests.Add(url);

        (HttpStatusCode status, string body) = respond(url);
        return Task.FromResult(new HttpResponseMessage(status) { Content = new StringContent(body) });
    }
}

public class LibraryEnricherTests
{
    private static LibraryItem Song(string path = @"C:\m\Soda Stereo - Persiana Americana.mp3") =>
        new() { SourcePath = path, Kind = LibraryItemKind.Music };

    private static string RecordingJson(int score, string title = "Persiana Americana",
        string artist = "Soda Stereo", string album = "Signos", string date = "1986-11-20") =>
        """{"recordings":[{"id":"rec-1","score":SCORE,"title":"TITLE","artist-credit":[{"name":"ARTIST"}],"releases":[{"id":"rel-1","title":"ALBUM","date":"DATE","release-group":{"id":"rg-1"}}]}]}"""
            .Replace("SCORE", score.ToString())
            .Replace("TITLE", title)
            .Replace("ARTIST", artist)
            .Replace("ALBUM", album)
            .Replace("DATE", date);

    /// <summary>Un enriquecedor con MusicBrainz y LRCLIB apuntados al stub.</summary>
    private static (LibraryEnricher Enricher, StubHttpHandler Handler) Build(
        Func<string, (HttpStatusCode, string)> respond,
        TrackMetadata? localTags = null)
    {
        var handler = new StubHttpHandler(respond);
        var http = new HttpClient(handler);

        // Los CINCO clientes van al stub. Cualquiera que se deje con su cliente
        // por omisión sale a internet de verdad y la prueba deja de ser una
        // prueba: pasó con Deezer, que devolvió una carátula real.
        var enricher = new LibraryEnricher(
            musicBrainz: new MusicBrainzClient(http, rateLimiter: new MusicBrainzRateLimiter(0)),
            coverArt: new CoverArtArchiveClient(http),
            lrclib: new LRCLIBClient(http),
            fanartTV: new FanartTVClient(http, new NoApiKeys()),
            deezer: new DeezerClient(http),
            readTag: _ => Task.FromResult(localTags ?? new TrackMetadata()));

        return (enricher, handler);
    }

    /// <summary>Sin claves configuradas, como una instalación recién hecha.</summary>
    private sealed class NoApiKeys : IApiKeyStore
    {
        public string? Load(string service) => null;
    }

    private static (HttpStatusCode, string) NotFound(string _) => (HttpStatusCode.NotFound, "");

    // MARK: - Sin red

    [Fact]
    public async Task WithoutConnectionOnlyTheFileAndItsNameAreUsed()
    {
        (LibraryEnricher enricher, StubHttpHandler handler) = Build(
            _ => throw new InvalidOperationException("no debería tocar la red"));

        TrackMetadata metadata = await enricher.EnrichAsync(Song(), online: false);

        Assert.Equal("Soda Stereo", metadata.Artist);
        Assert.Equal("Persiana Americana", metadata.Title);
        Assert.Empty(handler.Requests);
    }

    [Fact]
    public async Task TheTagsOfTheFileWinOverTheGuessFromItsName()
    {
        var tags = new TrackMetadata { Title = "Persiana Americana", Artist = "Soda Stereo (remaster)" };
        (LibraryEnricher enricher, _) = Build(NotFound, tags);

        TrackMetadata metadata = await enricher.EnrichAsync(
            new LibraryItem { SourcePath = @"C:\m\Otro - Otra cosa.mp3", Kind = LibraryItemKind.Music },
            online: false);

        Assert.Equal("Soda Stereo (remaster)", metadata.Artist);
        Assert.Equal("Persiana Americana", metadata.Title);
    }

    // MARK: - El piso de puntaje

    [Fact]
    public async Task ALowScoreResultIsRejectedInsteadOfInventingAnAlbum()
    {
        // Sin este piso, dos canciones del mismo álbum real terminaban con
        // álbumes distintos. "Sin álbum" se puede revisar; un álbum inventado
        // pasa desapercibido.
        (LibraryEnricher enricher, _) = Build(url =>
            url.Contains("musicbrainz") ? (HttpStatusCode.OK, RecordingJson(score: 40)) : NotFound(url));

        TrackMetadata metadata = await enricher.EnrichAsync(Song(), lyrics: false);

        Assert.Null(metadata.Album);
        Assert.Null(metadata.MusicBrainzRecordingId);
    }

    [Fact]
    public async Task AResultWithoutScoreIsTreatedAsZero()
    {
        (LibraryEnricher enricher, _) = Build(url => url.Contains("musicbrainz")
            ? (HttpStatusCode.OK, """{"recordings":[{"id":"rec-1","title":"x","releases":[{"id":"r","title":"Álbum"}]}]}""")
            : NotFound(url));

        Assert.Null((await enricher.EnrichAsync(Song(), lyrics: false)).Album);
    }

    [Fact]
    public async Task AGoodResultFillsAlbumYearAndIds()
    {
        (LibraryEnricher enricher, _) = Build(url =>
            url.Contains("musicbrainz") ? (HttpStatusCode.OK, RecordingJson(score: 95)) : NotFound(url));

        TrackMetadata metadata = await enricher.EnrichAsync(Song(), lyrics: false);

        Assert.Equal("Signos", metadata.Album);
        Assert.Equal("1986", metadata.Year);       // solo el año, no la fecha entera
        Assert.Equal("rec-1", metadata.MusicBrainzRecordingId);
        Assert.Equal("rel-1", metadata.MusicBrainzReleaseId);
    }

    [Fact]
    public void TheThresholdIsTheOneTheDecisionFixed()
        => Assert.Equal(70, LibraryEnricher.MinimumMusicBrainzScore);

    // MARK: - Solo llena huecos

    [Fact]
    public async Task WhatTheUserAlreadyCorrectedIsNeverOverwritten()
    {
        var corregida = new TrackMetadata
        {
            Title = "Persiana Americana",
            Artist = "Soda Stereo",
            Album = "Signos (edición del usuario)"
        };

        (LibraryEnricher enricher, _) = Build(url =>
            url.Contains("musicbrainz") ? (HttpStatusCode.OK, RecordingJson(score: 99)) : NotFound(url));

        (TrackMetadata metadata, _) = await enricher.ReenrichAsync(
            Song(), corregida, fetchAlbumInfo: true, fetchLyrics: false);

        Assert.Equal("Signos (edición del usuario)", metadata.Album);
    }

    [Fact]
    public async Task AnEmptyFieldIsTheOneThatGetsFilled()
    {
        var incompleta = new TrackMetadata { Title = "Persiana Americana", Artist = "Soda Stereo" };

        (LibraryEnricher enricher, _) = Build(url =>
            url.Contains("musicbrainz") ? (HttpStatusCode.OK, RecordingJson(score: 99)) : NotFound(url));

        (TrackMetadata metadata, EnrichmentOutcome outcome) = await enricher.ReenrichAsync(
            Song(), incompleta, fetchAlbumInfo: true, fetchLyrics: false);

        Assert.Equal("Signos", metadata.Album);
        Assert.True(outcome.AlbumInfoFound);
    }

    // MARK: - "No encontré" no es "falló la red" (D-203)

    [Fact]
    public async Task FindingNothingIsNotAnError()
    {
        (LibraryEnricher enricher, _) = Build(url =>
            url.Contains("musicbrainz") ? (HttpStatusCode.OK, """{"recordings":[]}""") : NotFound(url));

        (_, EnrichmentOutcome outcome) = await enricher.ReenrichAsync(
            Song(), new TrackMetadata { Title = "x", Artist = "y" },
            fetchAlbumInfo: true, fetchLyrics: false);

        Assert.False(outcome.AlbumInfoFound);
        Assert.Null(outcome.NetworkErrorMessage);
    }

    [Fact]
    public async Task ANetworkFailureIsReportedInsteadOfLookingLikeNoResults()
    {
        // Un error de red silencioso es indistinguible de "no había nada", y es
        // la causa más probable de que esto pareciera no servir para nada.
        (LibraryEnricher enricher, _) = Build(url =>
            url.Contains("musicbrainz") ? (HttpStatusCode.InternalServerError, "boom") : NotFound(url));

        (_, EnrichmentOutcome outcome) = await enricher.ReenrichAsync(
            Song(), new TrackMetadata { Title = "x", Artist = "y" },
            fetchAlbumInfo: true, fetchLyrics: false);

        Assert.False(outcome.AlbumInfoFound);
        Assert.NotNull(outcome.NetworkErrorMessage);
    }

    [Fact]
    public async Task ImportingInBulkDoesNotStopBecauseTheNetworkFailed()
    {
        // El camino de importación sí se traga el error a propósito: la canción
        // entra igual, con lo que se sepa del archivo.
        (LibraryEnricher enricher, _) = Build(_ => (HttpStatusCode.InternalServerError, "boom"));

        TrackMetadata metadata = await enricher.EnrichAsync(Song());

        Assert.Equal("Soda Stereo", metadata.Artist);
        Assert.Equal("Persiana Americana", metadata.Title);
    }

    // MARK: - Letras

    [Fact]
    public async Task TheLyricsAreOnlyLookedUpWhenAsked()
    {
        (LibraryEnricher enricher, StubHttpHandler handler) = Build(url =>
            url.Contains("musicbrainz") ? (HttpStatusCode.OK, RecordingJson(score: 99)) : NotFound(url));

        await enricher.EnrichAsync(Song(), lyrics: false);
        Assert.DoesNotContain(handler.Requests, url => url.Contains("lrclib"));

        await enricher.EnrichAsync(Song(), lyrics: true);
        Assert.Contains(handler.Requests, url => url.Contains("lrclib"));
    }

    [Fact]
    public async Task LyricsFoundIsOnlyTrueWhenThereReallyAreLyrics()
    {
        (LibraryEnricher enricher, _) = Build(url => url.Contains("lrclib")
            ? (HttpStatusCode.OK, """{"syncedLyrics":"[00:01.00] hola"}""")
            : NotFound(url));

        (TrackMetadata metadata, EnrichmentOutcome outcome) = await enricher.ReenrichAsync(
            Song(), new TrackMetadata { Title = "x", Artist = "y" },
            fetchAlbumInfo: false, fetchLyrics: true);

        Assert.True(outcome.LyricsFound);
        Assert.Equal("[00:01.00] hola", metadata.SyncedLyrics);
    }

    // MARK: - Orden de proveedores de carátula

    [Fact]
    public async Task TheCoverComesFromTheFirstProviderThatHasOne()
    {
        (LibraryEnricher enricher, StubHttpHandler handler) = Build(url =>
            url.Contains("musicbrainz") ? (HttpStatusCode.OK, RecordingJson(score: 99)) : NotFound(url));

        await enricher.EnrichAsync(Song(), lyrics: false);

        // Cover Art Archive va primero por omisión, así que es a quien se le
        // pregunta antes que a nadie.
        Assert.Contains(handler.Requests, url => url.Contains("coverartarchive"));
    }

    [Fact]
    public async Task AProviderThatIsDownDoesNotStopTheOnesBehind()
    {
        (LibraryEnricher enricher, StubHttpHandler handler) = Build(url =>
            url.Contains("musicbrainz") ? (HttpStatusCode.OK, RecordingJson(score: 99))
            : url.Contains("coverartarchive") ? (HttpStatusCode.InternalServerError, "boom")
            : NotFound(url));

        TrackMetadata metadata = await enricher.EnrichAsync(Song(), lyrics: false);

        // No hay carátula, pero tampoco explotó ni se perdió el resto.
        Assert.Null(metadata.CoverArtData);
        Assert.Equal("Signos", metadata.Album);
    }

    [Fact]
    public void TheDefaultOrderIsTheOneOfTheDecision()
        => Assert.Equal(
            [CoverArtProvider.CoverArtArchive, CoverArtProvider.FanartTV, CoverArtProvider.Deezer],
            CoverArtProviderInfo.DefaultOrder);
}
