// Genera, una sola vez, la biblioteca sintética persistente que usan las
// capturas por idioma (ST-248, 0.4.1): unos pocos álbumes con carátula JPEG
// real (audio vacío, igual que tools/LibraryPerfCheck -- no hace falta
// reproducir nada para una captura de pantalla), suficiente para que
// Álbumes/Canciones/menús contextuales no se vean vacíos.
//
// A diferencia de LibraryPerfCheck y StorageFixtureCheck, esta NO se borra
// al terminar: capturas-idiomas.ps1 la reutiliza en cada corrida (una por
// idioma), y regenerarla en cada lanzamiento de la app sería más lento y no
// aporta nada para una captura visual.
//
// Cómo correrlo:
//   dotnet run --project tools/CapturasIdiomas -- <carpeta-destino>
//
// Si la carpeta ya tiene una biblioteca.json, no hace nada (idempotente).

using AuraStudio.Core.Library;

Console.OutputEncoding = System.Text.Encoding.UTF8;

if (args.Length < 1)
{
    Console.WriteLine("Uso: dotnet run --project tools/CapturasIdiomas -- <carpeta-destino>");
    Environment.Exit(1);
    return;
}

string root = args[0];
Directory.CreateDirectory(root);

string catalogPath = Path.Combine(root, "biblioteca.json");
if (File.Exists(catalogPath))
{
    Console.WriteLine($"Ya existe {catalogPath} -- no se regenera.");
    return;
}

const int albumCount = 6;
const int tracksPerAlbum = 5;

var items = new List<LibraryItem>();
for (int album = 0; album < albumCount; album++)
{
    string artist = $"Artista {album + 1:00}";
    string albumName = $"Álbum {album + 1:00}";
    byte[] cover = await AuraStudio.Tools.CapturasIdiomas.CoverFixtureGenerator.GenerateAsync(album);

    for (int track = 1; track <= tracksPerAlbum; track++)
    {
        string sourcePath = Path.Combine(root, "Música", artist, albumName, $"{track:00} Canción.mp3");
        Directory.CreateDirectory(Path.GetDirectoryName(sourcePath)!);
        // Sin audio real (ffmpeg no hace falta para una captura de pantalla),
        // pero el archivo SÍ tiene que existir: la vista de Álbumes filtra a
        // AvailableItems (File.Exists), y sin esto la biblioteca se ve vacía
        // aunque el catálogo tenga filas -- encontrado al capturar, ST-248.
        File.WriteAllBytes(sourcePath, [0xFF, 0xFB, 0x90, 0x00]);
        items.Add(new LibraryItem
        {
            SourcePath = sourcePath,
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
                DurationSeconds = 180 + track,
                CoverArtData = cover
            },
            FileSizeBytes = 3_500_000 + (album * 7 + track) * 12_345
        });
    }
}

var store = new LibraryStore(root) { CoversNormalized = CoverArtNormalization.NormalizedVersion };
store.SaveItems(items);

Console.WriteLine($"Biblioteca sintética generada en {root}: {albumCount} álbumes x {tracksPerAlbum} pistas = {items.Count} canciones.");
