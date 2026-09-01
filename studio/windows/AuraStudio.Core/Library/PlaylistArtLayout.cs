namespace AuraStudio.Core.Library;

/// <param name="X">Borde izquierdo, en píxeles desde la izquierda.</param>
/// <param name="Y">Borde superior, en píxeles desde <b>arriba</b>.</param>
public readonly record struct ArtRect(double X, double Y, double Width, double Height)
{
    public double CenterX => X + Width / 2;
    public double CenterY => Y + Height / 2;
}

/// <summary>
/// La geometría de la imagen por omisión de una lista: colage 2×2 de hasta 4
/// carátulas, o un tile con un glifo de "lista" si no hay ninguna. Port de la
/// parte calculable de <c>PlaylistArtGenerator.swift</c>; el dibujado va en la
/// capa de plataforma.
///
/// <para><b>Coordenadas desde arriba-izquierda</b>, que es como funcionan los
/// mapas de bits de Windows. El Swift las calcula desde abajo-izquierda porque
/// así es CoreGraphics; el resultado en pantalla es el mismo y las pruebas de
/// acá fijan cuál barra queda arriba y cuál abajo.</para>
/// </summary>
public static class PlaylistArtLayout
{
    /// <summary>
    /// 128 px: el mismo tope que una imagen elegida a mano. Es una fila de
    /// lista chica —el firmware la dibuja a 48 px—, no una portada grande.
    /// </summary>
    public const int Dimension = 128;

    /// <summary>La misma calidad que el resto de las imágenes de la app.</summary>
    public const double Quality = 0.85;

    /// <summary>
    /// Grises del tile sin carátulas: literales de
    /// <c>design-system/tokens.json</c>, los mismos tokens que usa
    /// <c>aura_albumart_default_tile()</c> en el firmware. El archivo es un JPEG
    /// estático y no puede leer el tema activo del dispositivo como sí hace el
    /// C, así que se fija al tema claro — mismo criterio que el tile de
    /// referencia del firmware, para que los dos no desentonen si el usuario
    /// los ve uno junto al otro.
    /// </summary>
    public static readonly (byte R, byte G, byte B) PlaceholderBackground = (0xE5, 0xE5, 0xEA);

    public static readonly (byte R, byte G, byte B) PlaceholderInk = (0x9A, 0x9A, 0x9E);

    public const int MaxCovers = 4;

    /// <summary>
    /// Los cuatro cuadrantes, en el orden en que se llenan: arriba-izquierda,
    /// arriba-derecha, abajo-izquierda, abajo-derecha.
    /// </summary>
    public static IReadOnlyList<ArtRect> Quadrants(int dimension = Dimension)
    {
        double half = dimension / 2.0;
        return
        [
            new ArtRect(0, 0, half, half),
            new ArtRect(half, 0, half, half),
            new ArtRect(0, half, half, half),
            new ArtRect(half, half, half, half)
        ];
    }

    /// <summary>
    /// Qué carátula va en cada cuadrante. Con menos de cuatro se <b>recicla
    /// desde el principio</b>: llenar el colage entero da más variedad visual
    /// que dejar cuadrantes en blanco.
    /// </summary>
    public static IReadOnlyList<int> CoverForEachQuadrant(int availableCovers)
    {
        if (availableCovers <= 0) return [];
        return [.. Enumerable.Range(0, MaxCovers).Select(i => i % availableCovers)];
    }

    /// <summary>
    /// El rectángulo al que hay que escalar una imagen de
    /// <paramref name="imageWidth"/>×<paramref name="imageHeight"/> para
    /// <b>llenar</b> <paramref name="target"/> sin deformarla, centrada. Lo que
    /// sobresale se recorta: es "aspect fill", el mismo criterio que las
    /// portadas normales, acá a mano porque el destino es un cuadrante y no la
    /// imagen completa.
    /// </summary>
    public static ArtRect AspectFill(int imageWidth, int imageHeight, ArtRect target)
    {
        if (imageWidth <= 0 || imageHeight <= 0) return target;

        double scale = Math.Max(target.Width / imageWidth, target.Height / imageHeight);
        double width = imageWidth * scale, height = imageHeight * scale;
        return new ArtRect(target.CenterX - width / 2, target.CenterY - height / 2, width, height);
    }

    /// <summary>
    /// Las tres barras redondeadas del glifo de "lista", de la más ancha a la
    /// más angosta — que es de abajo hacia arriba, igual que en macOS.
    /// </summary>
    public static IReadOnlyList<ArtRect> PlaceholderBars(int dimension = Dimension)
    {
        double size = dimension;
        double barHeight = size * 0.09;
        double gap = size * 0.16;
        double startX = size * 0.22;
        double centerY = size / 2;
        double[] widths = [size * 0.56, size * 0.44, size * 0.32];

        return [.. widths.Select((width, index) =>
            new ArtRect(startX, centerY - (index - 1) * gap - barHeight / 2, width, barHeight))];
    }

    /// <summary>El radio con el que se redondean las puntas de cada barra.</summary>
    public static double BarCornerRadius(int dimension = Dimension) => dimension * 0.09 / 2;
}
