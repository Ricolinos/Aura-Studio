using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El resumen de la barra de estado (ST-202). Lo que se protege es que el total
/// —la mitad cara— se calcule <b>una sola vez por versión del catálogo</b>, y que
/// la mitad que depende de la selección diga lo mismo que se ve en pantalla.
/// </summary>
public class StatusSummaryModelTests
{
    private static LibraryItem Song(
        string path, string album, string artist, double seconds = 200, long? size = null) => new()
    {
        SourcePath = path,
        Kind = LibraryItemKind.Music,
        Metadata = new TrackMetadata
        {
            Album = album,
            Artist = artist,
            AlbumArtist = artist,
            DurationSeconds = seconds
        },
        FileSizeBytes = size
    };

    /// <summary>Tres artistas, dos álbumes cada uno, dos canciones por álbum.</summary>
    private static LibraryCatalogIndex Catalog() => LibraryCatalogIndex.Build(
        [
            .. Enumerable.Range(0, 3).SelectMany(artist =>
                Enumerable.Range(0, 2).SelectMany(album =>
                    Enumerable.Range(0, 2).Select(track =>
                        Song($@"C:\{artist}-{album}-{track}.mp3",
                             $"Álbum {artist}-{album}", $"Artista {artist}", 100, 1024))))
        ],
        ArtistGroupingOptions.Default);

    [Fact]
    public void ElTotalDeAlbumesCuentaAlbumesArtistasYCanciones()
    {
        var model = new StatusSummaryModel();

        LibraryStatusSummary summary = model.Total(Catalog(), LibraryStatusSection.Albums, 1);

        Assert.Equal("6 álbumes · 3 artistas · 12 canciones", summary.Total);
        Assert.False(summary.HasSelection);
    }

    [Fact]
    public void ElTotalDeCancionesEmpiezaPorLasCanciones()
    {
        var model = new StatusSummaryModel();

        Assert.Equal(
            "12 canciones · 3 artistas · 6 álbumes",
            model.Total(Catalog(), LibraryStatusSection.Songs, 1).Total);
    }

    [Fact]
    public void ElTotalDeArtistasEmpiezaPorLosArtistas()
    {
        var model = new StatusSummaryModel();

        Assert.Equal(
            "3 artistas · 6 álbumes · 12 canciones",
            model.Total(Catalog(), LibraryStatusSection.Artists, 1).Total);
    }

    [Fact]
    public void ElDatoDeLaDerechaLlevaDuracionYTamano()
    {
        var model = new StatusSummaryModel();

        // 12 canciones de 100 s = 20 min; 12 KB.
        Assert.Equal("20 min · 12.0 KB", model.Total(Catalog(), LibraryStatusSection.Albums, 1).Trailing);
    }

    [Fact]
    public void ElTotalNoSeVuelveACalcularConLaMismaVersion()
    {
        // Es el punto entero del modelo: recorrer la biblioteca es lo caro, y no
        // puede pasar en cada cambio de selección.
        var model = new StatusSummaryModel();
        LibraryCatalogIndex first = Catalog();

        LibraryStatusSummary one = model.Total(first, LibraryStatusSection.Albums, 7);

        // Un índice distinto, con OTRO contenido, y la misma versión: tiene que
        // devolver lo guardado, no volver a calcular.
        var other = LibraryCatalogIndex.Build([Song(@"C:\z.mp3", "Otro", "Otra")]);
        LibraryStatusSummary two = model.Total(other, LibraryStatusSection.Albums, 7);

        Assert.Same(one, two);
    }

    [Fact]
    public void CambiarLaVersionLoRecalcula()
    {
        var model = new StatusSummaryModel();
        model.Total(Catalog(), LibraryStatusSection.Albums, 1);

        var other = LibraryCatalogIndex.Build([Song(@"C:\z.mp3", "Otro", "Otra")]);

        Assert.Equal("1 álbum · 1 artista · 1 canción", model.Total(other, LibraryStatusSection.Albums, 2).Total);
    }

    [Fact]
    public void CambiarDeSeccionLoRecalculaAunqueLaVersionSeaLaMisma()
    {
        // El modelo es uno por vista, pero la cuadrícula es una sola pantalla
        // para cinco secciones: si no se enterara del cambio, Álbumes mostraría
        // el resumen de Canciones.
        var model = new StatusSummaryModel();
        LibraryCatalogIndex index = Catalog();

        model.Total(index, LibraryStatusSection.Albums, 1);

        Assert.Equal(
            "12 canciones · 3 artistas · 6 álbumes",
            model.Total(index, LibraryStatusSection.Songs, 1).Total);
    }

    [Fact]
    public void SinSeleccionNoHayTextoDeSeleccion()
    {
        var model = new StatusSummaryModel();

        LibraryStatusSummary summary = model.Summary(
            Catalog(), LibraryStatusSection.Albums, 1, [], 0);

        Assert.False(summary.HasSelection);
        Assert.Equal("", summary.Selection);
    }

    [Fact]
    public void EnAlbumesLaSeleccionSeCuentaEnAlbumes()
    {
        // "2 de 6 seleccionados" son ÁLBUMES, no canciones: la tarjeta es el
        // álbum. Las canciones alcanzadas van aparte, que es lo que el usuario
        // necesita saber antes de sincronizar.
        var model = new StatusSummaryModel();
        LibraryCatalogIndex index = Catalog();

        IReadOnlyList<LibraryItem> selected = index.ItemsForKeys(
            LibraryGroupKind.Album,
            [
                LibraryGrouping.AlbumKeyOf(index.Items[0], ArtistGroupingOptions.Default),
                LibraryGrouping.AlbumKeyOf(index.Items[2], ArtistGroupingOptions.Default)
            ]);

        LibraryStatusSummary summary = model.Summary(
            index, LibraryStatusSection.Albums, 1, selected, 2);

        Assert.Equal("2 de 6 seleccionados · 1 artista · 4 canciones · 6 min", summary.Selection);
    }

    [Fact]
    public void EnCancionesLaSeleccionSeCuentaEnCanciones()
    {
        var model = new StatusSummaryModel();
        LibraryCatalogIndex index = Catalog();

        LibraryStatusSummary summary = model.Summary(
            index, LibraryStatusSection.Songs, 1, [index.Items[0], index.Items[1]], 2);

        Assert.Equal("2 de 12 seleccionadas · 1 artista · 1 álbum · 3 min", summary.Selection);
    }

    [Fact]
    public void ElTotalSobreviveAlTextoDeSeleccion()
    {
        var model = new StatusSummaryModel();
        LibraryCatalogIndex index = Catalog();

        LibraryStatusSummary summary = model.Summary(
            index, LibraryStatusSection.Albums, 1, [index.Items[0]], 1);

        Assert.Equal("6 álbumes · 3 artistas · 12 canciones", summary.Total);
        Assert.True(summary.HasTrailing);
    }

    [Fact]
    public void UnaBibliotecaVaciaNoDiceNadaRaro()
    {
        var model = new StatusSummaryModel();

        LibraryStatusSummary summary = model.Total(LibraryCatalogIndex.Empty, LibraryStatusSection.Albums, 1);

        Assert.Equal("0 álbumes · 0 artistas · 0 canciones", summary.Total);
        Assert.False(summary.HasTrailing);
    }
}

/// <summary>
/// Los cálculos sueltos de la barra: pluralización, duración y tamaño, en
/// español de México pase lo que pase.
/// </summary>
public class LibraryStatsTests
{
    [Theory]
    [InlineData(0, "0 canciones")]
    [InlineData(1, "1 canción")]
    [InlineData(2, "2 canciones")]
    [InlineData(12000, "12,000 canciones")]
    public void PluralizaYSeparaLosMiles(int value, string expected) =>
        Assert.Equal(expected, LibraryStats.Count(value, "canción", "canciones"));

    [Theory]
    [InlineData(0, "")]
    [InlineData(45, "45 s")]
    [InlineData(600, "10 min")]
    [InlineData(3600, "1 h 0 min")]
    [InlineData(11532, "3 h 12 min")]
    [InlineData(90000, "1 día 1 h")]
    [InlineData(200000, "2 días 7 h")]
    public void DiceLaDuracionComoLaDiriaUnaPersona(double seconds, string expected) =>
        Assert.Equal(expected, LibraryStats.DurationText(seconds));

    [Theory]
    [InlineData(0, "")]
    [InlineData(-1, "")]
    [InlineData(512, "512 bytes")]
    [InlineData(1536, "1.5 KB")]
    [InlineData(15360, "15.0 KB")]
    [InlineData(1288490188, "1.2 GB")]
    public void DiceElTamanoConLasUnidadesDelExplorador(long bytes, string expected) =>
        Assert.Equal(expected, LibraryStats.SizeText(bytes));

    [Fact]
    public void NoSaberCuantoPesaNoEsPesarCero()
    {
        // ST-201: lo que todavía no se midió queda ausente, y la barra no puede
        // afirmar "0 bytes" cuando lo que pasa es que no lo sabe.
        Assert.Equal("", LibraryStats.SizeText(0));
    }

    [Fact]
    public void UneSaltandoLoVacio() =>
        Assert.Equal("a · b", LibraryStats.Join("a", "", null, "b"));

    [Fact]
    public void ElTamanoSaleDelCatalogoYNoDelDisco()
    {
        // Es lo que hace que la barra se pueda recalcular en cada cambio de
        // selección sin tocar el disco (ST-201).
        LibraryItem[] items =
        [
            new() { SourcePath = @"C:\a.mp3", Kind = LibraryItemKind.Music, FileSizeBytes = 1000 },
            new() { SourcePath = @"C:\b.mp3", Kind = LibraryItemKind.Music, FileSizeBytes = 2000 },
            new() { SourcePath = @"C:\c.mp3", Kind = LibraryItemKind.Music }
        ];

        Assert.Equal(3000, LibraryStats.TotalSize(items));
    }
}
