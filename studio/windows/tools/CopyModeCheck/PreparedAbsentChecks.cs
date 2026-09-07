using AuraStudio.App.Services;
using AuraStudio.App.ViewModels;
using AuraStudio.Core.Library;
using AuraStudio.Core.Networking;

namespace AuraStudio.Tools.CopyModeCheck;

/// <summary>
/// Que "sin preparado" sea un estado válido de punta a punta (ST-247, recibido
/// de ST-224).
///
/// <para>La primera corrida de A4 en la Mac destapó tres sitios donde la regla
/// de ST-244 —una canción referenciada que ya coincide con el catálogo no
/// necesita preparado, y <c>preparedPath</c> queda ausente— rompía algo.
/// Windows no los tiene, y esto lo demuestra en vez de afirmarlo.</para>
///
/// <para>Vive en el arnés y no en <c>Core.Tests</c> porque los tres caminos
/// —el barrido del sync, la carga de la biblioteca y aplicar carátula— están en
/// el proyecto de la app, que es <c>net10.0-windows</c> con WinUI y no se puede
/// referenciar desde un proyecto de pruebas <c>net10.0</c>.</para>
/// </summary>
internal static class PreparedAbsentChecks
{
    public static async Task RunAsync(string root)
    {
        Console.WriteLine("--- \"Sin preparado\" es un estado válido (ST-224) ---");
        Console.WriteLine();

        string library = Path.Combine(root, "sin-preparado");
        Directory.CreateDirectory(library);

        // Una canción REFERENCIADA, lista, cuyo archivo ya dice lo que dice el
        // catálogo: no necesita preparado y no lo tiene.
        string outside = Path.Combine(root, "ajena", "Ingrata.mp3");
        Fixture.WriteMp3(outside);

        var song = new LibraryItem
        {
            Id = Guid.NewGuid(),
            Kind = LibraryItemKind.Music,
            SourcePath = outside,
            Storage = ItemStorageRules.ReferenceValue,
            Status = LibraryItemStatus.Ready,
            Metadata = new TrackMetadata { Title = "Ingrata", Artist = "Café Tacvba", Album = "Ré" }
        };

        LocalTagWriter.Write(song.SourcePath, song.Metadata);

        var store = new LibraryStore(library);
        store.SaveItems([song]);

        // --- 1. El sync la lleva, con su archivo de origen -------------------

        var preferences = new AppPreferences(Path.Combine(root, "prefs-sin-preparado.json"))
        {
            LibraryPath = library
        };

        var tasks = new BackgroundTaskCenter();
        var library1 = new LibraryViewModel(
            preferences, new NoOpProcessor(), new NoOpEnrichment(), tasks);

        await library1.LoadingTask;

        LibraryItem loaded = library1.Items[0];
        string travels = loaded.PreparedPath ?? loaded.SourcePath;

        Console.WriteLine($"  1. preparedPath del catálogo:  {loaded.PreparedPath ?? "(ausente, como debe)"}");
        Console.WriteLine($"     lo que viajaría al iPod:    {Path.GetFileName(travels)}");
        Console.WriteLine($"     ¿la descarta algún filtro?  {(loaded.Status.State == LibraryItemState.Ready && File.Exists(travels) ? "no" : "SÍ — MAL")}");
        Console.WriteLine($"     destino en el iPod:         {SyncLayout.DestinationRelativePath(loaded)}");
        Console.WriteLine();

        // --- 2. Cargar no encola trabajo ni crea archivos --------------------

        string preparedDirectory = Path.Combine(library, PersistedLibrary.PreparedDirName);
        int filesBefore = Directory.Exists(preparedDirectory)
            ? Directory.GetFiles(preparedDirectory).Length : 0;

        var counting = new CountingProcessor();
        var library2 = new LibraryViewModel(
            preferences, counting, new NoOpEnrichment(), new BackgroundTaskCenter());

        await library2.LoadingTask;
        await Task.Delay(200);   // por si algo se encolara en segundo plano

        int filesAfter = Directory.Exists(preparedDirectory)
            ? Directory.GetFiles(preparedDirectory).Length : 0;

        Console.WriteLine($"  2. trabajos encolados al cargar: {counting.Processed} (esperado 0)");
        Console.WriteLine($"     archivos en .preparados/:     {filesBefore} → {filesAfter} (esperado sin cambio)");
        Console.WriteLine();

        // --- 3. Aplicar carátula no inventa un preparado ---------------------

        string albumKey = LibraryGrouping.AlbumKeyOf(library2.Items[0], library2.ArtistGrouping);
        int applied = library2.ApplyAlbumCover(albumKey, OnePixelPng());

        Console.WriteLine($"  3. carátulas aplicadas:        {applied}");
        Console.WriteLine($"     preparedPath después:       "
                          + $"{library2.Items[0].PreparedPath ?? "(sigue ausente, como debe)"}");
        Console.WriteLine();
    }

    private static byte[] OnePixelPng() => Convert.FromBase64String(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==");

    private sealed class NoOpProcessor : ILibraryProcessor
    {
        public Task<bool> ProcessAsync(LibraryItem item, CancellationToken ct = default) =>
            Task.FromResult(false);

        public Task<bool> CopyIntoLibraryAsync(
            LibraryItem item, bool force = false, CancellationToken ct = default) =>
            Task.FromResult(true);
    }

    /// <summary>Cuenta cuántos elementos se mandaron a procesar. Cero es la respuesta correcta.</summary>
    private sealed class CountingProcessor : ILibraryProcessor
    {
        public int Processed { get; private set; }

        public Task<bool> ProcessAsync(LibraryItem item, CancellationToken ct = default)
        {
            Processed++;
            return Task.FromResult(false);
        }

        public Task<bool> CopyIntoLibraryAsync(
            LibraryItem item, bool force = false, CancellationToken ct = default) =>
            Task.FromResult(true);
    }

    private sealed class NoOpEnrichment : IEnrichmentService
    {
        public Task<EnrichmentReport> EnrichAsync(
            IReadOnlyList<LibraryItem> items, IProgress<string>? progress = null, CancellationToken ct = default) =>
            Task.FromResult(new EnrichmentReport(0, 0, 0, null));

        public Task<ArtistImageBatch> FetchArtistImagesAsync(
            IReadOnlyList<LibraryItem> items, string libraryRoot,
            IProgress<string>? progress = null, CancellationToken ct = default) =>
            Task.FromResult(new ArtistImageBatch(0, 0, false));

        public Task<int> FetchVideoPostersAsync(
            IReadOnlyList<LibraryItem> items, IProgress<string>? progress = null, CancellationToken ct = default) =>
            Task.FromResult(0);
    }
}
