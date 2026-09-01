using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El caso real que motivó esto: un catálogo de <b>2809 elementos</b> hecho en
/// la Mac aparecía en Windows como biblioteca vacía. La causa era una sola
/// fecha — Swift la escribe como número de segundos desde 2001 — y el error al
/// leerla se llevaba el catálogo entero por delante.
/// </summary>
public class AppleEpochDateConverterTests : IDisposable
{
    private readonly string _root;

    public AppleEpochDateConverterTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "AuraApple-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ }
    }

    private void WriteCatalog(string json) =>
        File.WriteAllText(LibraryCatalogStore.CatalogPath(_root), json);

    [Fact]
    public void TheAppleEpochIsTheFirstOfJanuaryOf2001()
        => Assert.Equal(new DateTimeOffset(2001, 1, 1, 0, 0, 0, TimeSpan.Zero),
            AppleEpochDateConverter.AppleEpoch);

    [Fact]
    public void ADateWrittenBySwiftIsUnderstood()
    {
        // El valor sale del catálogo real: 808784218.004062 segundos desde 2001.
        DateTimeOffset date = AppleEpochDateConverter.FromAppleSeconds(808784218.004062);

        Assert.Equal(2026, date.Year);
        Assert.Equal(8, date.Month);
    }

    [Fact]
    public void TheConversionGoesInBothDirections()
    {
        var date = new DateTimeOffset(2026, 3, 15, 10, 30, 0, TimeSpan.Zero);
        double seconds = AppleEpochDateConverter.ToAppleSeconds(date);

        Assert.Equal(date, AppleEpochDateConverter.FromAppleSeconds(seconds));
    }

    // MARK: - Lo que importa: el catálogo entero sobrevive

    [Fact]
    public void ACatalogFromMacOsLoadsInsteadOfLookingEmpty()
    {
        // Forma exacta del archivo real, incluida la fecha como número.
        WriteCatalog("""
        {
          "items" : [
            {
              "id" : "F26DBF19-0C21-4662-9A78-84BFBC2F0482",
              "sourceRelativePath" : "Música/Fatboy Slim/01 Right Here.m4a",
              "kind" : "music",
              "status" : "ready",
              "addedAt" : 808784218.004062,
              "metadata" : { "title" : "Right Here, Right Now", "artist" : "Fatboy Slim" }
            }
          ]
        }
        """);

        LibraryCatalogStore.CatalogLoad load = LibraryCatalogStore.TryLoad(_root);

        Assert.False(load.Failed, load.Error);
        PersistedLibraryItem item = Assert.Single(load.Catalog.Items);
        Assert.Equal("Right Here, Right Now", item.Metadata!.Title);
        Assert.Equal(2026, item.AddedAt!.Value.Year);
    }

    [Fact]
    public void ADateWrittenByThisAppKeepsWorking()
    {
        // Un catálogo guardado por una versión anterior de esta app trae la
        // fecha en ISO 8601. Se sigue leyendo: arreglar lo ajeno no puede
        // romper lo propio, aunque hoy ya se escriba como número (ver
        // SwiftInteropTests).
        WriteCatalog("""
        {
          "items" : [
            { "id" : "11111111-1111-1111-1111-111111111111",
              "sourceRelativePath" : "a.mp3", "kind" : "music", "status" : "ready",
              "addedAt" : "2026-03-15T10:30:00.0000000+00:00" }
          ]
        }
        """);

        PersistedLibrary catalog = LibraryCatalogStore.Load(_root);

        Assert.Equal(new DateTimeOffset(2026, 3, 15, 10, 30, 0, TimeSpan.Zero),
            catalog.Items[0].AddedAt);
    }

    [Fact]
    public void WhatThisAppWritesIsReadableByItselfAgain()
    {
        var original = new PersistedLibrary
        {
            Items = [new PersistedLibraryItem
            {
                Id = Guid.NewGuid(),
                SourceRelativePath = "a.mp3",
                AddedAt = new DateTimeOffset(2026, 3, 15, 10, 30, 0, TimeSpan.Zero)
            }]
        };

        LibraryCatalogStore.Save(_root, original);

        Assert.Equal(original.Items[0].AddedAt, LibraryCatalogStore.Load(_root).Items[0].AddedAt);
    }

    [Fact]
    public void ADateThatIsNonsenseCostsTheDateNotTheCatalog()
    {
        WriteCatalog("""
        {
          "items" : [
            { "id" : "11111111-1111-1111-1111-111111111111",
              "sourceRelativePath" : "a.mp3", "kind" : "music", "status" : "ready",
              "addedAt" : "no soy una fecha" }
          ]
        }
        """);

        LibraryCatalogStore.CatalogLoad load = LibraryCatalogStore.TryLoad(_root);

        Assert.False(load.Failed, load.Error);
        Assert.Single(load.Catalog.Items);
    }

    // MARK: - "Vacía" y "no la pude leer" son distintas

    [Fact]
    public void ALibraryWithoutCatalogIsNotAnError()
    {
        LibraryCatalogStore.CatalogLoad load = LibraryCatalogStore.TryLoad(_root);

        Assert.False(load.Failed);
        Assert.Empty(load.Catalog.Items);
    }

    [Fact]
    public void ABrokenCatalogSaysSoInsteadOfLookingEmpty()
    {
        // Este es el fondo del asunto: en pantalla, "está vacía" y "no la pude
        // leer" se veían idénticas, y por eso el problema pasó desapercibido.
        WriteCatalog("{ esto no es json");

        LibraryCatalogStore.CatalogLoad load = LibraryCatalogStore.TryLoad(_root);

        Assert.True(load.Failed);
        Assert.NotNull(load.Error);
        Assert.Empty(load.Catalog.Items);
    }

    [Fact]
    public void TheOldLoadStillNeverThrows()
    {
        WriteCatalog("{ roto");
        Assert.Empty(LibraryCatalogStore.Load(_root).Items);
    }
}
