using System.Runtime.CompilerServices;
using AuraStudio.App.ViewModels;
using AuraStudio.Core.Library;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Graphics.Imaging;

namespace AuraStudio.App.Platform;

/// <summary>
/// Lo que hay entre una tarjeta y su miniatura (ST-205): de dónde salen los
/// bytes, con qué clave se guardan y cómo se pintan sin pintar la de otra.
///
/// <para>Vive aparte de las páginas porque las tres —la cuadrícula, la lista de
/// Artistas y el selector de tapas— tienen exactamente el mismo problema, y tres
/// copias de esto son tres oportunidades de que una se olvide de cancelar.</para>
/// </summary>
internal static class CoverThumbnails
{
    /// <summary>
    /// La carga en curso de cada control de imagen. Se cancela la anterior antes
    /// de empezar otra: los contenedores de la cuadrícula se reciclan, y sin esto
    /// una carátula que tardó en leerse aterriza en la tarjeta que ocupó su
    /// lugar — el álbum equivocado, con su nombre debajo.
    ///
    /// <para>Es una tabla débil para no retener contenedores que ya no existen, y
    /// se toca <b>solo desde el hilo de interfaz</b>: por eso no lleva candado.</para>
    /// </summary>
    private static readonly ConditionalWeakTable<FrameworkElement, CancellationTokenSource> Loading = new();

    /// <summary>
    /// Corta lo que ese control estuviera cargando y abre un pedido nuevo.
    /// </summary>
    public static CancellationToken Restart(FrameworkElement element)
    {
        Cancel(element);

        var fresh = new CancellationTokenSource();
        Loading.AddOrUpdate(element, fresh);
        return fresh.Token;
    }

    /// <summary>Corta lo que ese control estuviera cargando, si algo cargaba.</summary>
    public static void Cancel(FrameworkElement element)
    {
        if (!Loading.TryGetValue(element, out CancellationTokenSource? previous)) return;

        Loading.Remove(element);

        previous.Cancel();
        previous.Dispose();
    }

    /// <summary>
    /// La miniatura de la carátula de un elemento del catálogo.
    ///
    /// <para>Con <c>coverHash</c> conocido, la caché responde <b>sin tocar el
    /// disco</b>: esa es toda la diferencia entre desplazarse y volver a leer mil
    /// archivos. Sin él —una biblioteca anterior a ST-208— se lee una vez, la
    /// lectura lo deja anotado en el elemento y el siguiente guardado lo
    /// persiste; a partir de ahí esta rama no vuelve a correr.</para>
    /// </summary>
    public static async Task<SoftwareBitmap?> ForItemAsync(
        LibraryViewModel library, LibraryItem item, int side, CancellationToken ct)
    {
        if (CoverThumbnailKey.ForHash(item.CoverHash, side) is { } key)
            return await CoverThumbnailCache.Shared.ThumbnailAsync(
                key, side, _ => library.ReadCoverAsync(item), ct);

        byte[]? data = await library.ReadCoverAsync(item);
        if (data is not { Length: > 0 }) return null;

        // La lectura pudo dejar el hash anotado; si no, la clave sale del
        // contenido, que es lo mismo con más trabajo.
        string? resolved = CoverThumbnailKey.ForHash(item.CoverHash, side)
                           ?? CoverThumbnailKey.For(data, side);

        if (resolved is null) return null;

        return await CoverThumbnailCache.Shared.ThumbnailAsync(
            resolved, side, _ => Task.FromResult<byte[]?>(data), ct);
    }

    /// <summary>
    /// La miniatura de una imagen que vive en una ruta y no en el catálogo: una
    /// foto, la vista previa de un álbum de fotos.
    /// </summary>
    public static async Task<SoftwareBitmap?> ForPathAsync(string path, int side, CancellationToken ct)
    {
        if (CoverThumbnailKey.ForPath(path, side) is not { } key) return null;

        return await CoverThumbnailCache.Shared.ThumbnailAsync(key, side, ReadFileAsync, ct);

        async Task<byte[]?> ReadFileAsync(CancellationToken _)
        {
            // El File.Exists va acá, en el hilo de fondo, y no antes de pedir:
            // preguntarle al disco por cada tarjeta desde la interfaz es el mismo
            // trabajo que ST-203 sacó de la carga.
            try
            {
                return File.Exists(path) ? await File.ReadAllBytesAsync(path) : null;
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                return null;
            }
        }
    }

    /// <summary>
    /// La miniatura, ya como fuente de imagen. Se pinta una <b>copia</b>: la que
    /// está en la caché la comparten todas las tarjetas que muestren esa
    /// carátula, y entregársela a un control sería dejar que su ciclo de vida
    /// decida por las demás.
    ///
    /// <para>Corre en el hilo de interfaz, que es donde se pueden crear las
    /// fuentes de XAML.</para>
    /// </summary>
    public static async Task<ImageSource?> SourceAsync(SoftwareBitmap? bitmap)
    {
        if (bitmap is null) return null;

        try
        {
            var source = new SoftwareBitmapSource();
            await source.SetBitmapAsync(SoftwareBitmap.Copy(bitmap));
            return source;
        }
        catch (Exception)
        {
            // Una miniatura que no se puede pintar deja la tarjeta con su
            // inicial, igual que si no hubiera carátula.
            return null;
        }
    }
}
