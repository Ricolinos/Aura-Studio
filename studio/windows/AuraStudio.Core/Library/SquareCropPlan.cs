namespace AuraStudio.Core.Library;

/// <summary>
/// Dónde recortar una imagen para dejarla cuadrada, y de qué lado sale. Es
/// aritmética pura, separada del codificador para poder verificarla sin WIC —
/// el equivalente exacto de <c>SquareCropPlan.swift</c> en macOS: mismos casos
/// de prueba, mismos números.
///
/// <para>"Cuadrada" significa siempre <b>rellenar y recortar al centro</b>
/// (fill + center-crop): se conserva el cuadrado central del lado corto y se
/// tira la mitad sobrante del lado largo, repartida en los dos extremos. Nunca
/// se estira ni se agregan bandas — <c>CONTRATO-firmware-studio.md</c> §A.1 de
/// la ronda de carátulas cuadradas (contrato v18) y §D.5, donde el firmware
/// describe la misma primitiva para su caché maestra.</para>
/// </summary>
/// <param name="SourceWidth">
/// Ancho de la imagen de origen <b>ya orientado</b> (una foto vertical de
/// cámara viene guardada horizontal con la rotación en EXIF; el plan se calcula
/// sobre lo que se ve, no sobre lo que está guardado).
/// </param>
/// <param name="SourceHeight">Alto de la imagen de origen, ya orientado.</param>
/// <param name="CropX">Esquina izquierda del cuadrado que se conserva.</param>
/// <param name="CropY">Esquina superior del cuadrado que se conserva.</param>
/// <param name="CropSide">Lado del cuadrado que se conserva: el lado corto del origen.</param>
/// <param name="OutputSide">
/// Lado de la imagen final: <c>min(lado corto, maxSide)</c>. Nunca se escala
/// hacia arriba — una fuente más chica que <c>maxSide</c> sale con su propio
/// tamaño, igual que <see cref="ImageResizePlan.TargetSize"/>.
/// </param>
public readonly record struct SquareCropPlan(
    int SourceWidth, int SourceHeight, int CropX, int CropY, int CropSide, int OutputSide)
{
    /// <summary>
    /// El plan vacío: la fuente no tiene un tamaño utilizable (o el lado pedido
    /// no lo es). El llamador falla con un mensaje claro en vez de mandarle al
    /// codificador una imagen de cero píxeles.
    /// </summary>
    public static SquareCropPlan Empty => new(0, 0, 0, 0, 0, 0);

    public static SquareCropPlan For(int width, int height, int maxSide)
    {
        if (width <= 0 || height <= 0 || maxSide <= 0) return Empty;

        int side = Math.Min(width, height);
        // La división entera reparte el sobrante de forma determinista: con un
        // margen impar el píxel de más se descarta del lado DERECHO (o
        // INFERIOR), nunca "el que toque". Que las dos plataformas recorten el
        // mismo píxel es lo que hace comparables sus pruebas.
        return new SquareCropPlan(width, height,
                                  (width - side) / 2, (height - side) / 2,
                                  side, Math.Min(side, maxSide));
    }

    public bool IsEmpty => CropSide <= 0 || OutputSide <= 0;

    /// <summary><c>false</c> cuando la fuente ya era cuadrada: no hay nada que tirar.</summary>
    public bool NeedsCrop => !IsEmpty && (CropSide != SourceWidth || CropSide != SourceHeight);

    /// <summary>
    /// <c>false</c> cuando el cuadrado recortado ya mide lo pedido: no hay que
    /// remuestrear (y remuestrear de gratis solo pierde definición).
    /// </summary>
    public bool NeedsResize => !IsEmpty && OutputSide != CropSide;
}
