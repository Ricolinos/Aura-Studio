using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El peligro de ST-208, clavado con pruebas.
///
/// <para>Desde ST-208 la carátula <b>no se carga al abrir</b>: los elementos
/// llegan con la ruta y el hash, y sin bytes. Eso convierte una regla que antes
/// era inofensiva —"si no hay bytes, no hay carátula"— en una forma de <b>borrar
/// las mil carátulas del usuario en el primer guardado</b>: cargar y guardar sin
/// tocar nada las habría dejado sin ruta en el catálogo y sus archivos
/// borrados de <c>.portadas\</c>.</para>
///
/// <para>Y no solo acá: el catálogo es compartido, así que la app de macOS
/// habría abierto la biblioteca y encontrado que se quedó sin tapas.</para>
///
/// <para>Estas pruebas existen para que eso no pueda volver a pasar sin que algo
/// se ponga rojo.</para>
/// </summary>
public class CoverArtPreservationTests : IDisposable
{
    private readonly string _root;
    private readonly LibraryStore _store;

    public CoverArtPreservationTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "AuraTapas-" + Guid.NewGuid().ToString("N"));
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

    private int CoverFilesOnDisk() =>
        Directory.Exists(_store.CoversDirectory)
            ? Directory.GetFiles(_store.CoversDirectory).Length
            : 0;

    [Fact]
    public void CargarYGuardarSinTocarNadaNoPierdeLaCaratula()
    {
        // LA prueba de ST-208. Cargar deja los elementos SIN bytes; guardarlos
        // así no puede significar "quítales la tapa".
        _store.SaveItems([Song("Música/a.mp3", [1, 2, 3])]);
        Assert.Equal(1, CoverFilesOnDisk());

        IReadOnlyList<LibraryItem> loaded = _store.LoadItems();
        Assert.Null(loaded[0].Metadata?.CoverArtData);   // no se cargó: ese es el punto
        Assert.True(loaded[0].HasCover);                 // pero se sabe que la tiene

        _store.SaveItems(loaded);

        Assert.Equal(1, CoverFilesOnDisk());
        Assert.True(_store.LoadItems()[0].HasCover);
        Assert.Equal([1, 2, 3], _store.ReadCover(_store.LoadItems()[0]));
    }

    [Fact]
    public void CargarYGuardarConservaLaRutaAnotadaEnElCatalogo()
    {
        // Si la ruta se perdiera, la app de macOS —que lee ese mismo campo—
        // abriría la biblioteca sin tapas.
        _store.SaveItems([Song("Música/a.mp3", [1])]);

        _store.SaveItems(_store.LoadItems());

        PersistedLibraryItem persisted = LibraryCatalogStore.Load(_root).Items.Single();
        Assert.False(string.IsNullOrEmpty(persisted.CoverRelativePath));
    }

    [Fact]
    public void GuardarDiezVecesSeguidasNoBorraNada()
    {
        _store.SaveItems([Song("Música/a.mp3", [4, 5])]);

        for (int round = 0; round < 10; round++) _store.SaveItems(_store.LoadItems());

        Assert.Equal(1, CoverFilesOnDisk());
        Assert.Equal([4, 5], _store.ReadCover(_store.LoadItems()[0]));
    }

    [Fact]
    public void QuitarLaCaratulaSiBorraElArchivo()
    {
        // Lo contrario también tiene que seguir funcionando: cuando el usuario
        // quita la tapa, se va de verdad.
        _store.SaveItems([Song("Música/a.mp3", [1])]);

        LibraryItem item = _store.LoadItems().Single();
        _store.RemoveCover(item);
        _store.SaveItems([item]);

        Assert.Equal(0, CoverFilesOnDisk());
        Assert.False(_store.LoadItems()[0].HasCover);
        Assert.Null(_store.ReadCover(_store.LoadItems()[0]));
    }

    [Fact]
    public void PonerUnaCaratulaNuevaLaEscribeYAnotaSuHash()
    {
        _store.SaveItems([Song("Música/a.mp3")]);

        LibraryItem item = _store.LoadItems().Single();
        Assert.False(item.HasCover);

        _store.WriteCover(item, [7, 7, 7]);
        _store.SaveItems([item]);

        LibraryItem reloaded = _store.LoadItems().Single();
        Assert.True(reloaded.HasCover);
        Assert.Equal([7, 7, 7], _store.ReadCover(reloaded));
        Assert.Equal(CoverArtHash.Of([7, 7, 7]), reloaded.CoverHash);
    }

    [Fact]
    public void CambiarLaCaratulaCambiaElHash()
    {
        _store.SaveItems([Song("Música/a.mp3", [1])]);
        LibraryItem item = _store.LoadItems().Single();
        string? before = item.CoverHash;

        _store.WriteCover(item, [2, 2]);
        _store.SaveItems([item]);

        LibraryItem reloaded = _store.LoadItems().Single();
        Assert.NotEqual(before, reloaded.CoverHash);
        Assert.Equal([2, 2], _store.ReadCover(reloaded));
    }

    [Fact]
    public void UnCatalogoSinHashSeLeeYSeLoCalculaAlLeerElArchivo()
    {
        // Migración transparente: los catálogos viejos —y los que escribe la Mac
        // hasta que adopte el campo— no traen `coverHash`. Ausente es "no se
        // sabe", nunca "sin carátula".
        _store.SaveItems([Song("Música/a.mp3", [9])]);

        PersistedLibrary catalog = LibraryCatalogStore.Load(_root);
        catalog.Items[0].CoverHash = null;
        LibraryCatalogStore.Save(_root, catalog);

        LibraryItem item = _store.LoadItems().Single();
        Assert.True(item.HasCover);
        Assert.Null(item.CoverHash);

        // Al leerla, se calcula y queda anotado para el próximo guardado.
        Assert.Equal([9], _store.ReadCover(item));
        Assert.Equal(CoverArtHash.Of([9]), item.CoverHash);
    }

    [Fact]
    public void SinCaratulaNoHayHash()
    {
        // La invariante que fijó la maestra: sin ruta tampoco hay hash.
        _store.SaveItems([Song("Música/a.mp3")]);

        PersistedLibraryItem persisted = LibraryCatalogStore.Load(_root).Items.Single();

        Assert.Null(persisted.CoverRelativePath);
        Assert.Null(persisted.CoverHash);
    }

    [Fact]
    public void ElHashSeEscribeEnMayusculasYSinSeparadores()
    {
        _store.SaveItems([Song("Música/a.mp3", [1, 2, 3])]);

        string json = File.ReadAllText(LibraryCatalogStore.CatalogPath(_root));
        string hash = CoverArtHash.Of([1, 2, 3]);

        Assert.Equal(64, hash.Length);
        Assert.Equal(hash.ToUpperInvariant(), hash);
        Assert.Contains($"\"coverHash\":\"{hash}\"", json);
    }

    [Fact]
    public void LeerLaCaratulaDeUnElementoSinEllaDaNadaYNoLanza() =>
        Assert.Null(_store.ReadCover(Song("Música/a.mp3")));

    [Fact]
    public void UnaRutaAnotadaQueYaNoExisteNoInventaCaratula()
    {
        _store.SaveItems([Song("Música/a.mp3", [1])]);
        LibraryItem item = _store.LoadItems().Single();

        File.Delete(Path.Combine(_root, item.CoverRelativePath!.Replace('/', Path.DirectorySeparatorChar)));

        Assert.Null(_store.ReadCover(item));
    }
}
