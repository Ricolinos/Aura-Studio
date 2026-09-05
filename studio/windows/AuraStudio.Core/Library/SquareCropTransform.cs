namespace AuraStudio.Core.Library;

/// <summary>
/// Los números que hay que darle al decodificador de Windows para dejar una
/// imagen cuadrada cuando el archivo trae orientación EXIF (ST-162).
///
/// <para><b>Son dos espacios de coordenadas distintos, y ahí estaba el bug.</b>
/// El decodificador escala <b>antes</b> de aplicar la orientación y recorta
/// <b>después</b>: el escalado se pide en las medidas <b>crudas</b> (las del
/// archivo) y el recorte, en las medidas <b>orientadas</b> (las que se ven).
/// Con una foto de 400×200 y orientación 6 —que se ve 200×400— calcular las dos
/// cosas en el mismo espacio pedía recortar desde x=100 un cuadrado de 200 en
/// una imagen que ahí solo mide 200 de ancho: salía de 100×200, no cuadrada.</para>
///
/// <para>La aritmética del cuadrado sigue siendo la de
/// <see cref="SquareCropPlan"/> —lado corto, recorte al centro, nunca agrandar—;
/// acá solo se decide <b>en qué espacio va cada número</b>.</para>
/// </summary>
/// <param name="ScaledWidth">Ancho al que se escala, en el espacio <b>crudo</b>.</param>
/// <param name="ScaledHeight">Alto al que se escala, en el espacio <b>crudo</b>.</param>
/// <param name="SwapsSides">
/// Si la orientación gira un cuarto de vuelta (EXIF 5 a 8) y por lo tanto
/// intercambia ancho y alto. Las cuatro orientaciones que giran se tratan
/// igual: lo único que le importa al recorte es si los lados se intercambian,
/// no hacia dónde quedó la foto.
/// </param>
/// <param name="CropX">Esquina izquierda del recorte, en el espacio <b>orientado</b> y ya escalado.</param>
/// <param name="CropY">Esquina superior del recorte, en el espacio <b>orientado</b> y ya escalado.</param>
/// <param name="CropSide">Lado del recorte: el lado corto de la imagen escalada.</param>
/// <param name="OutputSide">Lado de la imagen final. Igual a <see cref="CropSide"/>.</param>
public readonly record struct SquareCropTransform(
    int ScaledWidth, int ScaledHeight, bool SwapsSides,
    int CropX, int CropY, int CropSide, int OutputSide)
{
    /// <summary>La fuente no tiene un tamaño utilizable (o el lado pedido no lo es).</summary>
    public static SquareCropTransform Empty => new(0, 0, false, 0, 0, 0, 0);

    public bool IsEmpty => CropSide <= 0 || OutputSide <= 0;

    /// <summary>
    /// Las medidas sobre las que cae el recorte: la imagen ya escalada <b>y ya
    /// orientada</b>. Existe para poder afirmar en una prueba justo lo que
    /// ST-162 rompía — que el cuadrado cabe entero adentro.
    /// </summary>
    public (int Width, int Height) CropSpace =>
        SwapsSides ? (ScaledHeight, ScaledWidth) : (ScaledWidth, ScaledHeight);

    public static SquareCropTransform For(int rawWidth, int rawHeight,
                                          int orientedWidth, int orientedHeight,
                                          int maxSide)
    {
        if (rawWidth <= 0 || rawHeight <= 0) return Empty;

        // El cuadrado se decide sobre lo que se VE: una foto vertical de cámara
        // viene guardada horizontal, y el lado del que se recorta es el corto de
        // la vertical.
        SquareCropPlan plan = SquareCropPlan.For(orientedWidth, orientedHeight, maxSide);
        if (plan.IsEmpty) return Empty;

        int side = plan.OutputSide;

        // Se fija el lado CORTO (el que sobrevive al recorte) exactamente en lo
        // pedido y el largo se redondea hacia arriba: así el recorte nunca tiene
        // que agrandar nada y la salida mide exacto lo que fija el contrato v18
        // (320, 128). La orientación solo intercambia o espeja los lados, así
        // que el lado corto es el mismo en los dos espacios.
        int scaledWidth, scaledHeight;
        if (rawWidth <= rawHeight)
        {
            scaledWidth = side;
            scaledHeight = Math.Max(side, (int)Math.Ceiling((double)rawHeight * side / rawWidth));
        }
        else
        {
            scaledHeight = side;
            scaledWidth = Math.Max(side, (int)Math.Ceiling((double)rawWidth * side / rawHeight));
        }

        // Las orientaciones 5 a 8 giran un cuarto de vuelta: intercambian los
        // lados. Como el recorte se aplica DESPUÉS de orientar, cae sobre las
        // medidas escaladas ya intercambiadas — y con ellas se intercambian el
        // margen horizontal y el vertical, que es lo que se perdía.
        bool swapsSides = orientedWidth != rawWidth || orientedHeight != rawHeight;
        (int cropSpaceWidth, int cropSpaceHeight) =
            swapsSides ? (scaledHeight, scaledWidth) : (scaledWidth, scaledHeight);

        SquareCropPlan crop = SquareCropPlan.For(cropSpaceWidth, cropSpaceHeight, side);

        return new SquareCropTransform(scaledWidth, scaledHeight, swapsSides,
                                       crop.CropX, crop.CropY, crop.CropSide, side);
    }
}
