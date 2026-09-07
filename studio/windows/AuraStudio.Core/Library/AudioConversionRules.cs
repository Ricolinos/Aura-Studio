namespace AuraStudio.Core.Library;

/// <summary>A qué se convierte un audio, si es que se convierte (ST-244).</summary>
public enum AudioCodec
{
    /// <summary>No se convierte: el archivo viaja tal cual.</summary>
    None,

    /// <summary>ALAC en un contenedor <c>.m4a</c>. Sin pérdida.</summary>
    Alac,

    /// <summary>MP3 de 256 kbps (promedio, no tasa constante).</summary>
    Mp3
}

/// <summary>Qué hacer con un archivo de audio: a qué códec y con qué extensión.</summary>
/// <param name="Extension">
/// La extensión del archivo resultante, o <c>null</c> si no cambia.
/// </param>
public readonly record struct AudioConversion(AudioCodec Codec, string? Extension)
{
    public static readonly AudioConversion None = new(AudioCodec.None, null);

    public bool Converts => Codec != AudioCodec.None;
}

/// <summary>
/// El <b>único</b> lugar que decide qué se convierte y a qué (ST-244).
///
/// <para>Existe como punto único a propósito. La decisión se toma en dos
/// momentos —al copiar un archivo a la biblioteca y al preparar uno referenciado
/// para el iPod— y con dos reglas distintas sería cuestión de tiempo que la
/// biblioteca y el iPod terminaran con formatos que no se corresponden, sin que
/// nadie lo hubiera decidido.</para>
///
/// <para><b>La tabla</b> (fijada con la Mac, plan §0.2 y §2):</para>
///
/// <list type="table">
/// <listheader><term>entrada</term><description>Original sin pérdida / Comprimido</description></listheader>
/// <item><term>WAV, AIFF</term><description>ALAC (<c>.m4a</c>) / MP3 256 kbps</description></item>
/// <item><term>FLAC, ALAC, M4A, MP3</term><description>tal cual / MP3 256 kbps</description></item>
/// </list>
///
/// <para><b>Por qué WAV y AIFF nunca se quedan como están.</b> Ocupan diez veces
/// lo que la misma canción comprimida y el disco del iPod no da abasto. Y por
/// qué a <b>ALAC</b> y no a MP3 cuando el usuario pidió "sin pérdida": porque
/// "sin pérdida" tiene que significar sin pérdida. Convertir a MP3 ahí sería
/// esconder una pérdida debajo de una etiqueta que promete lo contrario.</para>
///
/// <para><b>Y por qué ALAC y no FLAC:</b> es lo que las dos plataformas pueden
/// escribir de forma nativa —macOS no trae codificador MP3, Windows sí trae
/// ALAC— y el iPod con Aura lo reproduce. Elegir un formato que una de las dos
/// no pueda escribir partiría la biblioteca compartida en dos.</para>
/// </summary>
public static class AudioConversionRules
{
    /// <summary>
    /// Los que nunca se quedan como están: por tamaño, no por formato.
    /// </summary>
    public static readonly IReadOnlySet<string> NeverKeptAsIs =
        new HashSet<string>(["wav", "wave", "aif", "aiff", "aifc"], StringComparer.OrdinalIgnoreCase);

    public const string AlacExtension = "m4a";
    public const string Mp3Extension = "mp3";

    /// <summary>Qué hacer con este archivo, según la calidad que eligió el usuario.</summary>
    public static AudioConversion For(string? path, AudioQuality quality)
    {
        if (path is not { Length: > 0 }) return AudioConversion.None;

        string extension = Path.GetExtension(path).TrimStart('.');
        if (extension.Length == 0) return AudioConversion.None;

        if (quality == AudioQuality.Compressed)
        {
            // Todo a MP3 — salvo lo que ya es MP3, que no se recodifica: pasar
            // un MP3 por el codificador otra vez pierde calidad y no gana nada.
            return extension.Equals(Mp3Extension, StringComparison.OrdinalIgnoreCase)
                ? AudioConversion.None
                : new AudioConversion(AudioCodec.Mp3, Mp3Extension);
        }

        return NeverKeptAsIs.Contains(extension)
            ? new AudioConversion(AudioCodec.Alac, AlacExtension)
            : AudioConversion.None;
    }

    /// <summary>Si hay que convertirlo.</summary>
    public static bool Converts(string? path, AudioQuality quality) => For(path, quality).Converts;

    /// <summary>
    /// La extensión que va a tener el archivo resultante, o <c>null</c> si es la
    /// misma que la del original. Sale de acá y no de cada llamador para que la
    /// ruta que se anota en el catálogo y el archivo que se escribe no puedan
    /// discrepar (ST-107).
    /// </summary>
    public static string? ResultingExtension(string? path, AudioQuality quality) =>
        For(path, quality).Extension;
}
