using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El tamaño de archivo en el catálogo (ST-201): que sobreviva a un guardado, que
/// un catálogo anterior a este campo se lea igual, y que un catálogo con el campo
/// no le rompa nada a la app de macOS —que todavía no lo escribe—.
/// </summary>
public class FileSizePersistenceTests : IDisposable
{
    private readonly string _root;
    private readonly LibraryStore _store;

    public FileSizePersistenceTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "AuraTamano-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
        _store = new LibraryStore(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ }
    }

    private LibraryItem Song(string relative, long? size)
    {
        string path = Path.Combine(_root, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, [0]);

        return new LibraryItem
        {
            SourcePath = path,
            Kind = LibraryItemKind.Music,
            Status = LibraryItemStatus.Ready,
            Metadata = new TrackMetadata { Title = "Canción", Album = "Álbum" },
            FileSizeBytes = size
        };
    }

    [Fact]
    public void ElTamanoSobreviveAGuardarYVolverALeer()
    {
        _store.SaveItems([Song("Música/a.mp3", 4_812_345)]);

        Assert.Equal(4_812_345, _store.LoadItems().Single().FileSizeBytes);
    }

    [Fact]
    public void UnElementoSinMedirSeGuardaSinTamanoYSigueSinMedir()
    {
        // Ausente tiene que seguir siendo ausente: si volviera como 0, nunca más
        // se mediría y la columna diría "--" para siempre.
        _store.SaveItems([Song("Música/a.mp3", null)]);

        LibraryItem leido = _store.LoadItems().Single();

        Assert.Null(leido.FileSizeBytes);
        Assert.True(FileSizeBackfill.NeedsSize(leido));
    }

    [Fact]
    public void UnCatalogoAnteriorAlCampoSeLeeCompletoYSinTamano()
    {
        // La migración transparente: un catálogo hecho antes de ST-201 —o por la
        // app de macOS, que todavía no escribe el campo— se lee entero, y lo que
        // falta lo mide el relleno en segundo plano.
        string song = Path.Combine(_root, "Música", "a.mp3");
        Directory.CreateDirectory(Path.GetDirectoryName(song)!);
        File.WriteAllBytes(song, [0]);

        File.WriteAllText(LibraryCatalogStore.CatalogPath(_root), """
        {
          "items": [
            {
              "id": "6B2A8C1E-0000-4000-8000-000000000001",
              "sourceRelativePath": "Música/a.mp3",
              "kind": "music",
              "status": "ready",
              "metadata": { "title": "Canción", "album": "Álbum" }
            }
          ],
          "playlists": []
        }
        """);

        LibraryItem leido = _store.LoadItems().Single();

        Assert.Equal("Canción", leido.Metadata?.Title);
        Assert.Null(leido.FileSizeBytes);
    }

    [Fact]
    public void ElTamanoViajaConElNombreQueUsaMacOS()
    {
        // La biblioteca es la misma carpeta desde las dos apps. El campo se llama
        // igual que la propiedad de macOS a propósito: cuando allá se persista
        // (fase F6), las dos tienen que estar hablando del mismo dato.
        _store.SaveItems([Song("Música/a.mp3", 777)]);

        string json = File.ReadAllText(LibraryCatalogStore.CatalogPath(_root));

        Assert.Contains("\"fileSizeBytes\":777", json);
    }

    [Fact]
    public void GuardarNoInventaUnTamanoDondeNoLoHay()
    {
        _store.SaveItems([Song("Música/a.mp3", null)]);

        string json = File.ReadAllText(LibraryCatalogStore.CatalogPath(_root));

        Assert.DoesNotContain("fileSizeBytes", json);
    }
}
