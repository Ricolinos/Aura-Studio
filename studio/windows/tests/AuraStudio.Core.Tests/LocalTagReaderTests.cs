using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El lector de etiquetas de punta a punta, contra archivos reales escritos en
/// el momento — no solo las reglas puras, sino el pegado con la librería.
///
/// Los archivos son MP3 mínimos pero **válidos**: tramas MPEG-1 Layer III de
/// verdad, con sus etiquetas escritas y releídas. Así se verifica que el mapeo
/// de campos es el que macOS produce, sin depender de tener música en el disco.
/// </summary>
public class LocalTagReaderTests : IDisposable
{
    private readonly string _root;

    public LocalTagReaderTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "AuraTags-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ }
    }

    /// <summary>Un MP3 de verdad: 40 tramas MPEG-1 Layer III de 128 kbps / 44,1 kHz.</summary>
    private string MakeMp3(string relative)
    {
        string path = Path.Combine(_root, relative.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);

        var frame = new List<byte> { 0xFF, 0xFB, 0x90, 0x64 };
        frame.AddRange(new byte[413]);
        var bytes = new List<byte>();
        for (int i = 0; i < 40; i++) bytes.AddRange(frame);

        File.WriteAllBytes(path, bytes.ToArray());
        return path;
    }

    private static void Tag(string path, Action<TagLib.Tag> configure)
    {
        using TagLib.File file = TagLib.File.Create(path);
        configure(file.Tag);
        file.Save();
    }

    private string MakeImage(string relative)
    {
        string path = Path.Combine(_root, relative.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, [0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4]);
        return path;
    }

    // MARK: - Mapeo de campos

    [Fact]
    public void EveryFieldLandsWhereItShould()
    {
        string song = MakeMp3("Album/pista.mp3");
        Tag(song, tag =>
        {
            tag.Title = "Canción";
            tag.Performers = ["Artista"];
            tag.Album = "Álbum";
            tag.AlbumArtists = ["Artista del álbum"];
            tag.Composers = ["Compositor"];
            tag.Genres = ["Rock"];
            tag.Year = 2013;
            tag.Track = 3;
            tag.Disc = 2;
            tag.Lyrics = "[00:12.00] una línea";
        });

        TrackMetadata metadata = LocalTagReader.Read(song);

        Assert.Equal("Canción", metadata.Title);
        Assert.Equal("Artista", metadata.Artist);
        Assert.Equal("Álbum", metadata.Album);
        Assert.Equal("Artista del álbum", metadata.AlbumArtist);
        Assert.Equal("Compositor", metadata.Composer);
        Assert.Equal("Rock", metadata.Genre);
        Assert.Equal("2013", metadata.Year);
        Assert.Equal(3, metadata.TrackNumber);
        Assert.Equal(2, metadata.DiscNumber);
        Assert.Equal("[00:12.00] una línea", metadata.SyncedLyrics);
        Assert.True(metadata.IsComplete);
    }

    [Fact]
    public void TheYearKeepsTheFourDigitShape()
    {
        // Se normaliza igual que en macOS, donde viene de una fecha completa.
        string song = MakeMp3("a.mp3");
        Tag(song, tag => tag.Year = 1999);
        Assert.Equal("1999", LocalTagReader.Read(song).Year);
    }

    [Fact]
    public void WithoutATrackArtistTheAlbumArtistServes()
    {
        // Mejor atribuir la pista al artista del álbum que dejarla sin artista.
        string song = MakeMp3("a.mp3");
        Tag(song, tag =>
        {
            tag.Title = "Sin intérprete";
            tag.AlbumArtists = ["Solo del álbum"];
        });

        TrackMetadata metadata = LocalTagReader.Read(song);
        Assert.Equal("Solo del álbum", metadata.Artist);
        Assert.Equal("Solo del álbum", metadata.AlbumArtist);
    }

    [Fact]
    public void AFileWithoutTagsGivesEmptyMetadataNotAnError()
    {
        string song = MakeMp3("sin-etiquetas.mp3");
        TrackMetadata metadata = LocalTagReader.Read(song);

        Assert.Null(metadata.Title);
        Assert.Null(metadata.Artist);
        Assert.False(metadata.IsComplete);
    }

    [Fact]
    public void TheDurationComesFromTheFileItself()
    {
        // En macOS este campo lo mide ffmpeg y queda vacío si no está
        // instalado; acá sale de las cabeceras y siempre está.
        string song = MakeMp3("a.mp3");
        double? duration = LocalTagReader.Read(song).DurationSeconds;

        Assert.NotNull(duration);
        Assert.InRange(duration!.Value, 0.5, 2.0);   // 40 tramas ≈ 1 s
    }

    // MARK: - Carátula

    [Fact]
    public void TheEmbeddedCoverIsReadAsIs()
    {
        string song = MakeMp3("Album/pista.mp3");
        byte[] art = [0xFF, 0xD8, 0xFF, 0xE0, 9, 9, 9, 9, 9, 9];
        Tag(song, tag => tag.Pictures =
        [
            new TagLib.Picture(new TagLib.ByteVector(art)) { MimeType = "image/jpeg" }
        ]);

        Assert.Equal(art, LocalTagReader.Read(song).CoverArtData);
    }

    [Fact]
    public void WithoutEmbeddedCoverTheFolderOneIsUsed()
    {
        // ST-012: la carátula de carpeta es un asset de la canción. Es lo que
        // hace que un álbum arrastrado con su cover.jpg conserve la portada.
        string song = MakeMp3("Album/pista.mp3");
        string cover = MakeImage("Album/cover.jpg");

        Assert.Equal(File.ReadAllBytes(cover), LocalTagReader.Read(song).CoverArtData);
    }

    [Fact]
    public void TheEmbeddedCoverWinsOverTheFolderOne()
    {
        string song = MakeMp3("Album/pista.mp3");
        MakeImage("Album/cover.jpg");
        byte[] embedded = [0xFF, 0xD8, 0xFF, 0xE0, 7, 7, 7, 7];
        Tag(song, tag => tag.Pictures =
        [
            new TagLib.Picture(new TagLib.ByteVector(embedded)) { MimeType = "image/jpeg" }
        ]);

        Assert.Equal(embedded, LocalTagReader.Read(song).CoverArtData);
    }

    [Fact]
    public void APhotoNextToTheSongIsNotACover()
    {
        string song = MakeMp3("Album/pista.mp3");
        MakeImage("Album/IMG_1234.jpg");

        Assert.Null(LocalTagReader.Read(song).CoverArtData);
    }

    // MARK: - Robustez

    [Fact]
    public void ABrokenFileNeverThrows()
    {
        // Un archivo malo no puede tumbar la importación de una carpeta entera.
        string broken = Path.Combine(_root, "roto.mp3");
        File.WriteAllText(broken, "esto no es audio");

        TrackMetadata metadata = LocalTagReader.Read(broken);
        Assert.Null(metadata.Title);
    }

    [Fact]
    public void AMissingOrEmptyPathIsHandled()
    {
        Assert.Null(LocalTagReader.Read(Path.Combine(_root, "no-existe.mp3")).Title);
        Assert.Null(LocalTagReader.Read("").Title);
    }
}
