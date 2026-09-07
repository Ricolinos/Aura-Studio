using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El modo copia (ST-243): dónde va cada archivo dentro de la biblioteca y qué
/// pasa al meterlo.
///
/// <para>Lo que se protege acá es el archivo del usuario: se <b>copia</b>, nunca
/// se mueve ni se toca, y la copia es la que pasa a estar bajo nuestro
/// mando.</para>
/// </summary>
public class LibraryCopyModeTests : IDisposable
{
    private readonly string _root;

    public LibraryCopyModeTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "AuraCopia-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ }
    }

    // MARK: - Dónde va

    /// <summary>
    /// La música se acomoda con el mismo criterio con el que se acomoda en el
    /// iPod: es lo que el usuario eligió en Ajustes, y tener dos reglas para lo
    /// mismo sería que la carpeta de la computadora y la del iPod no se
    /// parecieran sin que nadie lo hubiera decidido.
    /// </summary>
    [Fact]
    public void LaMusicaVaPorArtistaYAlbum()
    {
        LibraryItem song = Music("a.mp3", artist: "Café Tacvba", album: "Ré", title: "Ingrata");

        Assert.Equal("Música/Café Tacvba/Ré/Ingrata.mp3", LibraryFileLayout.RelativePath(song));
    }

    [Fact]
    public void LaMusicaRespetaLaOrganizacionElegida()
    {
        LibraryItem song = Music("a.mp3", artist: "Artista", album: "Álbum", title: "Título", track: 3);

        Assert.Equal("Música/Álbum/Título.mp3",
            LibraryFileLayout.RelativePath(song, MusicOrganization.Album));

        Assert.Equal("Música/Artista/Álbum/03 Título.mp3",
            LibraryFileLayout.RelativePath(song, MusicOrganization.ArtistAlbum,
                MusicFilenameFormat.TrackNumberTitle));
    }

    /// <summary>
    /// El WAV que se convierte llega con la extensión del archivo que de verdad
    /// se va a escribir. Si la ruta dijera <c>.wav</c> y el archivo fuera un MP3,
    /// el catálogo apuntaría a algo que no existe (ST-107).
    /// </summary>
    [Fact]
    public void LoConvertidoLlevaLaExtensionDelArchivoQueSeEscribe()
    {
        LibraryItem song = Music("a.wav", artist: "Artista", album: "Álbum", title: "Título");

        Assert.Equal("Música/Artista/Álbum/Título.mp3",
            LibraryFileLayout.RelativePath(song, extensionOverride: "mp3"));
    }

    /// <summary>
    /// Foto y video conservan su nombre: no hay un "título" mejor que el nombre
    /// que el usuario ya le puso, y renombrárselo sería no reconocer su propia
    /// foto en el Explorador.
    /// </summary>
    [Fact]
    public void LasFotosYLosVideosConservanSuNombreYVanPorCategoria()
    {
        LibraryItem photo = new() { Id = Guid.NewGuid(), Kind = LibraryItemKind.Photo, SourcePath = @"D:\DCIM\IMG_0042.jpg", Category = "Cámara" };
        LibraryItem video = new() { Id = Guid.NewGuid(), Kind = LibraryItemKind.Video, SourcePath = @"D:\cosas\Peli.mkv", Category = "Películas" };

        Assert.Equal("Imágenes/Cámara/IMG_0042.jpg", LibraryFileLayout.RelativePath(photo));
        Assert.Equal("Videos/Películas/Peli.mkv", LibraryFileLayout.RelativePath(video));

        // Y si el usuario apagó la organización por categoría, quedan planos.
        Assert.Equal("Imágenes/IMG_0042.jpg",
            LibraryFileLayout.RelativePath(photo, organizePhotosByCategory: false));

        Assert.Equal("Videos/Peli.mkv",
            LibraryFileLayout.RelativePath(video, organizeVideosByCategory: false));
    }

    [Fact]
    public void LoQueNoTraeCategoriaNoQuedaSueltoEnLaRaiz()
    {
        LibraryItem photo = new() { Id = Guid.NewGuid(), Kind = LibraryItemKind.Photo, SourcePath = @"D:\a.jpg" };

        // Una carpeta con diez mil fotos sueltas no la abre nadie.
        Assert.Equal($"Imágenes/{LibraryFileLayout.UncategorizedFolder}/a.jpg",
            LibraryFileLayout.RelativePath(photo));
    }

    // MARK: - Copiar

    [Fact]
    public void CopiarDejaElOriginalIntactoYLaCopiaEnSuLugar()
    {
        string original = Outside("original.mp3", [1, 2, 3, 4, 5]);

        LibraryCopyResult result = LibraryFileCopier.Copy(original, _root, "Música/Artista/Álbum/Título.mp3");

        Assert.True(result.Copied, result.Reason);
        Assert.Equal(5, result.BytesWritten);
        Assert.Equal(Path.Combine(_root, "Música", "Artista", "Álbum", "Título.mp3"), result.Path);
        Assert.Equal<byte[]>([1, 2, 3, 4, 5], File.ReadAllBytes(result.Path));

        // Lo que de verdad importa: el archivo del usuario sigue donde estaba y
        // como estaba.
        Assert.True(File.Exists(original));
        Assert.Equal<byte[]>([1, 2, 3, 4, 5], File.ReadAllBytes(original));
    }

    /// <summary>
    /// Dos canciones distintas con el mismo artista, álbum y título existen —las
    /// hay en vivo y en estudio— y la segunda no puede pisar a la primera.
    /// </summary>
    [Fact]
    public void UnDestinoOcupadoSeDesambiguaEnVezDePisar()
    {
        LibraryFileCopier.Copy(Outside("uno.mp3", [1]), _root, "Música/A/B/Título.mp3");
        LibraryCopyResult second = LibraryFileCopier.Copy(Outside("dos.mp3", [2]), _root, "Música/A/B/Título.mp3");

        Assert.True(second.Copied, second.Reason);
        Assert.EndsWith("Título 2.mp3", second.Path);

        Assert.Equal<byte[]>([1], File.ReadAllBytes(Path.Combine(_root, "Música", "A", "B", "Título.mp3")));
        Assert.Equal<byte[]>([2], File.ReadAllBytes(second.Path));
    }

    [Fact]
    public void LoQueYaEstaAdentroNoSeCopiaSobreSiMismo()
    {
        string inside = Path.Combine(_root, "Música", "ya.mp3");
        Directory.CreateDirectory(Path.GetDirectoryName(inside)!);
        File.WriteAllBytes(inside, [7]);

        LibraryCopyResult result = LibraryFileCopier.Copy(inside, _root, "Música/A/B/otro.mp3");

        Assert.False(result.Copied);
        Assert.Equal(inside, result.Path);
        Assert.Single(Directory.GetFiles(Path.Combine(_root, "Música"), "*", SearchOption.AllDirectories));
    }

    /// <summary>
    /// <c>C:\Bib2</c> empieza con <c>C:\Bib</c> y no está adentro de ella:
    /// comparar prefijos de texto en vez de rutas es cómo un archivo de afuera
    /// se toma por propio.
    /// </summary>
    [Fact]
    public void EstarAdentroSeDecidePorRutaYNoPorPrefijoDeTexto()
    {
        Assert.True(LibraryFileCopier.IsInside(@"C:\Bib", @"C:\Bib\Música\a.mp3"));
        Assert.False(LibraryFileCopier.IsInside(@"C:\Bib", @"C:\Bib2\Música\a.mp3"));
        Assert.False(LibraryFileCopier.IsInside(@"C:\Bib", @"D:\otra\a.mp3"));
        Assert.False(LibraryFileCopier.IsInside(@"C:\Bib", @"C:\Bib"));
    }

    [Fact]
    public void NoQuedanTemporalesNiSeCopiaLoQueNoEsta()
    {
        LibraryCopyResult missing = LibraryFileCopier.Copy(
            Path.Combine(_root, "fantasma.mp3"), _root, "Música/A/B/x.mp3");

        Assert.False(missing.Copied);
        Assert.Equal("el archivo no está", missing.Reason);

        LibraryFileCopier.Copy(Outside("uno.mp3", [1]), _root, "Música/A/B/Título.mp3");

        Assert.DoesNotContain(
            Directory.GetFiles(_root, "*", SearchOption.AllDirectories),
            path => path.EndsWith(LibraryFileCopier.TemporarySuffix, StringComparison.Ordinal));
    }

    /// <summary>
    /// Un error de disco no puede tumbar una importación de mil archivos: se
    /// devuelve el motivo y el que sigue se copia igual.
    /// </summary>
    [Fact]
    public void UnErrorDeDiscoSeExplicaYNoLanza()
    {
        var broken = new ExplodingFileSystem();

        LibraryCopyResult result = LibraryFileCopier.Copy(
            Outside("uno.mp3", [1]), _root, "Música/A/B/Título.mp3", broken);

        Assert.False(result.Copied);
        Assert.Contains("no se pudo copiar", result.Reason);
        Assert.Contains("no queda espacio", result.Reason);
    }

    // MARK: - Fixture

    private static LibraryItem Music(
        string name, string artist, string album, string title, int? track = null) =>
        new()
        {
            Id = Guid.NewGuid(),
            Kind = LibraryItemKind.Music,
            SourcePath = Path.Combine(@"D:\descargas", name),
            Metadata = new TrackMetadata
            {
                Artist = artist,
                AlbumArtist = artist,
                Album = album,
                Title = title,
                TrackNumber = track
            }
        };

    private string Outside(string name, byte[] bytes)
    {
        // Fuera de la biblioteca, que es de donde vienen los archivos del
        // usuario en modo copia.
        string directory = Path.Combine(Path.GetTempPath(), "AuraAjeno-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);

        string path = Path.Combine(directory, name);
        File.WriteAllBytes(path, bytes);
        return path;
    }

    /// <summary>Un disco que se queda sin espacio a mitad de la copia.</summary>
    private sealed class ExplodingFileSystem : ILibraryFileSystem
    {
        public bool FileExists(string path) => File.Exists(path);
        public void CreateDirectory(string path) => Directory.CreateDirectory(path);
        public void Copy(string source, string destination) => throw new IOException("no queda espacio en el disco");
        public void Move(string source, string destination) => throw new IOException("no queda espacio en el disco");
        public long Length(string path) => 0;
        public void TryDelete(string path) { }
    }
}
