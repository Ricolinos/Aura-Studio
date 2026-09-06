using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La carga del catálogo con avance y cancelación (ST-203), y la carátula
/// leída por la ruta anotada con respaldo por identificador — que es lo que la
/// app de macOS ya hacía y Windows no.
/// </summary>
public class LibraryLoadTests : IDisposable
{
    private readonly string _root;
    private readonly LibraryStore _store;

    public LibraryLoadTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "AuraCarga-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
        _store = new LibraryStore(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ }
    }

    private LibraryItem Song(string relative, byte[]? cover = null)
    {
        string path = Path.Combine(_root, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, [0]);

        return new LibraryItem
        {
            SourcePath = path,
            Kind = LibraryItemKind.Music,
            Status = LibraryItemStatus.Ready,
            Metadata = new TrackMetadata { Title = "Canción", Album = "Álbum", CoverArtData = cover }
        };
    }

    [Fact]
    public void AvisaDelAvanceYCierraEnElTotal()
    {
        _store.SaveItems([.. Enumerable.Range(0, 3).Select(n => Song($"Música/{n}.mp3"))]);

        List<(int Done, int Total)> progress = [];
        LibraryLoad load = _store.Load((done, total) => progress.Add((done, total)));

        Assert.Equal(3, load.Items.Count);
        Assert.Null(load.Error);

        // Con menos elementos que el paso de avance, el único aviso es el final
        // — y ese siempre sale, para que la barra no se quede corta.
        Assert.Equal([(3, 3)], progress);
    }

    [Fact]
    public void SePuedeDetenerAMitad()
    {
        _store.SaveItems([.. Enumerable.Range(0, 3).Select(n => Song($"Música/{n}.mp3"))]);

        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();

        Assert.Throws<OperationCanceledException>(() => _store.Load(ct: cancellation.Token));
    }

    [Fact]
    public void UnCatalogoIlegibleDaErrorYNoLanza()
    {
        File.WriteAllText(LibraryCatalogStore.CatalogPath(_root), "{ esto no es json");

        LibraryLoad load = _store.Load();

        Assert.Empty(load.Items);
        Assert.NotNull(load.Error);
    }

    [Fact]
    public void LaCaratulaSeLeeDeLaRutaANOTADAAntesQueDelIdentificador()
    {
        // ST-203: la biblioteca es compartida, y la Mac anota la ruta en la
        // forma que SÍ existe en disco. Derivarla siempre del identificador
        // dejaba invisible una carátula que estaba ahí, con otro nombre.
        LibraryItem item = Song("Música/a.mp3");
        _store.SaveItems([item]);

        // Se escribe una carátula con un nombre que NO es el canónico y se
        // anota esa ruta en el catálogo.
        string coversDirectory = Path.Combine(_root, PersistedLibrary.CoversDirName);
        Directory.CreateDirectory(coversDirectory);
        File.WriteAllBytes(Path.Combine(coversDirectory, "otra.jpg"), [1, 2, 3]);

        PersistedLibrary catalog = LibraryCatalogStore.Load(_root);
        catalog.Items[0].CoverRelativePath = PersistedLibrary.CoversDirName + "/otra.jpg";
        LibraryCatalogStore.Save(_root, catalog);

        Assert.Equal([1, 2, 3], _store.LoadItems().Single().Metadata?.CoverArtData);
    }

    [Fact]
    public void SinRutaAnotadaSigueValiendoElNombrePorIdentificador()
    {
        LibraryItem item = Song("Música/a.mp3", [9, 9]);
        _store.SaveItems([item]);

        // Se le quita la ruta anotada: tiene que encontrarla igual, por el
        // nombre canónico. Es el respaldo que hace que un catálogo viejo —o uno
        // escrito antes de que existiera el campo— siga funcionando.
        PersistedLibrary catalog = LibraryCatalogStore.Load(_root);
        catalog.Items[0].CoverRelativePath = null;
        LibraryCatalogStore.Save(_root, catalog);

        Assert.Equal([9, 9], _store.LoadItems().Single().Metadata?.CoverArtData);
    }

    [Fact]
    public void UnaRutaAnotadaQueYaNoExisteCaeAlRespaldo()
    {
        LibraryItem item = Song("Música/a.mp3", [7]);
        _store.SaveItems([item]);

        PersistedLibrary catalog = LibraryCatalogStore.Load(_root);
        catalog.Items[0].CoverRelativePath = PersistedLibrary.CoversDirName + "/no-existe.jpg";
        LibraryCatalogStore.Save(_root, catalog);

        Assert.Equal([7], _store.LoadItems().Single().Metadata?.CoverArtData);
    }

    [Fact]
    public void SinCaratulaEnNingunLadoElElementoCargaIgual()
    {
        _store.SaveItems([Song("Música/a.mp3")]);

        LibraryItem loaded = _store.LoadItems().Single();

        Assert.Null(loaded.Metadata?.CoverArtData);
        Assert.Equal("Canción", loaded.Metadata?.Title);
    }
}
