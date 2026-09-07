using System.Security.Cryptography;
using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La migración de una biblioteca anterior (ST-246).
///
/// <para>Lo que se protege acá es lo más delicado de toda la ronda: los
/// archivos del usuario. Abrir su biblioteca no puede escribirle nada, migrar
/// tiene que pedírselo, y correr la migración dos veces no puede tocar nada la
/// segunda.</para>
/// </summary>
public class LibraryMigrationTests : IDisposable
{
    private readonly string _root;
    private readonly LibraryStore _store;

    public LibraryMigrationTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "AuraMigra-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
        _store = new LibraryStore(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ }
    }

    // MARK: - Abrir no escribe nada

    /// <summary>
    /// <b>La prueba obligatoria.</b> Abrir una biblioteca anterior <b>no escribe
    /// un solo archivo</b>: lo único que pasa es que <c>storage</c> se infiere en
    /// memoria. El catálogo se deja fuera del cálculo a propósito —persistir la
    /// inferencia sí es parte del contrato—; lo que no puede cambiar es la
    /// música, las fotos, los videos y las carátulas del usuario.
    /// </summary>
    [Fact]
    public void AbrirUnaBibliotecaAnteriorNoTocaNingunArchivo()
    {
        LibraryItem song = CopiedMusic("vieja.mp3", "Ingrata", "Café Tacvba", "Ré");
        LegacyCatalog(song, withStorage: false);

        string before = HashOfLibraryFiles();

        IReadOnlyList<LibraryItem> loaded = _store.LoadItems();

        Assert.Single(loaded);
        Assert.Equal(before, HashOfLibraryFiles());
    }

    [Fact]
    public void LaInferenciaDeStorageOcurreEnMemoriaYSeCuentaAlCargar()
    {
        LegacyCatalog(CopiedMusic("a.mp3", "T", "A", "Á"), withStorage: false);

        LibraryLoad load = _store.Load();

        Assert.Equal(1, load.ItemsWithoutStorage);
        Assert.Equal(ItemStorage.Copy, load.Items[0].StorageKind);
    }

    // MARK: - Cuándo se avisa

    [Fact]
    public void SeAvisaSiFaltaStorage()
    {
        LibraryMigrationNeed need = LibraryMigrationScanner.Detect([Referenced("a.mp3")], 1);

        Assert.True(need.Needed);
        Assert.Equal(1, need.ItemsWithoutStorage);
    }

    [Fact]
    public void SeAvisaSiHayPreparadosConNombreViejo()
    {
        LibraryItem video = new()
        {
            Id = Guid.NewGuid(),
            Kind = LibraryItemKind.Video,
            SourcePath = @"D:\videos\peli.mkv",
            PreparedPath = Path.Combine(_root, ".preparados", "peli.mpg")
        };

        LibraryMigrationNeed need = LibraryMigrationScanner.Detect([video], 0);

        Assert.True(need.Needed);
        Assert.Equal(1, need.LegacyPrepared);
    }

    [Fact]
    public void UnaBibliotecaAlDiaNoAvisa()
    {
        var id = Guid.NewGuid();

        LibraryItem video = new()
        {
            Id = id,
            Kind = LibraryItemKind.Video,
            SourcePath = @"D:\videos\peli.mkv",
            Storage = ItemStorageRules.ReferenceValue,
            PreparedPath = Path.Combine(_root, ".preparados", CatalogPath.PreparedFileName(id, "mpg"))
        };

        Assert.False(LibraryMigrationScanner.Detect([video], 0).Needed);
    }

    /// <summary>
    /// La música copiada es su propio preparado (ST-241) y vive en
    /// <c>Música/</c>, no en <c>.preparados/</c>: su nombre no tiene por qué ser
    /// un identificador y contarla sería avisar de una migración que no hace
    /// falta, para siempre.
    /// </summary>
    [Fact]
    public void LaMusicaCopiadaNoCuentaComoPreparadoViejo()
    {
        LibraryItem song = CopiedMusic("Ingrata.mp3", "Ingrata", "Café Tacvba", "Ré");
        song.PreparedPath = song.SourcePath;

        Assert.False(LibraryMigrationScanner.HasLegacyPreparedName(song));
        Assert.False(LibraryMigrationScanner.Detect([song], 0).Needed);
    }

    // MARK: - Qué hace la migración

    [Fact]
    public async Task LeEscribeLasEtiquetasDelCatalogoALasCopias()
    {
        LibraryItem song = CopiedMusic("vieja.mp3", "Ingrata", "Café Tacvba", "Ré");

        // El archivo copiado tiene otro título: es una biblioteca de antes de
        // que Studio supiera escribir etiquetas.
        LocalTagWriter.Write(song.SourcePath, new TrackMetadata { Title = "Pista 1" });

        LibraryMigrationSummary summary = await LibraryMigrator.RunAsync(_root, [song]);

        Assert.Equal(1, summary.Tagged);
        Assert.Equal(0, summary.Failed);
        Assert.Equal("Ingrata", LocalTagReader.Read(song.SourcePath).Title);
    }

    [Fact]
    public async Task RenombraElPreparadoViejoYSuPosterHermano()
    {
        var id = Guid.NewGuid();
        string legacy = TouchInside(Path.Combine(".preparados", "peli.mpg"));
        TouchInside(Path.Combine(".preparados", "peli.jpg"));

        LibraryItem video = new()
        {
            Id = id,
            Kind = LibraryItemKind.Video,
            SourcePath = @"D:\videos\peli.mkv",
            Storage = ItemStorageRules.ReferenceValue,
            PreparedPath = legacy
        };

        LibraryMigrationSummary summary = await LibraryMigrator.RunAsync(_root, [video]);

        string expected = Path.Combine(_root, ".preparados", CatalogPath.PreparedFileName(id, "mpg"));

        Assert.Equal(1, summary.PreparedRenamed);
        Assert.Equal(expected, video.PreparedPath);
        Assert.True(File.Exists(expected));
        Assert.False(File.Exists(legacy));

        // Y el póster viajó con él: si se quedaba con el nombre viejo, el video
        // perdía su carátula sin que nadie lo notara.
        Assert.True(File.Exists(CatalogPath.PosterFor(expected)));
    }

    [Fact]
    public async Task BorraLoQueQuedoHuerfanoEnPreparados()
    {
        string orphan = TouchInside(Path.Combine(".preparados", "de-algo-que-ya-no-esta.mpg"));

        LibraryMigrationSummary summary = await LibraryMigrator.RunAsync(_root, []);

        Assert.Equal(1, summary.OrphansDeleted);
        Assert.False(File.Exists(orphan));
    }

    // MARK: - Se puede correr dos veces, y se puede parar

    /// <summary>
    /// <b>La segunda corrida no toca nada.</b> Se comprueba con el resumen y
    /// además con el árbol de la biblioteca byte a byte: si algo se reescribiera
    /// —aunque quedara igual de contenido— cambiaría la fecha, y con eso la
    /// sincronización volvería a copiar la biblioteca entera al iPod.
    /// </summary>
    [Fact]
    public async Task CorrerlaDosVecesNoTocaNadaLaSegunda()
    {
        LibraryItem song = CopiedMusic("vieja.mp3", "Ingrata", "Café Tacvba", "Ré");
        LocalTagWriter.Write(song.SourcePath, new TrackMetadata { Title = "Pista 1" });

        await LibraryMigrator.RunAsync(_root, [song]);

        string after = HashOfLibraryFiles();
        DateTime modified = File.GetLastWriteTimeUtc(song.SourcePath);

        LibraryMigrationSummary second = await LibraryMigrator.RunAsync(_root, [song]);

        Assert.Equal(0, second.Touched);
        Assert.Equal(after, HashOfLibraryFiles());
        Assert.Equal(modified, File.GetLastWriteTimeUtc(song.SourcePath));
    }

    /// <summary>
    /// Cancelar deja hecho lo hecho —es trabajo válido, no algo que deshacer— y
    /// lo que falta se hace en la siguiente corrida. Y no se borra ningún
    /// huérfano en una corrida cancelada: la lista de lo referenciado está a
    /// medias, y borrar con esa lista se llevaría archivos que sí hacen falta.
    /// </summary>
    [Fact]
    public async Task CancelarADeMitadNoRompeYSeReanuda()
    {
        LibraryItem first = CopiedMusic("una.mp3", "Una", "Artista", "Álbum");
        LibraryItem second = CopiedMusic("otra.mp3", "Otra", "Artista", "Álbum");

        LocalTagWriter.Write(first.SourcePath, new TrackMetadata { Title = "Vieja" });
        LocalTagWriter.Write(second.SourcePath, new TrackMetadata { Title = "Vieja" });

        string orphan = TouchInside(Path.Combine(".preparados", "huerfano.mpg"));

        using var cancellation = new CancellationTokenSource();

        LibraryMigrationSummary partial = await LibraryMigrator.RunAsync(
            _root, [first, second],
            onProgress: (index, _, _) => { if (index == 1) cancellation.Cancel(); },
            ct: cancellation.Token);

        Assert.True(partial.Cancelled);
        Assert.Equal(0, partial.OrphansDeleted);
        Assert.True(File.Exists(orphan));

        // Lo que alcanzó a hacer quedó hecho, y la segunda corrida termina.
        LibraryMigrationSummary rest = await LibraryMigrator.RunAsync(_root, [first, second]);

        Assert.False(rest.Cancelled);
        Assert.Equal("Una", LocalTagReader.Read(first.SourcePath).Title);
        Assert.Equal("Otra", LocalTagReader.Read(second.SourcePath).Title);
    }

    /// <summary>
    /// Un original que no está se salta: no se borra del catálogo ni se cuenta
    /// como error (ST-241). El disco puede estar desconectado.
    /// </summary>
    [Fact]
    public async Task UnArchivoQueNoEstaNoRompeLaMigracion()
    {
        LibraryItem ghost = CopiedMusic("fantasma.mp3", "Ingrata", "Café Tacvba", "Ré", write: false);

        LibraryMigrationSummary summary = await LibraryMigrator.RunAsync(_root, [ghost]);

        Assert.Equal(0, summary.Failed);
        Assert.Empty(summary.Errors);
    }

    // MARK: - Fixture

    private LibraryItem CopiedMusic(
        string name, string title, string artist, string album, bool write = true)
    {
        string relative = Path.Combine("Música", artist, album, name);
        string path = Path.Combine(_root, relative);

        if (write) MinimalAudioFiles.WriteMp3(path);

        return new LibraryItem
        {
            Id = Guid.NewGuid(),
            Kind = LibraryItemKind.Music,
            SourcePath = path,
            Storage = ItemStorageRules.CopyValue,
            PreparedPath = path,
            Metadata = new TrackMetadata { Title = title, Artist = artist, Album = album }
        };
    }

    private static LibraryItem Referenced(string name) => new()
    {
        Id = Guid.NewGuid(),
        Kind = LibraryItemKind.Music,
        SourcePath = Path.Combine(@"D:\ajena", name)
    };

    /// <summary>Un catálogo como el que escribía una versión anterior.</summary>
    private void LegacyCatalog(LibraryItem item, bool withStorage)
    {
        LibraryCatalogStore.Save(_root, new PersistedLibrary
        {
            Items =
            [
                new PersistedLibraryItem
                {
                    Id = item.Id,
                    SourceRelativePath = _store.ToStoredPath(item.SourcePath),
                    Kind = "music",
                    Storage = withStorage ? item.Storage : null
                }
            ]
        });
    }

    private string TouchInside(string relative)
    {
        string path = Path.Combine(_root, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, [1, 2, 3]);
        return path;
    }

    /// <summary>
    /// El resumen de <b>los archivos</b> de la biblioteca: ruta, tamaño y
    /// contenido. El catálogo se deja fuera porque persistir la inferencia de
    /// <c>storage</c> sí es parte del contrato; lo que no puede cambiar sin que
    /// el usuario lo pida es su música.
    /// </summary>
    private string HashOfLibraryFiles()
    {
        var lines = new List<string>();

        foreach (string path in Directory
                     .EnumerateFiles(_root, "*", SearchOption.AllDirectories)
                     .Where(path => Path.GetFileName(path) != PersistedLibrary.CatalogFileName)
                     .OrderBy(path => path, StringComparer.Ordinal))
        {
            byte[] bytes = File.ReadAllBytes(path);

            lines.Add($"{Path.GetRelativePath(_root, path)}|{bytes.Length}|"
                      + Convert.ToHexString(SHA256.HashData(bytes)));
        }

        return string.Join("\n", lines);
    }
}
