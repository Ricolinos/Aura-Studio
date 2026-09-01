using AuraStudio.Core.Library;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

namespace AuraStudio.App.Platform;

/// <summary>
/// La imagen por omisión de una lista, cuando el usuario no eligió una propia.
/// Port de <c>PlaylistArtGenerator.swift</c>; la geometría vive en
/// <see cref="PlaylistArtLayout"/> y acá solo se dibuja.
///
/// <para>Studio <b>siempre</b> deja un <c>.jpg</c> junto al <c>.m3u8</c> al
/// sincronizar. El firmware tiene su propio tile genérico de respaldo para una
/// lista puesta a mano, pero repetido en las 20 listas del usuario no dice nada:
/// un colage de las carátulas que ya están en la lista sí distingue una de
/// otra.</para>
///
/// <para>Sin ninguna carátula disponible —lista vacía, o pistas sin arte
/// conocido— se dibuja un tile plano con un glifo de "lista" en los mismos
/// grises que usa el firmware, para que los dos casos no desentonen entre
/// sí.</para>
/// </summary>
public static class PlaylistArtGenerator
{
    /// <summary>
    /// <paramref name="coverArtCandidates"/> son las carátulas conocidas de las
    /// pistas, en el orden de la lista (quien llama ya descartó las que no
    /// tienen). Siempre escribe un JPEG válido: colage o tile, nunca un archivo
    /// a medio escribir.
    /// </summary>
    public static async Task GenerateDefaultAsync(
        IReadOnlyList<byte[]> coverArtCandidates, string destinationPath)
    {
        byte[] jpeg = await ComposeAsync(coverArtCandidates).ConfigureAwait(false);

        string? directory = Path.GetDirectoryName(destinationPath);
        if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);

        // Se escribe a un temporal y se reemplaza: si el proceso muere a mitad,
        // la lista se queda con su imagen anterior en vez de con un JPEG roto.
        string temporary = destinationPath + ".tmp";
        await File.WriteAllBytesAsync(temporary, jpeg).ConfigureAwait(false);
        File.Move(temporary, destinationPath, overwrite: true);
    }

    /// <summary>El JPEG compuesto, ya verificado como baseline.</summary>
    public static async Task<byte[]> ComposeAsync(IReadOnlyList<byte[]> coverArtCandidates)
    {
        const int size = PlaylistArtLayout.Dimension;
        byte[] canvas = new byte[size * size * 4];

        List<byte[]> usable = await DecodableCoversAsync(coverArtCandidates).ConfigureAwait(false);

        if (usable.Count == 0) DrawPlaceholder(canvas, size);
        else await DrawCollageAsync(canvas, size, usable).ConfigureAwait(false);

        return await EncodeAsync(canvas, size).ConfigureAwait(false);
    }

    /// <summary>
    /// Solo las carátulas que WIC realmente puede abrir, hasta cuatro. Una
    /// imagen rota entre las candidatas no puede dejar un cuadrante negro.
    /// </summary>
    private static async Task<List<byte[]>> DecodableCoversAsync(IReadOnlyList<byte[]> candidates)
    {
        var usable = new List<byte[]>();

        foreach (byte[] candidate in candidates)
        {
            if (usable.Count == PlaylistArtLayout.MaxCovers) break;
            if (candidate is null or { Length: 0 }) continue;

            try
            {
                using IRandomAccessStream stream = await ToStreamAsync(candidate).ConfigureAwait(false);
                _ = await BitmapDecoder.CreateAsync(stream);
                usable.Add(candidate);
            }
            catch (Exception)
            {
                // Ilegible: se salta y se prueba la siguiente.
            }
        }

        return usable;
    }

    private static async Task DrawCollageAsync(byte[] canvas, int size, List<byte[]> covers)
    {
        IReadOnlyList<ArtRect> quadrants = PlaylistArtLayout.Quadrants(size);
        IReadOnlyList<int> assignment = PlaylistArtLayout.CoverForEachQuadrant(covers.Count);

        for (int quadrant = 0; quadrant < quadrants.Count; quadrant++)
        {
            ArtRect target = quadrants[quadrant];
            byte[]? tile = await RenderTileAsync(covers[assignment[quadrant]], target).ConfigureAwait(false);
            if (tile is null) continue;

            Blit(canvas, size, tile, (int)target.Width, (int)target.X, (int)target.Y);
        }
    }

    /// <summary>
    /// Una carátula escalada para <b>llenar</b> el cuadrante y recortada
    /// centrada. El escalado y el recorte los hace WIC; el rectángulo lo calcula
    /// <see cref="PlaylistArtLayout.AspectFill"/>, que está probado aparte.
    /// </summary>
    private static async Task<byte[]?> RenderTileAsync(byte[] cover, ArtRect target)
    {
        try
        {
            using IRandomAccessStream stream = await ToStreamAsync(cover).ConfigureAwait(false);
            BitmapDecoder decoder = await BitmapDecoder.CreateAsync(stream);

            ArtRect fill = PlaylistArtLayout.AspectFill(
                (int)decoder.OrientedPixelWidth, (int)decoder.OrientedPixelHeight, target);

            uint scaledWidth = (uint)Math.Max(target.Width, Math.Round(fill.Width));
            uint scaledHeight = (uint)Math.Max(target.Height, Math.Round(fill.Height));

            var transform = new BitmapTransform
            {
                ScaledWidth = scaledWidth,
                ScaledHeight = scaledHeight,
                InterpolationMode = BitmapInterpolationMode.Fant,
                // El recorte se aplica DESPUÉS del escalado, así que estas
                // coordenadas son las de la imagen ya escalada.
                Bounds = new BitmapBounds
                {
                    X = (scaledWidth - (uint)target.Width) / 2,
                    Y = (scaledHeight - (uint)target.Height) / 2,
                    Width = (uint)target.Width,
                    Height = (uint)target.Height
                }
            };

            using SoftwareBitmap tile = await decoder.GetSoftwareBitmapAsync(
                BitmapPixelFormat.Bgra8, BitmapAlphaMode.Ignore, transform,
                ExifOrientationMode.RespectExifOrientation, ColorManagementMode.ColorManageToSRgb);

            var buffer = new Windows.Storage.Streams.Buffer(
                (uint)(tile.PixelWidth * tile.PixelHeight * 4));
            tile.CopyToBuffer(buffer);
            return ToBytes(buffer);
        }
        catch (Exception)
        {
            return null;
        }
    }

    private static void Blit(byte[] canvas, int canvasSize, byte[] tile, int tileSize, int atX, int atY)
    {
        for (int y = 0; y < tileSize; y++)
        {
            int destinationY = atY + y;
            if (destinationY < 0 || destinationY >= canvasSize) continue;

            int source = y * tileSize * 4;
            int destination = (destinationY * canvasSize + atX) * 4;
            Array.Copy(tile, source, canvas, destination, tileSize * 4);
        }
    }

    private static void DrawPlaceholder(byte[] canvas, int size)
    {
        (byte R, byte G, byte B) background = PlaylistArtLayout.PlaceholderBackground;
        for (int i = 0; i < canvas.Length; i += 4)
        {
            canvas[i] = background.B;
            canvas[i + 1] = background.G;
            canvas[i + 2] = background.R;
            canvas[i + 3] = 255;
        }

        (byte R, byte G, byte B) ink = PlaylistArtLayout.PlaceholderInk;
        double radius = PlaylistArtLayout.BarCornerRadius(size);

        foreach (ArtRect bar in PlaylistArtLayout.PlaceholderBars(size))
        {
            for (int y = (int)bar.Y; y <= (int)(bar.Y + bar.Height) && y < size; y++)
            {
                if (y < 0) continue;
                for (int x = (int)bar.X; x <= (int)(bar.X + bar.Width) && x < size; x++)
                {
                    if (x < 0) continue;
                    double coverage = BarCoverage(x, y, bar, radius);
                    if (coverage <= 0) continue;

                    int i = (y * size + x) * 4;
                    canvas[i] = Mix(canvas[i], ink.B, coverage);
                    canvas[i + 1] = Mix(canvas[i + 1], ink.G, coverage);
                    canvas[i + 2] = Mix(canvas[i + 2], ink.R, coverage);
                }
            }
        }
    }

    /// <summary>
    /// Qué fracción del píxel cae dentro de la barra, muestreando 4×4. Sin esto
    /// las puntas redondeadas quedan dentadas: el equivalente de macOS lo dibuja
    /// con el suavizado de CoreGraphics, que acá no existe.
    /// </summary>
    private static double BarCoverage(int pixelX, int pixelY, ArtRect bar, double radius)
    {
        const int samples = 4;
        int inside = 0;

        for (int sy = 0; sy < samples; sy++)
            for (int sx = 0; sx < samples; sx++)
            {
                double x = pixelX + (sx + 0.5) / samples;
                double y = pixelY + (sy + 0.5) / samples;
                if (IsInsideCapsule(x, y, bar, radius)) inside++;
            }

        return (double)inside / (samples * samples);
    }

    /// <summary>
    /// La barra es una cápsula: el rectángulo central más un semicírculo en
    /// cada punta, con el radio igual a la mitad del alto.
    /// </summary>
    private static bool IsInsideCapsule(double x, double y, ArtRect bar, double radius)
    {
        if (y < bar.Y || y > bar.Y + bar.Height) return false;

        double leftCap = bar.X + radius, rightCap = bar.X + bar.Width - radius;
        if (x >= leftCap && x <= rightCap) return true;

        double capX = x < leftCap ? leftCap : rightCap;
        double dx = x - capX, dy = y - bar.CenterY;
        return dx * dx + dy * dy <= radius * radius;
    }

    private static byte Mix(byte under, byte over, double coverage) =>
        (byte)Math.Round(under * (1 - coverage) + over * coverage);

    private static async Task<byte[]> EncodeAsync(byte[] canvas, int size)
    {
        var bitmap = new SoftwareBitmap(BitmapPixelFormat.Bgra8, size, size, BitmapAlphaMode.Ignore);
        bitmap.CopyFromBuffer(ToBuffer(canvas));

        using var output = new InMemoryRandomAccessStream();
        var options = new BitmapPropertySet
        {
            { "ImageQuality", new BitmapTypedValue(
                PlaylistArtLayout.Quality, Windows.Foundation.PropertyType.Single) }
        };
        BitmapEncoder encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.JpegEncoderId, output, options);
        encoder.SetSoftwareBitmap(bitmap);
        await encoder.FlushAsync();

        output.Seek(0);
        var buffer = new Windows.Storage.Streams.Buffer((uint)output.Size);
        await output.ReadAsync(buffer, (uint)output.Size, InputStreamOptions.None);
        byte[] jpeg = ToBytes(buffer);

        // D-291, igual que en ImageResizer: el visor del firmware solo decodifica
        // baseline, y esta imagen va al iPod como cualquier otra.
        if (!JpegMarkers.IsBaseline(jpeg))
            throw new ImageResizeException(
                "La imagen de la lista no salió como JPEG baseline y el iPod no podría mostrarla.");

        return jpeg;
    }

    private static async Task<IRandomAccessStream> ToStreamAsync(byte[] bytes)
    {
        var stream = new InMemoryRandomAccessStream();
        await stream.WriteAsync(ToBuffer(bytes));
        stream.Seek(0);
        return stream;
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
}
