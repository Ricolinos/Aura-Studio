using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Las rutas del catálogo se escriben y se comparan en <b>NFC</b> (addendum de
/// ST-241, contrato ampliado para las dos plataformas).
///
/// <para>"Música" se puede escribir de dos maneras que se ven idénticas:
/// compuesta —una sola letra acentuada— o descompuesta —la letra y el acento por
/// separado—. Para el catálogo son dos rutas distintas, y el modo de falla es
/// silencioso: la biblioteca copiada del dueño se leería como referenciada y
/// nadie vería un error.</para>
/// </summary>
public class CatalogPathNormalizationTests : IDisposable
{
    /// <summary>"Música" con la ené acentuada descompuesta, como la escribe macOS.</summary>
    private const string Descompuesta = "Mu\u0301sica";

    /// <summary>La misma palabra compuesta, como la escribe Windows.</summary>
    private const string Compuesta = "Música";

    private readonly string _root;

    public CatalogPathNormalizationTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "AuraNfc-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ }
    }

    [Fact]
    public void LasDosFormasSonDistintasComoTexto()
    {
        // Si esto fallara, el resto de las pruebas no probaría nada.
        Assert.NotEqual(Descompuesta, Compuesta);
        Assert.Equal(Compuesta, CatalogPath.Normalize(Descompuesta));
    }

    // MARK: - Escribir

    [Fact]
    public void UnaRutaRelativaSeEscribeEnFormaCompuesta()
    {
        string almacenada = CatalogPath.Store(_root, Path.Combine(_root, Descompuesta, "Artista", "a.mp3"));

        Assert.Equal(Compuesta + "/Artista/a.mp3", almacenada);
    }

    /// <summary>
    /// La vuelta completa: se guarda una ruta descompuesta y lo que queda en el
    /// catálogo —y lo que se relee de él— está en la forma compuesta, con el
    /// `storage` inferido como copia. Sin normalizar, ese mismo elemento se
    /// leería como referenciado.
    /// </summary>
    [Fact]
    public void IdaYVueltaConUnNombreDescompuesto()
    {
        var store = new LibraryStore(_root);
        string absoluta = Path.Combine(_root, Descompuesta, "Artista", "a.mp3");

        store.SaveItems([new LibraryItem
        {
            Id = Guid.NewGuid(),
            Kind = LibraryItemKind.Music,
            SourcePath = absoluta
        }]);

        // Contra lo que quedó ESCRITO en el catálogo, no contra lo que devuelve
        // la carga: si solo se mirara la carga, una normalización al leer taparía
        // el defecto y la Mac seguiría recibiendo la forma descompuesta.
        PersistedLibraryItem guardado = LibraryCatalogStore.Load(_root).Items[0];

        Assert.Equal(Compuesta + "/Artista/a.mp3", guardado.SourceRelativePath);
        Assert.NotEqual(Descompuesta + "/Artista/a.mp3", guardado.SourceRelativePath);
        Assert.Equal("copy", guardado.Storage);

        LibraryItem recargado = store.LoadItems()[0];

        Assert.Equal(ItemStorage.Copy, recargado.StorageKind);
        Assert.Equal("copy", recargado.Storage);
    }

    /// <summary>
    /// Una ruta <b>absoluta</b> no se normaliza. En Windows el nombre en disco es
    /// la secuencia exacta de caracteres con la que se creó: cambiarle la forma a
    /// la ruta de un archivo del usuario sería no encontrarlo.
    /// </summary>
    [Fact]
    public void UnaRutaAbsolutaSeGuardaSinTocar()
    {
        string afuera = Path.Combine(Path.GetTempPath(), "AjenoALaBiblioteca", Descompuesta, "a.mp3");

        Assert.Equal(afuera, CatalogPath.Store(_root, afuera));
        Assert.Equal(afuera, CatalogPath.Canonical(afuera));
    }

    // MARK: - Comparar

    [Fact]
    public void DosRutasIgualesEnDistintaFormaSonLaMisma()
    {
        Assert.True(CatalogPath.SameStoredPath(Descompuesta + "/a.mp3", Compuesta + "/a.mp3"));

        // Y el separador y las mayúsculas tampoco las separan.
        Assert.True(CatalogPath.SameStoredPath(Descompuesta + "\\A.MP3", Compuesta + "/a.mp3"));

        Assert.False(CatalogPath.SameStoredPath(Compuesta + "/a.mp3", Compuesta + "/b.mp3"));
    }

    // MARK: - Resolver la carpeta del medio

    /// <summary>
    /// La carpeta que ya está se <b>reusa</b>, aunque esté escrita en la otra
    /// forma. Sin esto, Windows crearía una segunda "Música" al lado de la que
    /// creó la Mac: dos carpetas que se ven iguales y la biblioteca partida en
    /// dos.
    /// </summary>
    [Fact]
    public void SeReusaLaCarpetaQueYaEstaAunqueVengaDescompuesta()
    {
        string existente = Path.Combine(_root, Descompuesta);

        Assert.Equal(existente,
            MediaRoots.Directory(_root, LibraryItemKind.Music, _ => [existente]));
    }

    [Fact]
    public void SinCarpetaSeProponeElNombreCanonico()
    {
        Assert.Equal(Path.Combine(_root, Compuesta),
            MediaRoots.Directory(_root, LibraryItemKind.Music, _ => []));

        // Y una biblioteca recién elegida, sin ninguna carpeta todavía, tampoco
        // es un error.
        Assert.Equal(Path.Combine(_root, "Videos"),
            MediaRoots.Directory(_root, LibraryItemKind.Video));
    }

    [Fact]
    public void CadaTipoDeMedioTieneSuCarpetaYLoNoSoportadoNoTieneNinguna()
    {
        Assert.Equal("Música", MediaRoots.DirectoryName(LibraryItemKind.Music));
        Assert.Equal("Imágenes", MediaRoots.DirectoryName(LibraryItemKind.Photo));
        Assert.Equal("Videos", MediaRoots.DirectoryName(LibraryItemKind.Video));

        // No se copia lo que no se sabe manejar, y devolver una carpeta
        // cualquiera sería empezar a llenarla.
        Assert.Throws<ArgumentOutOfRangeException>(
            () => MediaRoots.DirectoryName(LibraryItemKind.Unsupported));
    }
}
