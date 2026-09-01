using System.Text.Json;
using AuraStudio.Core.Library;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// La biblioteca es **compartida**: el dueño usa la misma carpeta desde la Mac
/// y desde Windows. Estas pruebas fijan la mitad que más fácil se rompe sin que
/// nadie lo note — que lo que Windows <b>escribe</b> sea lo que macOS puede
/// leer.
///
/// <para>Por qué "sin que nadie lo note": la app de macOS decodifica con
/// <c>try? JSONDecoder().decode(...)</c> y un <c>JSONDecoder()</c> por omisión.
/// Lo que no puede leer <b>no da error</b>: deja la biblioteca vacía. Un
/// nombre de campo con una letra distinta, o una fecha en el formato
/// equivocado, se ven exactamente igual que "no hay nada".</para>
/// </summary>
public class SwiftInteropTests : IDisposable
{
    private readonly string _root;

    public SwiftInteropTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "AuraSwift-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { /* best effort */ }
    }

    /// <summary>Un catálogo con todos los campos poblados, escrito por esta app.</summary>
    private JsonElement WriteFullCatalog()
    {
        var id = Guid.Parse("F26DBF19-0C21-4662-9A78-84BFBC2F0482");

        LibraryCatalogStore.Save(_root, new PersistedLibrary
        {
            Items =
            [
                new PersistedLibraryItem
                {
                    Id = id,
                    SourceRelativePath = "Música/Soda Stereo/Signos/01 Sin sobresaltos.mp3",
                    Kind = "music",
                    Status = "ready",
                    PreparedRelativePath = ".preparados/x.mp3",
                    CoverRelativePath = ".portadas/x.jpg",
                    Category = "Videos",
                    SeriesName = "Chespirito",
                    Season = 1,
                    Episode = 2,
                    PhotoAlbum = "Viaje",
                    MetadataEditedByUser = true,
                    AddedAt = new DateTimeOffset(2026, 8, 18, 12, 0, 0, TimeSpan.Zero),
                    Metadata = new PersistedTrackMetadata
                    {
                        Title = "Sin sobresaltos",
                        Artist = "Soda Stereo",
                        Album = "Signos",
                        AlbumArtist = "Soda Stereo",
                        Year = "1986",
                        Genre = "Rock",
                        Composer = "Cerati",
                        TrackNumber = 1,
                        SyncedLyrics = "[00:01.00] hola",
                        MusicBrainzRecordingId = "83c68fe1-9660-4e4a-ad7b-f27815730606",
                        MusicBrainzReleaseId = "011a766d-162f-4f4b-919e-6b42a8a10cb4",
                        DurationSeconds = 214.5,
                        Rating = 4,
                        IsFavorite = true,
                        DiscNumber = 1
                    }
                }
            ],
            Playlists =
            [
                new PersistedPlaylist
                {
                    Id = id,
                    Name = "Rolas del camino",
                    TrackItemIds = [id],
                    ImageRelativePath = ".portadas/lista.jpg"
                }
            ]
        });

        using var document = JsonDocument.Parse(
            File.ReadAllText(LibraryCatalogStore.CatalogPath(_root)));
        return document.RootElement.Clone();
    }

    // MARK: - Nombres de campo, exactos

    [Fact]
    public void TheFieldNamesAreTheOnesSwiftDeclares()
    {
        // El decodificador de Swift SÍ distingue mayúsculas. Estos tres son los
        // que no coinciden con la conversión automática a camelCase, y por eso
        // son los que se romperían sin darse cuenta.
        JsonElement root = WriteFullCatalog();
        JsonElement metadata = root.GetProperty("items")[0].GetProperty("metadata");

        Assert.True(metadata.TryGetProperty("musicBrainzRecordingID", out _));
        Assert.True(metadata.TryGetProperty("musicBrainzReleaseID", out _));
        Assert.False(metadata.TryGetProperty("musicBrainzRecordingId", out _));

        Assert.True(root.GetProperty("playlists")[0].TryGetProperty("trackItemIDs", out _));
    }

    [Fact]
    public void EveryFieldWrittenIsOneSwiftKnows()
    {
        // Un campo de más no rompe a Swift (lo ignora), pero un nombre mal
        // escrito sí pierde el dato en silencio. Se fija la lista completa.
        JsonElement item = WriteFullCatalog().GetProperty("items")[0];

        string[] expected =
        [
            "id", "sourceRelativePath", "kind", "status", "metadata",
            "preparedRelativePath", "coverRelativePath", "category", "seriesName",
            "season", "episode", "photoAlbum", "metadataEditedByUser", "addedAt"
        ];

        Assert.Equal(
            [.. expected.Order(StringComparer.Ordinal)],
            [.. item.EnumerateObject().Select(p => p.Name).Order(StringComparer.Ordinal)]);
    }

    [Fact]
    public void EveryMetadataFieldIsOneSwiftKnows()
    {
        JsonElement metadata = WriteFullCatalog().GetProperty("items")[0].GetProperty("metadata");

        string[] expected =
        [
            "title", "artist", "album", "albumArtist", "year", "genre", "composer",
            "trackNumber", "syncedLyrics", "musicBrainzRecordingID", "musicBrainzReleaseID",
            "durationSeconds", "rating", "isFavorite", "discNumber"
        ];

        Assert.Equal(
            [.. expected.Order(StringComparer.Ordinal)],
            [.. metadata.EnumerateObject().Select(p => p.Name).Order(StringComparer.Ordinal)]);
    }

    // MARK: - Tipos, exactos

    [Fact]
    public void TheDateIsWrittenAsANumberBecauseThatIsWhatSwiftReads()
    {
        // `JSONDecoder()` por omisión espera un Double con los segundos desde
        // 2001. Un texto ISO lo hace fallar, y con `try?` eso significa
        // "biblioteca vacía", no "error".
        JsonElement addedAt = WriteFullCatalog().GetProperty("items")[0].GetProperty("addedAt");

        Assert.Equal(JsonValueKind.Number, addedAt.ValueKind);
        Assert.Equal(
            new DateTimeOffset(2026, 8, 18, 12, 0, 0, TimeSpan.Zero),
            AppleEpochDateConverter.FromAppleSeconds(addedAt.GetDouble()));
    }

    [Fact]
    public void TheIdentifiersAreWrittenLikeSwiftWritesThem()
    {
        // UUID de Foundation se codifica en mayúsculas con guiones.
        string id = WriteFullCatalog().GetProperty("items")[0].GetProperty("id").GetString()!;

        Assert.Equal("F26DBF19-0C21-4662-9A78-84BFBC2F0482", id);
    }

    [Fact]
    public void AnAbsentValueIsAnAbsentKeyNotANull()
    {
        // Swift decodifica un opcional ausente como nil sin problema; un `null`
        // explícito también, pero macOS omite la clave y conviene escribir
        // igual para que los archivos se puedan comparar.
        LibraryCatalogStore.Save(_root, new PersistedLibrary
        {
            Items = [new PersistedLibraryItem { Id = Guid.NewGuid(), SourceRelativePath = "a.mp3" }]
        });

        using var document = JsonDocument.Parse(File.ReadAllText(LibraryCatalogStore.CatalogPath(_root)));
        JsonElement item = document.RootElement.GetProperty("items")[0];

        Assert.False(item.TryGetProperty("metadata", out _));
        Assert.False(item.TryGetProperty("addedAt", out _));
        Assert.False(item.TryGetProperty("season", out _));
    }

    // MARK: - Ida y vuelta completa

    [Fact]
    public void WhatWindowsWritesWindowsReadsBackIdentical()
    {
        JsonElement written = WriteFullCatalog();
        Assert.Equal(JsonValueKind.Object, written.ValueKind);

        PersistedLibrary reloaded = LibraryCatalogStore.Load(_root);
        PersistedLibraryItem item = Assert.Single(reloaded.Items);

        Assert.Equal("Sin sobresaltos", item.Metadata!.Title);
        Assert.Equal("83c68fe1-9660-4e4a-ad7b-f27815730606", item.Metadata.MusicBrainzRecordingId);
        Assert.Equal(new DateTimeOffset(2026, 8, 18, 12, 0, 0, TimeSpan.Zero), item.AddedAt);
        Assert.Equal(1, item.Season);
        Assert.True(item.MetadataEditedByUser);

        PersistedPlaylist playlist = Assert.Single(reloaded.Playlists);
        Assert.Equal("Rolas del camino", playlist.Name);
        Assert.Single(playlist.TrackItemIds);
    }

    [Fact]
    public void ACatalogFromMacOsSurvivesBeingRewrittenByWindows()
    {
        // El caso que de verdad ocurre: la Mac escribe, Windows abre y guarda,
        // la Mac vuelve a abrir. Nada se puede perder en ese viaje.
        File.WriteAllText(LibraryCatalogStore.CatalogPath(_root), """
        {
          "items" : [
            {
              "addedAt" : 808784218.004062,
              "coverRelativePath" : ".portadas/F26DBF19-0C21-4662-9A78-84BFBC2F0482.jpg",
              "id" : "F26DBF19-0C21-4662-9A78-84BFBC2F0482",
              "kind" : "music",
              "metadata" : {
                "album" : "You've Come A Long Way, Baby",
                "albumArtist" : "Fatboy Slim",
                "artist" : "Fatboy Slim",
                "musicBrainzRecordingID" : "83c68fe1-9660-4e4a-ad7b-f27815730606",
                "musicBrainzReleaseID" : "011a766d-162f-4f4b-919e-6b42a8a10cb4",
                "trackNumber" : 1
              },
              "metadataEditedByUser" : true,
              "sourceRelativePath" : "Música/Fatboy Slim/01 Right Here.m4a",
              "status" : "ready"
            }
          ]
        }
        """);

        PersistedLibrary fromMac = LibraryCatalogStore.Load(_root);
        LibraryCatalogStore.Save(_root, fromMac);

        using var document = JsonDocument.Parse(File.ReadAllText(LibraryCatalogStore.CatalogPath(_root)));
        JsonElement item = document.RootElement.GetProperty("items")[0];
        JsonElement metadata = item.GetProperty("metadata");

        // Los identificadores de MusicBrainz siguen ahí y con SU nombre.
        Assert.Equal("83c68fe1-9660-4e4a-ad7b-f27815730606",
            metadata.GetProperty("musicBrainzRecordingID").GetString());
        // La fecha vuelve a salir como número, con el mismo valor.
        Assert.Equal(808784218.004062, item.GetProperty("addedAt").GetDouble(), 3);
        // Y el id conserva su forma.
        Assert.Equal("F26DBF19-0C21-4662-9A78-84BFBC2F0482", item.GetProperty("id").GetString());
        Assert.True(item.GetProperty("metadataEditedByUser").GetBoolean());
    }
}
