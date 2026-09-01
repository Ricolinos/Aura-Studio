using System.Globalization;

namespace AuraStudio.Core.Media;

/// <param name="Width">Ancho real del video de origen, no el del contenedor.</param>
public readonly record struct VideoResolution(int Width, int Height);

/// <summary>
/// Lo que se le saca a la salida de ffmpeg. Port de los parsers de
/// <c>FFmpegTranscoder.swift</c>, puros para poder probarlos con texto suelto,
/// sin ffmpeg y sin un video.
/// </summary>
public static class FfmpegOutput
{
    /// <summary>De la línea <c>Duration: HH:MM:SS.ss, start: …</c>.</summary>
    public static double? ParseDuration(string output)
    {
        const string key = "Duration: ";
        int start = output.IndexOf(key, StringComparison.Ordinal);
        if (start < 0) return null;

        int from = start + key.Length;
        int comma = output.IndexOf(',', from);
        if (comma < 0) return null;

        return ParseTimecode(output[from..comma]);
    }

    /// <summary>
    /// El <c>NN fps</c> de la línea del stream de video. <c>null</c> si el
    /// archivo no tiene video, o si su contenedor no declara el dato — que pasa,
    /// aunque sea poco común.
    /// </summary>
    public static double? ParseFrameRate(string output)
    {
        foreach (string line in output.Split('\n'))
        {
            if (!line.Contains(" Video: ", StringComparison.Ordinal)) continue;

            int fps = line.IndexOf(" fps", StringComparison.Ordinal);
            if (fps < 0) continue;

            string before = line[..fps];
            int comma = before.LastIndexOf(',');
            if (comma < 0) continue;

            if (double.TryParse(before[(comma + 1)..].Trim(), NumberStyles.Float,
                    CultureInfo.InvariantCulture, out double value))
            {
                return value;
            }
        }

        return null;
    }

    /// <summary>
    /// El primer <c>NNNxNNN</c> de la línea del stream de video.
    ///
    /// <para>Se recorre carácter por carácter en vez de partir por comas porque
    /// el nombre del formato de píxel trae comas propias adentro de paréntesis
    /// (<c>yuv420p(tv, bt709, progressive)</c>), que partirían el resto de la
    /// línea en pedazos equivocados.</para>
    /// </summary>
    public static VideoResolution? ParseResolution(string output)
    {
        foreach (string line in output.Split('\n'))
        {
            if (!line.Contains(" Video: ", StringComparison.Ordinal)) continue;

            int i = 0;
            while (i < line.Length)
            {
                if (!char.IsAsciiDigit(line[i])) { i++; continue; }

                int j = i;
                while (j < line.Length && char.IsAsciiDigit(line[j])) j++;

                if (j < line.Length && line[j] == 'x')
                {
                    int k = j + 1;
                    while (k < line.Length && char.IsAsciiDigit(line[k])) k++;

                    if (k > j + 1
                        && int.TryParse(line[i..j], out int width)
                        && int.TryParse(line[(j + 1)..k], out int height)
                        && width > 0 && height > 0)
                    {
                        return new VideoResolution(width, height);
                    }
                }

                i = j;
            }
        }

        return null;
    }

    /// <summary>
    /// El <b>último</b> <c>crop=W:H:X:Y</c> de la salida de <c>cropdetect</c>:
    /// el filtro afina su estimación cuadro a cuadro, ampliándola lo justo para
    /// cubrir todo lo visto hasta ahí, así que el último valor de la muestra es
    /// el más seguro.
    ///
    /// <para>Sin el umbral de "vale la pena", que necesita la resolución de
    /// origen — ese lo aplica <see cref="CropFilterWorthApplying"/>.</para>
    /// </summary>
    public static string? ParseCropFilter(string output)
    {
        (int W, int H, int X, int Y)? crop = ParseCropComponents(output);
        return crop is { } c ? $"crop={c.W}:{c.H}:{c.X}:{c.Y}" : null;
    }

    /// <summary>
    /// El recorte, pero solo si es una franja de verdad.
    ///
    /// <para><c>cropdetect</c> encuentra un recorte minúsculo (2-3%) hasta en
    /// fuentes sin ninguna franja: ruido de compresión o viñeteado en el borde.
    /// Aplicarlo igual recortaría un poco de <b>todos</b> los videos sin
    /// necesidad. Recién cuando el recorte deja menos del 95% del ancho o del
    /// alto se considera una franja horneada que vale la pena quitar.</para>
    ///
    /// <para>Sin resolución de origen se confía en <c>cropdetect</c> igual:
    /// mejor eso que no aplicar nada.</para>
    /// </summary>
    public static string? CropFilterWorthApplying(string output)
    {
        if (ParseCropComponents(output) is not { } crop) return null;

        string filter = $"crop={crop.W}:{crop.H}:{crop.X}:{crop.Y}";

        if (ParseResolution(output) is not { } source) return filter;

        double widthRatio = (double)crop.W / source.Width;
        double heightRatio = (double)crop.H / source.Height;

        return widthRatio < 0.95 || heightRatio < 0.95 ? filter : null;
    }

    private static (int W, int H, int X, int Y)? ParseCropComponents(string output)
    {
        string? last = null;

        foreach (string line in output.Split('\n'))
        {
            int index = line.IndexOf("crop=", StringComparison.Ordinal);
            if (index >= 0) last = line[index..];
        }

        if (last is null) return null;

        string[] parts = last["crop=".Length..].Split(':');
        if (parts.Length != 4) return null;

        if (!int.TryParse(parts[0], out int w) || !int.TryParse(parts[1], out int h)
            || !int.TryParse(parts[2], out int x) || !int.TryParse(parts[3], out int y))
        {
            return null;
        }

        // Un ancho o alto en cero o negativo es una fuente rara: mejor no
        // recortar nada que arriesgar un filtro inválido que haga fallar todo.
        return w > 0 && h > 0 ? (w, h, x, y) : null;
    }

    /// <summary>
    /// El avance de <c>-progress pipe:1</c>, que emite bloques
    /// <c>clave=valor</c>. Se queda con el último <c>out_time_ms</c> leído.
    /// </summary>
    public static double? ParseOutTimeMicroseconds(string progressOutput)
    {
        const string key = "out_time_ms=";
        double? last = null;

        foreach (string line in progressOutput.Split('\n'))
        {
            if (!line.StartsWith(key, StringComparison.Ordinal)) continue;

            if (double.TryParse(line[key.Length..].Trim(), NumberStyles.Float,
                    CultureInfo.InvariantCulture, out double value))
            {
                last = value;
            }
        }

        return last;
    }

    private static double? ParseTimecode(string value)
    {
        string[] parts = value.Split(':');
        if (parts.Length != 3) return null;

        if (!double.TryParse(parts[0], NumberStyles.Float, CultureInfo.InvariantCulture, out double hours)
            || !double.TryParse(parts[1], NumberStyles.Float, CultureInfo.InvariantCulture, out double minutes)
            || !double.TryParse(parts[2], NumberStyles.Float, CultureInfo.InvariantCulture, out double seconds))
        {
            return null;
        }

        return hours * 3600 + minutes * 60 + seconds;
    }
}
