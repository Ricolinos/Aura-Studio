namespace AuraStudio.Core.Library;

/// <summary>
/// El tamaño de salida de una imagen que va al iPod. Es aritmética pura,
/// separada del codificador para poder verificarla sin depender de WIC.
/// </summary>
public static class ImageResizePlan
{
    /// <summary>
    /// Resolución nativa del LCD del iPod Classic. Es el valor por omisión;
    /// con la preferencia de calidad de foto en alta (D-191/D-192) el llamador
    /// pasa 640, que es el máximo que admite el firmware
    /// (<c>CONTRATO-firmware-studio.md</c>).
    /// </summary>
    public const int DefaultMaxDimension = 320;

    /// <summary>Máximo que el firmware acepta; más grande no se muestra mejor.</summary>
    public const int FirmwareMaxDimension = 640;

    /// <summary>
    /// El tamaño destino: el lado mayor queda en <paramref name="maxDimension"/>
    /// conservando el aspecto (no recorta ni deforma), y una imagen que ya es
    /// más chica se deja como está — escalarla hacia arriba solo agrega peso y
    /// la ve peor.
    /// </summary>
    public static (int Width, int Height) TargetSize(int width, int height, int maxDimension)
    {
        if (width <= 0 || height <= 0 || maxDimension <= 0) return (0, 0);
        if (width <= maxDimension && height <= maxDimension) return (width, height);

        double scale = (double)maxDimension / Math.Max(width, height);
        // Nunca 0: una imagen muy alargada (p. ej. 4000x3) redondearía su lado
        // corto a cero y el codificador fallaría con una imagen vacía.
        return (Math.Max(1, (int)Math.Round(width * scale)),
                Math.Max(1, (int)Math.Round(height * scale)));
    }
}

/// <summary>
/// Lectura de los marcadores de un JPEG. Sirve para una sola cosa, y crítica:
/// verificar que la salida sea <b>baseline</b>.
///
/// <para>D-291 del firmware (<c>aura_photos.c</c>): el visor de Aura solo
/// decodifica JPEG baseline — un progresivo (marcador SOF2) aparece en el iPod
/// como "Formato no soportado". macOS lo fuerza pidiéndole a ImageIO
/// <c>kCGImagePropertyJFIFIsProgressive: false</c>; el codificador JPEG de
/// Windows (WIC) no expone esa opción, así que acá la garantía se consigue del
/// otro lado: se <b>verifica</b> la salida y se falla si no es baseline, en vez
/// de confiar en que el codificador haga lo correcto.</para>
/// </summary>
public static class JpegMarkers
{
    /// <summary>Marcadores de inicio de cuadro (SOF) que son progresivos o aritméticos.</summary>
    private static readonly byte[] NonBaselineStartOfFrame = [0xC2, 0xC6, 0xCA, 0xCE];

    /// <summary>Marcadores SOF que sí decodifica el firmware (baseline y extendido secuencial).</summary>
    private static readonly byte[] BaselineStartOfFrame = [0xC0, 0xC1, 0xC9, 0xCD];

    /// <summary>
    /// <c>true</c> solo si los bytes son un JPEG con un SOF secuencial. Un
    /// archivo que no es JPEG, o uno truncado antes del SOF, da <c>false</c>:
    /// ante la duda no se declara apto.
    /// </summary>
    public static bool IsBaseline(ReadOnlySpan<byte> jpeg)
    {
        // SOI
        if (jpeg.Length < 4 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) return false;

        int i = 2;
        while (i + 3 < jpeg.Length)
        {
            if (jpeg[i] != 0xFF) { i++; continue; }   // relleno entre segmentos

            byte marker = jpeg[i + 1];
            if (marker is 0xFF or 0x00) { i++; continue; }

            if (NonBaselineStartOfFrame.Contains(marker)) return false;
            if (BaselineStartOfFrame.Contains(marker)) return true;

            // SOI/EOI y los RSTn no llevan longitud.
            if (marker is 0xD8 or 0xD9 || (marker >= 0xD0 && marker <= 0xD7)) { i += 2; continue; }

            int length = (jpeg[i + 2] << 8) | jpeg[i + 3];
            if (length < 2) return false;             // segmento corrupto
            i += 2 + length;
        }

        return false;   // se acabaron los bytes sin encontrar un SOF
    }
}
