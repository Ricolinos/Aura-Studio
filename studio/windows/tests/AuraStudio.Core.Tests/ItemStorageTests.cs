using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El contrato de <c>storage</c> y el nombrado de <c>.preparados/</c> (ST-241,
/// fijado con la Mac en ST-221). Son reglas puras: no tocan disco.
/// </summary>
public class ItemStorageTests
{
    // MARK: - Qué significa lo que trae el catálogo

    [Theory]
    [InlineData("copy", ItemStorage.Copy)]
    [InlineData("COPY", ItemStorage.Copy)]
    [InlineData("  copy  ", ItemStorage.Copy)]
    [InlineData("reference", ItemStorage.Reference)]
    public void LosDosValoresDelContratoSignificanLoQueDicen(string raw, ItemStorage expected) =>
        Assert.Equal(expected, ItemStorageRules.Interpret(raw));

    /// <summary>
    /// Todo lo que no se entienda es "referencia". Equivocarse hacia referencia
    /// hace que Studio toque de menos; hacia copia, que toque archivos ajenos —
    /// y de ese error no se vuelve.
    /// </summary>
    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("alias")]
    [InlineData("copia")]
    public void LoQueNoSeEntiendeEsReferencia(string? raw) =>
        Assert.Equal(ItemStorage.Reference, ItemStorageRules.Interpret(raw));

    // MARK: - La inferencia

    [Theory]
    [InlineData("Música/Artista/Album/a.mp3")]
    [InlineData("Imágenes/2024/foto.jpg")]
    [InlineData("Videos/pelicula.mkv")]
    [InlineData("música/a.mp3")]
    [InlineData("Música\\Artista\\a.mp3")]
    public void SeInfiereCopiaSoloBajoLasTresRaicesDeLaBiblioteca(string stored) =>
        Assert.Equal(ItemStorage.Copy, ItemStorageRules.Infer(stored));

    /// <summary>
    /// La Mac escribe los nombres acentuados descompuestos (`Mu` + acento
    /// combinante) y Windows compuestos. Sin normalizar, "Música" del catálogo
    /// de la Mac no sería "Música" acá y toda la biblioteca copiada se leería
    /// como referenciada — en silencio, que es el peor modo de fallar.
    /// </summary>
    [Fact]
    public void LaMusicaDeLaMacSeReconoceAunqueVengaDescompuesta()
    {
        const string descompuesta = "Mu\u0301sica/Artista/a.mp3";

        Assert.Equal(ItemStorage.Copy, ItemStorageRules.Infer(descompuesta));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("C:\\Users\\alguien\\Music\\a.mp3")]
    [InlineData("/Users/alguien/Music/a.mp3")]
    [InlineData(".preparados/A.mpg")]
    [InlineData(".portadas/A.jpg")]
    [InlineData("Descargas/a.mp3")]
    [InlineData("../afuera/a.mp3")]
    [InlineData("a.mp3")]
    public void TodoLoDemasSeInfiereReferencia(string? stored) =>
        Assert.Equal(ItemStorage.Reference, ItemStorageRules.Infer(stored));

    // MARK: - Qué se escribe de vuelta

    [Fact]
    public void AusenteSeInfiereYSePersiste()
    {
        Assert.Equal("copy", ItemStorageRules.Resolve(null, "Música/a.mp3"));
        Assert.Equal("reference", ItemStorageRules.Resolve(null, "D:\\Musica\\a.mp3"));
        Assert.Equal("reference", ItemStorageRules.Resolve("   ", "Descargas/a.mp3"));
    }

    /// <summary>
    /// Un valor que esta build no conoce se <b>conserva tal cual</b>. Se
    /// interpreta como referencia, sí, pero interpretar no es reescribir: si una
    /// versión futura de la Mac escribe algo nuevo, normalizarlo acá se lo
    /// borraría al volver a guardar. Es la misma regla que salvó a `coverHash`.
    /// </summary>
    [Fact]
    public void LoQueYaVeniaSeConservaTalCualAunqueNoSeEntienda()
    {
        Assert.Equal("alias", ItemStorageRules.Resolve("alias", "Música/a.mp3"));
        Assert.Equal("COPY", ItemStorageRules.Resolve("COPY", "Descargas/a.mp3"));

        // Y la inferencia no lo pisa: la ruta dice una cosa y el catálogo otra,
        // y manda el catálogo.
        Assert.Equal("reference", ItemStorageRules.Resolve("reference", "Música/a.mp3"));
    }

    // MARK: - El nombre de un preparado

    /// <summary>
    /// <c>&lt;ID en mayúsculas y con guiones&gt;.&lt;ext&gt;</c>, igual que las
    /// carátulas y por lo mismo: con otro formato cada app escribiría su propio
    /// preparado para el mismo elemento y ninguna vería el de la otra.
    /// </summary>
    [Fact]
    public void ElPreparadoSeNombraPorIdentificadorEnMayusculas()
    {
        var id = Guid.Parse("3f2b1c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d");

        Assert.Equal("3F2B1C4D-5E6F-4A7B-8C9D-0E1F2A3B4C5D.mpg",
            CatalogPath.PreparedFileName(id, "mpg"));

        // La extensión se acepta con punto o sin él, y baja a minúsculas.
        Assert.Equal("3F2B1C4D-5E6F-4A7B-8C9D-0E1F2A3B4C5D.jpg",
            CatalogPath.PreparedFileName(id, ".JPG"));

        Assert.Equal("3F2B1C4D-5E6F-4A7B-8C9D-0E1F2A3B4C5D",
            CatalogPath.PreparedFileName(id, null));

        // Y en el catálogo va con "/" y bajo `.preparados`, no con el separador
        // de esta máquina (ST-102).
        Assert.Equal(".preparados/3F2B1C4D-5E6F-4A7B-8C9D-0E1F2A3B4C5D.mpg",
            CatalogPath.PreparedRelative(id, "mpg"));
    }

    /// <summary>
    /// El póster viaja como <c>&lt;ID&gt;.jpg</c> hermano del
    /// <c>&lt;ID&gt;.mpg</c>: misma carpeta, mismo nombre base.
    /// </summary>
    [Fact]
    public void ElPosterEsHermanoDelPreparado()
    {
        var id = Guid.Parse("3f2b1c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d");
        string prepared = StagingPaths.ForItem("X:\\Bib\\.preparados", id, "mpg", exists: _ => false);

        Assert.Equal(
            Path.Combine("X:\\Bib\\.preparados", "3F2B1C4D-5E6F-4A7B-8C9D-0E1F2A3B4C5D.jpg"),
            StagingPaths.PosterFor(prepared));
    }

    /// <summary>
    /// Dos elementos distintos con el mismo nombre de archivo ya no se pelean el
    /// mismo preparado. Es ST-064 resuelto en la raíz: un identificador no se
    /// repite, así que no hay nada que desambiguar con un contador.
    /// </summary>
    [Fact]
    public void DosElementosDistintosNuncaComparteElMismoPreparado()
    {
        const string staging = "X:\\Bib\\.preparados";

        // El mismo nombre de archivo de origen, que es el caso de los duplicados.
        string uno = StagingPaths.ForItem(staging, Guid.NewGuid(), "mpg", exists: _ => false);
        string otro = StagingPaths.ForItem(staging, Guid.NewGuid(), "mpg", exists: _ => false);

        Assert.NotEqual(uno, otro);

        // Y ninguno necesitó un contador para desambiguar: el que se pide es el
        // que se obtiene, aunque la carpeta ya esté llena.
        var id = Guid.NewGuid();
        Assert.Equal(
            Path.Combine(staging, CatalogPath.PreparedFileName(id, "mpg")),
            StagingPaths.ForItem(staging, id, "mpg", exists: _ => true));
    }

    [Fact]
    public void UnPreparadoQueYaEstaNoSeRenombra()
    {
        var id = Guid.NewGuid();
        const string viejo = "X:\\Bib\\.preparados\\canción.mpg";

        // Está en disco: se devuelve tal cual. Cargar la biblioteca no mueve
        // archivos — al preparado lo encuentra el catálogo, no su nombre.
        Assert.Equal(viejo,
            StagingPaths.ForItem("X:\\Bib\\.preparados", id, "mpg", viejo, exists: path => path == viejo));

        // Y si ya no está, el nuevo se nombra por identificador.
        Assert.Equal(
            Path.Combine("X:\\Bib\\.preparados", CatalogPath.PreparedFileName(id, "mpg")),
            StagingPaths.ForItem("X:\\Bib\\.preparados", id, "mpg", viejo, exists: _ => false));
    }
}
