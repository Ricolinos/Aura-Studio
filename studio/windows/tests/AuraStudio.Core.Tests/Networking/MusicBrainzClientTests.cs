using AuraStudio.Core.Networking;
using Xunit;

namespace AuraStudio.Core.Tests.Networking;

/// <summary>
/// D-203: <c>buildQuery</c> es la pieza que causaba búsquedas rotas en
/// silencio con títulos reales (comillas, barras invertidas) — ver
/// DECISIONS.md. Sin red, verifica solo el armado de la query Lucene
/// (equivalente de MusicBrainzClientTests.swift).
/// </summary>
public class MusicBrainzClientTests
{
    [Fact]
    public void PlainTitleAndArtistAreQuoted()
    {
        var query = MusicBrainzClient.BuildQuery("Bohemian Rhapsody", "Queen");
        Assert.Equal("recording:\"Bohemian Rhapsody\" AND artist:\"Queen\"", query);
    }

    [Fact]
    public void DoubleQuoteInTitleIsEscapedNotLeftBroken()
    {
        var query = MusicBrainzClient.BuildQuery("Rock \"N\" Roll", null);
        Assert.Equal("recording:\"Rock \\\"N\\\" Roll\"", query);
    }

    [Fact]
    public void BackslashInArtistIsEscaped()
    {
        var query = MusicBrainzClient.BuildQuery(null, "Y\\N");
        Assert.Equal("artist:\"Y\\\\N\"", query);
    }

    [Fact]
    public void OnlyTitleOmitsArtistClause()
    {
        var query = MusicBrainzClient.BuildQuery("Yesterday", null);
        Assert.Equal("recording:\"Yesterday\"", query);
    }
}
