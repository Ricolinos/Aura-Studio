using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Un codificador de mentira: no decodifica nada, pero se comporta como el de
/// verdad para lo único que le importa a estas pruebas — qué mide cada imagen y
/// qué sale del recorte. Las imágenes son la cadena <c>"WxH"</c>; lo que
/// devuelve el recorte es <c>"LADOxLADO"</c>, con la misma regla que WIC e
/// ImageIO: lado = min(lado corto, side), nunca agrandar.
/// </summary>
internal sealed class FakeSquareEncoder : ISquareImageEncoder
{
    public int Encodes { get; private set; }
    public bool Throws { get; set; }

    public static byte[] Image(int width, int height) => System.Text.Encoding.UTF8.GetBytes($"{width}x{height}");

    public (int Width, int Height)? OrientedPixelSize(byte[] image)
    {
        string[] parts = System.Text.Encoding.UTF8.GetString(image).Split('x');
        if (parts.Length != 2 || !int.TryParse(parts[0], out int w) || !int.TryParse(parts[1], out int h))
            return null;
        return (w, h);
    }

    public byte[] EncodeSquare(byte[] source, int side, double quality)
    {
        Encodes++;
        if (Throws) throw new InvalidOperationException("el codificador de la plataforma falló");

        (int Width, int Height)? size = OrientedPixelSize(source);
        if (size is not { } measured) throw new InvalidOperationException("no es una imagen");

        int outputSide = Math.Min(Math.Min(measured.Width, measured.Height), side);
        return Image(outputSide, outputSide);
    }
}

/// <summary>
/// ST-141: toda carátula que entra a la biblioteca queda cuadrada. Las mismas
/// reglas que <c>CoverArtNormalizerTests.swift</c> en macOS.
/// </summary>
public class CoverArtNormalizationTests
{
    [Theory]
    [InlineData(1000, 1000, false)]
    [InlineData(500, 500, false)]
    [InlineData(1600, 1200, true)]    // 4:3
    [InlineData(1001, 1001, true)]    // cuadrada pero enorme
    [InlineData(300, 301, true)]      // por un píxel
    public void TheRuleIsSquareAndNoBiggerThanAThousand(int width, int height, bool expected)
        => Assert.Equal(expected, CoverArtNormalization.NeedsNormalizing(width, height));

    [Theory]
    [InlineData(0, 500)]
    [InlineData(-1, -1)]
    public void ADegenerateSizeIsNotWorthNormalizing(int width, int height)
    {
        // No hay nada que recortar y el codificador fallaría: se deja pasar.
        Assert.False(CoverArtNormalization.NeedsNormalizing(width, height));
    }

    [Fact]
    public void TheCanonicalNumbersMatchTheContract()
    {
        Assert.Equal(1000, CoverArtNormalization.MaxSide);
        Assert.Equal(0.92, CoverArtNormalization.Quality);
        Assert.Equal(2, CoverArtNormalization.NormalizedVersion);
    }

    [Fact]
    public void AFourThreeCoverComesBackSquare()
    {
        var encoder = new FakeSquareEncoder();
        byte[] normalized = new CoverArtNormalizer(encoder).Normalize(FakeSquareEncoder.Image(1600, 1200));

        Assert.Equal(FakeSquareEncoder.Image(1000, 1000), normalized);   // min(1200, tope 1000)
        Assert.Equal(1, encoder.Encodes);
    }

    [Fact]
    public void ASmallCoverIsNeverBlownUp()
    {
        byte[] normalized = new CoverArtNormalizer(new FakeSquareEncoder())
            .Normalize(FakeSquareEncoder.Image(400, 300));

        Assert.Equal(FakeSquareEncoder.Image(300, 300), normalized);
    }

    [Fact]
    public void AnAlreadySquareCoverIsReturnedUntouchedWithoutReencoding()
    {
        var encoder = new FakeSquareEncoder();
        byte[] original = FakeSquareEncoder.Image(800, 800);

        // Byte por byte, y sin pasar por el codificador: recomprimir de gratis
        // solo perdería calidad.
        Assert.Same(original, new CoverArtNormalizer(encoder).Normalize(original));
        Assert.Equal(0, encoder.Encodes);
    }

    [Fact]
    public void SomethingUnreadableIsReturnedAsIsInsteadOfLost()
    {
        // Perder la carátula por no poder normalizarla sería peor que dejarla
        // como está: el sync la recorta igual antes del iPod.
        var normalizer = new CoverArtNormalizer(new FakeSquareEncoder());
        byte[] garbage = [1, 2, 3, 4];

        Assert.Same(garbage, normalizer.Normalize(garbage));
        Assert.Empty(normalizer.Normalize([]));
    }

    [Fact]
    public void AnEncoderThatBlowsUpDoesNotCostTheCover()
    {
        var encoder = new FakeSquareEncoder { Throws = true };
        byte[] original = FakeSquareEncoder.Image(1600, 1200);

        Assert.Same(original, new CoverArtNormalizer(encoder).Normalize(original));
    }
}

/// <summary>La pasada única sobre los archivos de <c>.portadas\</c>.</summary>
public class CoverNormalizationMigrationTests : IDisposable
{
    private readonly string _directory =
        Path.Combine(Path.GetTempPath(), "aura-normalize-" + Guid.NewGuid().ToString("N"));

    public CoverNormalizationMigrationTests() => Directory.CreateDirectory(_directory);

    public void Dispose()
    {
        try { Directory.Delete(_directory, recursive: true); } catch (IOException) { }
    }

    private string WriteImage(string name, int width, int height)
    {
        string path = Path.Combine(_directory, name);
        File.WriteAllBytes(path, FakeSquareEncoder.Image(width, height));
        return path;
    }

    [Fact]
    public void ItSkipsWhatIsAlreadySquare()
    {
        List<string> files =
        [
            WriteImage("a.jpg", 800, 600),
            WriteImage("b.jpg", 1600, 1200),
            WriteImage("ok.jpg", 500, 500)
        ];

        (int done, int total) = (0, 0);
        CoverNormalizationMigration.Result result = CoverNormalizationMigration.Run(
            files, new CoverArtNormalizer(new FakeSquareEncoder()),
            onProgress: (d, t) => (done, total) = (d, t));

        Assert.Equal(2, result.Normalized);
        Assert.Equal(3, result.Visited);
        Assert.False(result.Cancelled);
        Assert.Equal((3, 3), (done, total));

        Assert.Equal(FakeSquareEncoder.Image(600, 600), File.ReadAllBytes(files[0]));
        Assert.Equal(FakeSquareEncoder.Image(500, 500), File.ReadAllBytes(files[2]));
    }

    [Fact]
    public void ItStopsWhenCancelledAndPicksUpWhereItLeftOff()
    {
        List<string> files =
        [
            WriteImage("a.jpg", 800, 600),
            WriteImage("b.jpg", 800, 600),
            WriteImage("c.jpg", 800, 600)
        ];
        var normalizer = new CoverArtNormalizer(new FakeSquareEncoder());

        // Se cancela después del primero.
        using var cancellation = new CancellationTokenSource();
        CoverNormalizationMigration.Result first = CoverNormalizationMigration.Run(
            files, normalizer, cancellation.Token, onProgress: (_, _) => cancellation.Cancel());

        Assert.True(first.Cancelled);
        Assert.Equal(1, first.Normalized);

        // Retomar: el ya hecho se salta sin reescribirse. Sin archivo de
        // progreso — saltarse lo que ya está cuadrado ES el mecanismo.
        CoverNormalizationMigration.Result second = CoverNormalizationMigration.Run(files, normalizer);
        Assert.False(second.Cancelled);
        Assert.Equal(2, second.Normalized);
        Assert.Equal(3, second.Visited);

        Assert.All(files, path => Assert.Equal(FakeSquareEncoder.Image(600, 600), File.ReadAllBytes(path)));

        // Y una tercera pasada ya no reescribe nada.
        Assert.Equal(0, CoverNormalizationMigration.Run(files, normalizer).Normalized);
    }

    [Fact]
    public void AFileThatIsNotAnImageIsLeftAlone()
    {
        string path = Path.Combine(_directory, "roto.jpg");
        File.WriteAllBytes(path, [0, 1, 2, 3]);

        CoverNormalizationMigration.Result result = CoverNormalizationMigration.Run(
            [path], new CoverArtNormalizer(new FakeSquareEncoder()));

        Assert.Equal(0, result.Normalized);
        Assert.Equal(1, result.Visited);
        Assert.Equal([0, 1, 2, 3], File.ReadAllBytes(path));
    }

    [Fact]
    public void VideoPostersAreNeverInTheList()
    {
        var store = new LibraryStore(_directory);
        Directory.CreateDirectory(store.CoversDirectory);

        var song = new LibraryItem { Id = Guid.NewGuid(), Kind = LibraryItemKind.Music, SourcePath = "a.mp3" };
        var movie = new LibraryItem { Id = Guid.NewGuid(), Kind = LibraryItemKind.Video, SourcePath = "a.mp4" };
        File.WriteAllBytes(store.CoverPath(song.Id), FakeSquareEncoder.Image(800, 600));
        File.WriteAllBytes(store.CoverPath(movie.Id), FakeSquareEncoder.Image(600, 800));

        string artists = Path.Combine(store.CoversDirectory, "artistas");
        Directory.CreateDirectory(artists);
        string artistPhoto = Path.Combine(artists, "gorillaz.jpg");
        File.WriteAllBytes(artistPhoto, FakeSquareEncoder.Image(1000, 750));

        List<string> files = CoverNormalizationMigration.FilesToNormalize([song, movie], store);

        // El póster del video es 3:4 POR DISEÑO: entra a la misma carpeta y con
        // el mismo formato de nombre que una carátula, y recortarlo cuadrado
        // sería el bug, no el arreglo.
        Assert.Contains(store.CoverPath(song.Id), files);
        Assert.Contains(artistPhoto, files);
        Assert.DoesNotContain(store.CoverPath(movie.Id), files);
    }

    [Fact]
    public void TheMarkTravelsInTheCatalogAndSurvivesASave()
    {
        var store = new LibraryStore(_directory);
        var song = new LibraryItem { Id = Guid.NewGuid(), Kind = LibraryItemKind.Music, SourcePath = "a.mp3" };

        store.CoversNormalized = CoverArtNormalization.NormalizedVersion;
        store.SaveItems([song]);

        // Se relee desde disco, con otra instancia: es lo que pasa al abrir la
        // app la próxima vez.
        var reopened = new LibraryStore(_directory);
        reopened.LoadItems();
        Assert.Equal(2, reopened.CoversNormalized);

        // Y guardar otra vez no la pierde: si se perdiera, la migración se
        // repetiría en cada apertura.
        reopened.SaveItems([song]);
        var third = new LibraryStore(_directory);
        third.LoadItems();
        Assert.Equal(2, third.CoversNormalized);
    }

    [Fact]
    public void ALibraryFromBeforeThisChangeHasNoMark()
    {
        var store = new LibraryStore(_directory);
        store.SaveItems([]);

        var reopened = new LibraryStore(_directory);
        reopened.LoadItems();
        Assert.Null(reopened.CoversNormalized);
    }
}
