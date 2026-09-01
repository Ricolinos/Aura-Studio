using System.Text.Json;
using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La forma canónica de las rutas del catálogo compartido (ST-102 / ST-107).
///
/// <para>Lo que se prueba acá tiene un modo de falla <b>silencioso</b>: un
/// elemento cuya ruta no resuelve se omite al leer, así que 401 rutas rotas se
/// ven exactamente igual que una biblioteca vacía. Fue lo que le pasó a la app
/// de macOS con el catálogo real, y es el mismo par de estados indistinguibles
/// que costó 2408 entradas en ST-087.</para>
/// </summary>
public sealed class CatalogPathTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "aura-cat-" + Guid.NewGuid().ToString("N"));

    public CatalogPathTests() => Directory.CreateDirectory(_root);

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch (IOException) { }
    }

    // MARK: - Separadores

    [Fact]
    public void WhatIsStoredNeverCarriesABackslash()
    {
        // Del otro lado, "Música\Soda Stereo\a.mp3" es UN componente con barras
        // adentro, no una ruta: el archivo no existe y el elemento desaparece.
        string stored = CatalogPath.Store(_root, Path.Combine(_root, "Música", "Soda Stereo", "a.mp3"));

        Assert.Equal("Música/Soda Stereo/a.mp3", stored);
        Assert.DoesNotContain('\\', stored);
    }

    [Fact]
    public void CanonicalIsIdempotent()
    {
        Assert.Equal("a/b/c.mp3", CatalogPath.Canonical(@"a\b\c.mp3"));
        Assert.Equal("a/b/c.mp3", CatalogPath.Canonical("a/b/c.mp3"));
        Assert.Equal("", CatalogPath.Canonical(null));
    }

    [Fact]
    public void SomethingOutsideTheLibraryStaysAbsoluteAndUntouched()
    {
        // Traducir sus separadores no la haría portable —una ruta absoluta de
        // Windows no significa nada en la Mac— y sí podría romperla acá.
        const string outside = @"D:\Música suelta\a.mp3";

        Assert.Equal(outside, CatalogPath.Store(_root, outside));
        Assert.Equal(outside, CatalogPath.Canonical(outside));
    }

    [Fact]
    public void ReadingAcceptsBothSeparators()
    {
        // Escribir es canónico; leer es tolerante. Un catálogo viejo, escrito
        // por esta misma app antes del arreglo, tiene que seguir abriendo.
        string expected = Path.Combine(_root, "Música", "a.mp3");

        Assert.Equal(expected, CatalogPath.Resolve(_root, "Música/a.mp3"));
        Assert.Equal(expected, CatalogPath.Resolve(_root, @"Música\a.mp3"));
    }

    // MARK: - Nombre de la carátula

    [Fact]
    public void TheCoverIsNamedTheWayTheMacNamesIt()
    {
        var id = Guid.Parse("f26dbf19-0c21-4a3b-9d5e-1a2b3c4d5e6f");

        Assert.Equal("F26DBF19-0C21-4A3B-9D5E-1A2B3C4D5E6F.jpg", CatalogPath.CoverFileName(id));
        Assert.Equal(".portadas/F26DBF19-0C21-4A3B-9D5E-1A2B3C4D5E6F.jpg", CatalogPath.CoverRelative(id));
    }

    [Fact]
    public void TheCatalogAndTheFileOnDiskNameTheCoverTheSame()
    {
        // El bug que ST-087 dejó a medias: arregló el archivo que se escribe en
        // disco y no el nombre que se anota en el catálogo. Windows no lo notó
        // nunca porque lee la carátula por el id, no por ese campo; macOS sí,
        // y vio 13 carátulas apuntando a nada con la imagen ahí al lado.
        var store = new LibraryStore(_root);
        var id = Guid.NewGuid();

        Assert.Equal(
            Path.Combine(_root, CatalogPath.CoverRelative(id).Replace('/', Path.DirectorySeparatorChar)),
            store.CoverPath(id));
    }

    // MARK: - Ida y vuelta con la forma exacta de macOS

    [Fact]
    public void ACatalogWrittenHereHasTheShapeTheMacExpects()
    {
        var store = new LibraryStore(_root);

        Guid id = Guid.NewGuid();
        string source = Path.Combine(_root, "Música", "Soda Stereo", "Signos", "01 Persiana.mp3");
        Directory.CreateDirectory(Path.GetDirectoryName(source)!);
        File.WriteAllText(source, "audio");

        store.SaveItems([
            new LibraryItem
            {
                Id = id,
                SourcePath = source,
                PreparedPath = Path.Combine(_root, ".preparados", "01 Persiana.mp3"),
                Kind = LibraryItemKind.Music,
                Status = LibraryItemStatus.Ready,
                Metadata = new TrackMetadata
                {
                    Title = "Persiana Americana", Artist = "Soda Stereo", Album = "Signos",
                    CoverArtData = [1, 2, 3]
                }
            }
        ]);

        using JsonDocument document = JsonDocument.Parse(
            File.ReadAllText(Path.Combine(_root, "biblioteca.json")));

        JsonElement item = document.RootElement.GetProperty("items")[0];

        Assert.Equal("Música/Soda Stereo/Signos/01 Persiana.mp3", item.GetProperty("sourceRelativePath").GetString());
        Assert.Equal(".preparados/01 Persiana.mp3", item.GetProperty("preparedRelativePath").GetString());
        Assert.Equal(CatalogPath.CoverRelative(id), item.GetProperty("coverRelativePath").GetString());
    }

    [Fact]
    public void EveryPathInTheWrittenCatalogResolvesToSomethingThatExists()
    {
        // La comprobación que de verdad importa: la Mac omite lo que no
        // resuelve, en silencio. Acá se verifica contra el disco de verdad.
        var store = new LibraryStore(_root);
        var items = new List<LibraryItem>();

        foreach (string name in (string[])["a.mp3", "b.mp3", "c.mp3"])
        {
            string path = Path.Combine(_root, "Música", "Artista", "Álbum", name);
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, "audio");

            items.Add(new LibraryItem
            {
                SourcePath = path,
                Kind = LibraryItemKind.Music,
                Status = LibraryItemStatus.Ready,
                Metadata = new TrackMetadata { Title = name, Artist = "Artista", Album = "Álbum" }
            });
        }

        store.SaveItems(items);

        using JsonDocument document = JsonDocument.Parse(
            File.ReadAllText(Path.Combine(_root, "biblioteca.json")));

        foreach (JsonElement item in document.RootElement.GetProperty("items").EnumerateArray())
        {
            string stored = item.GetProperty("sourceRelativePath").GetString()!;

            // Tal como lo pegaría la Mac: la raíz más la ruta guardada, sin
            // traducir nada.
            Assert.True(File.Exists(Path.Combine(_root, stored)), stored);
        }
    }

    [Fact]
    public void ACoverSavedByAnOlderWindowsVersionIsNotLost()
    {
        // La escribió esta misma app antes de ST-087, con el hexadecimal pelado.
        // Sin recuperarla, la imagen queda ahí al lado e invisible para las dos
        // apps, y la siguiente pasada la da por inexistente.
        var id = Guid.Parse("11111111-1111-4111-8111-111111111111");
        string source = Path.Combine(_root, "Música", "a.mp3");
        Directory.CreateDirectory(Path.GetDirectoryName(source)!);
        File.WriteAllText(source, "audio");

        Directory.CreateDirectory(Path.Combine(_root, ".portadas"));
        File.WriteAllBytes(Path.Combine(_root, ".portadas", id.ToString("N") + ".jpg"), [7, 7, 7]);

        File.WriteAllText(Path.Combine(_root, "biblioteca.json"), """
        {"version":1,"items":[{"id":"11111111-1111-4111-8111-111111111111",
        "sourceRelativePath":"Música/a.mp3","kind":"music","status":"ready",
        "metadata":{"title":"A","artist":"B","album":"C"}}],"playlists":[]}
        """);

        var store = new LibraryStore(_root);
        LibraryItem item = Assert.Single(store.LoadItems());

        Assert.Equal<byte[]>([7, 7, 7], item.Metadata!.CoverArtData!);

        // Y al guardar queda con el nombre canónico, sin que nadie migre nada.
        store.SaveItems([item]);
        Assert.True(File.Exists(store.CoverPath(id)));
    }

    [Fact]
    public void ACatalogWrittenWithBackslashesStillLoadsHere()
    {
        // El catálogo real del dueño ya tiene rutas con `\`: el arreglo no
        // puede dejar ilegible lo que esta misma app escribió ayer.
        string source = Path.Combine(_root, "Música", "a.mp3");
        Directory.CreateDirectory(Path.GetDirectoryName(source)!);
        File.WriteAllText(source, "audio");

        File.WriteAllText(Path.Combine(_root, "biblioteca.json"), """
        {"version":1,"items":[{"id":"11111111-1111-4111-8111-111111111111",
        "sourceRelativePath":"Música\\a.mp3","kind":"music","status":"ready"}],"playlists":[]}
        """);

        LibraryItem item = Assert.Single(new LibraryStore(_root).LoadItems());
        Assert.Equal(source, item.SourcePath);
    }

    [Fact]
    public void LoadingAndSavingCanonizesAnOldCatalogOnItsOwn()
    {
        // Efecto secundario deseable: el primer guardado deja el catálogo
        // compartido en la forma canónica, sin que nadie tenga que migrarlo.
        string source = Path.Combine(_root, "Música", "a.mp3");
        Directory.CreateDirectory(Path.GetDirectoryName(source)!);
        File.WriteAllText(source, "audio");

        File.WriteAllText(Path.Combine(_root, "biblioteca.json"), """
        {"version":1,"items":[{"id":"11111111-1111-4111-8111-111111111111",
        "sourceRelativePath":"Música\\a.mp3","kind":"music","status":"ready"}],"playlists":[]}
        """);

        var store = new LibraryStore(_root);
        store.SaveItems(store.LoadItems());

        using JsonDocument document = JsonDocument.Parse(
            File.ReadAllText(Path.Combine(_root, "biblioteca.json")));

        Assert.Equal("Música/a.mp3",
            document.RootElement.GetProperty("items")[0].GetProperty("sourceRelativePath").GetString());
    }
}
