using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// ST-012 / contrato §2: **las carátulas son assets de Música o Video, nunca
/// entradas de Imágenes**. Port de las reglas de `CoverArtAssets.swift`.
///
/// La regla que más importa y la más fácil de romper: soltar una imagen a
/// propósito en Fotos **gana** — ahí el usuario dijo "esto es una foto".
/// </summary>
public class CoverArtAssetsTests : IDisposable
{
    private readonly string _root;

    public CoverArtAssetsTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "AuraCover-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ }
    }

    private string Touch(string relative)
    {
        string path = Path.Combine(_root, relative.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "x");
        return path;
    }

    // MARK: - Clasificación por extensión

    [Theory]
    [InlineData("a.jpg", true)]
    [InlineData("a.JPEG", true)]
    [InlineData("a.png", true)]
    [InlineData("a.heic", true)]
    [InlineData("a.mp3", false)]
    [InlineData("a", false)]
    public void ImagesAreRecognizedByExtension(string name, bool expected)
        => Assert.Equal(expected, CoverArtAssets.IsImage(name));

    [Theory]
    [InlineData("a.flac", true)]
    [InlineData("a.MP3", true)]
    [InlineData("a.m4a", true)]
    [InlineData("a.mp4", false)]
    public void AudioIsRecognizedByExtension(string name, bool expected)
        => Assert.Equal(expected, CoverArtAssets.IsAudio(name));

    // MARK: - Nombres de carátula

    [Theory]
    [InlineData("cover.jpg")]
    [InlineData("Folder.PNG")]
    [InlineData("front-1.jpg")]
    [InlineData("cover (1).jpeg")]
    [InlineData("cover_small.jpg")]
    [InlineData("cover 2.jpg")]
    [InlineData("AlbumArt_{123}_Large.jpg")]
    [InlineData("poster.jpg")]
    public void TheseNamesLookLikeCoverArt(string name)
        => Assert.True(CoverArtAssets.HasCoverLikeName(name), name);

    [Theory]
    [InlineData("IMG_2024.jpg")]
    [InlineData("vacaciones.png")]
    [InlineData("discoteca.jpg")]      // empieza con "disc" pero no es esa palabra
    [InlineData("cover.mp3")]          // no es una imagen
    public void TheseDoNot(string name)
        => Assert.False(CoverArtAssets.HasCoverLikeName(name), name);

    // MARK: - Decisión de importación

    [Fact]
    public void AnImageInAFolderThatBringsAudioIsCoverArtWhateverItsName()
    {
        // Un álbum soltado entero: la portada puede llamarse como sea.
        string song = Touch("Album/pista.mp3");
        string image = Touch("Album/scan-0001.jpg");
        var context = new CoverArtDropContext([song, image]);

        Assert.True(CoverArtAssets.IsCoverAsset(image, context, droppedIntoPhotos: false));
    }

    [Fact]
    public void ThePosterOfAVideoInTheSetIsAnAsset()
    {
        string video = Touch("Videos/pelicula.mp4");
        string poster = Touch("Videos/pelicula.jpg");
        var context = new CoverArtDropContext([video, poster]);

        Assert.True(CoverArtAssets.IsCoverAsset(poster, context, droppedIntoPhotos: false));
    }

    [Fact]
    public void AVideoAloneDoesNotTurnItsFolderIntoAnAlbum()
    {
        // Solo el AUDIO define "carpeta de álbum": una carpeta de fotos de un
        // viaje puede traer clips y sus fotos siguen siendo fotos.
        string clip = Touch("Viaje/clip.mov");
        string photo = Touch("Viaje/IMG_1234.jpg");
        var context = new CoverArtDropContext([clip, photo]);

        Assert.False(CoverArtAssets.IsCoverAsset(photo, context, droppedIntoPhotos: false));
    }

    [Fact]
    public void DroppingItIntoPhotosOnPurposeWins()
    {
        // La regla más importante: ahí el usuario dijo "esto es una foto".
        string image = Touch("Fotos/cover.jpg");
        var context = new CoverArtDropContext([image]);

        Assert.True(CoverArtAssets.IsCoverAsset(image, context, droppedIntoPhotos: false));
        Assert.False(CoverArtAssets.IsCoverAsset(image, context, droppedIntoPhotos: true));
    }

    [Fact]
    public void UnlessItLivesWithAudioOnDisk()
    {
        // Evidencia fuera del arrastre: un cover.jpg suelto de la carpeta de un
        // álbum sigue siendo carátula aunque se suelte en Fotos.
        Touch("Album/pista.mp3");
        string image = Touch("Album/cover.jpg");
        var context = new CoverArtDropContext([image]);

        Assert.True(CoverArtAssets.IsCoverAsset(image, context, droppedIntoPhotos: true));
    }

    [Fact]
    public void APhotoWithAnOrdinaryNameIsNeverAnAsset()
    {
        string photo = Touch("Fotos/IMG_1234.jpg");
        var context = new CoverArtDropContext([photo]);
        Assert.False(CoverArtAssets.IsCoverAsset(photo, context, droppedIntoPhotos: false));
    }

    // MARK: - Carátula de carpeta

    [Fact]
    public void ThePreferredNameWinsOverTheOthers()
    {
        string song = Touch("Album/pista.mp3");
        Touch("Album/back.jpg");
        string cover = Touch("Album/cover.jpg");
        Touch("Album/booklet.jpg");

        Assert.Equal(cover, CoverArtAssets.FolderCover(song));
    }

    [Fact]
    public void TheOrderOfPreferenceIsRespected()
    {
        string song = Touch("Album/pista.mp3");
        Touch("Album/artwork.jpg");
        string folder = Touch("Album/folder.png");

        // "folder" va antes que "artwork" en la lista de preferencia.
        Assert.Equal(folder, CoverArtAssets.FolderCover(song));
    }

    [Fact]
    public void WithoutAPreferredNameAnyRecognizedCoverServes()
    {
        string song = Touch("Album/pista.mp3");
        string booklet = Touch("Album/booklet.jpg");

        Assert.Equal(booklet, CoverArtAssets.FolderCover(song));
    }

    [Fact]
    public void AFolderWithOnlyPhotosHasNoCover()
    {
        string song = Touch("Album/pista.mp3");
        Touch("Album/IMG_1234.jpg");

        Assert.Null(CoverArtAssets.FolderCover(song));
    }

    [Fact]
    public void AFolderWithoutImagesHasNoCover()
    {
        string song = Touch("Album/pista.mp3");
        Assert.Null(CoverArtAssets.FolderCover(song));
    }

    [Fact]
    public void AMissingFolderIsNotAnError()
    {
        Assert.Null(CoverArtAssets.FolderCover(Path.Combine(_root, "no-existe", "x.mp3")));
        Assert.Null(CoverArtAssets.FolderCover(""));
    }
}
