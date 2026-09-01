using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La biblioteca en disco. Lo que se protege acá: que mover la carpeta no rompa
/// nada, que las portadas no engorden el JSON, y que guardar los items no borre
/// lo que escribió otra parte de la app.
/// </summary>
public class LibraryStoreTests : IDisposable
{
    private readonly string _root;
    private readonly LibraryStore _store;

    public LibraryStoreTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "AuraStore-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
        _store = new LibraryStore(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ }
    }

    private string TouchInsideLibrary(string relative)
    {
        string path = Path.Combine(_root, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, [0]);
        return path;
    }

    // MARK: - Rutas

    [Fact]
    public void AFileInsideTheLibraryIsStoredRelative()
    {
        // Es lo que permite mover la carpeta entera a otro disco y que la
        // biblioteca siga entera.
        //
        // Y va con "/", no con el separador de esta máquina: el catálogo lo
        // comparten las dos apps, y del otro lado una ruta con "\\" es un solo
        // componente con barras adentro — el archivo no existe y el elemento
        // desaparece en silencio (ST-102 / ST-107).
        string absolute = Path.Combine(_root, "Música", "Artista", "a.mp3");
        Assert.Equal("Música/Artista/a.mp3", _store.ToStoredPath(absolute));
    }

    [Fact]
    public void AFileOutsideTheLibraryKeepsItsAbsolutePath()
    {
        // Con "copiar medios a la biblioteca" apagado el archivo vive donde el
        // usuario lo tiene, y ahí una ruta relativa no significa nada.
        string outside = Path.Combine(Path.GetTempPath(), "AjenoALaBiblioteca", "a.mp3");
        Assert.Equal(outside, _store.ToStoredPath(outside));
    }

    [Fact]
    public void PathsRoundTripInBothDirections()
    {
        string inside = Path.Combine(_root, "Videos", "peli.mp4");
        Assert.Equal(inside, _store.ToAbsolutePath(_store.ToStoredPath(inside)));

        string outside = Path.Combine(Path.GetTempPath(), "Otro", "peli.mp4");
        Assert.Equal(outside, _store.ToAbsolutePath(_store.ToStoredPath(outside)));
    }

    [Fact]
    public void ALibraryMovedToAnotherFolderStillResolvesItsFiles()
    {
        string original = TouchInsideLibrary(@"Música\a.mp3");
        _store.SaveItems([LibraryItem.FromDroppedFile(original)]);

        // La misma carpeta, ahora en otro lado.
        string moved = _root + "-mudada";
        Directory.Move(_root, moved);
        try
        {
            LibraryItem item = Assert.Single(new LibraryStore(moved).LoadItems());
            Assert.Equal(Path.Combine(moved, "Música", "a.mp3"), item.SourcePath);
            Assert.True(File.Exists(item.SourcePath));
        }
        finally
        {
            Directory.Move(moved, _root);
        }
    }

    // MARK: - Ida y vuelta

    [Fact]
    public void AnItemSurvivesSaveAndLoadWithAllItsFields()
    {
        var item = new LibraryItem
        {
            SourcePath = TouchInsideLibrary(@"Videos\cap.mkv"),
            Kind = LibraryItemKind.Video,
            Status = LibraryItemStatus.Ready,
            Category = "Series",
            SeriesName = "Chespirito",
            Season = 2,
            Episode = 7,
            MetadataEditedByUser = true,
            AddedAt = DateTimeOffset.Now,
            Metadata = new TrackMetadata { Title = "El capítulo" }
        };

        _store.SaveItems([item]);
        LibraryItem back = Assert.Single(_store.LoadItems());

        Assert.Equal(item.Id, back.Id);
        Assert.Equal(item.SourcePath, back.SourcePath);
        Assert.Equal(LibraryItemKind.Video, back.Kind);
        Assert.Equal(LibraryItemState.Ready, back.Status.State);
        Assert.Equal("Series", back.Category);
        Assert.Equal("Chespirito", back.SeriesName);
        Assert.Equal(2, back.Season);
        Assert.Equal(7, back.Episode);
        Assert.True(back.MetadataEditedByUser);
        Assert.Equal("El capítulo", back.Metadata!.Title);
    }

    [Fact]
    public void AFailedItemComesBackQueuedSoItIsRetried()
    {
        _store.SaveItems([new LibraryItem
        {
            SourcePath = TouchInsideLibrary("a.mp3"),
            Kind = LibraryItemKind.Music,
            Status = LibraryItemStatus.Failed("se cayó la red")
        }]);

        Assert.Equal(LibraryItemState.Queued, _store.LoadItems()[0].Status.State);
    }

    // MARK: - Portadas

    [Fact]
    public void TheCoverIsWrittenAsAFileNotIntoTheCatalog()
    {
        byte[] cover = [0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3];
        var item = new LibraryItem
        {
            SourcePath = TouchInsideLibrary("a.mp3"),
            Kind = LibraryItemKind.Music,
            Metadata = new TrackMetadata { Title = "x", CoverArtData = cover }
        };

        _store.SaveItems([item]);

        Assert.True(File.Exists(_store.CoverPath(item.Id)));
        Assert.Equal(cover, File.ReadAllBytes(_store.CoverPath(item.Id)));
        // Y el catálogo sigue siendo texto liviano.
        string json = File.ReadAllText(LibraryCatalogStore.CatalogPath(_root));
        Assert.DoesNotContain("coverArtData", json, StringComparison.OrdinalIgnoreCase);

        Assert.Equal(cover, _store.LoadItems()[0].Metadata!.CoverArtData);
    }

    [Fact]
    public void RemovingTheCoverDeletesItsFile()
    {
        var item = new LibraryItem
        {
            SourcePath = TouchInsideLibrary("a.mp3"),
            Kind = LibraryItemKind.Music,
            Metadata = new TrackMetadata { Title = "x", CoverArtData = [1, 2, 3] }
        };
        _store.SaveItems([item]);

        item.Metadata!.CoverArtData = null;
        _store.SaveItems([item]);

        Assert.False(File.Exists(_store.CoverPath(item.Id)));
        Assert.Null(_store.LoadItems()[0].Metadata!.CoverArtData);
    }

    [Fact]
    public void AnItemWithoutMetadataLoadsFine()
    {
        _store.SaveItems([new LibraryItem { SourcePath = TouchInsideLibrary("a.mp3"), Kind = LibraryItemKind.Music }]);
        Assert.Null(_store.LoadItems()[0].Metadata);
    }

    // MARK: - Convivencia

    [Fact]
    public void SavingItemsDoesNotDropThePlaylists()
    {
        // Guardar la biblioteca no puede borrar lo que escribió otra parte.
        var playlist = new PersistedPlaylist { Id = Guid.NewGuid(), Name = "Rolas del camino" };
        LibraryCatalogStore.Save(_root, new PersistedLibrary { Playlists = [playlist] });

        _store.SaveItems([LibraryItem.FromDroppedFile(TouchInsideLibrary("a.mp3"))]);

        PersistedLibrary catalog = LibraryCatalogStore.Load(_root);
        Assert.Single(catalog.Items);
        Assert.Equal("Rolas del camino", Assert.Single(catalog.Playlists).Name);
    }

    [Fact]
    public void AnEmptyLibraryLoadsEmptyInsteadOfFailing()
        => Assert.Empty(_store.LoadItems());
}
