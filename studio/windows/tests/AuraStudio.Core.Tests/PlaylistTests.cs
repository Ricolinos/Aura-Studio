using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El formato del `.m3u8` no es una preferencia de Studio: lo lee el firmware
/// con `playlist_create()` de Rockbox, que acepta rutas UNIX absolutas sin
/// tocarlas. Cambiarlo rompe las listas en el iPod.
/// </summary>
public class PlaylistExporterTests
{
    [Fact]
    public void TheFileStartsWithTheHeaderAndOneAbsolutePathPerLine()
    {
        string contents = PlaylistExporter.M3u8Contents(
            ["Music/Artista/Álbum/01 Canción.mp3", "Music/Otro/02 Otra.mp3"]);

        Assert.Equal(
            "#EXTM3U\n/Music/Artista/Álbum/01 Canción.mp3\n/Music/Otro/02 Otra.mp3\n",
            contents);
    }

    [Fact]
    public void TheLeadingSlashIsAddedHereAndOnlyHere()
    {
        // Quien llama pasa la misma ruta de destino con la que copia la pista,
        // sin "/" — si además la agregara, saldría "//Music/…".
        Assert.Contains("\n/Music/a.mp3\n", PlaylistExporter.M3u8Contents(["Music/a.mp3"]));
    }

    [Fact]
    public void AnEmptyPlaylistIsStillAValidFile()
        => Assert.Equal("#EXTM3U\n", PlaylistExporter.M3u8Contents([]));

    [Fact]
    public void LinesEndWithUnixNewlinesBecauseTheIPodReadsThem()
    {
        // Se escribe para el firmware, no para Windows.
        Assert.DoesNotContain("\r", PlaylistExporter.M3u8Contents(["Music/a.mp3"]));
    }

    [Fact]
    public void ThePlaylistAndItsCoverShareTheSanitizedBaseName()
    {
        // El firmware encuentra la portada pelándole la extensión al .m3u8 y
        // probando ese mismo nombre con .jpg: si los dos no sanitizan igual,
        // la lista sale sin imagen.
        const string name = "Rolas: del/camino";
        Assert.Equal(
            Path.GetFileNameWithoutExtension(PlaylistExporter.FileName(name)),
            Path.GetFileNameWithoutExtension(PlaylistExporter.ImageFileName(name)));
        Assert.EndsWith(".m3u8", PlaylistExporter.FileName(name));
        Assert.EndsWith(".jpg", PlaylistExporter.ImageFileName(name));
    }

    [Fact]
    public void ANameWithCharactersFat32RejectsBecomesSafe()
    {
        string fileName = PlaylistExporter.FileName("AC/DC: lo mejor?");
        Assert.DoesNotContain('/', fileName);
        Assert.DoesNotContain(':', fileName);
        Assert.DoesNotContain('?', fileName);
    }
}

public class PlaylistImporterTests
{
    private static readonly string Folder = Path.Combine(Path.GetTempPath(), "listas");

    [Fact]
    public void CommentsAndBlankLinesAreIgnored()
    {
        IReadOnlyList<string> paths = PlaylistImporter.ParseTrackPaths(
            """
            #EXTM3U
            #EXTINF:214,Artista - Canción

            /Music/a.mp3
            """, Folder);

        Assert.Equal(["/Music/a.mp3"], paths);
    }

    [Fact]
    public void TheOrderOfTheFileIsTheOrderOfThePlaylist()
    {
        IReadOnlyList<string> paths = PlaylistImporter.ParseTrackPaths(
            "/Music/c.mp3\n/Music/a.mp3\n/Music/b.mp3\n", Folder);

        Assert.Equal(["/Music/c.mp3", "/Music/a.mp3", "/Music/b.mp3"], paths);
    }

    [Fact]
    public void ARelativePathResolvesAgainstThePlaylistsOwnFolder()
    {
        // Es lo que hace cualquier reproductor al abrir un M3U, y lo que
        // exportan casi todos los programas.
        IReadOnlyList<string> paths = PlaylistImporter.ParseTrackPaths("sub\\a.mp3", Folder);
        Assert.Equal(Path.Combine(Folder, "sub", "a.mp3"), paths[0]);
    }

    [Fact]
    public void AWindowsAbsolutePathIsLeftAlone()
    {
        Assert.Equal(@"C:\Users\yo\Música\a.mp3",
            PlaylistImporter.ParseTrackPaths(@"C:\Users\yo\Música\a.mp3", Folder)[0]);
        Assert.Equal(@"\\servidor\musica\a.mp3",
            PlaylistImporter.ParseTrackPaths(@"\\servidor\musica\a.mp3", Folder)[0]);
    }

    [Fact]
    public void AUnixAbsolutePathIsKeptVerbatim()
    {
        // Una lista escrita para el iPod trae `/Music/...`. No son rutas de
        // esta PC; quien llama decide si alguna corresponde a su catálogo.
        Assert.Equal("/Music/a.mp3", PlaylistImporter.ParseTrackPaths("/Music/a.mp3", Folder)[0]);
    }

    [Fact]
    public void AFileUrlBecomesAPlainPath()
    {
        Assert.Equal(@"C:\musica\a.mp3",
            PlaylistImporter.ParseTrackPaths("file:///C:/musica/a.mp3", Folder)[0]);
    }

    [Fact]
    public void WindowsLineEndingsDoNotLeaveStrayCarriageReturns()
    {
        // Un M3U exportado en Windows trae "\r\n"; sin recortar, cada ruta
        // terminaría en "\r" y ninguna coincidiría con el catálogo.
        IReadOnlyList<string> paths = PlaylistImporter.ParseTrackPaths(
            "#EXTM3U\r\n/Music/a.mp3\r\n/Music/b.mp3\r\n", Folder);
        Assert.Equal(["/Music/a.mp3", "/Music/b.mp3"], paths);
    }

    [Fact]
    public void AnEmptyFileGivesAnEmptyPlaylistNotAnError()
        => Assert.Empty(PlaylistImporter.ParseTrackPaths("#EXTM3U\n\n", Folder));

    [Fact]
    public void TheSuggestedNameIsTheFileNameWithoutExtension()
    {
        Assert.Equal("Rolas del camino",
            PlaylistImporter.SuggestedName(@"C:\listas\Rolas del camino.m3u8"));
        Assert.Equal("Mix", PlaylistImporter.SuggestedName(@"C:\listas\Mix.m3u"));
    }
}

/// <summary>
/// El colage por omisión de una lista. Studio siempre deja un `.jpg` junto al
/// `.m3u8` al sincronizar: el firmware tiene su propio tile genérico de
/// respaldo, pero repetido en las 20 listas del usuario no dice nada.
/// </summary>
public class PlaylistArtLayoutTests
{
    [Fact]
    public void TheFourQuadrantsCoverTheWholeSquareWithoutOverlapping()
    {
        IReadOnlyList<ArtRect> quadrants = PlaylistArtLayout.Quadrants(128);

        Assert.Equal(4, quadrants.Count);
        Assert.All(quadrants, q => Assert.Equal(64, q.Width));
        Assert.All(quadrants, q => Assert.Equal(64, q.Height));
        // Arriba-izquierda, arriba-derecha, abajo-izquierda, abajo-derecha.
        Assert.Equal(new ArtRect(0, 0, 64, 64), quadrants[0]);
        Assert.Equal(new ArtRect(64, 0, 64, 64), quadrants[1]);
        Assert.Equal(new ArtRect(0, 64, 64, 64), quadrants[2]);
        Assert.Equal(new ArtRect(64, 64, 64, 64), quadrants[3]);
    }

    [Theory]
    [InlineData(4, new[] { 0, 1, 2, 3 })]
    [InlineData(3, new[] { 0, 1, 2, 0 })]
    [InlineData(2, new[] { 0, 1, 0, 1 })]
    [InlineData(1, new[] { 0, 0, 0, 0 })]
    public void WithFewerThanFourCoversTheCollageStillFillsUp(int available, int[] expected)
    {
        // Reciclar desde el principio da más variedad visual que dejar
        // cuadrantes en blanco.
        Assert.Equal(expected, PlaylistArtLayout.CoverForEachQuadrant(available));
    }

    [Fact]
    public void WithoutCoversThereIsNoCollageAtAll()
        => Assert.Empty(PlaylistArtLayout.CoverForEachQuadrant(0));

    [Fact]
    public void ASquareCoverFillsItsQuadrantExactly()
    {
        ArtRect fill = PlaylistArtLayout.AspectFill(500, 500, new ArtRect(0, 0, 64, 64));
        Assert.Equal(new ArtRect(0, 0, 64, 64), fill);
    }

    [Fact]
    public void AWideCoverOverflowsSidewaysAndStaysCentered()
    {
        // Aspect fill: llena el cuadrante y lo que sobra se recorta, no se
        // deforma ni deja franjas.
        ArtRect fill = PlaylistArtLayout.AspectFill(1000, 500, new ArtRect(0, 0, 64, 64));
        Assert.Equal(128, fill.Width);
        Assert.Equal(64, fill.Height);
        Assert.Equal(-32, fill.X);       // el excedente se reparte a ambos lados
        Assert.Equal(0, fill.Y);
        Assert.Equal(32, fill.CenterX);  // centrada en el cuadrante
    }

    [Fact]
    public void ATallCoverOverflowsVertically()
    {
        ArtRect fill = PlaylistArtLayout.AspectFill(500, 1000, new ArtRect(64, 0, 64, 64));
        Assert.Equal(64, fill.Width);
        Assert.Equal(128, fill.Height);
        Assert.Equal(-32, fill.Y);
        Assert.Equal(96, fill.CenterX);
    }

    [Fact]
    public void ACoverWithNoSizeDoesNotProduceGarbage()
    {
        var quadrant = new ArtRect(0, 0, 64, 64);
        Assert.Equal(quadrant, PlaylistArtLayout.AspectFill(0, 100, quadrant));
    }

    [Fact]
    public void ThePlaceholderBarsGetWiderTowardTheBottom()
    {
        IReadOnlyList<ArtRect> bars = PlaylistArtLayout.PlaceholderBars(128);

        Assert.Equal(3, bars.Count);
        // La más ancha abajo, la más angosta arriba — igual que en macOS.
        IEnumerable<ArtRect> topDown = bars.OrderBy(b => b.Y);
        Assert.Equal([128 * 0.32, 128 * 0.44, 128 * 0.56], topDown.Select(b => b.Width));
    }

    [Fact]
    public void ThePlaceholderBarsStayInsideTheTile()
    {
        foreach (ArtRect bar in PlaylistArtLayout.PlaceholderBars(128))
        {
            Assert.True(bar.X >= 0 && bar.X + bar.Width <= 128, $"ancho fuera del tile: {bar}");
            Assert.True(bar.Y >= 0 && bar.Y + bar.Height <= 128, $"alto fuera del tile: {bar}");
        }
    }

    [Fact]
    public void TheBarsAreCenteredAsAGroup()
    {
        IReadOnlyList<ArtRect> bars = PlaylistArtLayout.PlaceholderBars(128);
        Assert.Equal(64, bars[1].CenterY);   // la del medio, en el centro exacto
    }
}
