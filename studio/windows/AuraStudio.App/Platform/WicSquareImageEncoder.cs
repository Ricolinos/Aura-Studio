using AuraStudio.Core.Library;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

namespace AuraStudio.App.Platform;

/// <summary>
/// La mitad de plataforma de <see cref="CoverArtNormalizer"/> (ST-141): medir
/// una imagen y recortarla cuadrada, con WIC. La política —lado, calidad, qué
/// hace falta normalizar— vive en Core y se prueba ahí, sin Windows.
///
/// <para><b>Por qué es síncrono</b>: lo que normaliza son los puntos por donde
/// una carátula entra a la biblioteca (leer una etiqueta, aplicar una tapa,
/// guardar una foto de artista), y varios de ellos son síncronos y viven en
/// Core, que no puede esperar un <c>Task</c> de WinRT. El puente es
/// <c>Task.Run(...).GetAwaiter().GetResult()</c>: al correr en el pool, la
/// continuación de WinRT no necesita el hilo de interfaz y no hay bloqueo
/// cruzado. Lo que cuesta es una decodificación y una codificación de una
/// imagen de ~1000 px — decenas de milisegundos, una sola vez por carátula.</para>
/// </summary>
public sealed class WicSquareImageEncoder : ISquareImageEncoder
{
    /// <summary>
    /// El normalizador de la app: uno solo, sin estado, para que ningún punto
    /// de entrada de carátulas tenga que armar el suyo (y ninguno se olvide).
    /// </summary>
    public static readonly CoverArtNormalizer SharedNormalizer = new(new WicSquareImageEncoder());

    public (int Width, int Height)? OrientedPixelSize(byte[] image)
    {
        if (image.Length == 0) return null;

        try
        {
            return Block(async () =>
            {
                using var input = new InMemoryRandomAccessStream();
                var writer = new DataWriter();
                writer.WriteBytes(image);
                await input.WriteAsync(writer.DetachBuffer());
                input.Seek(0);

                BitmapDecoder decoder = await BitmapDecoder.CreateAsync(input);
                return ((int Width, int Height)?)
                    ((int)decoder.OrientedPixelWidth, (int)decoder.OrientedPixelHeight);
            });
        }
        catch (Exception)
        {
            // Unos bytes que no son una imagen no son un error acá: significan
            // "no hay nada que normalizar" (ver CoverArtNormalizer.Normalize).
            return null;
        }
    }

    public byte[] EncodeSquare(byte[] source, int side, double quality)
        => Block(() => ImageResizer.EncodeSquareAsync(source, side, quality));

    private static T Block<T>(Func<Task<T>> work) => Task.Run(work).GetAwaiter().GetResult();
}
