// ST-240 (B0): arnés de almacenamiento -- fixture con audio real y medición
// de qué escribe (o no) cada edición de campo, qué deja huérfano Eliminar, y
// qué política de carátula se aplica de verdad, contra el código de HEAD
// bd57116 (0.3.0), antes de tocar nada del contrato de B1..B8.
//
// ST-245 (B5) lo extiende: Eliminar de verdad (Papelera en copia, solo
// catálogo en referencia, con preparado y carátula reales por ID), huérfanos
// antes/después con OrphanFinder, y un caso con acento en NFD en disco / NFC
// en catálogo -- el mismo mecanismo que usa LibraryDiskPathResolver -- de
// punta a punta contra LibraryViewModel.Remove real, no solo la función pura.
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

    // Un elemento cuya carpeta de artista/álbum queda escrita en NFD en disco
    // -- como las crea la Mac (adición de A1 a ST-241, pedida para B5) --
    // mientras el catálogo, como manda el contrato, guarda todo en NFC.
    string artistaAcentuado = "Café Tacvba".Normalize(System.Text.NormalizationForm.FormD);
    string albumAcentuado = "Ré".Normalize(System.Text.NormalizationForm.FormD);
    string nfdDir = Path.Combine(root, "Música", artistaAcentuado, albumAcentuado);
    Directory.CreateDirectory(nfdDir);
    string nfdTrackPath = Path.Combine(nfdDir, "Ingrata.mp3");
    await FixtureAudio.SynthesizeMp3Async(ffmpeg, nfdTrackPath);
    FixtureAudio.WriteBaselineTags(nfdTrackPath, "Café Tacvba", "Ré", "Ingrata", 1, cover);

    var nfdItem = new LibraryItem
    {
        SourcePath = nfdTrackPath,
        Kind = LibraryItemKind.Music,
        Status = LibraryItemStatus.Ready,
        Metadata = new TrackMetadata { Title = "Ingrata", Artist = "Café Tacvba", Album = "Ré", DurationSeconds = 2 }
    };
    items.Add(nfdItem);
    Console.WriteLine($"  NFD   con acento: {nfdTrackPath} (carpeta real en NFD, catálogo va a guardar NFC)");

    Console.WriteLine();

    var store = new LibraryStore(root) { CoversNormalized = CoverArtNormalization.NormalizedVersion };
    store.SaveItems(items);

    string prefsPath = Path.Combine(root, "prefs.json");
    var preferences = new AppPreferences(prefsPath) { LibraryPath = root };
    var library = new LibraryViewModel(
        preferences, new NoOpLibraryProcessor(), new NoOpEnrichmentService(), new BackgroundTaskCenter());
    await library.LoadingTask;

    // El ítem NFD queda fuera de AvailableItems a propósito: item.SourcePath
    // se reconstruye en NFC desde el catálogo (ST-241 addendum) y esa ruta no
    // existe tal cual -- la carpeta real está en NFD. Es la premisa de la
    // sección 5, no un error del arnés: FileAvailability usa File.Exists
    // directo, sin el resolvedor de LibraryDeletion.
    Console.WriteLine($"Ítems disponibles: {library.AvailableItems.Count} (esperado {items.Count - 1} de {items.Count}: " +
        "el de acento en NFD queda \"no disponible\" al cargar, ver sección 5 más abajo)");
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
            WaitForBackgroundWriteToSettle(path);

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

    // Lo que el contrato de ST-243 dice que TIENE que pasar, no lo que decía
    // B0 antes de que existiera el modo copia real: los campos gobernados
    // (título/artista/álbum/pista/año/género) reescriben el archivo en los
    // formatos que LocalTagWriter sabe escribir (MP3/FLAC/M4A -- WAV no tiene
    // escritor nativo y en este fixture nunca se convirtió a MP3 porque entró
    // directo como archivo ya copiado, no por el importador); rating, favorito,
    // letra, categoría y -- con la política AlbumOnly de por omisión -- la
    // carátula, NUNCA. Y ningún campo genera un preparado nuevo: la música
    // copiada es su propio preparado (ST-241).
    var governedFields = new HashSet<string>(StringComparer.Ordinal)
        { "Título", "Artista", "Álbum", "Pista", "Año", "Género" };
    var writableFormats = new HashSet<string>(StringComparer.Ordinal) { "MP3", "FLAC", "M4A" };

    var unexpected = results.Where(r =>
    {
        bool shouldRewrite = governedFields.Contains(r.Field) && writableFormats.Contains(r.Format);
        return r.HashSame == shouldRewrite || r.NewPrepared;
    }).ToList();

    Console.WriteLine();
    Console.WriteLine(unexpected.Count == 0
        ? "Confirmado: los campos gobernados reescriben el archivo en MP3/FLAC/M4A (no en WAV, sin escritor nativo); " +
          "rating, favorito, letra, categoría y carátula (política AlbumOnly) no tocan el archivo; 0 preparados nuevos."
        : "ATENCIÓN: no coincide con el contrato de ST-243 en " + unexpected.Count + " fila(s) -- ver marcadas arriba.");

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

    // --- 3(b). Eliminar de verdad (ST-245, B5): Papelera en copia, solo
    // catálogo en referencia, y borra preparado + carátula en los dos ---

    Console.WriteLine();
    Console.WriteLine("--- Eliminar (ST-245): modo copia -- a la Papelera de reciclaje ---");

    (LibraryItem copyToDelete, _) = itemsByFormat["MP3"];
    string copyPath = copyToDelete.SourcePath;
    long copyBytes = new FileInfo(copyPath).Length;

    DeletionPreview copyPreview = library.PreviewRemoval([copyToDelete.Id]);
    Console.WriteLine($"PreviewRemoval: {copyPreview.CopyCount} de copia ({copyPreview.CopyBytes} bytes), {copyPreview.ReferenceCount} de referencia.");
    Console.WriteLine($"Antes: {copyPath} existe = {File.Exists(copyPath)} ({copyBytes} bytes)");

    library.Remove([copyToDelete.Id]);

    Console.WriteLine($"Después de Remove(): {copyPath} existe = {File.Exists(copyPath)}");
    Console.WriteLine(File.Exists(copyPath)
        ? "ATENCIÓN: el archivo de copia sigue en su lugar -- no se movió a la Papelera."
        : "Confirmado: desapareció de la biblioteca -- fue a la Papelera de reciclaje de Windows (SHFileOperationW, FOF_ALLOWUNDO), no un borrado definitivo. Verificar a simple vista que está ahí es cosa de alguien con la sesión de Windows delante.");

    Console.WriteLine();
    Console.WriteLine("--- Eliminar (ST-245): modo referencia -- solo del catálogo, con preparado y carátula por ID ---");

    (_, LibraryItem refToDelete) = itemsByFormat["M4A"];
    LibraryItem liveRef = library.Items.First(i => i.Id == refToDelete.Id);
    Console.WriteLine($"storage inferido para el referenciado: {liveRef.Storage} (esperado reference)");

    string realPreparedPath = Path.Combine(store.Root, CatalogPath.PreparedRelative(liveRef.Id, "m4a").Replace('/', Path.DirectorySeparatorChar));
    Directory.CreateDirectory(Path.GetDirectoryName(realPreparedPath)!);
    File.Copy(liveRef.SourcePath, realPreparedPath, overwrite: true);
    string realCoverPath = Path.Combine(store.Root, CatalogPath.CoverRelative(liveRef.Id).Replace('/', Path.DirectorySeparatorChar));
    Directory.CreateDirectory(Path.GetDirectoryName(realCoverPath)!);
    File.WriteAllBytes(realCoverPath, cover);

    liveRef.PreparedPath = realPreparedPath;
    liveRef.CoverRelativePath = CatalogPath.CoverRelative(liveRef.Id);
    library.SaveAndRefresh();

    long refOriginalBytes = new FileInfo(liveRef.SourcePath).Length;
    byte[] refOriginalHashBefore = SHA256.HashData(File.ReadAllBytes(liveRef.SourcePath));

    DeletionPreview refPreview = library.PreviewRemoval([liveRef.Id]);
    Console.WriteLine($"PreviewRemoval: {refPreview.CopyCount} de copia, {refPreview.ReferenceCount} de referencia (esperado 0/1).");
    Console.WriteLine($"Antes: preparado={File.Exists(realPreparedPath)}, carátula={File.Exists(realCoverPath)}, original={File.Exists(liveRef.SourcePath)}");

    library.Remove([liveRef.Id]);

    bool originalSurvives = File.Exists(liveRef.SourcePath);
    bool originalUnchanged = originalSurvives && SHA256.HashData(File.ReadAllBytes(liveRef.SourcePath)).SequenceEqual(refOriginalHashBefore);
    Console.WriteLine($"Después: preparado={File.Exists(realPreparedPath)}, carátula={File.Exists(realCoverPath)}, original={originalSurvives} (sin cambios: {originalUnchanged}, {refOriginalBytes} bytes)");
    Console.WriteLine(!File.Exists(realPreparedPath) && !File.Exists(realCoverPath) && originalUnchanged
        ? "Confirmado: preparado y carátula borrados; el original del usuario no se tocó."
        : "ATENCIÓN: algo no coincide con lo esperado -- ver arriba.");

    // --- 4. Huérfanos antes/después (ST-245) ---

    Console.WriteLine();
    Console.WriteLine("--- Huérfanos (ST-245): antes/después de \"Limpiar archivos huérfanos\" ---");

    string strayPreparedPath = Path.Combine(store.PreparedDirectory, Guid.NewGuid().ToString("D").ToUpperInvariant() + ".mpg");
    Directory.CreateDirectory(store.PreparedDirectory);
    File.WriteAllBytes(strayPreparedPath, new byte[50_000]);

    string strayCoverPath = store.CoverPath(Guid.NewGuid());
    Directory.CreateDirectory(store.CoversDirectory);
    File.WriteAllBytes(strayCoverPath, new byte[10_000]);

    OrphanScanResult orphansBefore = library.FindOrphans();
    Console.WriteLine($"Antes de limpiar: {orphansBefore.Count} huérfanos, {orphansBefore.TotalBytes} bytes.");
    foreach (OrphanFile file in orphansBefore.Files) Console.WriteLine($"  {file.AbsolutePath} ({file.SizeBytes} bytes)");

    library.CleanOrphans(orphansBefore);
    OrphanScanResult orphansAfter = library.FindOrphans();
    Console.WriteLine($"Después de limpiar: {orphansAfter.Count} huérfanos, {orphansAfter.TotalBytes} bytes.");
    Console.WriteLine(orphansAfter.Count == 0
        ? "Confirmado: 0 huérfanos después de limpiar."
        : "ATENCIÓN: quedaron huérfanos sin limpiar -- ver arriba.");

    // --- 5. Acento en NFD en disco, NFC en catálogo (adición de A1 a ST-241, pedida para B5) ---

    Console.WriteLine();
    Console.WriteLine("--- Acento con NFD en disco / NFC en catálogo, de punta a punta ---");

    // Un LibraryViewModel nuevo, apuntando al mismo catálogo ya guardado: lo
    // que importa es la ruta tal como la reconstruye CatalogPath.Resolve a
    // partir de lo que quedó ESCRITO (en NFC, ST-241 addendum), contra una
    // carpeta que sigue en NFD en disco -- no lo que ya tuviera en memoria
    // el LibraryViewModel original desde que se creó el ítem.
    var reloadedLibrary = new LibraryViewModel(
        preferences, new NoOpLibraryProcessor(), new NoOpEnrichmentService(), new BackgroundTaskCenter());
    await reloadedLibrary.LoadingTask;

    LibraryItem reloadedNfdItem = reloadedLibrary.Items.First(i => i.Id == nfdItem.Id);
    bool fastPathFindsIt = File.Exists(reloadedNfdItem.SourcePath);
    Console.WriteLine($"item.SourcePath tras recargar: {reloadedNfdItem.SourcePath}");
    Console.WriteLine($"El camino rápido (File.Exists directo) lo encuentra: {fastPathFindsIt} (se espera false: la carpeta real está en NFD, esto en NFC)");

    DeletionPreview nfdPreview = reloadedLibrary.PreviewRemoval([reloadedNfdItem.Id]);
    Console.WriteLine($"PreviewRemoval igual lo cuenta como copia: {nfdPreview.CopyCount} elemento(s).");

    reloadedLibrary.Remove([reloadedNfdItem.Id]);

    bool nfdFileGone = !File.Exists(nfdTrackPath);
    Console.WriteLine($"El archivo real en NFD sigue existiendo: {File.Exists(nfdTrackPath)}");
    Console.WriteLine(nfdFileGone
        ? "Confirmado: LibraryDiskPathResolver encontró el archivo en la carpeta NFD real a partir de la ruta NFC del catálogo, y Remove() lo mandó a la Papelera."
        : "ATENCIÓN: el archivo con acento en NFD no se pudo eliminar -- revisar LibraryDiskPathResolver/MediaRoots.");

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

/// <summary>
/// Hallazgo real de esta corrida (ST-245): <c>ApplyMetadataEdit</c> reescribe
/// el archivo de la biblioteca en un <c>Task.Run</c> sin ninguna señal pública
/// de cuándo termina -- a propósito, ST-243, para no congelar la ventana. Leer
/// bytes/hash inmediatamente después de llamarlo mide una carrera: casi
/// siempre "no cambió" porque la escritura de fondo ni empezó, y en una
/// corrida real con varias ediciones seguidas sobre el mismo archivo tiró
/// <c>IOException: en uso por otro programa</c> -- dos <c>Task.Run</c> de
/// <c>LocalTagWriter.Apply</c> pisándose el mismo <c>.aura-tmp</c>. Ninguna de
/// las dos cosas es del contrato que se está midiendo; son del arnés.
///
/// <para>Se espera con un margen inicial (para que el <c>Task.Run</c> alcance
/// a EMPEZAR) y después con reintentos de abrir en exclusiva hasta que ya no
/// esté en uso -- con tope, para no colgarse si de verdad algo se atoró.</para>
/// </summary>
static void WaitForBackgroundWriteToSettle(string path, int timeoutMs = 3000)
{
    Thread.Sleep(80);

    DateTime deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
    while (DateTime.UtcNow < deadline)
    {
        try
        {
            using FileStream handle = File.Open(path, FileMode.Open, FileAccess.Read, FileShare.None);
            return;
        }
        catch (IOException)
        {
            Thread.Sleep(15);
        }
    }
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
