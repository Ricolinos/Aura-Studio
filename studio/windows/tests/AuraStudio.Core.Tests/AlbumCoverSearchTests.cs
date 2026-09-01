using System.Net;
using AuraStudio.Core.Networking;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Buscar tapas de un álbum es <b>ofrecer, no aceptar</b> (ST-104).
///
/// <para>La diferencia con el póster de una película es deliberada: TMDB
/// identifica una película con bastante certeza, mientras que dos ediciones del
/// mismo disco tienen tapas distintas y <b>las dos son correctas</b>. Por eso
/// nada de esto aplica nada solo, ni siquiera cuando encuentra una sola.</para>
/// </summary>
public class AlbumCoverSearchTests
{
    private static readonly byte[] TapaA = [1, 1, 1, 1];
    private static readonly byte[] TapaB = [2, 2, 2, 2];

    private const string ReleasesJson = """
        {"releases":[
          {"id":"rel-1","title":"Signos","date":"1986-11-25"},
          {"id":"rel-2","title":"Signos (Remasterizado)","date":"2007"}
        ]}
        """;

    private const string DeezerJson = """
        {"data":[{"title":"Signos","cover_xl":"https://deezer/cover.jpg","artist":{"name":"Soda Stereo"}}]}
        """;

    /// <summary>
    /// Cover Art Archive contesta primero un índice de imágenes y recién después
    /// sirve la imagen: el stub tiene que imitar los dos pasos o no se prueba
    /// nada de lo que de verdad pasa en la app.
    /// </summary>
    private static string CaaJson(string image) =>
        "{\"images\":[{\"front\":true,\"image\":\"" + image +
        "\",\"thumbnails\":{\"large\":\"" + image + "\"}}]}";

    private const string PrimeraImagen = "https://caa-img/1.jpg";
    private const string SegundaImagen = "https://caa-img/2.jpg";

    /// <summary>Un buscador con las tres fuentes apuntadas al stub.</summary>
    private static AlbumCoverSearch Build(Func<string, (HttpStatusCode Status, byte[] Body)> respond)
    {
        var handler = new BytesStubHandler(respond);
        var http = new HttpClient(handler);

        return new AlbumCoverSearch(
            musicBrainz: new MusicBrainzClient(http, rateLimiter: new MusicBrainzRateLimiter(0),
                retryDelays: MusicBrainzClient.NoRetryDelays),
            coverArtArchive: new CoverArtArchiveClient(http),
            deezer: new DeezerClient(http));
    }

    private static (HttpStatusCode, byte[]) Text(string body) =>
        (HttpStatusCode.OK, System.Text.Encoding.UTF8.GetBytes(body));

    /// <summary>
    /// Todas las fuentes contestando. <paramref name="sameCover"/> hace que las
    /// dos ediciones devuelvan la misma imagen, que es el caso del dedupe.
    /// </summary>
    private static (HttpStatusCode, byte[]) Everything(string url, bool sameCover = false)
    {
        if (url.Contains("musicbrainz", StringComparison.OrdinalIgnoreCase)) return Text(ReleasesJson);

        if (url.Contains("coverartarchive", StringComparison.OrdinalIgnoreCase))
        {
            return Text(CaaJson(sameCover || url.Contains("rel-1") ? PrimeraImagen : SegundaImagen));
        }

        if (url == PrimeraImagen) return (HttpStatusCode.OK, TapaA);
        if (url == SegundaImagen) return (HttpStatusCode.OK, TapaB);

        if (url.Contains("album?q")) return Text(DeezerJson);

        return (HttpStatusCode.OK, TapaB);
    }

    [Fact]
    public async Task SeveralEditionsGiveSeveralCovers()
    {
        // Dos ediciones del mismo disco con arte distinto: ahí está la variedad
        // real que se le ofrece al usuario.
        IReadOnlyList<AlbumCoverCandidate> candidates =
            await Build(url => Everything(url)).CandidatesAsync("Signos", "Soda Stereo", deezerEnabled: false);

        Assert.Equal(2, candidates.Count);
        Assert.All(candidates, c => Assert.Equal(AlbumCoverSource.CoverArtArchive, c.Source));
        Assert.Equal("Signos · 1986", candidates[0].Detail);
        Assert.Equal("Signos (Remasterizado) · 2007", candidates[1].Detail);
    }

    [Fact]
    public async Task TwoEditionsThatShareTheSameImageAreShownOnce()
    {
        // Ofrecer dos veces lo mismo solo obliga a comparar dos imágenes
        // idénticas.
        IReadOnlyList<AlbumCoverCandidate> candidates =
            await Build(url => Everything(url, sameCover: true))
                .CandidatesAsync("Signos", "Soda Stereo", deezerEnabled: false);

        Assert.Single(candidates);
    }

    [Fact]
    public async Task DeezerOnlyAnswersWhenItIsEnabled()
    {
        // D-203: es opcional y se apaga desde Ajustes.
        AlbumCoverSearch search = Build(url => Everything(url, sameCover: true));

        Assert.Single(await search.CandidatesAsync("Signos", "Soda Stereo", deezerEnabled: false));
        Assert.Equal(2, (await search.CandidatesAsync("Signos", "Soda Stereo", deezerEnabled: true)).Count);
    }

    [Fact]
    public async Task MusicBrainzBeingDownDoesNotLeaveWithoutWhatDeezerCouldAnswer()
    {
        // Mejor esfuerzo de punta a punta.
        IReadOnlyList<AlbumCoverCandidate> candidates = await Build(url =>
        {
            if (url.Contains("musicbrainz", StringComparison.OrdinalIgnoreCase))
                return (HttpStatusCode.ServiceUnavailable, []);

            return url.Contains("album?q") ? Text(DeezerJson) : (HttpStatusCode.OK, TapaB);
        }).CandidatesAsync("Signos", "Soda Stereo");

        AlbumCoverCandidate only = Assert.Single(candidates);
        Assert.Equal(AlbumCoverSource.Deezer, only.Source);
    }

    [Fact]
    public async Task CoverArtArchiveGoesFirstBecauseItIsTheSourceAlignedWithTheRest()
    {
        IReadOnlyList<AlbumCoverCandidate> candidates =
            await Build(url => Everything(url, sameCover: true)).CandidatesAsync("Signos", "Soda Stereo");

        Assert.Equal(AlbumCoverSource.CoverArtArchive, candidates[0].Source);
        Assert.Equal(AlbumCoverSource.Deezer, candidates[1].Source);
    }

    // MARK: - Lo que no es un álbum

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("Sin álbum")]
    public async Task ThereIsNothingToSearchForWhatIsNotAnAlbum(string album)
    {
        // "Sin álbum" no es un disco sino el cajón de lo que no tiene uno.
        IReadOnlyList<AlbumCoverCandidate> candidates = await Build(
            _ => throw new InvalidOperationException("no debería tocar la red"))
            .CandidatesAsync(album, "Soda Stereo");

        Assert.Empty(candidates);
    }

    // MARK: - Sin resultados se explica

    [Fact]
    public void WithoutResultsItSaysWhatToCheck()
    {
        string message = AlbumCoverSearch.NoResultsMessage(deezerEnabled: true);

        Assert.Contains("título", message);
        Assert.Contains("artista", message);
        Assert.DoesNotContain("Deezer", message);
    }

    [Fact]
    public void WithDeezerOffItAlsoSaysThatItCanBeTurnedOn()
    {
        Assert.Contains("Deezer", AlbumCoverSearch.NoResultsMessage(deezerEnabled: false));
        Assert.Contains("Ajustes", AlbumCoverSearch.NoResultsMessage(deezerEnabled: false));
    }

    // MARK: - Detalle de cada tapa

    [Theory]
    [InlineData("1986-11-25", "1986")]
    [InlineData("1986", "1986")]
    [InlineData("no-es-fecha", null)]
    [InlineData(null, null)]
    public void TheYearComesOutOfWhateverMusicBrainzGives(string? date, string? expected)
    {
        Assert.Equal(expected, AlbumCoverSearch.Year(date));
    }

    [Fact]
    public void TheDetailSurvivesWithOnlyOneOfItsTwoParts()
    {
        Assert.Equal("Signos · 1986", AlbumCoverSearch.Detail("Signos", "1986"));
        Assert.Equal("Signos", AlbumCoverSearch.Detail("Signos", null));
        Assert.Null(AlbumCoverSearch.Detail(null, null));
    }
}

/// <summary>Stub que devuelve bytes: hace falta para las imágenes.</summary>
internal sealed class BytesStubHandler(Func<string, (HttpStatusCode Status, byte[] Body)> respond)
    : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
    {
        (HttpStatusCode status, byte[] body) = respond(request.RequestUri!.ToString());

        return Task.FromResult(new HttpResponseMessage(status) { Content = new ByteArrayContent(body) });
    }
}
