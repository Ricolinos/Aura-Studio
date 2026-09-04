namespace AuraStudio.Core.Library;

/// <summary>
/// La política de "toda carátula de la biblioteca es cuadrada" (ST-141, contrato
/// v18 §A.1). Un solo lugar decide el lado y la calidad, y un solo lugar decide
/// si una imagen ya cumple — macOS calca estos números
/// (<c>CoverArtNormalizer.swift</c>).
///
/// <para><b>Por qué desde el origen y no al sincronizar</b>: lo que viaja al
/// iPod se deriva de la copia local (<c>.portadas\</c>), así que una copia local
/// 4:3 obliga a recortar en cada sync y deja la vista previa de la app mostrando
/// una imagen distinta a la del aparato. Guardándola cuadrada una sola vez, la
/// app, el iPod y la carátula embebida muestran exactamente lo mismo.</para>
///
/// <para><b>Lo que se pierde, dicho de frente</b>: la franja recortada no se
/// puede recuperar. Es lo pedido (cuadrado siempre) y por eso la migración de
/// bibliotecas existentes nunca toca el archivo original del usuario — solo la
/// copia de <c>.portadas\</c>.</para>
/// </summary>
public static class CoverArtNormalization
{
    /// <summary>
    /// Tope del lado en la biblioteca local. 1000 px es lo que entrega fanart.tv
    /// y sobra para cualquier pantalla; el iPod recibe 320 (ST-142), derivado de
    /// esta copia.
    /// </summary>
    public const int MaxSide = 1000;

    /// <summary>
    /// Más alta que la del iPod (0.85): esta es la copia MAESTRA de la que se
    /// derivan las demás, y recomprimir sobre una fuente ya degradada acumula
    /// pérdida.
    /// </summary>
    public const double Quality = 0.92;

    /// <summary>
    /// Versión del formato de la biblioteca local, escrita en
    /// <c>biblioteca.json</c> como <c>coversNormalized</c> al terminar la
    /// migración. <c>1</c> sería "sin normalizar" (nunca se escribe): la
    /// ausencia de la clave ya significa eso. <c>2</c> = carátulas cuadradas.
    /// </summary>
    public const int NormalizedVersion = 2;

    /// <summary>
    /// <c>true</c> si la imagen NO cumple todavía: no es cuadrada, o excede el
    /// tope. Aritmética pura para poder probarla sin WIC.
    /// </summary>
    public static bool NeedsNormalizing(int width, int height)
    {
        if (width <= 0 || height <= 0) return false;
        return width != height || width > MaxSide;
    }
}

/// <summary>
/// Lo que hace falta de la plataforma para normalizar una imagen. La
/// implementación real vive en la app (WIC, <c>AuraStudio.App/Platform</c>);
/// acá solo la interfaz, para que la política y la migración se puedan probar
/// sin plataforma — el mismo criterio que <see cref="ImageResizePlan"/>.
/// </summary>
public interface ISquareImageEncoder
{
    /// <summary>
    /// Medidas de la imagen <b>ya orientadas</b> (la rotación EXIF aplicada), o
    /// <c>null</c> si los bytes no son una imagen legible. Debe leer solo la
    /// cabecera: la migración se lo pregunta a miles de archivos.
    /// </summary>
    (int Width, int Height)? OrientedPixelSize(byte[] image);

    /// <summary>
    /// El JPEG cuadrado de lado <paramref name="side"/>, recortado al centro
    /// (fill + center-crop). Nunca agranda: una fuente con el lado corto menor
    /// sale con ese lado corto.
    /// </summary>
    byte[] EncodeSquare(byte[] source, int side, double quality);
}

/// <summary>
/// Aplica <see cref="CoverArtNormalization"/> a bytes y a archivos. Port de
/// <c>CoverArtNormalizer.swift</c>.
/// </summary>
public sealed class CoverArtNormalizer(ISquareImageEncoder encoder)
{
    /// <summary>
    /// La versión cuadrada de estos bytes.
    ///
    /// <para>Devuelve <b>los mismos bytes</b> cuando ya cumple (no se recomprime
    /// de gratis: cada pasada por el codificador JPEG pierde algo) y también
    /// cuando la imagen no se puede leer o el recorte falla — perder una
    /// carátula por no poder normalizarla sería un mal negocio; el sync la
    /// recortará igual antes de escribirla al iPod.</para>
    /// </summary>
    public byte[] Normalize(byte[] cover)
    {
        if (cover.Length == 0) return cover;

        (int Width, int Height)? size = encoder.OrientedPixelSize(cover);
        if (size is not { } measured) return cover;
        if (!CoverArtNormalization.NeedsNormalizing(measured.Width, measured.Height)) return cover;

        try
        {
            byte[] square = encoder.EncodeSquare(cover, CoverArtNormalization.MaxSide, CoverArtNormalization.Quality);
            return square.Length == 0 ? cover : square;
        }
        catch (Exception)
        {
            // Cualquier cosa que el codificador de la plataforma tire: la
            // carátula se queda como está, no se pierde.
            return cover;
        }
    }

    /// <summary>
    /// Igual, para un archivo ya escrito. <c>true</c> si lo reescribió. Escribe
    /// de forma atómica (temporal + <c>Move</c>): una interrupción a media
    /// pasada deja el archivo anterior intacto, nunca uno truncado.
    /// </summary>
    public bool NormalizeFile(string path)
    {
        byte[] original;
        try { original = File.ReadAllBytes(path); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { return false; }

        byte[] normalized = Normalize(original);
        if (ReferenceEquals(normalized, original) || normalized.Length == 0) return false;

        try
        {
            string temporary = path + ".tmp";
            File.WriteAllBytes(temporary, normalized);
            File.Move(temporary, path, overwrite: true);
            return true;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }
}
