using System.Text.Json;
using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El catálogo de la biblioteca (`biblioteca.json`, D-180). Lo que estos casos
/// protegen es lo que duele perder: si el catálogo se corrompe o se descarta
/// entero por un campo nuevo, el usuario tiene que rearmar su biblioteca a mano.
/// </summary>
public class LibraryPersistenceTests : IDisposable
{
    private readonly string _root;

    public LibraryPersistenceTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "AuraCatalog-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ }
    }

    // MARK: - Estados

    [Fact]
    public void OnlyStableStatesArePersisted()
    {
        // Los transitorios y los fallidos vuelven a la cola: al reabrir se
        // reintentan, en vez de quedar congelados en un estado que ya no corre.
        Assert.Equal("ready", LibraryPersistenceMapper.PersistedStatus(LibraryItemStatus.Ready));
        Assert.Equal("needsReview", LibraryPersistenceMapper.PersistedStatus(LibraryItemStatus.NeedsReview));
        Assert.Equal("queued", LibraryPersistenceMapper.PersistedStatus(LibraryItemStatus.Queued));
        Assert.Equal("queued", LibraryPersistenceMapper.PersistedStatus(LibraryItemStatus.Enriching));
        Assert.Equal("queued", LibraryPersistenceMapper.PersistedStatus(LibraryItemStatus.Transcoding(0.5)));
        Assert.Equal("queued", LibraryPersistenceMapper.PersistedStatus(LibraryItemStatus.Failed("x")));
    }

    [Fact]
    public void AnUnknownStateBecomesQueued()
    {
        Assert.Equal(LibraryItemState.Queued, LibraryPersistenceMapper.LiveStatus("transcodificando").State);
        Assert.Equal(LibraryItemState.Queued, LibraryPersistenceMapper.LiveStatus(null).State);
    }

    // MARK: - Tipos

    [Theory]
    [InlineData(LibraryItemKind.Music, "music")]
    [InlineData(LibraryItemKind.Video, "video")]
    [InlineData(LibraryItemKind.Photo, "photo")]
    [InlineData(LibraryItemKind.Unsupported, "unsupported")]
    public void KindsRoundTrip(LibraryItemKind kind, string raw)
    {
        Assert.Equal(raw, LibraryPersistenceMapper.PersistedKind(kind));
        Assert.Equal(kind, LibraryPersistenceMapper.LiveKind(raw));
    }

    // MARK: - Categorías heredadas (D-228)

    [Theory]
    [InlineData("images", "Imágenes")]
    [InlineData("homeVideos", "Series")]
    [InlineData("movies", "Películas")]
    [InlineData("aiGenerated", "IA")]
    public void OldCategoryValuesAreTranslated(string stored, string expected)
        => Assert.Equal(expected, LibraryPersistenceMapper.LiveCategory(stored));

    [Fact]
    public void AnUnknownCategoryPassesThroughUntouched()
    {
        // Puede ser un nombre nuevo, o una colección que creó el usuario.
        Assert.Equal("Conciertos", LibraryPersistenceMapper.LiveCategory("Conciertos"));
        Assert.Null(LibraryPersistenceMapper.LiveCategory(null));
    }

    // MARK: - Metadata

    [Fact]
    public void MetadataSurvivesTheRoundTrip()
    {
        var original = new TrackMetadata
        {
            Title = "Canción",
            Artist = "Artista",
            Album = "Álbum",
            AlbumArtist = "Artista del álbum",
            Year = "2013",
            Genre = "Rock",
            Composer = "Compositor",
            TrackNumber = 3,
            DiscNumber = 2,
            SyncedLyrics = "[00:01.00] hola",
            DurationSeconds = 214.5,
            Rating = 4,
            IsFavorite = true
        };

        TrackMetadata? back = LibraryPersistenceMapper.ToLive(
            LibraryPersistenceMapper.ToPersisted(original), coverArtData: null);

        Assert.NotNull(back);
        Assert.Equal("Canción", back!.Title);
        Assert.Equal("Artista del álbum", back.AlbumArtist);
        Assert.Equal(3, back.TrackNumber);
        Assert.Equal(2, back.DiscNumber);
        Assert.Equal(214.5, back.DurationSeconds);
        Assert.Equal(4, back.Rating);
        Assert.True(back.IsFavorite);
    }

    [Fact]
    public void TheCoverDoesNotTravelInsideTheJson()
    {
        // Una imagen por pista inflaría el catálogo a decenas de megabytes y
        // cada guardado sería una reescritura completa. Vive en `.portadas/`.
        var metadata = new TrackMetadata { Title = "x", CoverArtData = [1, 2, 3, 4] };
        PersistedTrackMetadata? persisted = LibraryPersistenceMapper.ToPersisted(metadata);

        string json = JsonSerializer.Serialize(persisted);
        Assert.DoesNotContain("cover", json, StringComparison.OrdinalIgnoreCase);

        // Y al volver, la portada la aporta quien la leyó del archivo.
        byte[] fromDisk = [9, 9];
        Assert.Equal(fromDisk, LibraryPersistenceMapper.ToLive(persisted, fromDisk)!.CoverArtData);
    }

    [Fact]
    public void FalseFavoriteIsNotWrittenOut()
    {
        // Un catálogo lleno de `false` explícitos no aporta nada.
        var metadata = new TrackMetadata { Title = "x", IsFavorite = false };
        Assert.Null(LibraryPersistenceMapper.ToPersisted(metadata)!.IsFavorite);
        Assert.False(LibraryPersistenceMapper.ToLive(new PersistedTrackMetadata(), null)!.IsFavorite);
    }

    // MARK: - Archivo

    [Fact]
    public void ACatalogSurvivesSaveAndLoad()
    {
        var catalog = new PersistedLibrary
        {
            Items =
            [
                new PersistedLibraryItem
                {
                    Id = Guid.NewGuid(),
                    SourceRelativePath = @"Música\Artista\Álbum\pista.mp3",
                    Kind = "music",
                    Status = "ready",
                    AddedAt = DateTimeOffset.Now,
                    Metadata = new PersistedTrackMetadata { Title = "Canción" }
                }
            ],
            Playlists = [new PersistedPlaylist { Id = Guid.NewGuid(), Name = "Mis favoritas" }]
        };

        LibraryCatalogStore.Save(_root, catalog);
        PersistedLibrary loaded = LibraryCatalogStore.Load(_root);

        Assert.Single(loaded.Items);
        Assert.Equal(@"Música\Artista\Álbum\pista.mp3", loaded.Items[0].SourceRelativePath);
        Assert.Equal("Canción", loaded.Items[0].Metadata!.Title);
        // Las playlists sobreviven aunque su módulo llegue después: cargar y
        // volver a guardar no puede perder lo que otra parte escribió.
        Assert.Single(loaded.Playlists);
        Assert.Equal("Mis favoritas", loaded.Playlists[0].Name);
    }

    [Fact]
    public void ACatalogWithoutTheNewerFieldsStillLoads()
    {
        // El caso que justifica que los campos sean anulables: uno solo
        // ausente NO puede tirar el catálogo entero.
        string json = """
        {
          "items": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "sourceRelativePath": "Musica/a.mp3",
              "kind": "music",
              "status": "ready"
            }
          ]
        }
        """;
        File.WriteAllText(LibraryCatalogStore.CatalogPath(_root), json);

        PersistedLibrary loaded = LibraryCatalogStore.Load(_root);
        Assert.Single(loaded.Items);
        Assert.Null(loaded.Items[0].MetadataEditedByUser);
        Assert.Null(loaded.Items[0].AddedAt);
        Assert.Empty(loaded.Playlists);
    }

    [Fact]
    public void AnUnreadableCatalogGivesAnEmptyLibraryNotACrash()
    {
        // Mejor arrancar vacío y que el usuario reimporte, que no abrir.
        File.WriteAllText(LibraryCatalogStore.CatalogPath(_root), "{ esto no es json");
        Assert.Empty(LibraryCatalogStore.Load(_root).Items);
    }

    [Fact]
    public void ALibraryWithoutCatalogIsSimplyEmpty()
        => Assert.Empty(LibraryCatalogStore.Load(_root).Items);

    [Fact]
    public void SavingLeavesNoTemporaryFileBehind()
    {
        LibraryCatalogStore.Save(_root, new PersistedLibrary());
        Assert.Empty(Directory.GetFiles(_root, "*.tmp"));
    }

    [Fact]
    public void SavingTwiceReplacesInsteadOfAppending()
    {
        LibraryCatalogStore.Save(_root, new PersistedLibrary
        {
            Items = [new PersistedLibraryItem { Id = Guid.NewGuid(), SourceRelativePath = "a.mp3" }]
        });
        LibraryCatalogStore.Save(_root, new PersistedLibrary());

        Assert.Empty(LibraryCatalogStore.Load(_root).Items);
    }

    // MARK: - Clasificación de un archivo soltado

    [Theory]
    [InlineData("cancion.mp3", LibraryItemKind.Music)]
    [InlineData("cancion.FLAC", LibraryItemKind.Music)]
    [InlineData("pelicula.mkv", LibraryItemKind.Video)]
    [InlineData("foto.HEIC", LibraryItemKind.Photo)]
    [InlineData("documento.pdf", LibraryItemKind.Unsupported)]
    public void ADroppedFileIsClassifiedByExtension(string name, LibraryItemKind expected)
        => Assert.Equal(expected, LibraryItem.FromDroppedFile(name).Kind);

    [Fact]
    public void ADroppedFileStartsQueuedAndDated()
    {
        LibraryItem item = LibraryItem.FromDroppedFile(@"C:\musica\a.mp3");
        Assert.Equal(LibraryItemState.Queued, item.Status.State);
        Assert.NotNull(item.AddedAt);
        Assert.NotEqual(Guid.Empty, item.Id);
        Assert.False(item.MetadataEditedByUser);
    }
}
