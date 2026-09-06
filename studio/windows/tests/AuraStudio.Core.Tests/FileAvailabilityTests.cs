using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Qué archivos del catálogo están (ST-203). Lo que se protege es que la
/// barrida cara se haga <b>una vez</b> y quede anotada: preguntarle al disco por
/// los 12 000 archivos en cada guardado era lo que congelaba la app con la
/// biblioteca en una unidad de red.
/// </summary>
public class FileAvailabilityTests
{
    private static LibraryItem Item(string path) => new()
    {
        SourcePath = path,
        Kind = LibraryItemKind.Music
    };

    private static IReadOnlyList<LibraryItem> Items(params string[] paths) => [.. paths.Select(Item)];

    [Fact]
    public void LaBarridaAnotaCadaRuta()
    {
        var known = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);

        FileAvailability.Sweep(Items(@"C:\a.mp3", @"C:\b.mp3"), known, path => path.EndsWith("a.mp3"));

        Assert.True(known[@"C:\a.mp3"]);
        Assert.False(known[@"C:\b.mp3"]);
    }

    [Fact]
    public void LaBarridaAvisaDelAvanceYSiempreTerminaEnElTotal()
    {
        var known = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
        List<(int Done, int Total)> progress = [];

        FileAvailability.Sweep(
            Items([.. Enumerable.Range(0, 5).Select(n => $@"C:\{n}.mp3")]),
            known, _ => true, (done, total) => progress.Add((done, total)), batchSize: 2);

        // 2, 4 por lote y 5 al final: el último aviso siempre cierra en el total,
        // porque una barra que se queda en 4 de 5 parece colgada.
        Assert.Equal([(2, 5), (4, 5), (5, 5)], progress);
    }

    [Fact]
    public void UnaBibliotecaVaciaNoAvisaDeNada()
    {
        var known = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
        int avisos = 0;

        FileAvailability.Sweep([], known, _ => true, (_, _) => avisos++);

        Assert.Equal(0, avisos);
    }

    [Fact]
    public void LaBarridaSePuedeDetener()
    {
        var known = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
        using var cancellation = new CancellationTokenSource();

        Assert.Throws<OperationCanceledException>(() => FileAvailability.Sweep(
            Items([.. Enumerable.Range(0, 100).Select(n => $@"C:\{n}.mp3")]),
            known,
            path => { if (path.Contains("10.")) cancellation.Cancel(); return true; },
            ct: cancellation.Token));

        Assert.NotEmpty(known);
        Assert.True(known.Count < 100);
    }

    [Fact]
    public void LoDisponibleSaleDeLoAnotadoSinTocarElDisco()
    {
        // Es el punto entero: después de la barrida, decidir qué se muestra no
        // vuelve a preguntar por ningún archivo.
        IReadOnlyList<LibraryItem> items = Items(@"C:\a.mp3", @"C:\b.mp3");
        var known = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase)
        {
            [@"C:\a.mp3"] = true,
            [@"C:\b.mp3"] = false
        };

        IReadOnlyList<LibraryItem> available = FileAvailability.Available(
            items, known, _ => throw new InvalidOperationException("no debía preguntar"));

        Assert.Single(available);
        Assert.Equal(@"C:\a.mp3", available[0].SourcePath);
    }

    [Fact]
    public void LoQueNoEstabaAnotadoSePreguntaYSeAnota()
    {
        // Los que acaban de entrar a la biblioteca: un puñado, no el catálogo.
        IReadOnlyList<LibraryItem> items = Items(@"C:\viejo.mp3", @"C:\nuevo.mp3");
        var known = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase)
        {
            [@"C:\viejo.mp3"] = true
        };

        List<string> preguntados = [];

        IReadOnlyList<LibraryItem> available = FileAvailability.Available(
            items, known, path => { preguntados.Add(path); return true; });

        Assert.Equal([@"C:\nuevo.mp3"], preguntados);
        Assert.Equal(2, available.Count);
        Assert.True(known[@"C:\nuevo.mp3"]);
    }

    [Fact]
    public void DosElementosConLaMismaRutaSePreguntanUnaSolaVez()
    {
        IReadOnlyList<LibraryItem> items = Items(@"C:\a.mp3", @"C:\a.mp3");
        var known = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
        int preguntas = 0;

        FileAvailability.Available(items, known, _ => { preguntas++; return true; });

        Assert.Equal(1, preguntas);
    }

    [Fact]
    public void UnaRutaImposibleEsAusenteYNoUnError()
    {
        // Nunca lanza: una ruta inválida o un permiso denegado son "no está",
        // no algo que pueda tumbar la carga de la biblioteca entera.
        Assert.False(FileAvailability.Exists(""));
        Assert.False(FileAvailability.Exists("\0inválida"));
        Assert.False(FileAvailability.Exists(@"Z:\no\existe\nada.mp3"));
    }

    [Fact]
    public void UnArchivoRealSeVeYUnoBorradoNo()
    {
        string path = Path.Combine(Path.GetTempPath(), "aura-disp-" + Guid.NewGuid().ToString("N"));
        File.WriteAllBytes(path, [0]);

        try
        {
            Assert.True(FileAvailability.Exists(path));
        }
        finally
        {
            File.Delete(path);
        }

        Assert.False(FileAvailability.Exists(path));
    }
}

/// <summary>
/// El avance de una tarea de fondo (ST-203): la diferencia entre saber cuánto
/// falta y no saberlo, que en pantalla es la diferencia entre una barra y un
/// anillo que gira.
/// </summary>
public class BackgroundTaskProgressTests
{
    [Fact]
    public void SinTotalEsIndeterminado()
    {
        Assert.False(BackgroundTaskProgress.Indeterminate.IsDeterminate);
        Assert.Null(BackgroundTaskProgress.Indeterminate.Fraction);
        Assert.Equal("", BackgroundTaskProgress.Indeterminate.CountText);
    }

    [Fact]
    public void ConTotalDaFraccionYTexto()
    {
        BackgroundTaskProgress progress = BackgroundTaskProgress.Of(3, 40);

        Assert.True(progress.IsDeterminate);
        Assert.Equal(0.075, progress.Fraction);
        Assert.Equal("3 de 40", progress.CountText);
    }

    [Fact]
    public void ElTextoSeparaLosMiles() =>
        Assert.Equal("3,000 de 12,000", BackgroundTaskProgress.Of(3000, 12000).CountText);

    [Fact]
    public void NoSePasaDeUnoNiBajaDeCero()
    {
        Assert.Equal(1, BackgroundTaskProgress.Of(50, 40).Fraction);
        Assert.Equal(0, BackgroundTaskProgress.Of(-5, 40).Fraction);
    }

    [Fact]
    public void ElAgregadoPromediaSoloLasQueSabenCuantoFalta()
    {
        double? aggregate = BackgroundTaskProgress.Aggregate(
        [
            BackgroundTaskProgress.Of(1, 2),
            BackgroundTaskProgress.Of(1, 4),
            BackgroundTaskProgress.Indeterminate
        ]);

        Assert.Equal(0.375, aggregate);
    }

    [Fact]
    public void SinNingunaQueSepaNoHayAgregado()
    {
        // Y eso es lo correcto: el indicador gira, no finge un porcentaje.
        Assert.Null(BackgroundTaskProgress.Aggregate([BackgroundTaskProgress.Indeterminate]));
        Assert.Null(BackgroundTaskProgress.Aggregate([]));
    }
}
