using AuraStudio.App.Services;
using AuraStudio.Core.Library;
using AuraStudio.Core.Networking;

namespace AuraStudio.Tools.StorageFixtureCheck;

/// <summary>Mínimo para construir <c>LibraryViewModel</c> desde una consola -- ver el mismo patrón en LibraryPerfCheck.</summary>
internal sealed class NoOpLibraryProcessor : ILibraryProcessor
{
    public Task<bool> ProcessAsync(LibraryItem item, CancellationToken ct = default) => Task.FromResult(false);
}

internal sealed class NoOpEnrichmentService : IEnrichmentService
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

/// <summary>Un JPEG real y chico (WIC), la misma vía que <c>PlaylistArtGenerator</c>/CoverFixtureGenerator de W0.</summary>
internal static class SimpleCoverGenerator
{
    private const int Dimension = 200;

    public static async Task<byte[]> GenerateAsync(int seed)
    {
        var random = new Random(seed);
        byte[] canvas = new byte[Dimension * Dimension * 4];

        for (int i = 0; i < canvas.Length; i += 4)
        {
            canvas[i] = (byte)random.Next(40, 220);
            canvas[i + 1] = (byte)random.Next(40, 220);
            canvas[i + 2] = (byte)random.Next(40, 220);
            canvas[i + 3] = 255;
        }

        var bitmap = new Windows.Graphics.Imaging.SoftwareBitmap(
            Windows.Graphics.Imaging.BitmapPixelFormat.Bgra8, Dimension, Dimension,
            Windows.Graphics.Imaging.BitmapAlphaMode.Ignore);

        var writer = new Windows.Storage.Streams.DataWriter();
        writer.WriteBytes(canvas);
        bitmap.CopyFromBuffer(writer.DetachBuffer());

        using var output = new Windows.Storage.Streams.InMemoryRandomAccessStream();
        var encoder = await Windows.Graphics.Imaging.BitmapEncoder.CreateAsync(
            Windows.Graphics.Imaging.BitmapEncoder.JpegEncoderId, output);
        encoder.SetSoftwareBitmap(bitmap);
        await encoder.FlushAsync();

        output.Seek(0);
        var buffer = new Windows.Storage.Streams.Buffer((uint)output.Size);
        await output.ReadAsync(buffer, (uint)output.Size, Windows.Storage.Streams.InputStreamOptions.None);

        byte[] jpeg = new byte[buffer.Length];
        Windows.Storage.Streams.DataReader.FromBuffer(buffer).ReadBytes(jpeg);
        return jpeg;
    }
}
