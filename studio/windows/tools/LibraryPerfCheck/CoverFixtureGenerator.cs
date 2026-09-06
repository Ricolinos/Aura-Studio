using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

namespace AuraStudio.Tools.LibraryPerfCheck;

/// <summary>
/// Carátulas reales (JPEG baseline decodificable, no bytes al azar) para la
/// fixture del arnés: una por álbum, reutilizada en sus pistas, igual que una
/// biblioteca real donde todas las canciones de un disco comparten la misma
/// carátula embebida. Semilla fija por índice de álbum: la misma corrida
/// siempre genera los mismos bytes, para que "biblioteca.json: N MB" sea
/// comparable entre corridas.
///
/// <para>Usa la misma vía que <c>PlaylistArtGenerator</c> (App):
/// <c>SoftwareBitmap</c> + <c>BitmapEncoder</c> de WIC, sin depender de
/// <c>System.Drawing</c>.</para>
/// </summary>
internal static class CoverFixtureGenerator
{
    private const int Dimension = 300;
    private const float Quality = 0.8f;

    public static async Task<IReadOnlyList<byte[]>> GenerateAsync(int count)
    {
        var covers = new byte[count][];
        for (int i = 0; i < count; i++) covers[i] = await GenerateOneAsync(i).ConfigureAwait(false);
        return covers;
    }

    /// <summary>
    /// Addendum de ST-200 (pedido del coordinador): sin esto, la biblioteca del
    /// arnés nace con <c>LibraryItem.FileSizeBytes</c> en <c>null</c> en las
    /// 12 000 canciones, y <c>FileSizeBackfill</c> (ST-201) dispara su medición
    /// en segundo plano + un guardado justo mientras el resto del arnés mide --
    /// cuatro filas salían infladas con código de Core idéntico. No se mide de
    /// un archivo real (la fixture no trae audio real): es un tamaño plausible
    /// de MP3 (~192 kbps), determinista por álbum y pista para que dos corridas
    /// den el mismo número.
    /// </summary>
    public static long DeterministicFileSizeBytes(int album, int track)
    {
        var random = new Random(album * 1000 + track);
        return 3_000_000 + random.Next(0, 5_000_000);
    }

    /// <summary>
    /// Un lienzo con manchas de color pseudoaleatorias (semilla = índice de
    /// álbum): suficiente entropía para que JPEG no lo comprima a nada, sin
    /// llegar al ruido puro que sí lo haría (una carátula real tampoco es
    /// ruido). ~300x300 a calidad 0.8 da algo del orden de los ~15 KB que pide
    /// el plan; el tamaño real de cada corrida se imprime en la tabla.
    /// </summary>
    private static async Task<byte[]> GenerateOneAsync(int seed)
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
