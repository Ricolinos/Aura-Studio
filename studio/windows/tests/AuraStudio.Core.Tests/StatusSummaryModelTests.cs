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

    // MARK: - Películas, Series y Fotos (addendum de ST-202)

    private static LibraryItem Movie(string path, string title, double seconds = 5400, long? size = null) => new()
    {
        SourcePath = path,
        Kind = LibraryItemKind.Video,
        Category = MediaCategory.Movies.DisplayName(),
        Metadata = new TrackMetadata { Title = title, DurationSeconds = seconds },
        FileSizeBytes = size
    };

    private static LibraryItem Episode(
        string path, string series, int season, int episode, double seconds = 2400) => new()
    {
        SourcePath = path,
        Kind = LibraryItemKind.Video,
        Category = MediaCategory.Series.DisplayName(),
        SeriesName = series,
        Season = season,
        Episode = episode,
        Metadata = new TrackMetadata { Title = $"{series} {season}x{episode}", DurationSeconds = seconds }
    };

    private static LibraryItem Photo(string path, string category, string? album = null, long? size = null) => new()
    {
        SourcePath = path,
        Kind = LibraryItemKind.Photo,
        Category = category,
        PhotoAlbum = album,
        FileSizeBytes = size
    };

    /// <summary>Dos películas, dos series (una de dos temporadas) y seis fotos.</summary>
    private static LibraryCatalogIndex Media() => LibraryCatalogIndex.Build(
        [
            Movie(@"C:\a.mp4", "Amélie", 7200, 1024),
            Movie(@"C:\b.mp4", "Brazil", 7200, 1024),

            Episode(@"C:\s1.mkv", "Twin Peaks", 1, 1),
            Episode(@"C:\s2.mkv", "Twin Peaks", 1, 2),
            Episode(@"C:\s3.mkv", "Twin Peaks", 2, 1),
            Episode(@"C:\o1.mkv", "Fargo", 1, 1),

            Photo(@"C:\p1.jpg", "Fotos", "Viaje", 100),
            Photo(@"C:\p2.jpg", "Fotos", "Viaje", 100),
            Photo(@"C:\p3.jpg", "Fotos", null, 100),
            Photo(@"C:\p4.jpg", "Imágenes", "Memes", 100),
            Photo(@"C:\p5.jpg", "Imágenes", null, 100),
            Photo(@"C:\p6.jpg", "IA", null, 100)
        ],
        ArtistGroupingOptions.Default);

    [Fact]
    public void ElTotalDePeliculasCuentaPeliculasNoArchivos()
    {
        var model = new StatusSummaryModel();

        LibraryStatusSummary summary = model.Total(Media(), LibraryStatusSection.Movies, 1);

        Assert.Equal("2 películas", summary.Total);
        Assert.True(summary.HasTrailing);
    }

    [Fact]
    public void ElTotalDeSeriesCuentaSeriesTemporadasYEpisodios()
    {
        var model = new StatusSummaryModel();

        // Twin Peaks tiene dos temporadas y Fargo una: tres, no dos. La
        // temporada 1 de dos series distintas son dos temporadas.
        Assert.Equal(
            "2 series · 3 temporadas · 4 episodios",
            model.Total(Media(), LibraryStatusSection.Series, 1).Total);
    }

    [Fact]
    public void LasPeliculasNoSeCuelanEnSeriesNiAlReves()
    {
        var model = new StatusSummaryModel();

        Assert.StartsWith("2 películas", model.Total(Media(), LibraryStatusSection.Movies, 1).Total);
        Assert.StartsWith("2 series", new StatusSummaryModel().Total(Media(), LibraryStatusSection.Series, 1).Total);
    }

    [Fact]
    public void ElTotalDeFotosDesglosaPorColeccionEnElOrdenConfigurado()
    {
        var model = new StatusSummaryModel();
        var scope = new LibraryStatusScope(
            LibraryStatusSection.Photos, Collections: ["Fotos", "Imágenes", "IA"]);

        LibraryStatusSummary summary = model.Total(Media(), scope, 1);

        Assert.Equal("6 fotos · 3 en Fotos · 2 en Imágenes · 1 en IA · 2 álbumes", summary.Total);
    }

    [Fact]
    public void UnaColeccionVaciaNoSeNombra()
    {
        var model = new StatusSummaryModel();
        var scope = new LibraryStatusScope(
            LibraryStatusSection.Photos, Collections: ["Fotos", "Imágenes", "IA", "Escaneos"]);

        // "0 en Escaneos" no le dice nada a nadie.
        Assert.DoesNotContain("Escaneos", model.Total(Media(), scope, 1).Total);
    }

    [Fact]
    public void SinColeccionesElTotalDeFotosSigueSiendoCorrecto()
    {
        var model = new StatusSummaryModel();

        // Sin el orden configurado no hay desglose, que es peor pero nunca
        // incorrecto.
        Assert.Equal("6 fotos · 2 álbumes", model.Total(Media(), LibraryStatusSection.Photos, 1).Total);
    }

    [Fact]
    public void LosAlbumesDeUnaColeccionNoCuentanLosDeOtra()
    {
        var model = new StatusSummaryModel();
        var scope = new LibraryStatusScope(LibraryStatusSection.PhotoAlbums, "Fotos");

        // "Viaje" con dos fotos, más una suelta. "Memes" es de Imágenes y no
        // entra: la categoría es parte de la clave a propósito.
        Assert.Equal("1 álbum · 3 fotos · 1 sin álbum", model.Total(Media(), scope, 1).Total);
    }

    [Fact]
    public void SinFotosSueltasNoSeDiceSinAlbum()
    {
        var index = LibraryCatalogIndex.Build(
            [Photo(@"C:\p1.jpg", "Fotos", "Viaje", 100)], ArtistGroupingOptions.Default);

        var model = new StatusSummaryModel();
        var scope = new LibraryStatusScope(LibraryStatusSection.PhotoAlbums, "Fotos");

        Assert.Equal("1 álbum · 1 foto", model.Total(index, scope, 1).Total);
    }

    [Fact]
    public void LaSeleccionDePeliculasSeCuentaEnPeliculas()
    {
        LibraryCatalogIndex index = Media();
        var model = new StatusSummaryModel();

        IReadOnlyList<LibraryItem> selected =
            index.ByVideoCollectionKey(LibraryGrouping.VideoCollectionKeyOf(
                index.Items.First(item => item.Metadata?.Title == "Amélie")));

        LibraryStatusSummary summary =
            model.Summary(index, LibraryStatusSection.Movies, 1, selected, 1);

        Assert.StartsWith("1 de 2 seleccionadas", summary.Selection);
    }

    [Fact]
    public void LaSeleccionDeSeriesDiceTemporadasYEpisodios()
    {
        LibraryCatalogIndex index = Media();
        var model = new StatusSummaryModel();

        IReadOnlyList<LibraryItem> selected =
            index.ByVideoCollectionKey(LibraryGrouping.VideoCollectionKeyOf(
                index.Items.First(item => item.SeriesName == "Twin Peaks")));

        LibraryStatusSummary summary =
            model.Summary(index, LibraryStatusSection.Series, 1, selected, 1);

        Assert.StartsWith("1 de 2 seleccionadas · 2 temporadas · 3 episodios", summary.Selection);
    }

    [Fact]
    public void LaSeleccionDeAlbumesDeFotosCuentaAlbumesYFotos()
    {
        LibraryCatalogIndex index = Media();
        var model = new StatusSummaryModel();
        var scope = new LibraryStatusScope(LibraryStatusSection.PhotoAlbums, "Fotos");

        IReadOnlyList<LibraryItem> selected = index.ByPhotoAlbumKey(
            LibraryGrouping.PhotoAlbumKeyOf(
                index.Items.First(item => item.PhotoAlbum == "Viaje"), "Fotos"));

        // Dos tarjetas en esa colección: "Viaje" y "Sin álbum". El denominador
        // las cuenta a las dos, aunque el total diga "1 álbum".
        LibraryStatusSummary summary = model.Summary(index, scope, 1, selected, 1);

        Assert.StartsWith("1 de 2 seleccionados · 2 fotos", summary.Selection);
    }

    [Fact]
    public void EnTodasLasFotosLaTarjetaEsLaFoto()
    {
        LibraryCatalogIndex index = Media();
        var model = new StatusSummaryModel();

        IReadOnlyList<LibraryItem> selected =
            [.. index.Items.Where(item => item.Kind == LibraryItemKind.Photo).Take(2)];

        LibraryStatusSummary summary =
            model.Summary(index, LibraryStatusSection.Photos, 1, selected, 2);

        Assert.StartsWith("2 de 6 seleccionadas", summary.Selection);
    }

    [Fact]
    public void CambiarDeSeccionRecalculaElTotalAunqueNoCambieElCatalogo()
    {
        LibraryCatalogIndex index = Media();
        var model = new StatusSummaryModel();

        Assert.Equal("2 películas", model.Total(index, LibraryStatusSection.Movies, 7).Total);
        Assert.StartsWith("2 series", model.Total(index, LibraryStatusSection.Series, 7).Total);
        Assert.Equal("2 películas", model.Total(index, LibraryStatusSection.Movies, 7).Total);
    }

    [Fact]
    public void CambiarDeColeccionRecalculaElTotalAunqueSeaLaMismaSeccion()
    {
        LibraryCatalogIndex index = Media();
        var model = new StatusSummaryModel();

        // El ámbito es más que la sección: dos colecciones de fotos son dos
        // totales distintos, y memoizar solo por sección devolvería el de la
        // anterior.
        Assert.Equal("1 álbum · 3 fotos · 1 sin álbum",
            model.Total(index, new LibraryStatusScope(LibraryStatusSection.PhotoAlbums, "Fotos"), 7).Total);

        Assert.Equal("1 álbum · 2 fotos · 1 sin álbum",
            model.Total(index, new LibraryStatusScope(LibraryStatusSection.PhotoAlbums, "Imágenes"), 7).Total);
    }
}
