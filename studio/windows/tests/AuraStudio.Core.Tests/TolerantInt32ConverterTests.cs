using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El segundo caso real del catálogo del dueño: una canción con
/// <c>"trackNumber" : 4294967295</c> hacía perder los 2809 elementos.
/// </summary>
public class TolerantInt32ConverterTests : IDisposable
{
    private readonly string _root;

    public TolerantInt32ConverterTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "AuraInt-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ }
    }

    private PersistedLibrary LoadWith(string metadata)
    {
        File.WriteAllText(LibraryCatalogStore.CatalogPath(_root), $$"""
        {
          "items" : [
            { "id" : "11111111-1111-1111-1111-111111111111",
              "sourceRelativePath" : "a.mp3", "kind" : "music", "status" : "ready",
              "metadata" : {{metadata}} }
          ]
        }
        """);

        LibraryCatalogStore.CatalogLoad load = LibraryCatalogStore.TryLoad(_root);
        Assert.False(load.Failed, load.Error);
        return load.Catalog;
    }

    [Fact]
    public void ATrackNumberThatDoesNotFitCostsTheNumberNotTheCatalog()
    {
        // 4294967295 es el máximo de un entero sin signo de 32 bits: lo que
        // devuelve una etiqueta rota leída como "sin signo".
        PersistedLibrary catalog = LoadWith("""{ "title" : "Your Love is my drog", "trackNumber" : 4294967295 }""");

        Assert.Single(catalog.Items);
        Assert.Equal("Your Love is my drog", catalog.Items[0].Metadata!.Title);
        Assert.Null(catalog.Items[0].Metadata!.TrackNumber);
    }

    [Fact]
    public void ANormalTrackNumberKeepsWorking()
        => Assert.Equal(3, LoadWith("""{ "trackNumber" : 3 }""").Items[0].Metadata!.TrackNumber);

    [Fact]
    public void ANegativeNumberIsNotATrackNumber()
        => Assert.Null(LoadWith("""{ "trackNumber" : -1 }""").Items[0].Metadata!.TrackNumber);

    [Fact]
    public void ZeroIsKeptBecauseItMeansSomething()
    {
        // "Sin número" en los átomos de iTunes es cero, y esa distinción la
        // maneja TrackTagRules — acá no se pierde.
        Assert.Equal(0, LoadWith("""{ "trackNumber" : 0 }""").Items[0].Metadata!.TrackNumber);
    }

    [Fact]
    public void ANumberWrittenAsTextIsUnderstood()
        => Assert.Equal(7, LoadWith("""{ "trackNumber" : "7" }""").Items[0].Metadata!.TrackNumber);

    [Fact]
    public void SomethingThatIsNotANumberAtAllIsJustAbsent()
        => Assert.Null(LoadWith("""{ "trackNumber" : "cuatro" }""").Items[0].Metadata!.TrackNumber);

    [Fact]
    public void ADecimalIsNotATrackNumberEither()
        => Assert.Null(LoadWith("""{ "trackNumber" : 3.5 }""").Items[0].Metadata!.TrackNumber);

    [Fact]
    public void TheSameToleranceAppliesToEveryOptionalNumber()
    {
        PersistedLibrary catalog = LoadWith(
            """{ "discNumber" : 4294967295, "rating" : 4294967295 }""");

        Assert.Null(catalog.Items[0].Metadata!.DiscNumber);
        Assert.Null(catalog.Items[0].Metadata!.Rating);
    }

    [Fact]
    public void SeasonAndEpisodeAreToleratedToo()
    {
        File.WriteAllText(LibraryCatalogStore.CatalogPath(_root), """
        {
          "items" : [
            { "id" : "11111111-1111-1111-1111-111111111111",
              "sourceRelativePath" : "a.mkv", "kind" : "video", "status" : "ready",
              "season" : 4294967295, "episode" : 2 }
          ]
        }
        """);

        LibraryCatalogStore.CatalogLoad load = LibraryCatalogStore.TryLoad(_root);

        Assert.False(load.Failed, load.Error);
        Assert.Null(load.Catalog.Items[0].Season);
        Assert.Equal(2, load.Catalog.Items[0].Episode);
    }

    [Fact]
    public void WhatIsWrittenBackIsANormalNumber()
    {
        LibraryCatalogStore.Save(_root, new PersistedLibrary
        {
            Items = [new PersistedLibraryItem
            {
                Id = Guid.NewGuid(),
                SourceRelativePath = "a.mp3",
                Metadata = new PersistedTrackMetadata { TrackNumber = 3 }
            }]
        });

        string json = File.ReadAllText(LibraryCatalogStore.CatalogPath(_root));
        Assert.Contains("\"trackNumber\": 3", json);
        Assert.Equal(3, LibraryCatalogStore.Load(_root).Items[0].Metadata!.TrackNumber);
    }
}
