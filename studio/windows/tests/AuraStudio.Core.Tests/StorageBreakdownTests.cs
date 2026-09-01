using AuraStudio.Core;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La barra de capacidad de General (R3-3, ST-128). Es la pieza que el dueño
/// señaló como ancla: una barra segmentada dice de un vistazo lo que cuatro
/// filas de números obligan a leer y restar.
/// </summary>
public sealed class StorageBreakdownTests
{
    private const long GB = 1_000_000_000;

    private static IPodDiskInfo Device(long capacity, long used, CatalogSummary? summary = null) => new()
    {
        DevicePath = @"\\.\PHYSICALDRIVE2",
        VolumePath = @"E:\",
        SizeBytes = capacity,
        UsedBytes = used,
        FreeBytes = Math.Max(capacity - used, 0),
        LibrarySummary = summary
    };

    private static CatalogSummary Summary(long music, long video, long photo) => new()
    {
        Music = new CatalogTypeSummary { Count = 1, Bytes = music },
        Video = new CatalogTypeSummary { Count = 1, Bytes = video },
        Photo = new CatalogTypeSummary { Count = 1, Bytes = photo }
    };

    private static long BytesOf(IReadOnlyList<StorageSegment> segments, string label) =>
        segments.Single(segment => segment.Label == label).Bytes;

    [Fact]
    public void LosTramosSalenDelResumenDelUltimoSync()
    {
        IReadOnlyList<StorageSegment> segments =
            StorageBreakdown.Segments(Device(100 * GB, 40 * GB, Summary(20 * GB, 10 * GB, 5 * GB)));

        Assert.Equal(20 * GB, BytesOf(segments, StorageBreakdown.Music));
        Assert.Equal(10 * GB, BytesOf(segments, StorageBreakdown.Video));
        Assert.Equal(5 * GB, BytesOf(segments, StorageBreakdown.Photos));

        // Lo usado que no es biblioteca: firmware, fuentes, temas, lo copiado
        // a mano.
        Assert.Equal(5 * GB, BytesOf(segments, StorageBreakdown.Other));
        Assert.Equal(60 * GB, BytesOf(segments, StorageBreakdown.Free));
    }

    [Fact]
    public void LosTramosSumanLaCapacidad()
    {
        IReadOnlyList<StorageSegment> segments =
            StorageBreakdown.Segments(Device(100 * GB, 40 * GB, Summary(20 * GB, 10 * GB, 5 * GB)));

        Assert.Equal(100 * GB, segments.Sum(segment => segment.Bytes));
    }

    /// <summary>
    /// El resumen lo dejó el último sync: puede haber quedado viejo. Si suma
    /// más que lo usado, "Otro" se recorta a cero — dibujar un tramo negativo
    /// daría una barra imposible.
    /// </summary>
    [Fact]
    public void UnResumenViejoQueSumaDeMasNoProduceUnTramoNegativo()
    {
        IReadOnlyList<StorageSegment> segments =
            StorageBreakdown.Segments(Device(100 * GB, 10 * GB, Summary(20 * GB, 10 * GB, 5 * GB)));

        Assert.Equal(0, BytesOf(segments, StorageBreakdown.Other));
        Assert.All(segments, segment => Assert.True(segment.Bytes >= 0));
    }

    [Fact]
    public void SinHaberSincronizadoNuncaSoloSeSabeLoUsadoYLoLibre()
    {
        IReadOnlyList<StorageSegment> segments = StorageBreakdown.Segments(Device(100 * GB, 30 * GB));

        Assert.Equal(0, BytesOf(segments, StorageBreakdown.Music));
        Assert.Equal(30 * GB, BytesOf(segments, StorageBreakdown.Other));
        Assert.Equal(70 * GB, BytesOf(segments, StorageBreakdown.Free));
    }

    /// <summary>"Libre" es el resto implícito de la barra: no lleva entrada propia (D-282).</summary>
    [Fact]
    public void LaLeyendaOmiteLoLibreYLosTramosVacios()
    {
        IReadOnlyList<StorageSegment> legend =
            StorageBreakdown.Legend(Device(100 * GB, 40 * GB, Summary(20 * GB, 0, 5 * GB)));

        Assert.Equal(
            new[] { StorageBreakdown.Music, StorageBreakdown.Photos, StorageBreakdown.Other },
            legend.Select(segment => segment.Label));
    }

    [Fact]
    public void LaFraccionEsLaParteDeLaCapacidad()
    {
        IPodDiskInfo device = Device(100 * GB, 40 * GB, Summary(20 * GB, 10 * GB, 5 * GB));
        IReadOnlyList<StorageSegment> segments = StorageBreakdown.Segments(device);

        Assert.Equal(0.20, StorageBreakdown.Fraction(segments[0], device), 3);
        Assert.Equal(0.60, StorageBreakdown.Fraction(segments[4], device), 3);
    }

    /// <summary>
    /// Con capacidad desconocida, cero: una barra vacía dice "no sé" mejor que
    /// una barra llena de un solo color.
    /// </summary>
    [Fact]
    public void SinCapacidadConocidaLaBarraNoSeLlena()
    {
        IPodDiskInfo device = Device(0, 0);

        Assert.All(StorageBreakdown.Segments(device),
            segment => Assert.Equal(0, StorageBreakdown.Fraction(segment, device)));
    }

    [Fact]
    public void LaLineaDeUsoDiceLoTresNumerosEnPalabras()
    {
        string line = StorageBreakdown.UsageLine(Device(125 * GB, 25 * GB));

        Assert.Contains("usados de", line, StringComparison.Ordinal);
        Assert.Contains("libres", line, StringComparison.Ordinal);
        Assert.Contains("125.0 GB", line, StringComparison.Ordinal);
    }
}
