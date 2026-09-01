using System.Diagnostics;
using AuraStudio.Core.Library;

// Cómo correrlo:
//   dotnet run --project tools/LibraryPerfCheck -- [álbumes] [pistas por álbum]
//
// Por omisión, 1000 álbumes de 12 pistas: el tamaño de la biblioteca del dueño.
// Genera un catálogo en una carpeta temporal, lo guarda, lo vuelve a leer y
// mide lo que la app hace en cada arranque y en cada cambio de sección.
//
// No borra nada de nadie: trabaja solo dentro de su carpeta temporal, y la
// borra al terminar.

int albums = args.Length > 0 && int.TryParse(args[0], out int a) ? a : 1000;
int tracksPerAlbum = args.Length > 1 && int.TryParse(args[1], out int t) ? t : 12;
int total = albums * tracksPerAlbum;

string root = Path.Combine(Path.GetTempPath(), "aura-perf-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);

Console.WriteLine($"Biblioteca de prueba: {albums} álbumes x {tracksPerAlbum} pistas = {total} canciones");
Console.WriteLine($"Carpeta: {root}");
Console.WriteLine();

try
{
    var store = new LibraryStore(root);

    List<LibraryItem> items = Measure("Generar el catálogo en memoria", () =>
    {
        var generated = new List<LibraryItem>(total);

        for (int album = 0; album < albums; album++)
        {
            // 40 artistas repartidos: una biblioteca real tiene muchos álbumes
            // por artista, no uno por uno.
            string artist = $"Artista {album % 40:000}";
            string albumName = $"Álbum {album:0000}";

            for (int track = 1; track <= tracksPerAlbum; track++)
            {
                generated.Add(new LibraryItem
                {
                    SourcePath = Path.Combine(root, "Música", artist, albumName, $"{track:00} Canción.mp3"),
                    Kind = LibraryItemKind.Music,
                    Status = LibraryItemStatus.Ready,
                    Metadata = new TrackMetadata
                    {
                        Title = $"Canción {track:00} de {albumName}",
                        Artist = artist,
                        AlbumArtist = artist,
                        Album = albumName,
                        Genre = "Rock",
                        Year = "1986",
                        TrackNumber = track,
                        DurationSeconds = 210 + track
                    }
                });
            }
        }

        return generated;
    });

    Measure("Guardar biblioteca.json", () => { store.SaveItems(items); return 0; });

    long bytes = new FileInfo(Path.Combine(root, "biblioteca.json")).Length;
    Console.WriteLine($"    biblioteca.json: {bytes / 1024.0 / 1024.0:0.0} MB");

    IReadOnlyList<LibraryItem> loaded = Measure("Leer biblioteca.json (arranque)", () => store.LoadItems());
    Console.WriteLine($"    elementos leídos: {loaded.Count}");

    IReadOnlyList<AlbumGroup> albumGroups = Measure("Agrupar por álbum", () => LibraryGrouping.Albums([.. loaded]));
    Console.WriteLine($"    álbumes: {albumGroups.Count}");

    IReadOnlyList<ArtistGroup> artistGroups = Measure("Agrupar por artista", () => LibraryGrouping.Artists([.. loaded]));
    Console.WriteLine($"    artistas: {artistGroups.Count}");

    Measure("Armar y ordenar la tabla de Canciones", () =>
        loaded.Select(item => new MediaTableRow(item))
            .Sorted(MusicSortField.ByTitle, ascending: true).Count);

    // Lo que de verdad puede doler: la app filtra por archivo presente en cada
    // recarga, y con la biblioteca en una carpeta compartida cada consulta se va
    // por la red. Acá se mide contra disco local, que es el piso.
    Measure("Comprobar que los archivos estén (disco local)", () =>
        loaded.Count(item => File.Exists(item.SourcePath)));

    Measure("Planificar una sincronización completa", () =>
    {
        var files = loaded.Select(item => new SyncSourceFile(
            item.SourcePath, 5_000_000, DateTimeOffset.UtcNow,
            SyncLayout.DestinationRelativePath(item))).ToList();

        return SyncPlanner.Plan(files, new DeviceSyncManifest()).Items.Count;
    });
}
finally
{
    try { Directory.Delete(root, recursive: true); } catch (IOException) { }
}

static T Measure<T>(string what, Func<T> action)
{
    var watch = Stopwatch.StartNew();
    T result = action();
    watch.Stop();

    Console.WriteLine($"{watch.ElapsedMilliseconds,6} ms  {what}");
    return result;
}
