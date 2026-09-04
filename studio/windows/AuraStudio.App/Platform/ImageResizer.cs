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

        return await EncodeJpegAsync(scaled, quality);
    }

    // --- Recorte cuadrado (contrato v18, ST-140) ---

    /// <summary>
    /// El JPEG cuadrado de lado <paramref name="side"/>, recortado al centro
    /// desde el lado corto de la fuente (fill + center-crop, nunca estirado ni
    /// con bandas). Es la primitiva que usan la biblioteca local y el sync:
    /// carátulas de álbum (<c>cover.jpg</c> 320), fotos de artista (128) y la
    /// copia local de <c>.portadas\</c> (lado corto, tope 1000).
    ///
    /// <para>Nunca escala hacia arriba: una fuente cuyo lado corto sea menor
    /// que <paramref name="side"/> sale con ese lado corto. La orientación EXIF
    /// se respeta y se hornea en los píxeles. Port de
    /// <c>ImageResizer.squareCrop(data:side:quality:)</c> en macOS — mismos
    /// números, misma aritmética (<see cref="SquareCropPlan"/>).</para>
    /// </summary>
    public static async Task<byte[]> EncodeSquareAsync(byte[] source, int side, double quality)
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
            string detail = string.IsNullOrWhiteSpace(ex.Message) ? "" : $" ({ex.Message.Trim()})";
            throw new ImageResizeException($"No se pudo leer la imagen de origen.{detail}");
        }

        // El plan se calcula sobre las medidas YA orientadas: lo que se recorta
        // es lo que se ve, no cómo está guardado el archivo.
        var plan = SquareCropPlan.For((int)decoder.OrientedPixelWidth, (int)decoder.OrientedPixelHeight, side);
        if (plan.IsEmpty)
            throw new ImageResizeException("La imagen de origen no tiene un tamaño válido.");

        // Lo que hay que fijar es el lado CORTO (el que sobrevive al recorte),
        // no el mayor: se lleva EXACTO al lado pedido y el largo se redondea
        // hacia arriba, para que el recorte nunca tenga que agrandar nada y el
        // resultado mida exactamente lo que el contrato v18 fija (320, 128).
        // Las medidas van en el espacio CRUDO, que es lo que espera
        // BitmapTransform; la orientación solo intercambia o espeja los lados,
        // así que el lado corto es el mismo en los dos espacios.
        int rawWidth = (int)decoder.PixelWidth, rawHeight = (int)decoder.PixelHeight;
        int scaledWidth, scaledHeight;
        if (rawWidth <= rawHeight)
        {
            scaledWidth = plan.OutputSide;
            scaledHeight = Math.Max(plan.OutputSide,
                                    (int)Math.Ceiling((double)rawHeight * plan.OutputSide / rawWidth));
        }
        else
        {
            scaledHeight = plan.OutputSide;
            scaledWidth = Math.Max(plan.OutputSide,
                                   (int)Math.Ceiling((double)rawWidth * plan.OutputSide / rawHeight));
        }

        // Bounds recorta sobre la imagen YA escalada. Un cuadrado centrado es
        // el mismo antes y después de la orientación EXIF (girar 90° o espejar
        // no mueve el centro), así que da igual en qué espacio lo aplique WIC:
        // lo único que puede cambiar de lado es el píxel sobrante de un margen
        // impar, que es medio píxel de diferencia con macOS y no se ve.
        var crop = SquareCropPlan.For(scaledWidth, scaledHeight, plan.OutputSide);
        var transform = new BitmapTransform
        {
            ScaledWidth = (uint)scaledWidth,
            ScaledHeight = (uint)scaledHeight,
            InterpolationMode = BitmapInterpolationMode.Fant,
            Bounds = new BitmapBounds
            {
                X = (uint)crop.CropX,
                Y = (uint)crop.CropY,
                Width = (uint)crop.CropSide,
                Height = (uint)crop.CropSide
            }
        };

        using SoftwareBitmap square = await decoder.GetSoftwareBitmapAsync(
            BitmapPixelFormat.Bgra8, BitmapAlphaMode.Straight, transform,
            ExifOrientationMode.RespectExifOrientation, ColorManagementMode.ColorManageToSRgb);

        return await EncodeJpegAsync(square, quality);
    }

    /// <summary>
    /// Escribe el JPEG cuadrado directo a un archivo, creando su carpeta.
    /// </summary>
    public static async Task SquareCropAsync(byte[] source, string destinationPath, int side,
                                             double quality = DefaultQuality)
    {
        byte[] jpeg = await EncodeSquareAsync(source, side, quality).ConfigureAwait(false);

        string? directory = Path.GetDirectoryName(destinationPath);
        if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);
        await File.WriteAllBytesAsync(destinationPath, jpeg).ConfigureAwait(false);
    }

    public static Task SquareCropAsync(string sourcePath, string destinationPath, int side,
                                       double quality = DefaultQuality)
        => SquareCropAsync(File.ReadAllBytes(sourcePath), destinationPath, side, quality);

    /// <summary>El JPEG de la imagen, aplanada sobre blanco y ya verificada como baseline.</summary>
    private static async Task<byte[]> EncodeJpegAsync(SoftwareBitmap bitmap, double quality)
    {
        using SoftwareBitmap flattened = FlattenOntoWhite(bitmap);

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
