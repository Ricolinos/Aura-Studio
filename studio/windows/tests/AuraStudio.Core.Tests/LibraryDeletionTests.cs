using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Eliminar un elemento (ST-245, B5): modo copia manda el archivo a la
/// Papelera y modo referencia solo lo quita del catálogo; los dos borran
/// preparado y carátula.
/// </summary>
public class LibraryDeletionTests : IDisposable
{
    private readonly string _root;

    public LibraryDeletionTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "AuraEliminar-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ }
    }

    /// <summary>Papelera falsa: registra qué le pidieron mandar, sin tocar la de verdad.</summary>
    private sealed class FakeRecycleBin : IRecycleBin
    {
        public List<string> Sent { get; } = [];
        public bool ShouldFail { get; set; }

        public bool MoveToRecycleBin(string path)
        {
            if (ShouldFail) return false;
            Sent.Add(path);
            return true;
        }
    }

    private string WriteFile(string relative)
    {
        string path = Path.Combine(_root, relative.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "x");
        return path;
    }

    // MARK: - Preview

    [Fact]
    public void ElPreviewCuentaSoloLosBytesDeModoCopia()
    {
        LibraryItem copiado = new()
        {
            Id = Guid.NewGuid(), Kind = LibraryItemKind.Music, Storage = ItemStorageRules.CopyValue,
            SourcePath = "x", FileSizeBytes = 1000
        };
        LibraryItem referenciado = new()
        {
            Id = Guid.NewGuid(), Kind = LibraryItemKind.Music, Storage = ItemStorageRules.ReferenceValue,
            SourcePath = "y", FileSizeBytes = 999999
        };

        DeletionPreview preview = LibraryDeletion.Preview([copiado, referenciado]);

        Assert.Equal(1, preview.CopyCount);
        Assert.Equal(1000, preview.CopyBytes);
        Assert.Equal(1, preview.ReferenceCount);
        Assert.Equal(2, preview.TotalCount);
    }

    [Fact]
    public void ElPreviewNoCuentaComoCeroUnTamanoTodaviaNoMedido()
    {
        // FileSizeBytes null = "todavía no se midió" (ST-201), no "pesa 0".
        // El preview lo trata como 0 a propósito: es una aproximación, no
        // garantiza medir todo antes de poder mostrar el diálogo.
        LibraryItem sinMedir = new()
        {
            Id = Guid.NewGuid(), Kind = LibraryItemKind.Music, Storage = ItemStorageRules.CopyValue,
            SourcePath = "x", FileSizeBytes = null
        };

        DeletionPreview preview = LibraryDeletion.Preview([sinMedir]);

        Assert.Equal(0, preview.CopyBytes);
        Assert.Equal(1, preview.CopyCount);
    }

    // MARK: - Modo copia: a la Papelera

    [Fact]
    public void ModoCopiaMandaElArchivoALaPapelera()
    {
        string file = WriteFile("Música/Artista/Álbum/Canción.mp3");
        var item = new LibraryItem
        {
            Id = Guid.NewGuid(), Kind = LibraryItemKind.Music,
            Storage = ItemStorageRules.CopyValue, SourcePath = file
        };
        var trash = new FakeRecycleBin();

        IReadOnlyList<DeletionResult> results = LibraryDeletion.Delete(_root, [item], trash);

        Assert.Equal(DeletionOutcome.SentToRecycleBin, results[0].Outcome);
        Assert.Equal([file], trash.Sent);
    }

    [Fact]
    public void ModoCopiaConArchivoQueYaNoEstaNoLanzaYLoDiceEnElResultado()
    {
        string file = Path.Combine(_root, "Música", "Artista", "Álbum", "Fantasma.mp3");
        var item = new LibraryItem
        {
            Id = Guid.NewGuid(), Kind = LibraryItemKind.Music,
            Storage = ItemStorageRules.CopyValue, SourcePath = file
        };
        var trash = new FakeRecycleBin();

        IReadOnlyList<DeletionResult> results = LibraryDeletion.Delete(_root, [item], trash);

        Assert.Equal(DeletionOutcome.SourceMissing, results[0].Outcome);
        Assert.Empty(trash.Sent);
    }

    // MARK: - Modo referencia: nunca se toca el original

    [Fact]
    public void ModoReferenciaNuncaTocaElOriginal()
    {
        string file = WriteFile("afuera/Canción.flac");
        var item = new LibraryItem
        {
            Id = Guid.NewGuid(), Kind = LibraryItemKind.Music,
            Storage = ItemStorageRules.ReferenceValue, SourcePath = file
        };
        var trash = new FakeRecycleBin();

        IReadOnlyList<DeletionResult> results = LibraryDeletion.Delete(_root, [item], trash);

        Assert.Equal(DeletionOutcome.ReferenceOnly, results[0].Outcome);
        Assert.Empty(trash.Sent);
        Assert.True(File.Exists(file), "el original del usuario no se toca jamás");
    }

    // MARK: - Preparado y carátula, en los dos modos

    [Fact]
    public void BorraElPreparadoYLaCaratulaEnModoReferencia()
    {
        Guid id = Guid.NewGuid();
        string original = WriteFile("afuera/Video.mkv");
        string preparado = WriteFile(CatalogPath.PreparedRelative(id, "mpg"));
        string poster = Path.ChangeExtension(preparado, ".jpg");
        File.WriteAllText(poster, "x");
        string caratula = WriteFile(CatalogPath.CoverRelative(id));

        var item = new LibraryItem
        {
            Id = id, Kind = LibraryItemKind.Video,
            Storage = ItemStorageRules.ReferenceValue, SourcePath = original,
            PreparedPath = preparado, CoverRelativePath = CatalogPath.CoverRelative(id)
        };

        LibraryDeletion.Delete(_root, [item], new FakeRecycleBin());

        Assert.False(File.Exists(preparado));
        Assert.False(File.Exists(poster));
        Assert.False(File.Exists(caratula));
        Assert.True(File.Exists(original));
    }

    /// <summary>
    /// Invariante de ST-241: música copiada es su propio preparado
    /// (<c>PreparedPath == SourcePath</c>). Borrar "el preparado" acá NO
    /// puede intentar borrar el archivo de la biblioteca una segunda vez —ya
    /// lo mandó la Papelera <see cref="ModoCopiaMandaElArchivoALaPapelera"/>.
    /// </summary>
    [Fact]
    public void LaMusicaCopiadaNoIntentaBorrarSuPreparadoPorSegundaVez()
    {
        string file = WriteFile("Música/Artista/Álbum/Canción.mp3");
        var item = new LibraryItem
        {
            Id = Guid.NewGuid(), Kind = LibraryItemKind.Music,
            Storage = ItemStorageRules.CopyValue, SourcePath = file, PreparedPath = file
        };
        var trash = new FakeRecycleBin();

        LibraryDeletion.Delete(_root, [item], trash);

        // Un solo envío a la Papelera, no dos.
        Assert.Single(trash.Sent);
        Assert.Equal(file, trash.Sent[0]);
    }

    [Fact]
    public void UnLoteConVariosElementosSigueAunqueUnoFalle()
    {
        string ok1 = WriteFile("Música/A/A/A.mp3");
        string faltante = Path.Combine(_root, "Música", "B", "B", "B.mp3");
        string ok2 = WriteFile("Música/C/C/C.mp3");

        var items = new List<LibraryItem>
        {
            new() { Id = Guid.NewGuid(), Kind = LibraryItemKind.Music, Storage = ItemStorageRules.CopyValue, SourcePath = ok1 },
            new() { Id = Guid.NewGuid(), Kind = LibraryItemKind.Music, Storage = ItemStorageRules.CopyValue, SourcePath = faltante },
            new() { Id = Guid.NewGuid(), Kind = LibraryItemKind.Music, Storage = ItemStorageRules.CopyValue, SourcePath = ok2 }
        };
        var trash = new FakeRecycleBin();

        IReadOnlyList<DeletionResult> results = LibraryDeletion.Delete(_root, items, trash);

        Assert.Equal(
            [DeletionOutcome.SentToRecycleBin, DeletionOutcome.SourceMissing, DeletionOutcome.SentToRecycleBin],
            [.. results.Select(r => r.Outcome)]);
        Assert.Equal(2, trash.Sent.Count);
    }
}
