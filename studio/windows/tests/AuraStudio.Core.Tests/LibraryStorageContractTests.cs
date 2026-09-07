using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El contrato de <c>storage</c> visto desde el catálogo en disco (ST-241,
/// fijado con la Mac en ST-221): qué se infiere al cargar, qué se persiste, qué
/// se conserva y qué invariante queda garantizada.
///
/// <para>Es donde se comprueba lo que de verdad importa: que una vuelta
/// completa —cargar, guardar, volver a cargar— no le cambie el significado a
/// nada ni le borre nada a la otra app.</para>
/// </summary>
public class LibraryStorageContractTests : IDisposable
{
    private readonly string _root;
    private readonly LibraryStore _store;

    public LibraryStorageContractTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "AuraStorage-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
        _store = new LibraryStore(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ }
    }

    // MARK: - Inferir una vez y persistir

    [Fact]
    public void UnCatalogoSinElCampoLoInfiereYLoDejaEscrito()
    {
        Save(
            Item(LibraryItemKind.Music, InsideLibrary("Música", "Artista", "a.mp3")),
            Item(LibraryItemKind.Photo, InsideLibrary("Imágenes", "foto.jpg")),
            Item(LibraryItemKind.Music, Path.Combine(Path.GetTempPath(), "AjenoALaBiblioteca", "b.mp3")));

        IReadOnlyList<LibraryItem> loaded = _store.LoadItems();

        Assert.Equal("copy", loaded[0].Storage);
        Assert.Equal("copy", loaded[1].Storage);
        Assert.Equal("reference", loaded[2].Storage);

        Assert.Equal(ItemStorage.Copy, loaded[0].StorageKind);
        Assert.Equal(ItemStorage.Reference, loaded[2].StorageKind);

        // "Una vez": lo inferido queda escrito, así que la próxima carga —y la
        // Mac— leen un dato, no una adivinanza.
        _store.SaveItems(loaded);
        Assert.Equal(["copy", "copy", "reference"], _store.LoadItems().Select(item => item.Storage));
    }

    /// <summary>
    /// Un valor que esta build no conoce se conserva letra por letra. Si una
    /// versión futura de la Mac escribe algo nuevo, abrir la biblioteca en
    /// Windows y guardar no puede borrárselo — es lo mismo que se protegió con
    /// `coverHash`.
    /// </summary>
    [Fact]
    public void UnValorDesconocidoSobreviveALaVuelta()
    {
        LibraryItem item = Item(LibraryItemKind.Music, InsideLibrary("Música", "a.mp3"));
        item.Storage = "alias";
        Save(item);

        LibraryItem loaded = _store.LoadItems()[0];

        Assert.Equal("alias", loaded.Storage);

        // Se interpreta como referencia —lo que no se entiende no autoriza nada—
        // pero eso no lo reescribe.
        Assert.Equal(ItemStorage.Reference, loaded.StorageKind);

        _store.SaveItems(_store.LoadItems());
        Assert.Equal("alias", _store.LoadItems()[0].Storage);
    }

    // MARK: - La música copiada es su propio preparado

    [Fact]
    public void LaMusicaCopiadaTienePreparadoIgualAlOrigen()
    {
        string source = InsideLibrary("Música", "Artista", "a.mp3");
        Save(Item(LibraryItemKind.Music, source));

        LibraryItem loaded = _store.LoadItems()[0];

        // Sin esto habría un segundo archivo en `.preparados/` que es copia de
        // la copia: la biblioteca del dueño pesando el doble sin ganar nada.
        Assert.Equal(loaded.SourcePath, loaded.PreparedPath);
    }

    [Fact]
    public void LaMusicaReferenciadaNoQuedaApuntandoAlArchivoDelUsuario()
    {
        string outside = Path.Combine(Path.GetTempPath(), "AjenoALaBiblioteca", "a.mp3");
        Save(Item(LibraryItemKind.Music, outside));

        LibraryItem loaded = _store.LoadItems()[0];

        Assert.Equal(ItemStorage.Reference, loaded.StorageKind);
        Assert.Null(loaded.PreparedPath);
    }

    /// <summary>
    /// Video y foto sí se convierten, así que su preparado es otro archivo y la
    /// invariante no los toca — ni siquiera estando copiados.
    /// </summary>
    [Fact]
    public void ElVideoCopiadoConservaSuPropioPreparado()
    {
        LibraryItem item = Item(LibraryItemKind.Video, InsideLibrary("Videos", "peli.mkv"));
        item.PreparedPath = Path.Combine(_root, ".preparados", CatalogPath.PreparedFileName(item.Id, "mpg"));
        Save(item);

        LibraryItem loaded = _store.LoadItems()[0];

        Assert.Equal(ItemStorage.Copy, loaded.StorageKind);
        Assert.EndsWith(CatalogPath.PreparedFileName(item.Id, "mpg"), loaded.PreparedPath);
        Assert.NotEqual(loaded.SourcePath, loaded.PreparedPath);
    }

    /// <summary>
    /// Cargar la biblioteca <b>no renombra archivos</b>. Un preparado con el
    /// nombre viejo —el del archivo de origen— sigue como está: al preparado lo
    /// encuentra el catálogo, no su nombre.
    /// </summary>
    [Fact]
    public void CargarNoRenombraUnPreparadoConNombreViejo()
    {
        LibraryItem item = Item(LibraryItemKind.Video, InsideLibrary("Videos", "peli.mkv"));
        string viejo = TouchInsideLibrary(Path.Combine(".preparados", "peli.mpg"));
        item.PreparedPath = viejo;
        Save(item);

        Assert.Equal(viejo, _store.LoadItems()[0].PreparedPath);
        Assert.True(File.Exists(viejo));
    }

    // MARK: - Un original que falta no se borra

    /// <summary>
    /// Paridad con la Mac: un archivo que ya no está se conserva en el catálogo
    /// como <b>no disponible</b>, nunca se borra. El disco puede estar
    /// desconectado, la unidad de red caída o el archivo movido a mano — y en
    /// los tres casos borrarle la entrada al usuario sería perderle la
    /// calificación, la categoría, la letra y la carátula de algo que va a
    /// volver.
    /// </summary>
    [Fact]
    public void UnOriginalQueFaltaSeConservaComoNoDisponible()
    {
        string presente = TouchInsideLibrary(Path.Combine("Música", "esta.mp3"));
        string ausente = Path.Combine(_root, "Música", "no-esta.mp3");

        Save(Item(LibraryItemKind.Music, presente), Item(LibraryItemKind.Music, ausente));

        IReadOnlyList<LibraryItem> items = _store.LoadItems();
        var known = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);

        FileAvailability.Sweep(items, known);

        // La barrida anota, no borra.
        Assert.Equal(2, items.Count);
        Assert.True(known[presente]);
        Assert.False(known[ausente]);

        // Lo que se muestra deja fuera al que falta...
        IReadOnlyList<LibraryItem> available = FileAvailability.Available(items, known);
        Assert.Equal(presente, Assert.Single(available).SourcePath);

        // ...pero guardar el catálogo entero lo conserva, y sigue ahí después de
        // recargar. Guardar la lista filtrada es lo que lo borraría.
        _store.SaveItems(items);
        Assert.Equal(2, _store.LoadItems().Count);
        Assert.Contains(_store.LoadItems(), item => item.SourcePath == ausente);
    }

    // MARK: - Fixture

    private void Save(params LibraryItem[] items) => _store.SaveItems(items);

    private static LibraryItem Item(LibraryItemKind kind, string sourcePath) =>
        new() { Id = Guid.NewGuid(), Kind = kind, SourcePath = sourcePath };

    private string InsideLibrary(params string[] parts) =>
        Path.Combine([_root, .. parts]);

    private string TouchInsideLibrary(string relative)
    {
        string path = Path.Combine(_root, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, [0]);
        return path;
    }
}
