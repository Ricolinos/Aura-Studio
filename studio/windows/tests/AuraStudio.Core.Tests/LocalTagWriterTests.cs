using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El escritor de etiquetas de punta a punta (ST-242): se escribe con
/// <see cref="LocalTagWriter"/> y se relee de las dos formas que importan —con
/// TagLib# crudo, para ver qué quedó realmente en el archivo, y con
/// <see cref="LocalTagReader"/>, que es por donde vuelve al catálogo—. Si esas
/// dos lecturas no coinciden, la ida y la vuelta no cierran y el usuario ve una
/// cosa distinta de la que grabó.
///
/// <para>Los tres formatos que se etiquetan (MP3, FLAC y M4A) corren las mismas
/// pruebas, porque el contrato es el mismo aunque el contenedor no lo sea. Los
/// archivos los arma <see cref="MinimalAudioFiles"/> en el momento: mínimos pero
/// válidos, para no depender de tener música en el disco.</para>
/// </summary>
public class LocalTagWriterTests : IDisposable
{
    private readonly string _root;

    public LocalTagWriterTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "AuraTagWriter-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ }
    }

    // MARK: - Ida y vuelta

    [Theory]
    [InlineData("mp3")]
    [InlineData("flac")]
    [InlineData("m4a")]
    public void LoQueSeEscribeEsLoQueSeRelee(string extension)
    {
        string path = MakeAudio("cancion." + extension);

        var metadata = new TrackMetadata
        {
            Title = "Cancion de prueba",
            Artist = "Artista",
            Album = "Album",
            AlbumArtist = "Artista del album",
            Composer = "Compositor",
            Genre = "Rock",
            Year = "1994",
            TrackNumber = 7,
            DiscNumber = 2
        };

        TagWriteResult result = LocalTagWriter.Write(path, metadata);

        Assert.True(result.Written, result.Reason);
        Assert.Equal(new FileInfo(path).Length, result.BytesWritten);

        // Lo que dice el archivo, leído con la librería directamente.
        using (TagLib.File file = TagLib.File.Create(path))
        {
            Assert.Equal("Cancion de prueba", file.Tag.Title);
            Assert.Equal("Artista", file.Tag.Performers[0]);
            Assert.Equal("Album", file.Tag.Album);
            Assert.Equal("Artista del album", file.Tag.AlbumArtists[0]);
            Assert.Equal("Compositor", file.Tag.Composers[0]);
            Assert.Equal("Rock", file.Tag.Genres[0]);
            Assert.Equal(1994u, file.Tag.Year);
            Assert.Equal(7u, file.Tag.Track);
            Assert.Equal(2u, file.Tag.Disc);
        }

        // Y lo que ve el catálogo cuando vuelve a leer ese mismo archivo.
        TrackMetadata reread = LocalTagReader.Read(path);

        Assert.Equal("Cancion de prueba", reread.Title);
        Assert.Equal("Artista", reread.Artist);
        Assert.Equal("Album", reread.Album);
        Assert.Equal("Artista del album", reread.AlbumArtist);
        Assert.Equal("Compositor", reread.Composer);
        Assert.Equal("Rock", reread.Genre);
        Assert.Equal("1994", reread.Year);
        Assert.Equal(7, reread.TrackNumber);
        Assert.Equal(2, reread.DiscNumber);
    }

    /// <summary>
    /// Acentos, eñes y japonés. Es lo que se rompe cuando una etiqueta se
    /// escribe en Latin-1 en vez de UTF-16/UTF-8 — y en una biblioteca en
    /// español eso pasa en la primera canción, no en un caso raro.
    /// </summary>
    [Theory]
    [InlineData("mp3")]
    [InlineData("flac")]
    [InlineData("m4a")]
    public void LosAcentosVuelvenIguales(string extension)
    {
        string path = MakeAudio("acentos." + extension);

        var metadata = new TrackMetadata
        {
            Title = "Corazón partío",
            Artist = "Joaquín Sabina & Peñas",
            Album = "Añoranza — Volumen II",
            AlbumArtist = "Various Artists · Ñ",
            Genre = "Ranchera",
            Composer = "坂本龍一"
        };

        Assert.True(LocalTagWriter.Write(path, metadata).Written);

        TrackMetadata reread = LocalTagReader.Read(path);

        Assert.Equal("Corazón partío", reread.Title);
        Assert.Equal("Joaquín Sabina & Peñas", reread.Artist);
        Assert.Equal("Añoranza — Volumen II", reread.Album);
        Assert.Equal("Various Artists · Ñ", reread.AlbumArtist);
        Assert.Equal("Ranchera", reread.Genre);
        Assert.Equal("坂本龍一", reread.Composer);
    }

    // MARK: - Carátula

    [Theory]
    [InlineData("mp3")]
    [InlineData("flac")]
    [InlineData("m4a")]
    public void ConPerTrackLaCaratulaQuedaIncrustada(string extension)
    {
        string path = MakeAudio("con-caratula." + extension);
        byte[] cover = OnePixelPng();

        TagWriteResult result = LocalTagWriter.Write(
            path, new TrackMetadata { Title = "Con carátula" }, CoverArtPolicy.PerTrack, cover);

        Assert.True(result.Written, result.Reason);
        Assert.Contains("carátula", result.Fields);

        using (TagLib.File file = TagLib.File.Create(path))
        {
            TagLib.IPicture picture = Assert.Single(file.Tag.Pictures);
            Assert.Equal(cover, picture.Data.Data);

            // El tipo sale de la firma de los bytes, no de la extensión de nada:
            // los bytes vienen del catálogo, sin nombre de archivo.
            Assert.Equal("image/png", picture.MimeType);
        }

        Assert.Equal(cover, LocalTagReader.Read(path).CoverArtData);
    }

    /// <summary>
    /// Sin carátula no aparece ninguna. Parece obvio, pero el defecto contrario
    /// —escribir una imagen vacía— deja al reproductor mostrando un cuadro negro
    /// en vez del ícono de "sin portada".
    /// </summary>
    [Theory]
    [InlineData("mp3")]
    [InlineData("flac")]
    [InlineData("m4a")]
    public void SinCaratulaNoSeInventaNinguna(string extension)
    {
        string path = MakeAudio("sin-caratula." + extension);

        Assert.True(LocalTagWriter.Write(path, new TrackMetadata { Title = "Pelada" }).Written);

        using TagLib.File file = TagLib.File.Create(path);
        Assert.Empty(file.Tag.Pictures);
        Assert.Null(LocalTagReader.Read(path).CoverArtData);
    }

    /// <summary>
    /// Con la política por álbum —la normal— la carátula viaja como
    /// <c>cover.jpg</c> de la carpeta, y la que el archivo ya traía <b>no se
    /// toca</b>: el catálogo no la gobierna, así que borrarla sería quitarle al
    /// usuario algo que no pidió quitar.
    /// </summary>
    [Theory]
    [InlineData("mp3")]
    [InlineData("flac")]
    [InlineData("m4a")]
    public void ConAlbumOnlyNoSeTocaLaCaratulaQueYaTenia(string extension)
    {
        string path = MakeAudio("caratula-ajena." + extension);
        byte[] suya = OnePixelPng();

        Assert.True(LocalTagWriter.Write(
            path, new TrackMetadata { Title = "Uno" }, CoverArtPolicy.PerTrack, suya).Written);

        // Otra carátula distinta, pero con la política por álbum: no entra, y la
        // que estaba tampoco se va.
        byte[] otra = [.. suya, 0x00];

        Assert.True(LocalTagWriter.Write(
            path, new TrackMetadata { Title = "Dos" }, CoverArtPolicy.AlbumOnly, otra).Written);

        using TagLib.File file = TagLib.File.Create(path);
        Assert.Equal("Dos", file.Tag.Title);
        Assert.Equal(suya, Assert.Single(file.Tag.Pictures).Data.Data);
    }

    // MARK: - Lo que el catálogo NO gobierna

    /// <summary>
    /// Rating, favorito y letra no son del archivo: el rating viaja en
    /// <c>ratings.cfg</c>, la letra como <c>.lrc</c> hermano y la categoría es
    /// organización de la biblioteca (vive en el <c>LibraryItem</c>, ni siquiera
    /// llega hasta acá). Cambiarlos no puede reescribir cincuenta megabytes de
    /// audio — y "no reescribe" se verifica byte a byte, no por el resultado que
    /// devuelve el propio código que se está probando.
    /// </summary>
    [Theory]
    [InlineData("mp3")]
    [InlineData("flac")]
    [InlineData("m4a")]
    public void RatingFavoritoYLetraDejanElArchivoIgual(string extension)
    {
        string path = MakeAudio("estrellas." + extension);

        var metadata = new TrackMetadata { Title = "Ya escrita", Artist = "Artista", Album = "Album" };
        Assert.True(LocalTagWriter.Write(path, metadata).Written);

        byte[] before = File.ReadAllBytes(path);
        DateTime modifiedBefore = File.GetLastWriteTimeUtc(path);

        metadata.Rating = 5;
        metadata.IsFavorite = true;
        metadata.SyncedLyrics = "[00:12.00]Una letra que no va al archivo";

        TagWriteResult result = LocalTagWriter.Write(path, metadata);

        Assert.False(result.Written);
        Assert.Equal(TagWriteResult.UpToDate.Reason, result.Reason);
        Assert.Equal(0, result.BytesWritten);
        Assert.Equal(before, File.ReadAllBytes(path));

        // La fecha de modificación es lo que mira la sincronización para decidir
        // si hay que volver a copiar la canción al iPod: moverla sin motivo
        // convierte poner una estrella en copiar el álbum entero otra vez.
        Assert.Equal(modifiedBefore, File.GetLastWriteTimeUtc(path));
    }

    /// <summary>
    /// Lo que el archivo traía y el catálogo no gobierna —acá, un comentario—
    /// sigue estando después de escribir. El escritor pone campos; no rehace el
    /// archivo.
    /// </summary>
    [Theory]
    [InlineData("mp3")]
    [InlineData("flac")]
    [InlineData("m4a")]
    public void SeConservaLoQueElCatalogoNoGobierna(string extension)
    {
        string path = MakeAudio("comentario." + extension);

        using (TagLib.File original = TagLib.File.Create(path))
        {
            original.Tag.Comment = "Ripeado en 2003";
            original.Save();
        }

        Assert.True(LocalTagWriter.Write(path, new TrackMetadata { Title = "Nuevo título" }).Written);

        using TagLib.File file = TagLib.File.Create(path);
        Assert.Equal("Nuevo título", file.Tag.Title);
        Assert.Equal("Ripeado en 2003", file.Tag.Comment);
    }

    /// <summary>
    /// Un campo que el catálogo no dice (<c>null</c>) no borra el que el archivo
    /// tenía. "Sin dato" no es "vacío": es la misma regla de "ausente ≠ cero"
    /// que rige el resto del catálogo.
    /// </summary>
    [Theory]
    [InlineData("mp3")]
    [InlineData("flac")]
    [InlineData("m4a")]
    public void UnCampoNuloNoBorraLoQueHabia(string extension)
    {
        string path = MakeAudio("nulos." + extension);

        Assert.True(LocalTagWriter.Write(
            path, new TrackMetadata { Title = "Título", Artist = "Artista", Genre = "Jazz" }).Written);

        // El catálogo solo dice el título; del género y del artista no dice nada.
        Assert.True(LocalTagWriter.Write(path, new TrackMetadata { Title = "Otro título" }).Written);

        using TagLib.File file = TagLib.File.Create(path);
        Assert.Equal("Otro título", file.Tag.Title);
        Assert.Equal("Jazz", file.Tag.Genres[0]);
        Assert.Equal("Artista", file.Tag.Performers[0]);
    }

    // MARK: - Formatos que no se etiquetan

    [Theory]
    [InlineData("wav")]
    [InlineData("aiff")]
    [InlineData("ogg")]
    public void LosFormatosQueNoSeEtiquetanNoSeTocan(string extension)
    {
        // No hace falta que el contenido sea válido: el formato se descarta por
        // la extensión, antes de abrir nada. Eso es justamente lo que se prueba.
        string path = Path.Combine(_root, "no-etiquetable." + extension);
        File.WriteAllBytes(path, [1, 2, 3, 4]);

        Assert.False(LocalTagWriter.CanWrite(path));

        TagWriteResult result = LocalTagWriter.Write(path, new TrackMetadata { Title = "No" });

        Assert.False(result.Written);
        Assert.NotNull(result.Reason);
        Assert.Equal<byte[]>([1, 2, 3, 4], File.ReadAllBytes(path));
    }

    // MARK: - Paridad con la Mac

    /// <summary>
    /// ID3v2.3 y no la 2.4 que TagLib# usaría por omisión: es la versión que lee
    /// el tagcache de Rockbox y la misma que escribe <c>ID3Writer.swift</c>. Sin
    /// esto, las dos apps dejarían el mismo archivo con etiquetas distintas.
    /// </summary>
    [Fact]
    public void ElMp3QuedaEnId3v23()
    {
        string path = MakeAudio("version.mp3");

        Assert.True(LocalTagWriter.Write(path, new TrackMetadata { Title = "Versión" }).Written);

        using TagLib.File file = TagLib.File.Create(path);
        var id3 = (TagLib.Id3v2.Tag)file.GetTag(TagLib.TagTypes.Id3v2);

        Assert.Equal(3, id3.Version);
    }

    // MARK: - Escritura atómica y errores

    [Theory]
    [InlineData("mp3")]
    [InlineData("flac")]
    [InlineData("m4a")]
    public void NoQuedanTemporalesAlLadoDeLaMusica(string extension)
    {
        string path = MakeAudio("atomico." + extension);

        Assert.True(LocalTagWriter.Write(path, new TrackMetadata { Title = "Atómico" }).Written);

        Assert.Equal(["atomico." + extension], Directory.GetFiles(_root).Select(Path.GetFileName));
    }

    [Fact]
    public void UnArchivoQueNoEstaNoRompe()
    {
        TagWriteResult result = LocalTagWriter.Write(
            Path.Combine(_root, "fantasma.mp3"), new TrackMetadata { Title = "Nadie" });

        Assert.False(result.Written);
        Assert.Equal("el archivo no está", result.Reason);
    }

    [Fact]
    public void SinMetadataNoSeEscribe()
    {
        string path = MakeAudio("sin-metadata.mp3");
        byte[] before = File.ReadAllBytes(path);

        TagWriteResult result = LocalTagWriter.Write(path, metadata: null);

        Assert.False(result.Written);
        Assert.Equal(before, File.ReadAllBytes(path));
    }

    [Fact]
    public void CanWriteReconoceLosTresFormatosSinImportarMayusculas()
    {
        Assert.True(LocalTagWriter.CanWrite("a.MP3"));
        Assert.True(LocalTagWriter.CanWrite("a.Flac"));
        Assert.True(LocalTagWriter.CanWrite("a.m4a"));
        Assert.False(LocalTagWriter.CanWrite("a.wav"));
        Assert.False(LocalTagWriter.CanWrite("sin-extension"));
        Assert.False(LocalTagWriter.CanWrite(null));
        Assert.False(LocalTagWriter.CanWrite(""));
    }

    // MARK: - Fixture

    private string MakeAudio(string name)
    {
        string path = Path.Combine(_root, name);

        switch (Path.GetExtension(name).TrimStart('.').ToLowerInvariant())
        {
            case "mp3": MinimalAudioFiles.WriteMp3(path); break;
            case "flac": MinimalAudioFiles.WriteFlac(path); break;
            case "m4a": MinimalAudioFiles.WriteM4a(path); break;
            default: throw new ArgumentException("formato sin fixture: " + name, nameof(name));
        }

        return path;
    }

    /// <summary>Un PNG de 1×1 de verdad, para que la firma de los bytes sea la de un PNG.</summary>
    private static byte[] OnePixelPng() => Convert.FromBase64String(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==");
}
