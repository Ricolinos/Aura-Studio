using System.Net;
using AuraStudio.Core.Networking;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El póster de un video sale de TMDB —que resuelve el título— y, si hay clave,
/// de fanart.tv, que da la versión curada. <b>fanart.tv no busca por título</b>:
/// sin TMDB no hay póster por ningún camino.
///
/// <para>Lo que se prueba acá no es tanto el póster como <b>el motivo cuando no
/// hay</b>: "te falta la clave de TMDB" y "no se encontró" mandan al usuario a
/// lugares distintos, y confundirlos lo deja buscando un problema que no
/// existe.</para>
/// </summary>
public class VideoArtworkResolverTests
{
    private const string MovieJson =
        """{"results":[{"id":603,"title":"The Matrix","release_date":"1999-03-30","poster_path":"/m.jpg"}]}""";

    private const string ShowJson =
        """{"results":[{"id":1396,"name":"Breaking Bad","first_air_date":"2008-01-20","poster_path":"/b.jpg"}]}""";

    private static VideoArtworkResolver Build(
        Func<string, (HttpStatusCode, string)> respond, bool tmdbKey = true, bool fanartKey = false)
    {
        var handler = new ImageStubHandler(respond, [1, 2, 3]);
        var http = new HttpClient(handler);

        return new VideoArtworkResolver(
            tmdb: new TMDBClient(http, tmdbKey ? new KeyStore("clave") : new KeyStore(null)),
            fanart: new FanartTVClient(http, fanartKey ? new KeyStore("clave") : new KeyStore(null)),
            hasFanartKey: () => fanartKey);
    }

    [Fact]
    public async Task WithoutTheTmdbKeyItSaysSoInsteadOfSayingThereIsNoPoster()
    {
        VideoArtworkOutcome outcome = await Build(_ => (HttpStatusCode.OK, MovieJson), tmdbKey: false)
            .ResolveWithReasonAsync("The Matrix 1999", VideoArtworkResolver.Kind.Movie);

        Assert.False(outcome.Found);
        Assert.Equal(VideoArtworkResolver.MissingKeyReason, outcome.Reason);
        Assert.Contains("TMDB", outcome.Reason);
    }

    [Fact]
    public async Task AVideoThatTmdbDoesNotKnowSaysThatInstead()
    {
        VideoArtworkOutcome outcome = await Build(_ => (HttpStatusCode.OK, """{"results":[]}"""))
            .ResolveWithReasonAsync("Video de la cámara 0042", VideoArtworkResolver.Kind.Movie);

        Assert.False(outcome.Found);
        Assert.Equal(VideoArtworkResolver.NoMatchReason, outcome.Reason);
    }

    [Fact]
    public async Task AMovieGetsItsPosterAndTheMatchedTitleComesBack()
    {
        // El título con el que casó importa: es lo que le deja al usuario ver
        // que el póster corresponde a su video y no a otra película.
        VideoArtworkOutcome outcome = await Build(_ => (HttpStatusCode.OK, MovieJson))
            .ResolveWithReasonAsync("The.Matrix.1999.1080p.BluRay.x264", VideoArtworkResolver.Kind.Movie);

        Assert.True(outcome.Found);
        Assert.Null(outcome.Reason);
        Assert.Equal("The Matrix", outcome.Poster!.Value.MatchedTitle);
        Assert.Equal(VideoArtworkResolver.Source.TMDB, outcome.Poster.Value.Source);
    }

    [Fact]
    public async Task AnEpisodeIsLookedUpAsASeries()
    {
        VideoArtworkOutcome outcome = await Build(_ => (HttpStatusCode.OK, ShowJson))
            .ResolveWithReasonAsync("Breaking Bad - S01E02", VideoArtworkResolver.Kind.Series);

        Assert.True(outcome.Found);
        Assert.Equal("Breaking Bad", outcome.Poster!.Value.MatchedTitle);
    }

    // MARK: - La categoría de Studio decide qué se busca

    [Theory]
    [InlineData("Películas", VideoArtworkResolver.Kind.Movie)]
    [InlineData("Movies", VideoArtworkResolver.Kind.Movie)]
    [InlineData("Series", VideoArtworkResolver.Kind.Series)]
    [InlineData("Videos", VideoArtworkResolver.Kind.Unknown)]
    [InlineData(null, VideoArtworkResolver.Kind.Unknown)]
    public void TheCategoryMapsToWhatGetsSearched(string? category, VideoArtworkResolver.Kind expected)
    {
        // Un catálogo escrito por la app de macOS dice "Movies" en inglés:
        // tratarlo como desconocido buscaría dos veces por nada.
        Assert.Equal(expected, VideoArtworkResolver.KindOf(category));
    }

    private sealed class KeyStore(string? key) : IApiKeyStore
    {
        public string? Load(string service) => key;
    }
}
