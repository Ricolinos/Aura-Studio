using AuraStudio.App.Platform;
using AuraStudio.App.Services;
using AuraStudio.Core.Library;
using AuraStudio.Tools.CopyModeCheck;

// ST-243 (B3): arnés del modo copia. No afirma, mide.
//
// Importa los cinco formatos con el pipeline de verdad (`LibraryProcessor`) y
// reporta: dónde quedó cada archivo, cuánto pesa, qué etiquetas tiene, a qué
// bitrate se convirtió lo que había que convertir y en cuánto tiempo, cuánto
// escribe una edición de campo, y qué pasa (nada) en modo referencia.
//
// El fixture se sintetiza acá: nada sale de la biblioteca del dueño.

string root = Path.Combine(Path.GetTempPath(), "AuraCopyMode-" + Guid.NewGuid().ToString("N"));
string incoming = Path.Combine(root, "entrada");
string library = Path.Combine(root, "biblioteca");

Directory.CreateDirectory(library);

Console.WriteLine($"Raíz del arnés: {root}");
Console.WriteLine();

// --- 0. Los textos salen del archivo de recursos -------------------------
//
// ST-247: que el `.resx` quedó embebido con el nombre que espera el
// `ResourceManager` no se puede comprobar con una prueba de Core —el proyecto
// de pruebas no puede referenciar la app de WinUI—, así que se comprueba acá,
// que es el único lugar que corre código de la app. Si esto imprimiera
// ⟦clave⟧ en la primera línea, la app abriría con los textos rotos.

Console.WriteLine("--- Textos desde recursos ---");
Console.WriteLine($"  app-strings.app-name     → {AuraStudio.App.Resources.Strings.Get("app-strings.app-name")}");
Console.WriteLine($"  una clave que no existe  → {AuraStudio.App.Resources.Strings.Get("no.existe")}");
Console.WriteLine();

// --- El fixture ---------------------------------------------------------

var sources = new List<(string Format, string Path)>
{
    ("mp3", Fixture.WriteMp3(Path.Combine(incoming, "cancion.mp3"))),
    ("flac", Fixture.WriteFlac(Path.Combine(incoming, "cancion.flac"))),
    ("m4a", Fixture.WriteM4a(Path.Combine(incoming, "cancion.m4a"))),
    ("wav", Fixture.WriteWav(Path.Combine(incoming, "cancion.wav"))),
    ("aiff", Fixture.WriteAiff(Path.Combine(incoming, "cancion.aiff")))
};

// Etiquetas de partida, para que el destino salga de artista y álbum de verdad.
foreach ((string format, string path) in sources)
{
    if (format is "wav" or "aiff") continue;

    using TagLib.File file = TagLib.File.Create(path);
    file.Tag.Title = "Ingrata";
    file.Tag.Performers = ["Café Tacvba"];
    file.Tag.AlbumArtists = ["Café Tacvba"];
    file.Tag.Album = "Ré";
    file.Save();
}

Console.WriteLine("--- Fixture sintetizado ---");
foreach ((string format, string path) in sources)
    Console.WriteLine($"  {format,-5} {new FileInfo(path).Length,12:N0} bytes  {Path.GetFileName(path)}");

Console.WriteLine();

// --- 1. Importar en modo copia ------------------------------------------

var preferences = new AppPreferences(Path.Combine(root, "prefs.json"))
{
    LibraryPath = library,
    CopyMediaIntoLibrary = true
};

var processor = new LibraryProcessor(preferences);

Console.WriteLine("--- Importar en modo copia ---");
Console.WriteLine();
Console.WriteLine($"{"Formato",-8} {"storage",-10} {"bytes",12}  {"ms",6}  destino");

var imported = new List<(string Format, LibraryItem Item, long Ms)>();

foreach ((string format, string path) in sources)
{
    var item = new LibraryItem { Id = Guid.NewGuid(), Kind = LibraryItemKind.Music, SourcePath = path };

    long started = Environment.TickCount64;
    await processor.ProcessAsync(item);
    long elapsed = Environment.TickCount64 - started;

    imported.Add((format, item, elapsed));

    string destination = item.SourcePath.StartsWith(library, StringComparison.OrdinalIgnoreCase)
        ? Path.GetRelativePath(library, item.SourcePath)
        : item.SourcePath + "   (NO SE COPIÓ)";

    string size = File.Exists(item.SourcePath) ? $"{new FileInfo(item.SourcePath).Length:N0}" : "—";

    Console.WriteLine($"{format,-8} {item.Storage,-10} {size,12}  {elapsed,6:N0}  {destination}");

    if (item.Status.State == LibraryItemState.Failed)
        Console.WriteLine($"         FALLÓ: {item.Status.Error}");
}

Console.WriteLine();

// --- 2. Qué quedó en el archivo copiado ---------------------------------

Console.WriteLine("--- Etiquetas releídas del archivo COPIADO ---");
Console.WriteLine();
Console.WriteLine($"{"Formato",-8} {"título",-12} {"artista",-14} {"álbum",-8} preparado == origen");

foreach ((string format, LibraryItem item, _) in imported)
{
    if (!File.Exists(item.SourcePath)) { Console.WriteLine($"{format,-8} (no hay archivo)"); continue; }

    TrackMetadata read = LocalTagReader.Read(item.SourcePath);
    bool preparedIsSource = item.PreparedPath == item.SourcePath;

    Console.WriteLine(
        $"{format,-8} {read.Title ?? "—",-12} {read.Artist ?? "—",-14} {read.Album ?? "—",-8} {preparedIsSource}");
}

Console.WriteLine();

// --- 3. La conversión, medida -------------------------------------------

Console.WriteLine("--- Conversión a MP3 (Windows.Media.Transcoding) ---");
Console.WriteLine();
Console.WriteLine($"{"Origen",-8} {"bytes origen",13} {"bytes MP3",11} {"ms",7} {"kbps medidos",13}");

foreach (string format in (string[])["wav", "aiff"])
{
    string source = sources.First(candidate => candidate.Format == format).Path;
    string destination = Path.Combine(root, $"medido-{format}.mp3");

    try
    {
        AudioTranscodeResult result = await AudioTranscoder.ToMp3Async(source, destination);
        double kbps = result.BytesWritten * 8.0 / Fixture.Seconds / 1000;

        Console.WriteLine(
            $"{format,-8} {new FileInfo(source).Length,13:N0} {result.BytesWritten,11:N0} "
            + $"{result.Elapsed.TotalMilliseconds,7:N0} {kbps,13:N1}");
    }
    catch (AudioTranscodeException ex)
    {
        Console.WriteLine($"{format,-8} FALLÓ: {ex.Message}");
    }
}

Console.WriteLine();
Console.WriteLine($"(El fixture dura {Fixture.Seconds} s exactos, así que los kbps son bytes×8/{Fixture.Seconds}/1000.)");
Console.WriteLine();

// --- 4. Cuánto escribe una edición --------------------------------------

Console.WriteLine("--- Edición de campos sobre el archivo de la BIBLIOTECA ---");
Console.WriteLine();
Console.WriteLine($"{"Formato",-8} {"campo",-12} {"bytes antes",12} {"bytes después",14} {"¿reescribió?",13} {"mtime igual?",13}");

foreach ((string format, LibraryItem item, _) in imported)
{
    if (!File.Exists(item.SourcePath) || item.StorageKind != ItemStorage.Copy) continue;

    Measure(item, "título", metadata => metadata.Title = "Ingrata (editado)");
    Measure(item, "rating", metadata => metadata.Rating = 5);
    Measure(item, "letra", metadata => metadata.SyncedLyrics = "[00:01.00]No va al archivo");

    void Measure(LibraryItem target, string field, Action<TrackMetadata> edit)
    {
        var metadata = new TrackMetadata
        {
            Title = target.Metadata?.Title,
            Artist = target.Metadata?.Artist,
            Album = target.Metadata?.Album,
            AlbumArtist = target.Metadata?.AlbumArtist
        };

        edit(metadata);

        long before = new FileInfo(target.SourcePath).Length;
        DateTime modifiedBefore = File.GetLastWriteTimeUtc(target.SourcePath);

        TagWriteResult result = LocalTagWriter.Write(target.SourcePath, metadata, preferences.CoverArtPolicy);

        long after = new FileInfo(target.SourcePath).Length;
        bool sameTime = File.GetLastWriteTimeUtc(target.SourcePath) == modifiedBefore;

        Console.WriteLine(
            $"{format,-8} {field,-12} {before,12:N0} {after,14:N0} {result.Written,13} {sameTime,13}");

        target.Metadata = metadata;
    }
}

Console.WriteLine();

// --- 4b. La calidad de audio, en modo copia -----------------------------
//
// Los tres casos del contrato: WAV siempre, FLAC solo con "Comprimido", FLAC
// con "Original" tal cual. `LibraryProcessor` vive en el proyecto de la app, así
// que copia se mide acá; referencia tiene pruebas propias en Core.Tests.

Console.WriteLine("--- Calidad de audio en modo copia ---");
Console.WriteLine();
Console.WriteLine($"{"origen",-6} {"calidad",-12} {"¿convirtió?",12} destino");

foreach ((string format, AudioQuality quality) in ((string, AudioQuality)[])
    [("wav", AudioQuality.OriginalLossless), ("wav", AudioQuality.Compressed),
     ("flac", AudioQuality.Compressed), ("flac", AudioQuality.OriginalLossless),
     ("mp3", AudioQuality.OriginalLossless)])
{
    string qualityLibrary = Path.Combine(root, $"biblioteca-{format}-{quality}");
    Directory.CreateDirectory(qualityLibrary);

    var qualityPreferences = new AppPreferences(Path.Combine(root, $"prefs-{format}-{quality}.json"))
    {
        LibraryPath = qualityLibrary,
        CopyMediaIntoLibrary = true,
        AudioQuality = quality
    };

    // Nombre propio por caso: reusar el mismo choca con el archivo que la
    // conversión anterior todavía tiene abierto.
    string origin = Path.Combine(incoming, $"calidad-{format}-{quality}.{format}");

    switch (format)
    {
        case "wav": Fixture.WriteWav(origin); break;

        // FLAC con audio de verdad, hecho con el codificador de Windows: el FLAC
        // mínimo del fixture no tiene muestras y no hay nada que convertir.
        case "flac": await Decoded.ToFlacAsync(Fixture.WriteWav(origin + ".wav"), origin); break;

        default: Fixture.WriteMp3(origin); break;
    }

    var item = new LibraryItem { Id = Guid.NewGuid(), Kind = LibraryItemKind.Music, SourcePath = origin };
    await new LibraryProcessor(qualityPreferences).ProcessAsync(item);

    string resulting = Path.GetExtension(item.SourcePath).TrimStart('.');
    bool converted = !resulting.Equals(format, StringComparison.OrdinalIgnoreCase);

    string where = item.SourcePath.StartsWith(qualityLibrary, StringComparison.OrdinalIgnoreCase)
        ? Path.GetRelativePath(qualityLibrary, item.SourcePath)
        : $"(no se copió) {item.Status.Error}";

    Console.WriteLine($"{format,-6} {quality,-12} {(converted ? "→ " + resulting : "no"),12}  {where}");
}

Console.WriteLine();

// --- 5. Modo referencia: no se toca nada --------------------------------

Console.WriteLine("--- Modo referencia ---");
Console.WriteLine();

string referenceLibrary = Path.Combine(root, "biblioteca-referencia");
Directory.CreateDirectory(referenceLibrary);

var referencePreferences = new AppPreferences(Path.Combine(root, "prefs-referencia.json"))
{
    LibraryPath = referenceLibrary,
    CopyMediaIntoLibrary = false
};

var referenceProcessor = new LibraryProcessor(referencePreferences);

string original = Fixture.WriteMp3(Path.Combine(incoming, "referenciada.mp3"));
byte[] beforeBytes = File.ReadAllBytes(original);
DateTime beforeTime = File.GetLastWriteTimeUtc(original);

var referenced = new LibraryItem { Id = Guid.NewGuid(), Kind = LibraryItemKind.Music, SourcePath = original };
await referenceProcessor.ProcessAsync(referenced);

Console.WriteLine($"  ruta sin cambiar:        {referenced.SourcePath == original}");
Console.WriteLine($"  storage:                 {referenced.Storage ?? "(sin fijar; se infiere al guardar)"}");
Console.WriteLine($"  bytes del original:      {(beforeBytes.SequenceEqual(File.ReadAllBytes(original)) ? "idénticos" : "CAMBIARON")}");
Console.WriteLine($"  fecha del original:      {(File.GetLastWriteTimeUtc(original) == beforeTime ? "sin mover" : "SE MOVIÓ")}");
Console.WriteLine($"  archivos en biblioteca:  {Directory.GetFiles(referenceLibrary, "*", SearchOption.AllDirectories).Length}");
Console.WriteLine();

// --- 6. Cuánto cuesta la PRIMERA conversión -----------------------------
//
// ST-244: en la corrida de B3, el primer WAV tardó 2 922 ms y el segundo 203.
// La diferencia es cargar Media Foundation, no convertir. Se mide aparte para
// saber si conviene calentarlo en segundo plano al abrir la app (B8).

Console.WriteLine("--- Arranque en frío de Media Foundation ---");
Console.WriteLine();

string cold = Fixture.WriteWav(Path.Combine(incoming, "frio.wav"));
var coldTimings = new List<double>();

for (int pass = 1; pass <= 3; pass++)
{
    AudioTranscodeResult measured =
        await AudioTranscoder.ToMp3Async(cold, Path.Combine(root, $"frio-{pass}.mp3"));

    coldTimings.Add(measured.Elapsed.TotalMilliseconds);
    Console.WriteLine($"  pasada {pass}: {measured.Elapsed.TotalMilliseconds,7:N0} ms");
}

Console.WriteLine();
Console.WriteLine($"  Costo de la primera vez: {coldTimings[0] - coldTimings.Skip(1).Average(),0:N0} ms sobre el promedio de las siguientes.");
Console.WriteLine();

// --- 6b. WAV y AIFF a ALAC: sin pérdida de verdad -----------------------
//
// ST-244: con "Original sin pérdida", WAV y AIFF van a ALAC y no a MP3. "Sin
// pérdida" tiene que significar sin pérdida, así que no alcanza con que el
// archivo exista: se decodifica la entrada y la salida a PCM y se comparan las
// muestras. Si no son idénticas, no es sin pérdida.

Console.WriteLine("--- WAV/AIFF → ALAC (sin pérdida) ---");
Console.WriteLine();
Console.WriteLine($"{"origen",-6} {"bytes origen",13} {"bytes ALAC",11} {"ms",7} {"¿mismas muestras?",18}");

foreach (string format in (string[])["wav", "aiff"])
{
    string source = sources.First(candidate => candidate.Format == format).Path;
    string destination = Path.Combine(root, $"sin-perdida-{format}.m4a");

    try
    {
        AudioTranscodeResult alac =
            await AudioTranscoder.ConvertAsync(source, destination, AudioCodec.Alac);

        (bool same, long sourceBytes, long alacBytes, long common) =
            await Decoded.ComparePcmAsync(source, destination);

        Console.WriteLine(
            $"{format,-6} {new FileInfo(source).Length,13:N0} {alac.BytesWritten,11:N0} "
            + $"{alac.Elapsed.TotalMilliseconds,7:N0} {same,18}");

        Console.WriteLine(
            $"       PCM origen {sourceBytes:N0} B, PCM ALAC {alacBytes:N0} B, comparados {common:N0} B");

        if (!same)
        {
            int? shift = await Decoded.FindSampleAlignmentAsync(source, destination);

            Console.WriteLine(shift is { } frames
                ? $"       alinean con {frames} cuadros de preámbulo: las muestras SON las mismas, "
                  + "el codificador solo mete relleno al principio"
                : "       NO alinean con ningún desplazamiento: se perdió audio de verdad");
        }

        // Y el .m4a resultante se etiqueta: `m4a` ya está en TaggableExtensions.
        LocalTagWriter.Write(destination, new TrackMetadata
        {
            Title = "Ingrata", Artist = "Café Tacvba", Album = "Ré", DiscNumber = 2
        });

        TrackMetadata back = LocalTagReader.Read(destination);
        Console.WriteLine($"       etiquetas releídas: {back.Title} / {back.Artist} / disco {back.DiscNumber}");
    }
    catch (AudioTranscodeException ex)
    {
        Console.WriteLine($"{format,-6} FALLÓ: {ex.Message}");
    }
}

Console.WriteLine();

// --- 7. Escribir etiquetas no puede cambiar lo que SUENA ----------------
//
// ST-244, encargo de ST-222: en M4A, escribir etiquetas obliga a mover el `moov`
// y a corregir los offsets de `stco`/`co64`. Un offset mal corregido da un
// archivo que abre sin error, se lee sin error y suena mal — ninguna prueba de
// etiquetas o de tamaños lo detecta. Acá se decodifica antes y después y se
// comparan las muestras.

Console.WriteLine("--- Muestras decodificadas antes y después de etiquetar ---");
Console.WriteLine();

string encodedM4a = Path.Combine(root, "con-audio.m4a");
await Decoded.ToM4aAsync(Fixture.WriteWav(Path.Combine(incoming, "para-m4a.wav")), encodedM4a);

// MediaTranscoder escribe el moov AL FINAL, que es el caso fácil: crecerlo no
// mueve ninguna muestra. El caso delicado es el contrario, así que se rearma el
// archivo con el moov adelante — y se comprueba que el rearmado suene igual
// ANTES de escribirle nada, para saber que el fixture es válido.
string realM4a = Path.Combine(root, "con-audio-moov-primero.m4a");
Decoded.RewriteWithMoovFirst(encodedM4a, realM4a);

Console.WriteLine($"  Cajas del original:  {Decoded.TopLevelBoxOrder(encodedM4a)}");
Console.WriteLine($"  Cajas del fixture:   {Decoded.TopLevelBoxOrder(realM4a)}");

(bool fixtureIsSound, long encodedPcm, long remuxedPcm, _) =
    await Decoded.ComparePcmAsync(encodedM4a, realM4a);

Console.WriteLine($"  ¿el fixture con moov adelante suena igual que el original? {fixtureIsSound} "
                  + $"({encodedPcm:N0} vs {remuxedPcm:N0} bytes)");
Console.WriteLine();

(string pcmHashBefore, long pcmBytesBefore) = await Decoded.PcmSummaryAsync(realM4a);

TagWriteResult tagged = LocalTagWriter.Write(realM4a, new TrackMetadata
{
    Title = "Ingrata",
    Artist = "Café Tacvba",
    Album = "Ré",
    Genre = "Rock",
    Year = "1994",
    TrackNumber = 7,
    DiscNumber = 2
});

(string pcmHashAfter, long pcmBytesAfter) = await Decoded.PcmSummaryAsync(realM4a);

Console.WriteLine($"  ¿escribió etiquetas?   {tagged.Written} ({string.Join(", ", tagged.Fields)})");
Console.WriteLine($"  PCM antes:             {pcmHashBefore}  ({pcmBytesBefore:N0} bytes)");
Console.WriteLine($"  PCM después:           {pcmHashAfter}  ({pcmBytesAfter:N0} bytes)");
Console.WriteLine($"  ¿SUENA IGUAL?          {pcmHashBefore == pcmHashAfter && pcmBytesBefore == pcmBytesAfter}");
Console.WriteLine();

TrackMetadata m4aRead = LocalTagReader.Read(realM4a);
Console.WriteLine($"  y las etiquetas volvieron: {m4aRead.Title} / {m4aRead.Artist} / disco {m4aRead.DiscNumber}");
Console.WriteLine();

// --- 7b. Una cabecera rota no tumba nada ni deja residuos ---------------
//
// ST-246, recibido de ST-223: un WAV con la cabecera destrozada tiene que
// fallar con motivo visible, sin dejar nada en Temp\Aura ni un `.aura-tmp` al
// lado del destino. Lo que no se puede es que se caiga el proceso o que quede
// medio archivo haciéndose pasar por una canción.

Console.WriteLine("--- Cabecera rota: se rechaza y no deja residuos ---");
Console.WriteLine();

string broken = Path.Combine(incoming, "rota.wav");
byte[] goodWav = await File.ReadAllBytesAsync(Fixture.WriteWav(Path.Combine(incoming, "buena.wav")));

// Se rompen la frecuencia, los canales y la alineación de bloque, dejando la
// firma RIFF/WAVE intacta: el archivo "parece" un WAV hasta que se lee.
byte[] brokenBytes = [.. goodWav];
for (int offset = 22; offset < 36; offset++) brokenBytes[offset] = 0;
await File.WriteAllBytesAsync(broken, brokenBytes);

string brokenDestination = Path.Combine(root, "rota-convertida.mp3");

try
{
    await AudioTranscoder.ToMp3Async(broken, brokenDestination);
    Console.WriteLine("  NO falló — MAL: una cabecera rota tiene que rechazarse");
}
catch (AudioTranscodeException ex)
{
    Console.WriteLine($"  Rechazada con motivo: {ex.Message}");
}

string workLeftovers = Directory.Exists(AudioTranscoder.WorkDirectory)
    ? string.Join(", ", Directory.GetFiles(AudioTranscoder.WorkDirectory).Select(Path.GetFileName))
    : "(no existe)";

Console.WriteLine($"  Restos en Temp\\Aura:      {(workLeftovers.Length == 0 ? "ninguno" : workLeftovers)}");
Console.WriteLine($"  .aura-tmp junto al destino: {File.Exists(brokenDestination + ".aura-tmp")}");
Console.WriteLine($"  destino a medias:           {File.Exists(brokenDestination)}");
Console.WriteLine();

// --- 8. Migrar una biblioteca anterior ----------------------------------
//
// ST-246: se sintetiza una biblioteca como la que dejaba una versión vieja
// —sin `storage`, con las copias sin etiquetas y con un preparado nombrado por
// el archivo de origen— y se migra. La tabla dice el antes y el después, y se
// comprueba lo que más importa: que abrir NO escriba nada, y que migrar dos
// veces no toque nada la segunda.

Console.WriteLine("--- Migrar una biblioteca anterior ---");
Console.WriteLine();

string oldLibrary = Path.Combine(root, "biblioteca-vieja");
string oldSong = Path.Combine(oldLibrary, "Música", "Café Tacvba", "Ré", "Ingrata.mp3");
Fixture.WriteMp3(oldSong);

// El archivo dice otra cosa que el catálogo: es de antes de que Studio supiera
// escribir etiquetas.
LocalTagWriter.Write(oldSong, new TrackMetadata { Title = "Pista 01" });

var oldVideoId = Guid.NewGuid();
string legacyPrepared = Path.Combine(oldLibrary, ".preparados", "peli.mpg");
Directory.CreateDirectory(Path.GetDirectoryName(legacyPrepared)!);
File.WriteAllBytes(legacyPrepared, new byte[2048]);
File.WriteAllBytes(CatalogPath.PosterFor(legacyPrepared), new byte[512]);

string orphan = Path.Combine(oldLibrary, ".preparados", "de-algo-borrado.mpg");
File.WriteAllBytes(orphan, new byte[1024]);

var oldStore = new LibraryStore(oldLibrary);

oldStore.SaveItems(
[
    new LibraryItem
    {
        Id = Guid.NewGuid(), Kind = LibraryItemKind.Music, SourcePath = oldSong,
        PreparedPath = oldSong,
        Metadata = new TrackMetadata { Title = "Ingrata", Artist = "Café Tacvba", Album = "Ré" }
    },
    new LibraryItem
    {
        Id = oldVideoId, Kind = LibraryItemKind.Video, SourcePath = @"D:\videos\peli.mkv",
        PreparedPath = legacyPrepared
    }
]);

// Y se le QUITA el campo `storage` al catálogo, que es como lo dejaba la
// versión vieja: ausente, no nulo. Se edita el JSON como JSON y no con texto:
// quitar `"storage":"copy"` a mano deja una coma suelta cuando es el primer o
// el último campo, y el catálogo queda ilegible — que no es la biblioteca vieja
// que se quería simular.
string oldCatalog = Path.Combine(oldLibrary, PersistedLibrary.CatalogFileName);

System.Text.Json.Nodes.JsonNode catalogJson =
    System.Text.Json.Nodes.JsonNode.Parse(await File.ReadAllTextAsync(oldCatalog))!;

foreach (System.Text.Json.Nodes.JsonNode? entry in catalogJson["items"]!.AsArray())
    entry!.AsObject().Remove("storage");

await File.WriteAllTextAsync(oldCatalog, catalogJson.ToJsonString());

string TreeOf(string directory) => string.Join("\n", Directory
    .EnumerateFiles(directory, "*", SearchOption.AllDirectories)
    .Where(path => Path.GetFileName(path) != PersistedLibrary.CatalogFileName)
    .OrderBy(path => path, StringComparer.Ordinal)
    .Select(path => $"{Path.GetRelativePath(directory, path)}|{new FileInfo(path).Length}"
                    + $"|{File.GetLastWriteTimeUtc(path):O}"));

string treeBeforeOpening = TreeOf(oldLibrary);

LibraryLoad oldLoad = oldStore.Load();
LibraryMigrationNeed need = LibraryMigrationScanner.Detect(oldLoad.Items, oldLoad.ItemsWithoutStorage);

Console.WriteLine($"  Al abrir: {oldLoad.ItemsWithoutStorage} sin storage, "
                  + $"{need.LegacyPrepared} preparados con nombre viejo, ¿avisa? {need.Needed}");
Console.WriteLine($"  ¿abrir escribió algo?  {(TreeOf(oldLibrary) == treeBeforeOpening ? "NO" : "SÍ — MAL")}");
Console.WriteLine();

Console.WriteLine($"  Antes  título en el archivo: {LocalTagReader.Read(oldSong).Title}");
Console.WriteLine($"  Antes  preparado del video:  {Path.GetFileName(legacyPrepared)}");
Console.WriteLine($"  Antes  huérfanos en disco:   {Directory.GetFiles(Path.Combine(oldLibrary, ".preparados")).Length} archivos");
Console.WriteLine();

LibraryMigrationSummary migration = await LibraryMigrator.RunAsync(
    oldLibrary, oldLoad.Items, transcode: AudioTranscoder.ForPreparedAsync);

oldStore.SaveItems(oldLoad.Items);

string expectedPrepared = CatalogPath.PreparedFileName(oldVideoId, "mpg");

Console.WriteLine($"  Después título en el archivo: {LocalTagReader.Read(oldSong).Title}");
Console.WriteLine($"  Después preparado del video:  {Path.GetFileName(oldLoad.Items[1].PreparedPath ?? "—")}"
                  + $"  (esperado {expectedPrepared})");
Console.WriteLine($"  Después póster hermano:       {File.Exists(Path.Combine(oldLibrary, ".preparados", Path.ChangeExtension(expectedPrepared, ".jpg")))}");
Console.WriteLine($"  Resumen: {migration.Tagged} etiquetados, {migration.PreparedRenamed} renombrados, "
                  + $"{migration.OrphansDeleted} huérfanos borrados, {migration.Failed} fallidos");
Console.WriteLine();

LibraryLoad afterLoad = oldStore.Load();
LibraryMigrationNeed afterNeed = LibraryMigrationScanner.Detect(afterLoad.Items, afterLoad.ItemsWithoutStorage);

Console.WriteLine($"  ¿vuelve a avisar? {afterNeed.Needed}");

string treeAfterFirst = TreeOf(oldLibrary);
LibraryMigrationSummary again = await LibraryMigrator.RunAsync(
    oldLibrary, afterLoad.Items, transcode: AudioTranscoder.ForPreparedAsync);

Console.WriteLine($"  Segunda corrida: {again.Touched} archivos tocados "
                  + $"(árbol idéntico: {TreeOf(oldLibrary) == treeAfterFirst})");
Console.WriteLine();

Console.WriteLine($"Listo. Para borrar todo: rmdir /s /q \"{root}\"");
