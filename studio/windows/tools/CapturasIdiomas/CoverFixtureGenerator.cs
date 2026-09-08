using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

namespace AuraStudio.Tools.CapturasIdiomas;

/// <summary>
/// Carátulas reales (JPEG baseline decodificable) para la biblioteca
/// sintética de capturas por idioma -- copia reducida de la de
/// <c>tools/LibraryPerfCheck</c> (mismo mecanismo, <c>SoftwareBitmap</c> +
/// <c>BitmapEncoder</c> de WIC): no vale la pena una referencia entre dos
/// proyectos de herramientas por una clase de 80 líneas sin estado.
/// </summary>
internal static class CoverFixtureGenerator
{
    private const int Dimension = 300;
    private const float Quality = 0.8f;

    public static async Task<byte[]> GenerateAsync(int seed)
    {
        var random = new Random(seed);
        byte[] canvas = new byte[Dimension * Dimension * 4];

        (byte R, byte G, byte B) background = (
            (byte)random.Next(40, 220), (byte)random.Next(40, 220), (byte)random.Next(40, 220));
        FillBackground(canvas, background);

        int blobs = 18 + random.Next(10);
        for (int b = 0; b < blobs; b++) DrawBlob(canvas, random);

        return await EncodeAsync(canvas).ConfigureAwait(false);
    }

    private static void FillBackground(byte[] canvas, (byte R, byte G, byte B) color)
    {
        for (int i = 0; i < canvas.Length; i += 4)
        {
            canvas[i] = color.B;
            canvas[i + 1] = color.G;
            canvas[i + 2] = color.R;
            canvas[i + 3] = 255;
        }
    }

    private static void DrawBlob(byte[] canvas, Random random)
    {
        int w = random.Next(15, 90), h = random.Next(15, 90);
        int x0 = random.Next(0, Dimension), y0 = random.Next(0, Dimension);
        byte r = (byte)random.Next(0, 256), g = (byte)random.Next(0, 256), bl = (byte)random.Next(0, 256);

        for (int y = y0; y < y0 + h && y < Dimension; y++)
        {
            for (int x = x0; x < x0 + w && x < Dimension; x++)
            {
                int i = (y * Dimension + x) * 4;
                canvas[i] = bl;
                canvas[i + 1] = g;
                canvas[i + 2] = r;
                canvas[i + 3] = 255;
            }
        }
    }

    private static async Task<byte[]> EncodeAsync(byte[] canvas)
    {
        var bitmap = new SoftwareBitmap(BitmapPixelFormat.Bgra8, Dimension, Dimension, BitmapAlphaMode.Ignore);
        bitmap.CopyFromBuffer(ToBuffer(canvas));

        using var output = new InMemoryRandomAccessStream();
        var options = new BitmapPropertySet
        {
            { "ImageQuality", new BitmapTypedValue(Quality, Windows.Foundation.PropertyType.Single) }
        };

        BitmapEncoder encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.JpegEncoderId, output, options);
        encoder.SetSoftwareBitmap(bitmap);
        await encoder.FlushAsync();

        output.Seek(0);
        var buffer = new Windows.Storage.Streams.Buffer((uint)output.Size);
        await output.ReadAsync(buffer, (uint)output.Size, InputStreamOptions.None);

        byte[] jpeg = new byte[buffer.Length];
        DataReader.FromBuffer(buffer).ReadBytes(jpeg);
        return jpeg;
    }

    private static IBuffer ToBuffer(byte[] bytes)
    {
        var writer = new DataWriter();
        writer.WriteBytes(bytes);
        return writer.DetachBuffer();
    }
}
