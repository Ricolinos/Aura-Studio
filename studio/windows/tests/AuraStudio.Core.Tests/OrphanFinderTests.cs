using System.Text;
using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El detector de huérfanos en <c>.preparados/</c> y <c>.portadas/</c>
/// (ST-245, B5): lo que nadie del catálogo referencia.
/// </summary>
public class OrphanFinderTests : IDisposable
{
    private readonly string _root;

    public OrphanFinderTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "AuraHuerfanos-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ }
    }

    private string WriteFile(string relative)
    {
        string path = Path.Combine(_root, relative.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "x");
        return path;
    }

    [Fact]
    public void UnPreparadoSinNingunElementoQueLoUseEsHuerfano()
    {
        string huerfano = WriteFile(CatalogPath.PreparedRelative(Guid.NewGuid(), "mpg"));

        OrphanScanResult scan = OrphanFinder.Scan(_root, []);

        Assert.Equal([huerfano], [.. scan.Files.Select(f => f.AbsolutePath)]);
    }

    [Fact]
    public void UnPreparadoReferenciadoPorUnElementoNoEsHuerfano()
    {
        Guid id = Guid.NewGuid();
        string preparado = WriteFile(CatalogPath.PreparedRelative(id, "mpg"));
        var item = new LibraryItem
        {
            Id = id, Kind = LibraryItemKind.Video, Storage = ItemStorageRules.ReferenceValue,
            SourcePath = "afuera.mkv", PreparedPath = preparado
        };

        OrphanScanResult scan = OrphanFinder.Scan(_root, [item]);

        Assert.Empty(scan.Files);
    }

    [Fact]
    public void UnaCaratulaReferenciadaNoEsHuerfana()
    {
        Guid id = Guid.NewGuid();
        string caratula = WriteFile(CatalogPath.CoverRelative(id));
        var item = new LibraryItem
        {
            Id = id, Kind = LibraryItemKind.Music, Storage = ItemStorageRules.ReferenceValue,
            SourcePath = "afuera.mp3", CoverRelativePath = CatalogPath.CoverRelative(id)
        };

        OrphanScanResult scan = OrphanFinder.Scan(_root, [item]);

        Assert.Empty(scan.Files);
    }

    [Fact]
    public void ElPosterDeUnVideoPreparadoNoEsHuerfano()
    {
        Guid id = Guid.NewGuid();
        string preparado = WriteFile(CatalogPath.PreparedRelative(id, "mpg"));
        string poster = Path.ChangeExtension(preparado, ".jpg");
        File.WriteAllText(poster, "x");

        var item = new LibraryItem
        {
            Id = id, Kind = LibraryItemKind.Video, Storage = ItemStorageRules.ReferenceValue,
            SourcePath = "afuera.mkv", PreparedPath = preparado
        };

        OrphanScanResult scan = OrphanFinder.Scan(_root, [item]);

        Assert.Empty(scan.Files);
    }

    /// <summary>
    /// La música copiada nunca vive en <c>.preparados/</c>
    /// (<c>PreparedPath == SourcePath</c>, ST-241): un archivo que por
    /// coincidencia se llame igual al valor de <c>PreparedPath</c> de un
    /// elemento así <b>sigue siendo huérfano de verdad</b>.
    /// </summary>
    [Fact]
    public void UnPreparadoQueCoincideConMusicaCopiadaSigueSiendoHuerfano()
    {
        string file = WriteFile("Música/Artista/Álbum/Canción.mp3");
        string huerfanoConElMismoNombre = WriteFile(".preparados/Canción.mp3");

        var item = new LibraryItem
        {
            Id = Guid.NewGuid(), Kind = LibraryItemKind.Music, Storage = ItemStorageRules.CopyValue,
            SourcePath = file, PreparedPath = file
        };

        OrphanScanResult scan = OrphanFinder.Scan(_root, [item]);

        Assert.Equal([huerfanoConElMismoNombre], [.. scan.Files.Select(f => f.AbsolutePath)]);
    }

    /// <summary>
    /// El caso que pidió el coordinador: un preparado nombrado por el archivo
    /// de origen (el nombrado viejo, <see cref="StagingPaths.Resolve"/>,
    /// todavía en uso hasta B4) con acento, escrito en el catálogo en una
    /// forma Unicode y en disco en la otra. Comparar crudo lo marcaría como
    /// huérfano sin serlo, y se borraría un preparado en uso.
    /// </summary>
    [Fact]
    public void UnPreparadoConAcentoEnOtraFormaUnicodeNoQuedaComoHuerfano()
    {
        string nfd = "Ré".Normalize(NormalizationForm.FormD);
        string preparadoEnDisco = WriteFile($".preparados/{nfd}.mp3");

        // El catálogo (y por lo tanto item.PreparedPath) trae la forma NFC,
        // como escribe CatalogPath.Canonical.
        string preparadoSegunCatalogo = Path.Combine(_root, ".preparados", "Ré.mp3");
        Assert.NotEqual(preparadoEnDisco, preparadoSegunCatalogo);

        var item = new LibraryItem
        {
            Id = Guid.NewGuid(), Kind = LibraryItemKind.Music, Storage = ItemStorageRules.ReferenceValue,
            SourcePath = "afuera/Ré.mp3", PreparedPath = preparadoSegunCatalogo
        };

        OrphanScanResult scan = OrphanFinder.Scan(_root, [item]);

        Assert.Empty(scan.Files);
    }

    [Fact]
    public void ElTotalSumaLosBytesDeLosHuerfanos()
    {
        string a = WriteFile(CatalogPath.PreparedRelative(Guid.NewGuid(), "mpg"));
        File.WriteAllText(a, new string('a', 100));
        string b = WriteFile(CatalogPath.CoverRelative(Guid.NewGuid()));
        File.WriteAllText(b, new string('b', 50));

        OrphanScanResult scan = OrphanFinder.Scan(_root, []);

        Assert.Equal(2, scan.Count);
        Assert.Equal(150, scan.TotalBytes);
    }

    [Fact]
    public void DeleteBorraLoQueEncontroElEscaneo()
    {
        string huerfano = WriteFile(CatalogPath.PreparedRelative(Guid.NewGuid(), "mpg"));
        OrphanScanResult scan = OrphanFinder.Scan(_root, []);

        OrphanFinder.Delete(scan);

        Assert.False(File.Exists(huerfano));
    }

    [Fact]
    public void UnaBibliotecaSinCarpetasTecnicasNoRevientaYNoEncuentraNada()
    {
        OrphanScanResult scan = OrphanFinder.Scan(_root, []);

        Assert.Empty(scan.Files);
    }
}
