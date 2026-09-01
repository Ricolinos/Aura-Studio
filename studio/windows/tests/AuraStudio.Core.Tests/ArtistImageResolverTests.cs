using System.Net;
using AuraStudio.Core.Library;
using AuraStudio.Core.Networking;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La foto de un artista son dos llamadas encadenadas y ninguna se puede
/// saltar: fanart.tv <b>no busca por nombre</b>, así que MusicBrainz tiene que
/// resolver primero el identificador.
///
/// <para>Lo que más importa acá no es la foto sino <b>el motivo cuando no
/// hay</b>: "no se encontró" y "te falta la clave" son cosas distintas, y
/// mezclarlas manda al usuario a buscar donde no es.</para>
/// </summary>
public class ArtistImageResolverTests
{
    private static readonly byte[] Jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3];

    private const string ArtistJson =
        """{"artists":[{"id":"mbid-soda","name":"Soda Stereo","score":100}]}""";

    private static ArtistImageResolver Build(
        Func<string, (HttpStatusCode, string)> respond, bool hasKey = true, byte[]? image = null)
    {
        var handler = new ImageStubHandler(respond, image);
        var http = new HttpClient(handler);

        return new ArtistImageResolver(
            musicBrainz: new MusicBrainzClient(http, rateLimiter: new MusicBrainzRateLimiter(0)),
            fanartTV: new FanartTVClient(http, new AlwaysKey()),
            hasFanartKey: () => hasKey);
    }

    private static (HttpStatusCode, string) Respond(string url) =>
        url.Contains("musicbrainz", StringComparison.OrdinalIgnoreCase)
            ? (HttpStatusCode.OK, ArtistJson)
            : (HttpStatusCode.OK, """{"artistthumb":[{"url":"https://fanart/x.jpg"}]}""");

    [Fact]
    public async Task WithoutTheKeyItSaysSoInsteadOfSayingThereIsNoPhoto()
    {
        // Sin clave, fanart.tv devuelve 401 a todo: reportarlo como "no se
        // encontró" mandaría al usuario a buscar un problema que no existe.
        ArtistImageResult result = await Build(Respond, hasKey: false).ResolveAsync("Soda Stereo");

        Assert.False(result.Found);
        Assert.Equal(ArtistImageResolver.MissingKeyReason, result.Reason);
        Assert.Contains("fanart.tv", result.Reason);
    }

    [Fact]
    public async Task AnArtistThatMusicBrainzDoesNotKnowSaysThat()
    {
        ArtistImageResult result = await Build(_ => (HttpStatusCode.OK, """{"artists":[]}"""))
            .ResolveAsync("Nombre inventado");

        Assert.Equal(ArtistImageResolver.NoMatchReason, result.Reason);
    }

    [Fact]
    public async Task AnEmptyNameNeverReachesTheNetwork()
    {
        ArtistImageResult result = await Build(_ => throw new InvalidOperationException("no debería llamar"))
            .ResolveAsync("   ");

        Assert.Equal(ArtistImageResolver.NoMatchReason, result.Reason);
    }

    [Fact]
    public async Task AKnownIdSkipsTheSearch()
    {
        // Si el identificador ya vino en las etiquetas, pedirle a MusicBrainz
        // que lo busque otra vez es una llamada de red para nada.
        var handler = new ImageStubHandler(Respond, Jpeg);
        var resolver = new ArtistImageResolver(
            musicBrainz: new MusicBrainzClient(new HttpClient(handler), rateLimiter: new MusicBrainzRateLimiter(0)),
            fanartTV: new FanartTVClient(new HttpClient(handler), new AlwaysKey()),
            hasFanartKey: () => true);

        ArtistImageResult result = await resolver.ResolveAsync("Soda Stereo", "mbid-soda");

        Assert.True(result.Found);
        Assert.DoesNotContain(handler.Requests, url => url.Contains("musicbrainz", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public async Task AnArtistWithoutAPhotoOnFanartSaysThatToo()
    {
        ArtistImageResult result = await Build(url =>
            url.Contains("musicbrainz", StringComparison.OrdinalIgnoreCase)
                ? (HttpStatusCode.OK, ArtistJson)
                : (HttpStatusCode.NotFound, "")).ResolveAsync("Soda Stereo");

        Assert.Equal(ArtistImageResolver.NoImageReason, result.Reason);
    }

    // MARK: - Sobre una biblioteca

    [Fact]
    public async Task AnArtistThatAlreadyHasAPhotoIsNotAskedAgain()
    {
        // Son dos llamadas de red por artista y una biblioteca real tiene
        // cientos: volver a pedir lo que ya está sería media hora de espera.
        string library = Path.Combine(Path.GetTempPath(), "aura-artfoto-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(library);

        try
        {
            var store = new ArtistImageStore(library);
            store.Save(LibraryGrouping.ArtistKeyOf(Song("Soda Stereo")), Jpeg);

            var handler = new ImageStubHandler(_ => throw new InvalidOperationException("no debería llamar"), null);
            var resolver = new ArtistImageResolver(
                musicBrainz: new MusicBrainzClient(new HttpClient(handler), rateLimiter: new MusicBrainzRateLimiter(0)),
                fanartTV: new FanartTVClient(new HttpClient(handler), new AlwaysKey()),
                hasFanartKey: () => true);

            Assert.Equal(0, (await resolver.FetchMissingAsync([Song("Soda Stereo")], store)).Found);
        }
        finally
        {
            try { Directory.Delete(library, recursive: true); } catch (IOException) { }
        }
    }

    private static LibraryItem Song(string artist) => new()
    {
        Kind = LibraryItemKind.Music,
        SourcePath = @"C:\m\a.mp3",
        Metadata = new TrackMetadata { Title = "A", Artist = artist, Album = "Signos" }
    };

    /// <summary>Una instalación con la clave de fanart.tv puesta.</summary>
    private sealed class AlwaysKey : IApiKeyStore
    {
        public string? Load(string service) => "clave";
    }
}

/// <summary>
/// Igual que <c>StubHttpHandler</c>, pero también sirve bytes para la descarga
/// de la imagen.
/// </summary>
internal sealed class ImageStubHandler(Func<string, (HttpStatusCode Status, string Body)> respond, byte[]? image)
    : HttpMessageHandler
{
    public List<string> Requests { get; } = [];

    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
    {
        string url = request.RequestUri!.ToString();
        Requests.Add(url);

        if (url.EndsWith(".jpg", StringComparison.OrdinalIgnoreCase))
        {
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new ByteArrayContent(image ?? [1, 2, 3])
            });
        }

        (HttpStatusCode status, string body) = respond(url);
        return Task.FromResult(new HttpResponseMessage(status) { Content = new StringContent(body) });
    }
}

/// <summary>
/// HTTP 503 de MusicBrainz es <b>saturación</b>, no "no existe" ni "se cayó tu
/// internet" (hallazgo del dueño). Lo que importa: que un artista que falla no
/// tumbe el lote, y que el resumen lo diga sin un diálogo.
/// </summary>
public class MusicBrainzSaturationTests : IDisposable
{
    private readonly string _library = Path.Combine(Path.GetTempPath(), "aura-503-" + Guid.NewGuid().ToString("N"));

    public MusicBrainzSaturationTests() => Directory.CreateDirectory(_library);

    public void Dispose()
    {
        try { Directory.Delete(_library, recursive: true); } catch (IOException) { }
    }

    private static LibraryItem Song(string artist, string title) => new()
    {
        Kind = LibraryItemKind.Music,
        SourcePath = $@"C:\m\{title}.mp3",
        Metadata = new TrackMetadata { Title = title, Artist = artist, Album = "Álbum" }
    };

    private static ArtistImageResolver Saturated(out ImageStubHandler handler)
    {
        var stub = new ImageStubHandler(_ => (HttpStatusCode.ServiceUnavailable, ""), null);
        handler = stub;

        var http = new HttpClient(stub);

        return new ArtistImageResolver(
            musicBrainz: new MusicBrainzClient(http, rateLimiter: new MusicBrainzRateLimiter(0),
                retryDelays: MusicBrainzClient.NoRetryDelays),
            fanartTV: new FanartTVClient(http, new AlwaysKeyStore()),
            hasFanartKey: () => true);
    }

    [Fact]
    public async Task A503IsSaturationAndNotSomethingTheUserBroke()
    {
        Assert.True(MusicBrainzClient.IsSaturation(EnrichmentError.Http(503)));
        Assert.True(MusicBrainzClient.IsSaturation(EnrichmentError.Http(429)));
        Assert.False(MusicBrainzClient.IsSaturation(EnrichmentError.Http(404)));
        Assert.False(MusicBrainzClient.IsSaturation(new IOException("disco")));
    }

    [Fact]
    public async Task TheBatchStopsInsteadOfAskingHundredsOfTimesForNothing()
    {
        // Con el servicio caído, insistir por cada uno de cientos de artistas
        // son veinte minutos de espera para terminar sin nada.
        ArtistImageResolver resolver = Saturated(out _);

        ArtistImageBatch batch = await resolver.FetchMissingAsync(
            [
                Song("Uno", "a"), Song("Dos", "b"), Song("Tres", "c"),
                Song("Cuatro", "d"), Song("Cinco", "e")
            ],
            new ArtistImageStore(_library));

        Assert.True(batch.StoppedBySaturation);
        Assert.Equal(0, batch.Found);
        Assert.Equal(3, batch.Failed);
        Assert.Contains("saturado", batch.Summary);
        Assert.Contains("en un rato", batch.Summary);
    }

    [Fact]
    public async Task WhatWasAlreadyDoneIsReportedTogetherWithTheSaturation()
    {
        // Media docena de fotos conseguidas antes de que el servicio se cayera
        // no se pierden ni se callan.
        var batch = new ArtistImageBatch(6, 3, StoppedBySaturation: true);

        Assert.Contains("6", batch.Summary);
        Assert.Contains("saturado", batch.Summary);
    }

    [Fact]
    public async Task NothingFoundIsNotTheSameAsSaturated()
    {
        // Confundirlas manda al usuario a creer que su biblioteca no tiene
        // artistas reconocibles, cuando lo único que pasa es que hay que
        // volver más tarde.
        Assert.DoesNotContain("saturado", new ArtistImageBatch(0, 0, false).Summary);
        Assert.Contains("ninguna foto", new ArtistImageBatch(0, 0, false).Summary);
    }

    [Fact]
    public async Task OneArtistThatFailsDoesNotTakeDownTheOnesThatFollow()
    {
        // El usuario pidió las fotos de su biblioteca, no las de uno.
        int calls = 0;

        var stub = new ImageStubHandler(url =>
        {
            if (!url.Contains("musicbrainz", StringComparison.OrdinalIgnoreCase))
                return (HttpStatusCode.OK, """{"artistthumb":[{"url":"https://fanart/x.jpg"}]}""");

            // El primero revienta con algo que no es saturación; el resto anda.
            return ++calls == 1
                ? (HttpStatusCode.BadRequest, "")
                : (HttpStatusCode.OK, """{"artists":[{"id":"mbid","name":"X","score":100}]}""");
        }, [9, 9, 9]);

        var http = new HttpClient(stub);
        var resolver = new ArtistImageResolver(
            musicBrainz: new MusicBrainzClient(http, rateLimiter: new MusicBrainzRateLimiter(0),
                retryDelays: MusicBrainzClient.NoRetryDelays),
            fanartTV: new FanartTVClient(http, new AlwaysKeyStore()),
            hasFanartKey: () => true);

        ArtistImageBatch batch = await resolver.FetchMissingAsync(
            [Song("Uno", "a"), Song("Dos", "b"), Song("Tres", "c")],
            new ArtistImageStore(_library));

        Assert.False(batch.StoppedBySaturation);
        Assert.Equal(1, batch.Failed);
        Assert.Equal(2, batch.Found);
    }

    private sealed class AlwaysKeyStore : IApiKeyStore
    {
        public string? Load(string service) => "clave";
    }
}
