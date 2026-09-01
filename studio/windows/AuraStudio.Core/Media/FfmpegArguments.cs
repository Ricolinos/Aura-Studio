using System.Globalization;

namespace AuraStudio.Core.Media;

/// <summary>
/// Los argumentos con los que se invoca a ffmpeg. Port de la parte pura de
/// <c>FFmpegTranscoder.swift</c>.
///
/// <para><b>Esto es contrato con el aparato, no preferencia.</b> El iPod
/// Classic reproduce video por el plugin <c>mpegplayer</c> de Rockbox: MPEG-1/2
/// dentro de 320x240, audio MPEG Layer II. Cambiar cualquiera de estos valores
/// sin probarlo en el aparato produce archivos que se copian bien y no se
/// reproducen.</para>
///
/// <para>Va en Core y sin tocar procesos a propósito: así lo que se le manda a
/// ffmpeg se puede revisar en una prueba, sin ffmpeg instalado y sin un video
/// de verdad.</para>
/// </summary>
public static class FfmpegArguments
{
    public const int VideoWidth = 320;
    public const int VideoHeight = 240;

    /// <summary>Moderado para no ahogar la lectura de disco del iPod.</summary>
    public const int DefaultVideoBitrateKbps = 768;

    /// <summary>
    /// Tope de cuadros por segundo que el S5L8702 decodifica sin ahogarse. Un
    /// video de teléfono a 60 fps se ve a tirones; uno a 10 no se toca, porque
    /// forzarlo a 24 duplicaría cuadros y agrandaría el archivo sin ganar nada.
    /// </summary>
    public const double MaxFrameRate = 24;

    /// <summary>
    /// Escala para <b>caber dentro</b> de 320x240 conservando la relación de
    /// aspecto real: ni recorta ni deforma, y <b>no rellena con barras
    /// negras</b>.
    ///
    /// <para>Las barras horneadas eran lo que hacía antes, y volvían inútil la
    /// lógica de centrado del firmware: con todo saliendo a 320x240 exactos, no
    /// había forma de distinguir "video angosto" de "video con barras". Ahora el
    /// <c>.mpg</c> conserva su ancho o alto real y es el firmware el que decide
    /// al reproducir si deja franjas o recorta para llenar la pantalla.</para>
    ///
    /// <para><c>force_divisible_by=2</c> asegura dimensiones pares, que es lo
    /// que exige el submuestreo de crominancia 4:2:0 de MPEG-2.</para>
    /// </summary>
    public const string ScaleFilter =
        "scale=320:240:force_original_aspect_ratio=decrease:force_divisible_by=2";

    /// <param name="cropFilter">
    /// Un <c>crop=W:H:X:Y</c> ya detectado, que se antepone al escalado. Algunos
    /// rips traen franjas negras <b>horneadas como píxeles</b> dentro de un
    /// contenedor 4:3: <c>scale</c> no las ve —solo mira la metadata del
    /// stream— y sin quitarlas el firmware tampoco puede distinguirlas de un
    /// video angosto de verdad.
    /// </param>
    public static IReadOnlyList<string> ForVideo(
        string inputPath, string outputPath,
        int videoBitrateKbps = DefaultVideoBitrateKbps,
        double? sourceFrameRate = null,
        string? cropFilter = null)
    {
        string filter = cropFilter is { Length: > 0 } crop ? $"{crop},{ScaleFilter}" : ScaleFilter;

        List<string> arguments =
        [
            "-y", "-loglevel", "error",
            "-i", inputPath,
            "-vf", filter,
            "-c:v", "mpeg2video", "-b:v", $"{videoBitrateKbps}k"
        ];

        // Un keyframe cada ~0.6 s: sin GPU para decodificar cuadros P/B rápido,
        // un GOP largo se ve "sucio" durante el primer segundo tras un salto.
        if (sourceFrameRate is { } rate && rate > MaxFrameRate)
            arguments.AddRange(["-r", "24", "-g", "15"]);

        // 44100: libmad, el decodificador de mpegplayer, solo entiende las
        // frecuencias estándar de MPEG audio — los 48 kHz que trae casi todo
        // video de teléfono quedarían sin sonido.
        arguments.AddRange(["-c:a", "mp2", "-b:a", "128k", "-ar", "44100", "-f", "mpeg", outputPath]);

        return arguments;
    }

    /// <summary>
    /// El póster de un video: un solo cuadro, tomado donde ya empezó el
    /// contenido.
    /// </summary>
    public static IReadOnlyList<string> ForPoster(string inputPath, string outputPath, double seekSeconds) =>
    [
        "-y", "-loglevel", "error",
        "-ss", seekSeconds.ToString("0.00", CultureInfo.InvariantCulture),
        "-i", inputPath,
        "-frames:v", "1",
        "-pix_fmt", "yuvj420p",
        outputPath
    ];

    /// <summary>
    /// Solo abrir el archivo. ffmpeg termina con error ("At least one output
    /// file must be specified") pero <b>ya imprimió la cabecera</b> con la
    /// duración, la resolución y los cuadros por segundo: alcanza para no tener
    /// que pedir también <c>ffprobe</c>.
    /// </summary>
    public static IReadOnlyList<string> ForProbe(string inputPath) => ["-i", inputPath];

    /// <summary>
    /// Busca franjas horneadas sobre una muestra de 100 cuadros, arrancando al
    /// 20% de la duración: así se saltan las intros y los logos, que suelen ser
    /// negros de verdad y no franja. Sin audio, que no hace falta decodificar.
    /// </summary>
    public static IReadOnlyList<string> ForCropDetect(string inputPath, double? durationSeconds)
    {
        double duration = durationSeconds ?? 0;
        double seek = Math.Clamp(duration * 0.2, 0, Math.Max(duration - 1, 0));

        return
        [
            "-ss", seek.ToString("0.00", CultureInfo.InvariantCulture),
            "-i", inputPath,
            "-an",
            "-vf", "cropdetect=24:2:0",
            "-frames:v", "100",
            "-f", "null", "-"
        ];
    }

    /// <summary>
    /// Audio a MP3 de 256 kbps CBR: buena calidad y, sobre todo, <b>tamaño
    /// predecible</b> — con VBR no hay forma de decirle al usuario de antemano
    /// cuánto va a ocupar su biblioteca.
    /// </summary>
    public static IReadOnlyList<string> ForAudio(string inputPath, string outputPath) =>
    [
        "-y", "-loglevel", "error",
        "-i", inputPath,
        "-map", "0:a:0", "-vn",
        "-c:a", "libmp3lame", "-b:a", "256k",
        outputPath
    ];
}
