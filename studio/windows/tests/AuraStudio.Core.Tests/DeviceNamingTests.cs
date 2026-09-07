using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// Cómo se llama cada archivo <b>en el iPod</b> (ST-244, contrato recibido de
/// ST-221). Es lo que el usuario ve con el aparato en la mano, así que un
/// descuido acá se nota más que cualquier otro.
/// </summary>
public class DeviceNamingTests
{
    // MARK: - El nombre sale del original, no del preparado

    /// <summary>
    /// Desde que lo preparado se nombra por identificador (ST-241), tomar el
    /// nombre del preparado le mostraría al usuario <c>A1B2C3D4-….mpg</c> donde
    /// tenía el nombre de su video.
    /// </summary>
    [Fact]
    public void ElNombreEnElIPodSaleDelOriginalYLaExtensionDelDerivado()
    {
        var id = Guid.Parse("a1b2c3d4-5e6f-4a7b-8c9d-0e1f2a3b4c5d");

        var video = new LibraryItem
        {
            Id = id,
            Kind = LibraryItemKind.Video,
            SourcePath = @"D:\videos\Vacaciones en la playa.mkv",
            PreparedPath = @"X:\Bib\.preparados\A1B2C3D4-5E6F-4A7B-8C9D-0E1F2A3B4C5D.mpg"
        };

        Assert.Equal("Vacaciones en la playa.mpg", SyncLayout.DeviceFilename(video));
        Assert.Equal("Videos/Vacaciones en la playa.mpg", SyncLayout.DestinationRelativePath(video));
    }

    /// <summary>Una foto que se convierte viaja con su nombre y la extensión nueva.</summary>
    [Fact]
    public void UnHeicViajaComoJpgPeroConSuNombre()
    {
        var photo = new LibraryItem
        {
            Id = Guid.NewGuid(),
            Kind = LibraryItemKind.Photo,
            SourcePath = @"D:\DCIM\IMG_0042.heic",
            PreparedPath = @"X:\Bib\.preparados\B1B2C3D4-5E6F-4A7B-8C9D-0E1F2A3B4C5D.jpg"
        };

        Assert.Equal("Photos/IMG_0042.jpg", SyncLayout.DestinationRelativePath(photo));
    }

    // MARK: - El choque en la carpeta plana

    /// <summary>
    /// <c>/Photos/</c> es plana en el iPod: dos <c>IMG_1.jpg</c> de carpetas
    /// distintas del usuario chocan ahí y no antes. El primero en orden de
    /// catálogo conserva el nombre limpio.
    /// </summary>
    [Fact]
    public void DosOriginalesConElMismoNombreNoSePisan()
    {
        var claimed = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        Assert.Equal("Photos/IMG_1.jpg",
            SyncLayout.UniqueDestination("Photos/IMG_1.jpg", claimed, SyncLayout.DeviceFilenameMaxBytes));

        Assert.Equal("Photos/IMG_1 2.jpg",
            SyncLayout.UniqueDestination("Photos/IMG_1.jpg", claimed, SyncLayout.DeviceFilenameMaxBytes));

        Assert.Equal("Photos/IMG_1 3.jpg",
            SyncLayout.UniqueDestination("Photos/IMG_1.jpg", claimed, SyncLayout.DeviceFilenameMaxBytes));
    }

    /// <summary>
    /// Y vale para la música: dos canciones con el mismo artista, álbum y título
    /// caían en la misma ruta y una pisaba a la otra en silencio — el usuario
    /// terminaba con menos canciones de las que mandó.
    /// </summary>
    [Fact]
    public void DosCancionesConMismoArtistaAlbumYTituloTampocoSePisan()
    {
        var claimed = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        const string path = "Music/Artista/Álbum/Título.mp3";

        Assert.Equal(path, SyncLayout.UniqueDestination(path, claimed));
        Assert.Equal("Music/Artista/Álbum/Título 2.mp3", SyncLayout.UniqueDestination(path, claimed));
    }

    /// <summary>
    /// El sufijo <b>nunca se mutila</b>: si se recortara el nombre ya sufijado,
    /// " 12" quedaría en " 1" y volverían a ser dos archivos con el mismo
    /// nombre — justo lo que esto viene a evitar. El presupuesto se calcula
    /// antes y se recorta la base.
    /// </summary>
    [Fact]
    public void ElNombreConSufijoNoSePasaDelLimiteDelFirmware()
    {
        var claimed = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        // Un nombre que ya está pegado al límite, con acentos (más bytes que
        // caracteres), y su extensión.
        string stem = new('á', 45);
        string path = $"Photos/{stem}.jpg";

        Assert.Equal(path, SyncLayout.UniqueDestination(path, claimed, SyncLayout.DeviceFilenameMaxBytes));

        string second = SyncLayout.UniqueDestination(path, claimed, SyncLayout.DeviceFilenameMaxBytes);

        Assert.EndsWith(" 2.jpg", second);
        Assert.True(
            System.Text.Encoding.UTF8.GetByteCount(second["Photos/".Length..]) <= SyncLayout.DeviceFilenameMaxBytes,
            $"«{second}» se pasa del buffer de 96 bytes del firmware");
    }

    /// <summary>
    /// La música no tiene ese límite: sus carpetas no son planas y el tagcache
    /// indexa a cualquier profundidad. Ponérselo le cambiaría la ruta a canciones
    /// que ya están en el iPod y las haría copiar de nuevo, sin ganar nada.
    /// </summary>
    [Fact]
    public void LaMusicaNoTieneLimiteDeNombreYLaFotoSi()
    {
        Assert.Equal(int.MaxValue, SyncLayout.FilenameBudgetFor(LibraryItemKind.Music));
        Assert.Equal(SyncLayout.DeviceFilenameMaxBytes, SyncLayout.FilenameBudgetFor(LibraryItemKind.Photo));
        Assert.Equal(SyncLayout.DeviceFilenameMaxBytes, SyncLayout.FilenameBudgetFor(LibraryItemKind.Video));
    }
}

/// <summary>
/// Lo que va al catálogo va <b>ya canónico</b> (ST-244, contrato de ST-221).
///
/// <para>La Mac tuvo un defecto donde la tolerancia de ST-102 a rutas con
/// separadores de Windows conservaba la ruta como llegó y la volvía a guardar
/// con <c>\</c> — que del otro lado es <b>un solo componente con barras
/// adentro</b>, no una ruta—, corrompiendo el catálogo compartido. Esta es la
/// prueba equivalente en Windows: <b>leer es tolerante, escribir es
/// canónico</b>, y escribir nunca conserva la forma en que llegó.</para>
/// </summary>
public class CatalogCanonicalWriteTests : IDisposable
{
    private readonly string _root;
    private readonly LibraryStore _store;

    public CatalogCanonicalWriteTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "AuraCanon-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
        _store = new LibraryStore(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ }
    }

    /// <summary>
    /// Una ruta que llega con <c>\</c> —de un catálogo que escribió una versión
    /// con el defecto— se lee igual, pero se vuelve a guardar con <c>/</c>.
    /// </summary>
    [Fact]
    public void UnaRutaQueLlegaConBarrasInvertidasSeGuardaConBarras()
    {
        Guid id = Guid.NewGuid();

        LibraryCatalogStore.Save(_root, new PersistedLibrary
        {
            Items =
            [
                new PersistedLibraryItem
                {
                    Id = id,
                    SourceRelativePath = @"Música\Artista\a.mp3",
                    Kind = "music"
                }
            ]
        });

        _store.SaveItems(_store.LoadItems());

        Assert.Equal("Música/Artista/a.mp3",
            LibraryCatalogStore.Load(_root).Items[0].SourceRelativePath);
    }

    /// <summary>Y una que llega descompuesta se vuelve a guardar compuesta (addendum de ST-241).</summary>
    [Fact]
    public void UnaRutaQueLlegaDescompuestaSeGuardaCompuesta()
    {
        LibraryCatalogStore.Save(_root, new PersistedLibrary
        {
            Items =
            [
                new PersistedLibraryItem
                {
                    Id = Guid.NewGuid(),
                    SourceRelativePath = "Mu\u0301sica/Artista/a.mp3",
                    Kind = "music"
                }
            ]
        });

        _store.SaveItems(_store.LoadItems());

        string stored = LibraryCatalogStore.Load(_root).Items[0].SourceRelativePath;

        Assert.Equal("M\u00FAsica/Artista/a.mp3", stored);
        Assert.NotEqual("Mu\u0301sica/Artista/a.mp3", stored);
    }
}
