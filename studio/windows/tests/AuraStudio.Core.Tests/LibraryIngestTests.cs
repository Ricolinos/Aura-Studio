using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Qué entra a la biblioteca al soltar archivos. La regla que más fácil se
/// rompe —y la que más duele— es ST-012: <b>las carátulas son assets de Música o
/// Video, nunca entradas de Imágenes</b>.
/// </summary>
public class LibraryIngestTests : IDisposable
{
    private readonly string _root;

    public LibraryIngestTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "AuraIngest-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ }
    }

    /// <summary>Crea el archivo de verdad: la regla de carátulas mira el disco.</summary>
    private string Touch(string relative)
    {
        string path = Path.Combine(_root, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, [0]);
        return path;
    }

    // MARK: - Cada sección ingiere solo su tipo

    [Fact]
    public void MusicDroppedIntoMusicComesIn()
    {
        LibraryIngestResult result = LibraryIngest.Ingest(
            [Touch(@"a\1.mp3"), Touch(@"a\2.flac")], LibraryItemKind.Music);

        Assert.Equal(2, result.Added.Count);
        Assert.All(result.Added, item => Assert.Equal(LibraryItemKind.Music, item.Kind));
    }

    [Fact]
    public void ASongDroppedIntoPhotosIsReportedNotSwallowed()
    {
        // Que desaparezca sin explicación se lee como que la app está rota.
        LibraryIngestResult result = LibraryIngest.Ingest(
            [Touch(@"a\1.mp3")], LibraryItemKind.Photo);

        Assert.Empty(result.Added);
        Assert.Single(result.WrongSection);
        Assert.Equal("1 archivo no es una imagen y no se agregó acá.",
            LibraryIngest.Summary(result, LibraryItemKind.Photo));
    }

    [Fact]
    public void AVideoDroppedIntoMusicDoesNotSneakIn()
    {
        LibraryIngestResult result = LibraryIngest.Ingest(
            [Touch(@"a\peli.mp4")], LibraryItemKind.Music);

        Assert.Empty(result.Added);
        Assert.Single(result.WrongSection);
    }

    [Fact]
    public void SomethingThatIsNotMediaIsRejectedAsIncompatible()
    {
        LibraryIngestResult result = LibraryIngest.Ingest(
            [Touch(@"a\notas.pdf")], LibraryItemKind.Music);

        Assert.Empty(result.Added);
        Assert.Single(result.Unsupported);
        Assert.Contains("no es compatible", LibraryIngest.Summary(result, LibraryItemKind.Music));
    }

    // MARK: - ST-012: las carátulas no son fotos

    [Fact]
    public void ACoverDroppedAlongsideItsAlbumIsNotAddedAsAPhoto()
    {
        string song = Touch(@"Signos\01.mp3");
        string cover = Touch(@"Signos\cover.jpg");

        LibraryIngestResult result = LibraryIngest.Ingest([song, cover], LibraryItemKind.Music);

        Assert.Single(result.Added);
        Assert.Equal(LibraryItemKind.Music, result.Added[0].Kind);
        Assert.Equal([cover], result.CoverAssets);
        Assert.Contains("carátula", LibraryIngest.Summary(result, LibraryItemKind.Music));
    }

    [Fact]
    public void AnImageBesideAVideoIsTakenAsItsPoster()
    {
        string video = Touch(@"Pelis\LaPeli.mp4");
        string poster = Touch(@"Pelis\LaPeli.jpg");

        LibraryIngestResult result = LibraryIngest.Ingest([video, poster], LibraryItemKind.Video);

        Assert.Single(result.Added);
        Assert.Equal([poster], result.CoverAssets);
    }

    [Fact]
    public void DroppingAnImageIntoPhotosOnPurposeWins()
    {
        // Ahí el usuario dijo "esto es una foto", aunque se llame cover.jpg.
        string cover = Touch(@"Recortes\cover.jpg");

        LibraryIngestResult result = LibraryIngest.Ingest([cover], LibraryItemKind.Photo);

        Assert.Single(result.Added);
        Assert.Equal(LibraryItemKind.Photo, result.Added[0].Kind);
        Assert.Empty(result.CoverAssets);
    }

    [Fact]
    public void ButNotIfItLivesInAFolderWithMusic()
    {
        // Evidencia fuera del arrastre: ahí sí es la carátula del álbum, aunque
        // se haya soltado en Fotos.
        Touch(@"Signos\01.mp3");
        string cover = Touch(@"Signos\cover.jpg");

        LibraryIngestResult result = LibraryIngest.Ingest([cover], LibraryItemKind.Photo);

        Assert.Empty(result.Added);
        Assert.Single(result.CoverAssets);
    }

    [Fact]
    public void ARealPhotoDroppedIntoPhotosComesInNormally()
    {
        LibraryIngestResult result = LibraryIngest.Ingest(
            [Touch(@"Viaje\IMG_0001.jpg")], LibraryItemKind.Photo);

        Assert.Single(result.Added);
        Assert.Empty(result.CoverAssets);
    }

    // MARK: - Duplicados

    [Fact]
    public void SomethingAlreadyInTheLibraryIsNotAddedTwice()
    {
        string song = Touch(@"a\1.mp3");

        LibraryIngestResult result = LibraryIngest.Ingest(
            [song], LibraryItemKind.Music, existingPaths: [song]);

        Assert.Empty(result.Added);
        Assert.Single(result.AlreadyInLibrary);
        Assert.Contains("ya estaba", LibraryIngest.Summary(result, LibraryItemKind.Music));
    }

    [Fact]
    public void TheSameFileTwiceInOneDropOnlyEntersOnce()
    {
        string song = Touch(@"a\1.mp3");

        LibraryIngestResult result = LibraryIngest.Ingest([song, song], LibraryItemKind.Music);

        Assert.Single(result.Added);
        Assert.Single(result.AlreadyInLibrary);
    }

    // MARK: - Lo que se le dice al usuario

    [Fact]
    public void TheSummaryNamesEverythingThatDidNotComeIn()
    {
        string song = Touch(@"Signos\01.mp3");
        string cover = Touch(@"Signos\cover.jpg");
        string photo = Touch(@"Viaje\IMG_1.jpg");
        string pdf = Touch(@"a\notas.pdf");

        LibraryIngestResult result = LibraryIngest.Ingest(
            [song, cover, photo, pdf], LibraryItemKind.Music);

        string summary = LibraryIngest.Summary(result, LibraryItemKind.Music);

        Assert.Contains("Se agregó 1 elemento", summary);
        Assert.Contains("carátula", summary);
        Assert.Contains("no es música", summary);
        Assert.Contains("no es compatible", summary);
    }

    [Fact]
    public void DroppingNothingUsefulSaysSoInsteadOfStayingSilent()
        => Assert.Equal("No había nada que agregar.",
            LibraryIngest.Summary(LibraryIngest.Ingest([], LibraryItemKind.Music), LibraryItemKind.Music));

    [Fact]
    public void EverythingComesInQueuedAndDated()
    {
        LibraryIngestResult result = LibraryIngest.Ingest(
            [Touch(@"a\1.mp3")], LibraryItemKind.Music);

        Assert.Equal(LibraryItemState.Queued, result.Added[0].Status.State);
        Assert.NotNull(result.Added[0].AddedAt);
    }

    [Fact]
    public void TheOrderOfTheDropIsPreserved()
    {
        string first = Touch(@"a\z.mp3"), second = Touch(@"a\a.mp3");

        LibraryIngestResult result = LibraryIngest.Ingest([first, second], LibraryItemKind.Music);

        Assert.Equal([first, second], result.Added.Select(item => item.SourcePath));
    }
}
