using AuraStudio.Core.Library;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

namespace AuraStudio.App.Platform;

public sealed class ImageResizeException(string message) : Exception(message);

/// <summary>
/// Redimensiona fotos a la resolución del LCD del iPod usando WIC
/// (<c>Windows.Graphics.Imaging</c>) — nativo de Windows, sin depender de
/// ffmpeg para algo que el sistema ya resuelve bien. Port de
/// <c>ImageResizer.swift</c>, que allá usa ImageIO.
///
/// <para>La salida siempre es JPEG: es uno de los dos formatos que decodifica
/// el visor de Aura (D-028 del firmware; el otro es BMP, sin compresión, que
/// para fotos no tiene sentido).</para>
/// </summary>
public static class ImageResizer
{
    /// <summary>La misma calidad que macOS, para que las dos apps produzcan lo mismo.</summary>
    public const double DefaultQuality = 0.85;

    public static Task ResizeToLcdOptimalAsync(
        string sourcePath, string destinationPath,
        int maxDimension = ImageResizePlan.DefaultMaxDimension,
        double quality = DefaultQuality)
        => ResizeAsync(() => File.ReadAllBytes(sourcePath), destinationPath, maxDimension, quality);

    /// <summary>
    /// ST-033: la misma conversión desde bytes en memoria (el póster de un
    /// video descargado, que nunca toca el disco como original).
    /// </summary>
    public static Task ResizeToLcdOptimalAsync(
        byte[] source, string destinationPath,
        int maxDimension = ImageResizePlan.DefaultMaxDimension,
        double quality = DefaultQuality)
        => ResizeAsync(() => source, destinationPath, maxDimension, quality);

    private static async Task ResizeAsync(Func<byte[]> readSource, string destinationPath,
                                          int maxDimension, double quality)
    {
        byte[] jpeg = await EncodeAsync(readSource(), maxDimension, quality).ConfigureAwait(false);

        string? directory = Path.GetDirectoryName(destinationPath);
        if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);
        await File.WriteAllBytesAsync(destinationPath, jpeg).ConfigureAwait(false);
    }

    /// <summary>El JPEG resultante, ya verificado como baseline.</summary>
    public static async Task<byte[]> EncodeAsync(byte[] source, int maxDimension, double quality)
    {
        if (source.Length == 0) throw new ImageResizeException("No se pudo leer la imagen de origen.");

        using var input = new InMemoryRandomAccessStream();
        await input.WriteAsync(ToBuffer(source));
        input.Seek(0);

        BitmapDecoder decoder;
        try
        {
            decoder = await BitmapDecoder.CreateAsync(input);
        }
        catch (Exception ex)
        {
            // WIC a veces no trae mensaje; una frase con dos puntos colgando
            // en pantalla es peor que la frase sola.
            string detail = string.IsNullOrWhiteSpace(ex.Message) ? "" : $" ({ex.Message.Trim()})";
            throw new ImageResizeException($"No se pudo leer la imagen de origen.{detail}");
        }

        // El tamaño destino se calcula sobre las medidas YA orientadas (una foto
        // vertical de cámara viene guardada horizontal con la orientación en
        // EXIF). El factor de escala es el mismo en ambos espacios —la
        // orientación solo intercambia o espeja los lados—, así que se aplica
        // sobre las medidas crudas, que es lo que espera BitmapTransform.
        (int orientedWidth, int orientedHeight) = ImageResizePlan.TargetSize(
            (int)decoder.OrientedPixelWidth, (int)decoder.OrientedPixelHeight, maxDimension);
        if (orientedWidth == 0 || orientedHeight == 0)
            throw new ImageResizeException("La imagen de origen no tiene un tamaño válido.");

        double scale = (double)orientedWidth / decoder.OrientedPixelWidth;
        var transform = new BitmapTransform
        {
            ScaledWidth = (uint)Math.Max(1, (int)Math.Round(decoder.PixelWidth * scale)),
            ScaledHeight = (uint)Math.Max(1, (int)Math.Round(decoder.PixelHeight * scale)),
            InterpolationMode = BitmapInterpolationMode.Fant
        };

        using SoftwareBitmap scaled = await decoder.GetSoftwareBitmapAsync(
            BitmapPixelFormat.Bgra8, BitmapAlphaMode.Straight, transform,
            ExifOrientationMode.RespectExifOrientation, ColorManagementMode.ColorManageToSRgb);

        using SoftwareBitmap flattened = FlattenOntoWhite(scaled);

        using var output = new InMemoryRandomAccessStream();
        var options = new BitmapPropertySet
        {
            { "ImageQuality", new BitmapTypedValue(quality, Windows.Foundation.PropertyType.Single) }
        };
        BitmapEncoder encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.JpegEncoderId, output, options);
        encoder.SetSoftwareBitmap(flattened);
        await encoder.FlushAsync();

        byte[] jpeg = await ToBytesAsync(output);

        // D-291: el visor del firmware solo decodifica JPEG baseline. macOS se
        // lo pide explícitamente a ImageIO; el codificador de WIC no expone esa
        // opción, así que la garantía se consigue verificando la salida. Si
        // algún día dejara de ser baseline, se sabe acá y no en el iPod.
        if (!JpegMarkers.IsBaseline(jpeg))
            throw new ImageResizeException(
                "El JPEG generado no es baseline y el iPod no podría mostrarlo.");

        return jpeg;
    }

    /// <summary>
    /// Compone la imagen sobre blanco opaco y descarta el canal alfa.
    ///
    /// <para>Una fuente PNG/GIF con transparencia llegaba tal cual al
    /// codificador JPEG —que no tiene canal alfa—, así que el RGB debajo de los
    /// píxeles transparentes quedaba a su criterio (con frecuencia negro, en
    /// vez del fondo blanco esperado). Se aplana <b>siempre</b>: para una imagen
    /// ya opaca no cambia nada visible.</para>
    /// </summary>
    private static SoftwareBitmap FlattenOntoWhite(SoftwareBitmap source)
    {
        var buffer = new Windows.Storage.Streams.Buffer(
            (uint)(source.PixelWidth * source.PixelHeight * 4));
        source.CopyToBuffer(buffer);
        byte[] pixels = ToBytes(buffer);

        for (int i = 0; i + 3 < pixels.Length; i += 4)
        {
            byte alpha = pixels[i + 3];
            if (alpha == 255) continue;

            // BGRA, alfa no premultiplicado: c sobre blanco = c·a + 255·(1-a).
            for (int channel = 0; channel < 3; channel++)
                pixels[i + channel] = (byte)((pixels[i + channel] * alpha + 255 * (255 - alpha) + 127) / 255);
            pixels[i + 3] = 255;
        }

        var flattened = new SoftwareBitmap(
            BitmapPixelFormat.Bgra8, source.PixelWidth, source.PixelHeight, BitmapAlphaMode.Ignore);
        flattened.CopyFromBuffer(ToBuffer(pixels));
        return flattened;
    }

    private static IBuffer ToBuffer(byte[] bytes)
    {
        var writer = new DataWriter();
        writer.WriteBytes(bytes);
        return writer.DetachBuffer();
    }

    private static byte[] ToBytes(IBuffer buffer)
    {
        byte[] bytes = new byte[buffer.Length];
        DataReader.FromBuffer(buffer).ReadBytes(bytes);
        return bytes;
    }

    private static async Task<byte[]> ToBytesAsync(IRandomAccessStream stream)
    {
        stream.Seek(0);
        var buffer = new Windows.Storage.Streams.Buffer((uint)stream.Size);
        await stream.ReadAsync(buffer, (uint)stream.Size, InputStreamOptions.None);
        return ToBytes(buffer);
    }
}
