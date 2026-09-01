using AuraStudio.Core.Library;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

namespace AuraStudio.App.Platform;

/// <summary>
/// Miniaturas de carátulas para las cuadrículas de Álbumes y Artistas (ST-031).
/// Port de <c>CoverThumbnailCache.swift</c>.
///
/// <para>Las carátulas se guardan a tamaño completo (~1000 px con fanart.tv);
/// decodificar eso por cada celda visible en cada scroll es exactamente lo que
/// hace lentas esas vistas. WIC decodifica <b>ya reducido</b>
/// (<c>BitmapTransform</c>, el mismo primitivo que usa <see cref="ImageResizer"/>),
/// y acá se guarda el resultado.</para>
///
/// <para><b>El aspecto real se respeta.</b> Fue un bug visible en macOS: forzar
/// la miniatura a un cuadrado hacía que una carátula 16:9 se estirara para
/// llenarlo. El lado mayor se acota a <c>side</c> y el menor sale de la
/// proporción, así que <c>Stretch="UniformToFill"</c> <b>recorta</b> en vez de
/// deformar.</para>
/// </summary>
public sealed class CoverThumbnailCache
{
    public static CoverThumbnailCache Shared { get; } = new();

    /// <summary>Mismo tope que macOS. Se descarta lo más viejo, no todo.</summary>
    private const int Capacity = 600;

    private readonly Lock _gate = new();
    private readonly Dictionary<string, SoftwareBitmap> _entries = [];
    private readonly LinkedList<string> _order = [];

    /// <summary>
    /// La miniatura de esa carátula a ese lado, o <c>null</c> si no hay carátula
    /// o la imagen no se puede leer. <b>Nunca lanza</b>: una carátula rota no
    /// puede tumbar la cuadrícula entera.
    /// </summary>
    public async Task<SoftwareBitmap?> ThumbnailAsync(byte[]? cover, int side)
    {
        string? key = CoverThumbnailKey.For(cover, side);
        if (key is null) return null;

        if (TryGet(key, out SoftwareBitmap? cached)) return cached;

        SoftwareBitmap? decoded = await DecodeAsync(cover!, side).ConfigureAwait(false);
        if (decoded is null) return null;

        return Store(key, decoded);
    }

    private bool TryGet(string key, out SoftwareBitmap? bitmap)
    {
        lock (_gate)
        {
            if (_entries.TryGetValue(key, out SoftwareBitmap? found))
            {
                _order.Remove(key);
                _order.AddLast(key);
                bitmap = found;
                return true;
            }
        }
        bitmap = null;
        return false;
    }

    private SoftwareBitmap Store(string key, SoftwareBitmap bitmap)
    {
        lock (_gate)
        {
            // Otra celda con la misma carátula pudo decodificarla mientras
            // tanto; se queda la que ya está para no tener dos copias vivas.
            if (_entries.TryGetValue(key, out SoftwareBitmap? existing))
            {
                bitmap.Dispose();
                return existing;
            }

            _entries[key] = bitmap;
            _order.AddLast(key);

            while (_order.Count > Capacity && _order.First is { } oldest)
            {
                _order.RemoveFirst();
                if (_entries.Remove(oldest.Value, out SoftwareBitmap? evicted)) evicted.Dispose();
            }

            return bitmap;
        }
    }

    private static async Task<SoftwareBitmap?> DecodeAsync(byte[] cover, int side)
    {
        try
        {
            using var stream = new InMemoryRandomAccessStream();
            var writer = new DataWriter();
            writer.WriteBytes(cover);
            await stream.WriteAsync(writer.DetachBuffer());
            stream.Seek(0);

            BitmapDecoder decoder = await BitmapDecoder.CreateAsync(stream);

            (int width, int height) = ImageResizePlan.TargetSize(
                (int)decoder.OrientedPixelWidth, (int)decoder.OrientedPixelHeight, side);
            if (width == 0 || height == 0) return null;

            double scale = (double)width / decoder.OrientedPixelWidth;
            var transform = new BitmapTransform
            {
                ScaledWidth = (uint)Math.Max(1, (int)Math.Round(decoder.PixelWidth * scale)),
                ScaledHeight = (uint)Math.Max(1, (int)Math.Round(decoder.PixelHeight * scale)),
                InterpolationMode = BitmapInterpolationMode.Fant
            };

            // Premultiplicado: es lo que pide SoftwareBitmapSource para pintar.
            return await decoder.GetSoftwareBitmapAsync(
                BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied, transform,
                ExifOrientationMode.RespectExifOrientation, ColorManagementMode.ColorManageToSRgb);
        }
        catch (Exception)
        {
            // Una carátula ilegible se muestra como celda sin imagen.
            return null;
        }
    }

    /// <summary>Suelta todo lo guardado (al cambiar de biblioteca, por ejemplo).</summary>
    public void Clear()
    {
        lock (_gate)
        {
            foreach (SoftwareBitmap bitmap in _entries.Values) bitmap.Dispose();
            _entries.Clear();
            _order.Clear();
        }
    }
}
