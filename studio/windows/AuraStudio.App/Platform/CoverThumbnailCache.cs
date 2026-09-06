using AuraStudio.Core.Library;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

namespace AuraStudio.App.Platform;

/// <summary>
/// Miniaturas de carátulas para las cuadrículas y las listas (ST-031, cableada
/// en ST-205). Port de <c>CoverThumbnailCache.swift</c>.
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
///
/// <para><b>Lo que cambió en ST-205.</b> Hasta entonces nadie la usaba: las
/// vistas leían el archivo y decodificaban la carátula entera cada vez que una
/// tarjeta aparecía, y desplazarse hacia atrás lo volvía a pagar. Ahora
/// (1) la clave sale del <c>coverHash</c> del catálogo, así que responder desde
/// la caché <b>no toca el disco</b>; (2) el tope es de memoria —64 MB— y no de
/// cantidad; (3) dos tarjetas que piden lo mismo a la vez decodifican
/// <b>una</b>; y (4) se puede cancelar, que es lo que evita pintar la carátula
/// de un álbum en la tarjeta de otro al reciclar contenedores.</para>
/// </summary>
public sealed class CoverThumbnailCache
{
    public static CoverThumbnailCache Shared { get; } = new();

    private readonly Lock _gate = new();
    private readonly Dictionary<string, SoftwareBitmap> _entries = new(StringComparer.Ordinal);
    private readonly ThumbnailCacheIndex _index;

    /// <summary>
    /// Lo que se está decodificando ahora mismo, por clave. Doce tarjetas del
    /// mismo álbum apareciendo juntas son <b>una</b> decodificación, no doce.
    /// </summary>
    private readonly Dictionary<string, Task<SoftwareBitmap?>> _inFlight = new(StringComparer.Ordinal);

    public CoverThumbnailCache(long costLimit = ThumbnailCacheIndex.DefaultCostLimit) =>
        _index = new ThumbnailCacheIndex(costLimit);

    /// <summary>Lo que ocupan ahora las miniaturas guardadas, en bytes.</summary>
    public long Cost { get { lock (_gate) return _index.Cost; } }

    /// <summary>Cuántas hay guardadas.</summary>
    public int Count { get { lock (_gate) return _index.Count; } }

    /// <summary>Cuántas veces se respondió sin decodificar. Para medir, no para decidir.</summary>
    public int Hits { get; private set; }

    /// <summary>Cuántas veces hubo que decodificar.</summary>
    public int Misses { get; private set; }

    /// <summary>
    /// La miniatura de esa clave, decodificando los bytes <b>solo si hace
    /// falta</b>. <b>Nunca lanza</b>: una carátula rota no puede tumbar la
    /// cuadrícula entera.
    /// </summary>
    /// <param name="key">
    /// De <see cref="CoverThumbnailKey"/>. Es lo que hace que responder desde la
    /// caché no toque el disco: sale del <c>coverHash</c> que ya está en el
    /// catálogo.
    /// </param>
    /// <param name="loadBytes">
    /// De dónde salen los bytes cuando no está guardada. Se llama <b>solo</b> en
    /// ese caso, y fuera del hilo de interfaz.
    /// </param>
    public async Task<SoftwareBitmap?> ThumbnailAsync(
        string key, int side, Func<CancellationToken, Task<byte[]?>> loadBytes, CancellationToken ct = default)
    {
        if (side <= 0) return null;

        if (TryGet(key, out SoftwareBitmap? cached)) return cached;

        // Una sola tarea por clave: la primera decodifica y las demás esperan la
        // misma. Sin esto, entrar a una sección con doce tarjetas del mismo
        // álbum decodificaba doce veces la misma imagen.
        Task<SoftwareBitmap?> work;

        lock (_gate)
        {
            if (!_inFlight.TryGetValue(key, out Task<SoftwareBitmap?>? running))
            {
                Misses++;

                // La entrada se registra ANTES de empezar el trabajo, y por eso
                // pasa por una promesa en vez de por la tarea misma: si la
                // decodificación terminara antes de que la tarea llegara al
                // diccionario, su limpieza correría primero y la entrada quedaría
                // ahí para siempre, devolviendo una miniatura ya expulsada —y
                // liberada— a todo el que la pidiera después.
                var promise = new TaskCompletionSource<SoftwareBitmap?>(
                    TaskCreationOptions.RunContinuationsAsynchronously);

                running = promise.Task;
                _inFlight[key] = running;

                _ = DecodeAndStoreAsync(promise, key, side, loadBytes);
            }

            work = running;
        }

        // La cancelación es de ESTE pedido, no de la decodificación: si la
        // tarjeta se recicló, lo decodificado le sirve igual a la siguiente que
        // pida lo mismo, y tirarlo sería volver a leer el archivo.
        SoftwareBitmap? bitmap = await work.WaitAsync(ct).ConfigureAwait(false);

        return ct.IsCancellationRequested ? null : bitmap;
    }

    /// <summary>
    /// La forma directa, para el arnés y para quien ya tenga los bytes en la
    /// mano: la clave sale del contenido.
    /// </summary>
    public Task<SoftwareBitmap?> ThumbnailAsync(byte[]? cover, int side)
    {
        string? key = CoverThumbnailKey.For(cover, side);
        if (key is null) return Task.FromResult<SoftwareBitmap?>(null);

        return ThumbnailAsync(key, side, _ => Task.FromResult<byte[]?>(cover));
    }

    private async Task DecodeAndStoreAsync(
        TaskCompletionSource<SoftwareBitmap?> promise,
        string key,
        int side,
        Func<CancellationToken, Task<byte[]?>> loadBytes)
    {
        SoftwareBitmap? result = null;

        try
        {
            byte[]? cover;

            try
            {
                cover = await loadBytes(CancellationToken.None).ConfigureAwait(false);
            }
            catch (Exception)
            {
                // Un archivo que se fue entre que se pidió y que se leyó deja la
                // tarjeta con su inicial, que es lo mismo que se ve sin carátula.
                cover = null;
            }

            if (cover is { Length: > 0 } && await DecodeAsync(cover, side).ConfigureAwait(false) is { } decoded)
                result = Store(key, decoded);
        }
        finally
        {
            // Primero se saca de "lo que se está decodificando" y recién después
            // se entrega: al revés, quien despierte podría encontrar la entrada
            // vieja y esperar una tarea que ya terminó.
            lock (_gate) _inFlight.Remove(key);

            promise.SetResult(result);
        }
    }

    private bool TryGet(string key, out SoftwareBitmap? bitmap)
    {
        lock (_gate)
        {
            if (_index.Touch(key) && _entries.TryGetValue(key, out SoftwareBitmap? found))
            {
                Hits++;
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

            foreach (string evicted in _index.Add(key, CostOf(bitmap)))
            {
                if (_entries.Remove(evicted, out SoftwareBitmap? old) && !ReferenceEquals(old, bitmap))
                    old.Dispose();
            }

            return bitmap;
        }
    }

    /// <summary>
    /// Lo que ocupa de verdad: cuatro bytes por píxel, que es como vive un
    /// <c>Bgra8</c> en memoria. El tamaño del JPEG no dice nada — una carátula
    /// de 40 KB comprimidos son 4 MB descomprimidos.
    /// </summary>
    private static long CostOf(SoftwareBitmap bitmap) =>
        (long)bitmap.PixelWidth * bitmap.PixelHeight * 4;

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
            foreach (string key in _index.Clear())
            {
                if (_entries.Remove(key, out SoftwareBitmap? bitmap)) bitmap.Dispose();
            }

            _entries.Clear();
        }
    }
}
