using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El índice de agrupación por versión del catálogo (ST-201). Lo que se prueba
/// acá es que responde <b>exactamente lo mismo</b> que recorrer la biblioteca a
/// mano con <see cref="LibraryGrouping"/>: si divergen, la cuadrícula muestra un
/// álbum y el menú contextual actúa sobre otro.
/// </summary>
public class LibraryCatalogIndexTests
{
    private static LibraryItem Song(
        string path, string? album = null, string? artist = null, string? albumArtist = null) => new()
    {
        SourcePath = path,
        Kind = LibraryItemKind.Music,
        Metadata = new TrackMetadata { Album = album, Artist = artist, AlbumArtist = albumArtist }
    };

    private static LibraryItem Video(string path, string category, string? title = null, string? series = null,
        int? season = null) => new()
    {
        SourcePath = path,
        Kind = LibraryItemKind.Video,
        Category = category,
        SeriesName = series,
        Season = season,
        Metadata = new TrackMetadata { Title = title }
    };

    private static LibraryItem Photo(string path, string category, string? photoAlbum = null) => new()
    {
        SourcePath = path,
        Kind = LibraryItemKind.Photo,
        Category = category,
        PhotoAlbum = photoAlbum
    };

    [Fact]
    public void AgrupaLasCancionesPorLaMismaClaveQueLaCuadricula()
    {
        LibraryItem a = Song(@"C:\a.mp3", "Kid A", "Radiohead");
        LibraryItem b = Song(@"C:\b.mp3", "Kid A", "Radiohead");
        LibraryItem otro = Song(@"C:\c.mp3", "OK Computer", "Radiohead");

        var index = LibraryCatalogIndex.Build([a, b, otro]);

        Assert.Equal([a, b], index.ByAlbumKey(LibraryGrouping.AlbumKeyOf(a)));
        Assert.Equal([otro], index.ByAlbumKey(LibraryGrouping.AlbumKeyOf(otro)));
        Assert.Equal(2, index.GroupCount(LibraryGroupKind.Album));
    }

    [Fact]
    public void UnaClaveQueNoEstaDevuelveVacioYNoLanza()
    {
        var index = LibraryCatalogIndex.Build([Song(@"C:\a.mp3", "Kid A", "Radiohead")]);

        Assert.Empty(index.ByAlbumKey("no existe"));
        Assert.Empty(index.ByArtistKey("no existe"));
        Assert.Empty(index.ByVideoCollectionKey("no existe"));
        Assert.Empty(index.ByPhotoAlbumKey("no existe"));
        Assert.Null(index.ById(Guid.NewGuid()));
    }

    [Fact]
    public void ConservaElOrdenDelCatalogoDentroDeCadaGrupo()
    {
        // Es el orden con el que la tabla decide cuál es "la primera pista" de un
        // álbum, y de ahí sale la tapa y el título que se recomienda.
        LibraryItem primera = Song(@"C:\1.mp3", "Kid A", "Radiohead");
        LibraryItem segunda = Song(@"C:\2.mp3", "Kid A", "Radiohead");

        var index = LibraryCatalogIndex.Build([primera, segunda]);

        Assert.Same(primera, index.ByAlbumKey(LibraryGrouping.AlbumKeyOf(primera))[0]);
    }

    [Fact]
    public void LasClavesRespetanElCriterioDeAgrupacionDeArtistas()
    {
        // R2-4: con la agrupación encendida, la colaboración cae bajo el
        // principal; apagada, es su propio artista. El índice tiene que armar la
        // clave con el mismo criterio o el menú alcanzaría otro álbum.
        LibraryItem solo = Song(@"C:\a.mp3", "Demon Days", albumArtist: "Gorillaz");
        LibraryItem feat = Song(@"C:\b.mp3", "Demon Days", albumArtist: "Gorillaz feat. De La Soul");

        var agrupado = LibraryCatalogIndex.Build([solo, feat], ArtistGroupingOptions.Default);
        Assert.Equal(2, agrupado.ByAlbumKey(LibraryGrouping.AlbumKeyOf(solo, ArtistGroupingOptions.Default)).Count);

        var suelto = LibraryCatalogIndex.Build([solo, feat], ArtistGroupingOptions.Off);
        Assert.Single(suelto.ByAlbumKey(LibraryGrouping.AlbumKeyOf(solo, ArtistGroupingOptions.Off)));
    }

    [Fact]
    public void AgrupaSeriesYPeliculasComoLaCuadriculaDeVideo()
    {
        LibraryItem e1 = Video(@"C:\s01e01.mp4", "Series", series: "Chernobyl", season: 1);
        LibraryItem e2 = Video(@"C:\s01e02.mp4", "Series", series: "Chernobyl", season: 1);
        LibraryItem pelicula = Video(@"C:\alien.mp4", "Películas", title: "Alien");

        var index = LibraryCatalogIndex.Build([e1, e2, pelicula]);

        Assert.Equal([e1, e2], index.ByVideoCollectionKey(LibraryGrouping.VideoCollectionKeyOf(e1)));
        Assert.Equal([pelicula], index.ByVideoCollectionKey(LibraryGrouping.VideoCollectionKeyOf(pelicula)));
    }

    [Fact]
    public void AgrupaLosAlbumesDeFotosPorColeccionYNombre()
    {
        // La categoría entra en la clave a propósito: "Fotos" e "Imágenes"
        // pueden tener cada una un álbum llamado igual sin que se mezclen.
        LibraryItem enFotos = Photo(@"C:\1.jpg", "Fotos", "Verano");
        LibraryItem enImagenes = Photo(@"C:\2.jpg", "Imágenes", "Verano");

        var index = LibraryCatalogIndex.Build([enFotos, enImagenes]);

        Assert.Equal([enFotos], index.ByPhotoAlbumKey(LibraryGrouping.PhotoAlbumKeyOf(enFotos, "Fotos")));
        Assert.Equal([enImagenes], index.ByPhotoAlbumKey(LibraryGrouping.PhotoAlbumKeyOf(enImagenes, "Imágenes")));
    }

    [Fact]
    public void LosAlbumesDeFotosCoincidenConLaAgrupacionDeLaCuadricula()
    {
        // El identificador de la tarjeta sale de LibraryGrouping.PhotoAlbums; si
        // el índice armara la clave de otra forma, el menú contextual de un álbum
        // de fotos no alcanzaría ninguna foto — que es lo que pasaba antes de
        // ST-201, cuando se buscaba por identificador de elemento.
        LibraryItem una = Photo(@"C:\1.jpg", "Fotos", "Verano");
        LibraryItem otra = Photo(@"C:\2.jpg", "Fotos", "Verano");

        var index = LibraryCatalogIndex.Build([una, otra]);
        PhotoAlbumGroup grupo = LibraryGrouping.PhotoAlbums([una, otra], "Fotos").Single();

        Assert.Equal([una, otra], index.ByPhotoAlbumKey(grupo.Id));
    }

    [Fact]
    public void PorIdentificadorEnTextoResuelveLasCuadriculasPlanas()
    {
        LibraryItem foto = Photo(@"C:\1.jpg", "Fotos");
        var index = LibraryCatalogIndex.Build([foto]);

        Assert.Same(foto, index.ById(foto.Id.ToString("D")));
        Assert.Null(index.ById("esto no es un identificador"));
    }

    [Fact]
    public void VariasClavesNoRepitenUnElementoAlcanzadoDosVeces()
    {
        LibraryItem a = Song(@"C:\a.mp3", "Kid A", "Radiohead");
        LibraryItem b = Song(@"C:\b.mp3", "OK Computer", "Radiohead");

        var index = LibraryCatalogIndex.Build([a, b]);
        string clave = LibraryGrouping.AlbumKeyOf(a);

        Assert.Equal([a], index.ItemsForKeys(LibraryGroupKind.Album, [clave, clave]));
    }

    [Fact]
    public void VariasClavesRespondenEnElOrdenEnQueLlegan()
    {
        LibraryItem a = Song(@"C:\a.mp3", "Kid A", "Radiohead");
        LibraryItem b = Song(@"C:\b.mp3", "OK Computer", "Radiohead");

        var index = LibraryCatalogIndex.Build([a, b]);

        Assert.Equal(
            [b, a],
            index.ItemsForKeys(
                LibraryGroupKind.Album,
                [LibraryGrouping.AlbumKeyOf(b), LibraryGrouping.AlbumKeyOf(a)]));
    }

    [Fact]
    public void LosIdentificadoresAlcanzadosSonLosDeLosElementos()
    {
        LibraryItem a = Song(@"C:\a.mp3", "Kid A", "Radiohead");
        LibraryItem b = Song(@"C:\b.mp3", "Kid A", "Radiohead");

        var index = LibraryCatalogIndex.Build([a, b]);

        Assert.Equal(
            [a.Id, b.Id],
            index.ItemIdsForKeys(LibraryGroupKind.Album, [LibraryGrouping.AlbumKeyOf(a)]));
    }

    [Fact]
    public void ElIndiceVacioContestaVacioYNoLanza()
    {
        Assert.Empty(LibraryCatalogIndex.Empty.Items);
        Assert.Empty(LibraryCatalogIndex.Empty.ByAlbumKey(""));
        Assert.Empty(LibraryCatalogIndex.Empty.ItemsForKeys(LibraryGroupKind.Album, ["a", "b"]));
    }

    [Fact]
    public void ResponderPorClaveDaLoMismoQueFiltrarElCatalogoAMano()
    {
        // La prueba que importa: el índice es una optimización, no una regla
        // nueva. Si alguna vez contesta distinto que el filtro literal que
        // reemplazó, es un bug del índice.
        List<LibraryItem> catalogo =
        [
            .. Enumerable.Range(0, 60).Select(n =>
                Song($@"C:\{n}.mp3", $"Álbum {n % 7}", $"Artista {n % 3}"))
        ];

        var index = LibraryCatalogIndex.Build(catalogo, ArtistGroupingOptions.Default);

        foreach (LibraryItem item in catalogo)
        {
            string clave = LibraryGrouping.AlbumKeyOf(item, ArtistGroupingOptions.Default);

            Assert.Equal(
                [.. catalogo.Where(other =>
                    LibraryGrouping.AlbumKeyOf(other, ArtistGroupingOptions.Default) == clave)],
                index.ByAlbumKey(clave));
        }
    }
}
