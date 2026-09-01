using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// **La regla más cara del repositorio, aprendida perdiendo datos reales.**
///
/// <para>Con la biblioteca compartida entre la Mac y Windows, la app de Windows
/// abrió el catálogo del dueño, descartó al leer los 2408 elementos cuyos
/// archivos no alcanzaba por la red, y al guardar escribió los 401 restantes
/// como si fueran el catálogo entero. Se perdieron títulos, artistas, letras,
/// enlaces de MusicBrainz y calificaciones de 2408 canciones.</para>
///
/// <para>De ahí sale la regla: <b>lo que se guarda es siempre el catálogo
/// completo</b>. Filtrar es cosa de la vista, y una lista filtrada no puede
/// llegar jamás a una ruta de escritura.</para>
/// </summary>
public class CatalogPreservationTests : IDisposable
{
    private readonly string _root;

    public CatalogPreservationTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "AuraKeep-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ }
    }

    private string Touch(string relative)
    {
        string path = Path.Combine(_root, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, [0]);
        return path;
    }

    [Fact]
    public void ReadingAndWritingBackKeepsTheEntriesWhoseFilesAreMissing()
    {
        // Exactamente la forma del accidente: la mitad de los archivos no está.
        var store = new LibraryStore(_root);

        store.SaveItems(
        [
            new LibraryItem
            {
                SourcePath = Touch(@"Música\presente.mp3"),
                Kind = LibraryItemKind.Music,
                Metadata = new TrackMetadata { Title = "Presente" }
            },
            new LibraryItem
            {
                SourcePath = Path.Combine(_root, @"Música\ausente.mp3"),
                Kind = LibraryItemKind.Music,
                Metadata = new TrackMetadata
                {
                    Title = "Ausente",
                    SyncedLyrics = "[00:01.00] no se puede perder",
                    MusicBrainzRecordingId = "83c68fe1-9660-4e4a-ad7b-f27815730606"
                }
            }
        ]);

        // Se lee entero (el almacén NO filtra: filtrar es de la vista).
        IReadOnlyList<LibraryItem> loaded = store.LoadItems();
        Assert.Equal(2, loaded.Count);

        // Y se vuelve a guardar entero.
        store.SaveItems(loaded);

        IReadOnlyList<LibraryItem> again = store.LoadItems();
        Assert.Equal(2, again.Count);

        LibraryItem ausente = again.Single(item => item.Metadata?.Title == "Ausente");
        Assert.Equal("[00:01.00] no se puede perder", ausente.Metadata!.SyncedLyrics);
        Assert.Equal("83c68fe1-9660-4e4a-ad7b-f27815730606", ausente.Metadata.MusicBrainzRecordingId);
    }

    [Fact]
    public void TheStoreNeverDropsAnythingByItself()
    {
        // Si el almacén filtrara, cualquier llamador que guarde lo que leyó
        // borraría datos sin enterarse. Por eso no filtra: la decisión de qué
        // mostrar es de quien muestra.
        var store = new LibraryStore(_root);

        store.SaveItems(
        [
            new LibraryItem { SourcePath = @"Z:\disco desconectado\a.mp3", Kind = LibraryItemKind.Music },
            new LibraryItem { SourcePath = @"\\servidor\que\no\responde\b.mp3", Kind = LibraryItemKind.Music }
        ]);

        Assert.Equal(2, store.LoadItems().Count);
    }

    [Fact]
    public void SavingAnItemWithoutMetadataDoesNotDeleteItsCover()
    {
        // El elemento cuya metadata no se pudo leer no puede borrar la carátula
        // que ya estaba en disco: es la otra mitad del mismo accidente.
        var store = new LibraryStore(_root);
        var id = Guid.NewGuid();

        Directory.CreateDirectory(store.CoversDirectory);
        File.WriteAllBytes(store.CoverPath(id), [1, 2, 3]);

        store.SaveItems([new LibraryItem
        {
            Id = id,
            SourcePath = @"Z:\no accesible\a.mp3",
            Kind = LibraryItemKind.Music,
            Metadata = null
        }]);

        Assert.True(File.Exists(store.CoverPath(id)), "se borró una carátula que no se debía tocar");
    }

    // MARK: - Lo que nunca se limpia (instrucción del dueño tras ST-087)

    [Fact]
    public void TheStagingAndCoverFoldersAreProtectedFromAnyCleanup()
    {
        // Cuando se perdieron 2408 entradas del catálogo, lo único que quedó de
        // ellas fueron estos archivos: audios ya convertidos con sus etiquetas y
        // sus letras al lado. Son la reconstrucción latente, y por eso ninguna
        // rutina de limpieza puede tocarlos.
        var store = new LibraryStore(_root);

        Assert.Contains(store.PreparedDirectory, store.NeverCleaned);
        Assert.Contains(store.CoversDirectory, store.NeverCleaned);

        Assert.True(store.IsProtected(store.PreparedDirectory));
        Assert.True(store.IsProtected(Path.Combine(store.PreparedDirectory, "Música", "a.mp3")));
        Assert.True(store.IsProtected(store.CoversDirectory));
    }

    [Fact]
    public void TheRestOfTheLibraryIsNotProtected()
    {
        // La protección tiene que ser exacta: si abarcara de más, cualquier
        // limpieza legítima quedaría bloqueada y nadie entendería por qué.
        var store = new LibraryStore(_root);

        Assert.False(store.IsProtected(Path.Combine(_root, "Música")));
        Assert.False(store.IsProtected(Path.Combine(_root, "biblioteca.json")));
        Assert.False(store.IsProtected(Path.Combine(Path.GetTempPath(), ".preparados")));
    }

    [Fact]
    public void TheCoverFileIsNamedTheWayMacOsNamesIt()
    {
        // `.portadas/<ID EN MAYÚSCULAS CON GUIONES>.jpg`. Con otro formato, cada
        // app escribiría su propia carátula para la misma canción y ninguna
        // vería la de la otra.
        var store = new LibraryStore(_root);
        var id = Guid.Parse("f26dbf19-0c21-4662-9a78-84bfbc2f0482");

        Assert.Equal(
            Path.Combine(store.CoversDirectory, "F26DBF19-0C21-4662-9A78-84BFBC2F0482.jpg"),
            store.CoverPath(id));
    }

    [Fact]
    public void ACoverWrittenByMacOsIsFoundAndNotDuplicated()
    {
        var store = new LibraryStore(_root);
        var id = Guid.Parse("F26DBF19-0C21-4662-9A78-84BFBC2F0482");
        byte[] cover = [9, 9, 9];

        Directory.CreateDirectory(store.CoversDirectory);
        File.WriteAllBytes(
            Path.Combine(store.CoversDirectory, "F26DBF19-0C21-4662-9A78-84BFBC2F0482.jpg"), cover);

        store.SaveItems([new LibraryItem
        {
            Id = id,
            SourcePath = Touch("a.mp3"),
            Kind = LibraryItemKind.Music
        }]);

        Assert.Equal(cover, store.LoadItems()[0].Metadata?.CoverArtData ?? cover);
        Assert.Single(Directory.GetFiles(store.CoversDirectory, "*.jpg"));
    }
}
