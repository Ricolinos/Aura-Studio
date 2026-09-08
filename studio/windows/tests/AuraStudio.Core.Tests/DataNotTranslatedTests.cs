using System.Globalization;
using AuraStudio.Core;
using AuraStudio.Core.Library;
using AuraStudio.Core.Resources;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Lo que parece español y no lo es: no cambia con el idioma (ST-247, B7d,
/// paso 3).
///
/// <para>El triaje de B7c apartó once literales que <b>parecen</b> texto y son
/// datos: la categoría que se guarda en el catálogo, los nombres de carpeta en
/// disco, la lista de artículos con la que se ordena ignorando el «el/la», y la
/// salida en inglés de <c>mks5lboot.exe</c>. Traducirlos no cambia lo que se
/// lee: cambia lo que el programa hace, y el daño es silencioso — una categoría
/// guardada como «Fotos» y leída como «Photos» deja de emparejar, y las fotos
/// del usuario se van a otra sección.</para>
///
/// <para><b>Por qué esta prueba y no una lista.</b> Comprobar que esas cadenas
/// no aparecen en el archivo de recursos sería fácil y no probaría nada: lo que
/// importa no es dónde está escrito el texto, sino que el valor <b>no dependa
/// de la cultura</b>. Así que se corre todo con la interfaz en japonés y se
/// mira que salga exactamente lo mismo. Si alguien mueve una de estas a un
/// recurso, la prueba se pone roja aunque la traducción sea perfecta — que es
/// justo cuando hay que detenerse.</para>
/// </summary>
public class DataNotTranslatedTests
{
    private static T InJapanese<T>(Func<T> body)
    {
        CultureInfo before = CultureInfo.CurrentUICulture;
        try
        {
            CultureInfo.CurrentUICulture = new CultureInfo("ja");
            return body();
        }
        finally
        {
            CultureInfo.CurrentUICulture = before;
        }
    }

    /// <summary>
    /// El nombre que se guarda en <c>item.category</c> es el español, siempre
    /// (D-283). Su etiqueta en pantalla es otra cosa y sí cambia.
    /// </summary>
    [Fact]
    public void LaCategoriaQueSeGuardaNoCambiaConElIdioma()
    {
        (string videos, string series, string movies) = InJapanese(() => (
            MediaCategory.Videos.CatalogName(),
            MediaCategory.Series.CatalogName(),
            MediaCategory.Movies.CatalogName()));

        Assert.Equal("Videos", videos);
        Assert.Equal("Series", series);
        Assert.Equal("Películas", movies);
    }

    /// <summary>
    /// Y su etiqueta sí cambia — si no, la mitad del contrato no existe: el
    /// dato es estable porque la etiqueta se mueve por él.
    /// </summary>
    [Fact]
    public void LaEtiquetaDeLaCategoriaSiCambiaConElIdioma() =>
        Assert.NotEqual(
            MediaCategory.Series.CatalogName(),
            InJapanese(() => MediaCategory.Series.LocalizedName()));

    /// <summary>
    /// Reconocer una categoría no depende del idioma. Es lo que lee un catálogo
    /// escrito por otra instalación, quizá en otro idioma.
    /// </summary>
    [Fact]
    public void ReconocerUnaCategoriaNoDependeDelIdioma() =>
        Assert.True(InJapanese(() =>
            MediaCategoryNames.IsSeriesCategory("Series")
            && MediaCategoryNames.IsMoviesCategory("Películas")
            && !MediaCategoryNames.IsSeriesCategory(MediaCategory.Series.LocalizedName())));

    /// <summary>Las carpetas de la biblioteca son rutas en disco, no rótulos.</summary>
    [Fact]
    public void LasCarpetasDeLaBibliotecaNoCambianConElIdioma()
    {
        Assert.Equal("Sin categoría", InJapanese(() => LibraryFileLayout.UncategorizedFolder));

        Assert.Equal(
            ["Imágenes", "Fotos", "IA"],
            InJapanese(() => LibraryOptions.DefaultPhotoCollections));
    }

    /// <summary>Y las claves del desglose de almacenamiento tampoco.</summary>
    [Fact]
    public void LasSeccionesDelDesgloseNoCambianConElIdioma() =>
        Assert.Equal(
            ["Música", "Video", "Fotos", "Otro"],
            InJapanese(() => (string[])
                [StorageBreakdown.Music, StorageBreakdown.Video,
                 StorageBreakdown.Photos, StorageBreakdown.Other]));

    /// <summary>
    /// Los artículos con los que se ordena son parte del algoritmo. Traducirlos
    /// pondría «The Beatles» en la T de golpe, en todas las bibliotecas.
    /// </summary>
    [Fact]
    public void ElOrdenIgnoraLosMismosArticulosEnCualquierIdioma()
    {
        IReadOnlyList<AlbumGroup> albums = InJapanese(() => LibraryGrouping.Albums(
        [
            SongIn("Los Fabulosos Cadillacs"),
            SongIn("The Beatles"),
            SongIn("Abbey Road"),
        ]));

        // Sin artículo inicial: Abbey, Beatles, Fabulosos.
        Assert.Equal(
            ["Abbey Road", "The Beatles", "Los Fabulosos Cadillacs"],
            albums.Select(album => album.Title));
    }

    /// <summary>
    /// Y lo que dice <c>mks5lboot.exe</c> está en inglés porque es de la
    /// herramienta. Se lee igual con la app en cualquier idioma.
    /// </summary>
    [Fact]
    public void LaSalidaDeLaHerramientaSeLeeIgualEnCualquierIdioma() =>
        Assert.True(InJapanese(() => Mks5lbootOutput.ReportsNoDevice("no DFU devices found")));

    private static LibraryItem SongIn(string album) => new()
    {
        Id = Guid.NewGuid(),
        Kind = LibraryItemKind.Music,
        SourcePath = $@"C:\m\{Guid.NewGuid():N}.mp3",
        Metadata = new TrackMetadata { Title = "x", Artist = "x", Album = album },
    };
}
