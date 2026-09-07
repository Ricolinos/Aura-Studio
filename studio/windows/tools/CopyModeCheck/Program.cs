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

Console.WriteLine($"Listo. Para borrar todo: rmdir /s /q \"{root}\"");
