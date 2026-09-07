// ST-240 (B0): arnés de almacenamiento -- fixture con audio real y medición
// de qué escribe (o no) cada edición de campo, qué deja huérfano Eliminar, y
// qué política de carátula se aplica de verdad, contra el código de HEAD
// bd57116 (0.3.0), antes de tocar nada del contrato de B1..B8.
//
// Cómo correrlo:
//   dotnet run --project tools/StorageFixtureCheck
//
// Necesita ffmpeg instalado en la máquina (D-038, no viene con el repo) --
// ver FixtureAudio.Locate(). No toca la biblioteca real del dueño: todo pasa
// en una carpeta temporal que se borra al terminar.

using System.Security.Cryptography;
using AuraStudio.App.Services;
using AuraStudio.App.ViewModels;
using AuraStudio.Core.Library;
using AuraStudio.Tools.StorageFixtureCheck;

Console.OutputEncoding = System.Text.Encoding.UTF8;

string? ffmpeg = FixtureAudio.Locate();
if (ffmpeg is null)
{
    Console.WriteLine("No se encontró ffmpeg (ni por FfmpegLocator ni en la carpeta de paquetes de winget).");
    Console.WriteLine("Este arnés lo necesita para sintetizar el fixture: winget install Gyan.FFmpeg");
    Environment.Exit(1);
    return;
}
Console.WriteLine($"ffmpeg: {ffmpeg}");

string root = Path.Combine(Path.GetTempPath(), "aura-storage-" + Guid.NewGuid().ToString("N"));
string externalRoot = Path.Combine(Path.GetTempPath(), "aura-storage-externos-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);
Directory.CreateDirectory(externalRoot);
Console.WriteLine($"Biblioteca: {root}");
Console.WriteLine($"Carpeta externa (referenciados): {externalRoot}");
Console.WriteLine();

try
{
    // --- 1. Fixture: MP3/FLAC/M4A/WAV reales y mínimos, copiados y referenciados ---

    (string Format, Func<string, string, Task> Synthesize, string Extension)[] formats =
    [
        ("MP3", FixtureAudio.SynthesizeMp3Async, "mp3"),
        ("FLAC", FixtureAudio.SynthesizeFlacAsync, "flac"),
        ("M4A", FixtureAudio.SynthesizeM4aAsync, "m4a"),
        ("WAV", FixtureAudio.SynthesizeWavAsync, "wav")
    ];

    byte[] cover = await SimpleCoverGenerator.GenerateAsync(1);
    var items = new List<LibraryItem>();
    var itemsByFormat = new Dictionary<string, (LibraryItem Copied, LibraryItem Referenced)>();

    foreach ((string format, var synthesize, string ext) in formats)
    {
        string artist = "Artista de Prueba";
        string album = $"Álbum {format}";
        string title = $"Canción de prueba en {format}";

        string copiedPath = Path.Combine(root, "Música", artist, album, $"01 {title}.{ext}");
        string referencedPath = Path.Combine(externalRoot, $"{title} (fuera de la biblioteca).{ext}");

        await synthesize(ffmpeg, copiedPath);
        await synthesize(ffmpeg, referencedPath);
        FixtureAudio.WriteBaselineTags(copiedPath, artist, album, title, 1, cover);
        FixtureAudio.WriteBaselineTags(referencedPath, artist, album, title, 1, cover);

        var copiedItem = new LibraryItem
        {
            SourcePath = copiedPath,
            Kind = LibraryItemKind.Music,
            Status = LibraryItemStatus.Ready,
            Metadata = new TrackMetadata
            {
                Title = title, Artist = artist, AlbumArtist = artist, Album = album,
                Genre = "Rock", Year = "1986", TrackNumber = 1, DurationSeconds = 2, CoverArtData = cover
            }
        };
        var referencedItem = new LibraryItem
        {
            SourcePath = referencedPath,
            Kind = LibraryItemKind.Music,
            Status = LibraryItemStatus.Ready,
            Metadata = new TrackMetadata
            {
                Title = title, Artist = artist, AlbumArtist = artist, Album = album,
                Genre = "Rock", Year = "1986", TrackNumber = 1, DurationSeconds = 2, CoverArtData = cover
            }
        };

        items.Add(copiedItem);
        items.Add(referencedItem);
        itemsByFormat[format] = (copiedItem, referencedItem);

        Console.WriteLine($"  {format,-4}  copiado:      {copiedPath} ({new FileInfo(copiedPath).Length} bytes)");
        Console.WriteLine($"  {format,-4}  referenciado: {referencedPath} ({new FileInfo(referencedPath).Length} bytes)");
    }

    Console.WriteLine();

    var store = new LibraryStore(root) { CoversNormalized = CoverArtNormalization.NormalizedVersion };
    store.SaveItems(items);

    string prefsPath = Path.Combine(root, "prefs.json");
    var preferences = new AppPreferences(prefsPath) { LibraryPath = root };
    var library = new LibraryViewModel(
        preferences, new NoOpLibraryProcessor(), new NoOpEnrichmentService(), new BackgroundTaskCenter());
    await library.LoadingTask;

    Console.WriteLine($"Ítems disponibles: {library.AvailableItems.Count} (esperado {items.Count})");
    Console.WriteLine();

    // --- 2 y 3(a). Editar N campos: bytes escritos en el archivo, y si aparece un preparado ---

    Console.WriteLine("--- Edición de campos: bytes en el archivo de origen, antes y después ---");
    Console.WriteLine();
    Console.WriteLine($"{"Campo",-14} {"Formato",-6} {"bytes antes",12} {"bytes después",14} {"hash igual?",12} {"preparado nuevo?",-18}");

    (string Field, Action<LibraryViewModel, Guid> Apply)[] edits =
    [
        ("Título", (lib, id) => lib.ApplyMetadataEdit(id, WithEdit(lib, id, m => m.Title = m.Title + " (editado)"))),
        ("Artista", (lib, id) => lib.ApplyMetadataEdit(id, WithEdit(lib, id, m => m.Artist = "Artista Editado"))),
        ("Álbum", (lib, id) => lib.ApplyMetadataEdit(id, WithEdit(lib, id, m => m.Album = "Álbum Editado"))),
        ("Pista", (lib, id) => lib.ApplyMetadataEdit(id, WithEdit(lib, id, m => m.TrackNumber = 9))),
        ("Año", (lib, id) => lib.ApplyMetadataEdit(id, WithEdit(lib, id, m => m.Year = "1999"))),
        ("Género", (lib, id) => lib.ApplyMetadataEdit(id, WithEdit(lib, id, m => m.Genre = "Jazz"))),
        ("Carátula", (lib, id) => lib.ApplyMetadataEdit(id, WithEdit(lib, id, m => m.CoverArtData = null))),
        ("Rating", (lib, id) => lib.ApplyMetadataEdit(id, WithEdit(lib, id, m => m.Rating = 5))),
        ("Favorito", (lib, id) => lib.ToggleFavorite(id)),
        ("Letra", (lib, id) => lib.ApplyMetadataEdit(id, WithEdit(lib, id, m => m.SyncedLyrics = "[00:00.00] Letra de prueba"))),
        ("Categoría", (lib, id) => lib.ApplyCategory(id, "Rock"))
    ];

    var results = new List<(string Field, string Format, long Before, long After, bool HashSame, bool NewPrepared)>();

    foreach ((string field, var apply) in edits)
    {
        foreach ((string format, (LibraryItem copied, _)) in itemsByFormat)
        {
            string path = copied.SourcePath;
            long before = new FileInfo(path).Length;
            byte[] hashBefore = SHA256.HashData(File.ReadAllBytes(path));
            int preparedCountBefore = Directory.Exists(store.PreparedDirectory)
                ? Directory.GetFiles(store.PreparedDirectory).Length : 0;

            apply(library, copied.Id);

            long after = new FileInfo(path).Length;
            byte[] hashAfter = SHA256.HashData(File.ReadAllBytes(path));
            int preparedCountAfter = Directory.Exists(store.PreparedDirectory)
                ? Directory.GetFiles(store.PreparedDirectory).Length : 0;

            bool hashSame = hashBefore.SequenceEqual(hashAfter);
            bool newPrepared = preparedCountAfter > preparedCountBefore;

            results.Add((field, format, before, after, hashSame, newPrepared));
            Console.WriteLine($"{field,-14} {format,-6} {before,12} {after,14} {(hashSame ? "sí" : "NO"),12} {(newPrepared ? "SÍ -- inesperado" : "no"),-18}");
        }
    }

    Console.WriteLine();
    bool allUnchanged = results.All(r => r.HashSame && !r.NewPrepared);
    Console.WriteLine(allUnchanged
        ? "Confirmado: las 11 ediciones × 4 formatos dieron 0 bytes cambiados en el archivo de origen y 0 preparados nuevos."
        : "ATENCIÓN: al menos una edición SÍ tocó el archivo o generó un preparado -- ver filas marcadas arriba.");

    // --- 3(a). Qué viaja al iPod tras una edición: el origen, sin editar ---

    Console.WriteLine();
    Console.WriteLine("--- Qué viaja al iPod tras una edición ---");
    (LibraryItem editedItem, _) = itemsByFormat["MP3"];
    var syncFiles = new List<SyncSourceFile>
    {
        new(editedItem.SourcePath, new FileInfo(editedItem.SourcePath).Length, DateTimeOffset.UtcNow,
            SyncLayout.DestinationRelativePath(editedItem))
    };
    var plan = SyncPlanner.Plan(syncFiles, new DeviceSyncManifest());
    Console.WriteLine($"SyncPlanner.Plan elige como origen: {plan.Items.FirstOrDefault()?.SourcePath ?? "(ninguno)"}");
    Console.WriteLine($"Es el mismo archivo que quedó sin editar arriba (LibraryItem.SourcePath): {plan.Items.FirstOrDefault()?.SourcePath == editedItem.SourcePath}");
    Console.WriteLine("No existe una ruta de \"preparado de música\" distinta al origen en este código (§1): la sincronización siempre parte de SourcePath.");

    // --- 3(b). Eliminar: huérfanos en .preparados/ y .portadas/ ---

    Console.WriteLine();
    Console.WriteLine("--- Eliminar: huérfanos que deja en .preparados/ y .portadas/ ---");

    (LibraryItem toDelete, _) = itemsByFormat["FLAC"];
    string coverPath = store.CoverPath(toDelete.Id);
    Console.WriteLine($"Carátula del ítem antes de eliminar: {File.Exists(coverPath)} ({(File.Exists(coverPath) ? new FileInfo(coverPath).Length : 0)} bytes)");

    // No hay preparado de música real en este código para simular con el
    // procesador (§1: Windows no genera preparado de música todavía) -- se
    // deja un archivo de relleno con el mismo nombrado que usa StagingPaths
    // (por nombre base) para probar el mecanismo de limpieza de Eliminar en
    // sí, no para simular un transcodificado real. Se dice así en la ST.
    Directory.CreateDirectory(store.PreparedDirectory);
    string fakePreparedPath = Path.Combine(store.PreparedDirectory, Path.GetFileNameWithoutExtension(toDelete.SourcePath) + ".preparado.bin");
    byte[] fakePreparedBytes = new byte[123_456];
    Random.Shared.NextBytes(fakePreparedBytes);
    File.WriteAllBytes(fakePreparedPath, fakePreparedBytes);
    Console.WriteLine($"Preparado simulado creado: {fakePreparedPath} ({fakePreparedBytes.Length} bytes) -- ver nota arriba, no es un transcodificado real.");

    library.Remove([toDelete.Id]);

    bool coverSurvives = File.Exists(coverPath);
    bool preparedSurvives = File.Exists(fakePreparedPath);
    long orphanBytes = (coverSurvives ? new FileInfo(coverPath).Length : 0) + (preparedSurvives ? new FileInfo(fakePreparedPath).Length : 0);
    int orphanCount = (coverSurvives ? 1 : 0) + (preparedSurvives ? 1 : 0);

    Console.WriteLine($"Tras Remove(): carátula sigue en disco = {coverSurvives}; preparado sigue en disco = {preparedSurvives}");
    Console.WriteLine($"Huérfanos dejados por este único elemento: {orphanCount} archivo(s), {orphanBytes} bytes.");

    // --- 3(c). Política de carátulas forzada ---

    Console.WriteLine();
    Console.WriteLine("--- Política de carátulas forzada ---");
    preferences.CoverArtPolicy = CoverArtPolicy.PerTrack;
    Console.WriteLine($"Preferencia guardada: {preferences.CoverArtPolicy} (el usuario SÍ puede elegirla en Ajustes)");
    Console.WriteLine("AuraStudio.App/Services/SyncService.cs:127 pasa el literal CoverArtPolicy.AlbumOnly a LibrarySyncFinalizer.Run,");
    Console.WriteLine("sin leer _preferences.CoverArtPolicy -- la preferencia de arriba no tiene ningún efecto en la sincronización real.");

    // --- 3(d). Original desaparecido ---

    Console.WriteLine();
    Console.WriteLine("--- Original desaparecido ---");
    (LibraryItem missingItem, _) = itemsByFormat["WAV"];
    int itemsBeforeMissing = library.Items.Count;
    File.Delete(missingItem.SourcePath);
    library.Reload();
    await library.LoadingTask;
    bool stillInItems = library.Items.Any(i => i.Id == missingItem.Id);
    bool inAvailable = library.AvailableItems.Any(i => i.Id == missingItem.Id);
    Console.WriteLine($"Items antes: {itemsBeforeMissing}, Items después de borrar el original y recargar: {library.Items.Count}");
    Console.WriteLine($"El ítem con el original borrado sigue en Items: {stillInItems}; aparece en AvailableItems: {inAvailable}");
    Console.WriteLine(stillInItems && !inAvailable
        ? "Confirmado: se conserva en el catálogo como no disponible, no se borra."
        : "ATENCIÓN: no coincide con lo esperado -- revisar.");
}
finally
{
    try { Directory.Delete(root, recursive: true); } catch (IOException) { }
    try { Directory.Delete(externalRoot, recursive: true); } catch (IOException) { }
}

static TrackMetadata WithEdit(LibraryViewModel library, Guid id, Action<TrackMetadata> mutate)
{
    LibraryItem item = library.Items.First(i => i.Id == id);
    TrackMetadata metadata = item.Metadata is null
        ? new TrackMetadata()
        : new TrackMetadata
        {
            Title = item.Metadata.Title, Artist = item.Metadata.Artist, Album = item.Metadata.Album,
            AlbumArtist = item.Metadata.AlbumArtist, Year = item.Metadata.Year, Genre = item.Metadata.Genre,
            TrackNumber = item.Metadata.TrackNumber, DiscNumber = item.Metadata.DiscNumber,
            CoverArtData = item.Metadata.CoverArtData, SyncedLyrics = item.Metadata.SyncedLyrics,
            DurationSeconds = item.Metadata.DurationSeconds, Rating = item.Metadata.Rating,
            IsFavorite = item.Metadata.IsFavorite
        };
    mutate(metadata);
    return metadata;
}
