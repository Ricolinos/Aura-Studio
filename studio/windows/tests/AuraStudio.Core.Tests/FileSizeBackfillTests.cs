using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La migración del tamaño de archivo al catálogo (ST-201). Lo que se prueba es
/// sobre todo lo que <b>no</b> hace: no guarda un cero por no haber podido leer,
/// no vuelve a medir lo que ya sabe, y no escribe una medición sobre un elemento
/// al que le cambiaron la ruta mientras tanto.
/// </summary>
public class FileSizeBackfillTests
{
    private static LibraryItem Song(string path, long? size = null) => new()
    {
        SourcePath = path,
        Kind = LibraryItemKind.Music,
        FileSizeBytes = size
    };

    [Fact]
    public void FaltaElTamanoSoloDondeNoSeMidio()
    {
        Assert.True(FileSizeBackfill.NeedsSize(Song(@"C:\a.mp3")));
        Assert.False(FileSizeBackfill.NeedsSize(Song(@"C:\a.mp3", 1234)));

        // Cero es una medición válida —un archivo vacío—, no una ausencia.
        Assert.False(FileSizeBackfill.NeedsSize(Song(@"C:\a.mp3", 0)));
    }

    [Fact]
    public void LoQueNoSePuedeSincronizarNoSeMide()
    {
        var raro = new LibraryItem { SourcePath = @"C:\a.xyz", Kind = LibraryItemKind.Unsupported };
        var sinRuta = new LibraryItem { Kind = LibraryItemKind.Music };

        Assert.False(FileSizeBackfill.NeedsSize(raro));
        Assert.False(FileSizeBackfill.NeedsSize(sinRuta));
    }

    [Fact]
    public void MedirNoTocaLosElementos()
    {
        // Medir corre en el pool y aplicar en el hilo de interfaz: por eso son
        // dos pasos y no uno.
        LibraryItem item = Song(@"C:\a.mp3");

        IReadOnlyList<MeasuredFileSize> medido =
            FileSizeBackfill.MeasureBatch([item], _ => 4096);

        Assert.Null(item.FileSizeBytes);
        Assert.Equal(4096, medido.Single().Bytes);
    }

    [Fact]
    public void LoQueNoSePudoLeerNoSeMideYSeReintenta()
    {
        LibraryItem item = Song(@"C:\se-fue-el-disco.mp3");

        Assert.Empty(FileSizeBackfill.MeasureBatch([item], _ => null));

        // Sigue pendiente: la próxima apertura lo vuelve a intentar.
        Assert.True(FileSizeBackfill.NeedsSize(item));
    }

    [Fact]
    public void AplicarEscribeLoMedido()
    {
        LibraryItem item = Song(@"C:\a.mp3");
        IReadOnlyList<MeasuredFileSize> medido = FileSizeBackfill.MeasureBatch([item], _ => 99);

        Assert.Equal(1, FileSizeBackfill.Apply(medido));
        Assert.Equal(99, item.FileSizeBytes);
    }

    [Fact]
    public void NoAplicaUnaMedicionSobreOtroArchivo()
    {
        // Entre medir y aplicar pudo copiarse el archivo a la biblioteca
        // (D-228), y entonces esos bytes son de otro archivo.
        LibraryItem item = Song(@"C:\a.mp3");
        IReadOnlyList<MeasuredFileSize> medido = FileSizeBackfill.MeasureBatch([item], _ => 99);

        item.SourcePath = @"C:\Biblioteca\a.mp3";

        Assert.Equal(0, FileSizeBackfill.Apply(medido));
        Assert.Null(item.FileSizeBytes);
    }

    [Fact]
    public void CambiarLaRutaOlvidaElTamano()
    {
        LibraryItem item = Song(@"C:\a.mp3", 1234);

        item.SourcePath = @"C:\b.mp3";

        Assert.Null(item.FileSizeBytes);
    }

    [Fact]
    public void AsignarLaMismaRutaNoOlvidaNada()
    {
        LibraryItem item = Song(@"C:\a.mp3", 1234);

        item.SourcePath = @"C:\a.mp3";

        Assert.Equal(1234, item.FileSizeBytes);
    }

    [Fact]
    public void RecorreTodoLoPendientePorLotes()
    {
        List<LibraryItem> items = [.. Enumerable.Range(0, 12).Select(n => Song($@"C:\{n}.mp3"))];
        List<int> lotes = [];

        int total = FileSizeBackfill.Run(
            items,
            measured => { lotes.Add(measured.Count); FileSizeBackfill.Apply(measured); },
            _ => 10, batchSize: 5);

        Assert.Equal(12, total);
        Assert.Equal([5, 5, 2], lotes);
        Assert.All(items, item => Assert.Equal(10, item.FileSizeBytes));
    }

    [Fact]
    public void NoVuelveAMedirLoQueYaTieneTamano()
    {
        List<LibraryItem> items = [Song(@"C:\a.mp3", 1), Song(@"C:\b.mp3")];
        List<string> medidos = [];

        FileSizeBackfill.Run(
            items,
            measured => FileSizeBackfill.Apply(measured),
            path => { medidos.Add(path); return 7; });

        Assert.Equal([@"C:\b.mp3"], medidos);
        Assert.Equal(1, items[0].FileSizeBytes);
    }

    [Fact]
    public void SinNadaPendienteNoAvisaNiUnaVez()
    {
        List<LibraryItem> items = [Song(@"C:\a.mp3", 1)];
        int avisos = 0;

        Assert.Equal(0, FileSizeBackfill.Run(items, _ => avisos++, _ => 7));
        Assert.Equal(0, avisos);
    }

    [Fact]
    public void SeDetieneCuandoSeLoPiden()
    {
        List<LibraryItem> items = [.. Enumerable.Range(0, 100).Select(n => Song($@"C:\{n}.mp3"))];
        using var cancellation = new CancellationTokenSource();

        Assert.Throws<OperationCanceledException>(() => FileSizeBackfill.Run(
            items,
            measured => { FileSizeBackfill.Apply(measured); cancellation.Cancel(); },
            _ => 3, batchSize: 10, ct: cancellation.Token));

        // Lo del primer lote quedó bien; lo demás se mide la próxima vez.
        Assert.Equal(3, items[0].FileSizeBytes);
        Assert.Null(items[^1].FileSizeBytes);
    }

    [Fact]
    public void MedirUnArchivoQueNoExisteDaAusenteYNoCero()
    {
        Assert.Null(FileSizeBackfill.Measure(
            Path.Combine(Path.GetTempPath(), "aura-no-existe-" + Guid.NewGuid().ToString("N"))));
    }

    [Fact]
    public void MedirUnArchivoRealDaSuTamano()
    {
        string path = Path.Combine(Path.GetTempPath(), "aura-tamano-" + Guid.NewGuid().ToString("N"));
        File.WriteAllBytes(path, new byte[321]);

        try
        {
            Assert.Equal(321, FileSizeBackfill.Measure(path));
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void UnArchivoVacioMideCeroYNoQuedaPendiente()
    {
        string path = Path.Combine(Path.GetTempPath(), "aura-vacio-" + Guid.NewGuid().ToString("N"));
        File.WriteAllBytes(path, []);

        try
        {
            LibraryItem item = Song(path);
            FileSizeBackfill.Apply(FileSizeBackfill.MeasureBatch([item]));

            Assert.Equal(0, item.FileSizeBytes);
            Assert.False(FileSizeBackfill.NeedsSize(item));
        }
        finally
        {
            File.Delete(path);
        }
    }
}
