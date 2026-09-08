using AuraStudio.Core.Library;
using AuraStudio.Core.Media;
using Windows.Media.MediaProperties;
using Windows.Media.Transcoding;
using Windows.Storage;

using AuraStudio.Core.Resources;

namespace AuraStudio.App.Platform;

/// <summary>Un audio que no se pudo convertir, con el motivo dicho.</summary>
public sealed class AudioTranscodeException(string message) : Exception(message);

/// <summary>Qué salió de convertir un audio (ST-243).</summary>
/// <param name="Path">El MP3 que quedó.</param>
/// <param name="BytesWritten">Cuánto pesa.</param>
/// <param name="Elapsed">Cuánto tardó, para poder reportarlo.</param>
public readonly record struct AudioTranscodeResult(string Path, long BytesWritten, TimeSpan Elapsed);

/// <summary>
/// Convierte audio con el codificador que <b>ya trae Windows</b> (ST-243,
/// ampliado a ALAC en ST-244).
///
/// <para><b>Qué se convierte y a qué</b> lo decide
/// <see cref="AudioConversionRules"/>, en un solo lugar para los dos modos. Acá
/// está el <i>cómo</i>: MP3 de 256 kbps para "Comprimido", ALAC —sin pérdida,
/// contenedor <c>.m4a</c>— para "Original sin pérdida". macOS no trae
/// codificador MP3 y Windows sí trae ALAC, así que ALAC es el formato que las
/// dos plataformas pueden escribir de forma nativa: elegir otro partiría en dos
/// la biblioteca compartida.</para>
///
/// <para><b>Por qué no ffmpeg.</b> El iPod no reproduce WAV ni AIFF de forma
/// útil —son enormes y el disco duro no da abasto—, así que en modo copia hay
/// que convertirlos. Hacerlo con ffmpeg significaría meter el binario en el
/// instalador, con su peso y sus licencias, para algo que Media Foundation
/// resuelve de fábrica en Windows 10 y 11. Es la misma decisión que la Mac, que
/// usa AVFoundation. ffmpeg sigue siendo solo para video.</para>
///
/// <para><b>AIFF pasa antes por un WAV.</b> Media Foundation decodifica WAV
/// directo y no tiene fuente nativa para AIFF; <see cref="AiffToWav"/> lo
/// convierte —que es dar vuelta los bytes de cada muestra, no recodificar
/// nada— y de ahí sigue el mismo camino.</para>
///
/// <para><b>Escritura atómica</b>, como <c>LocalTagWriter</c>: se convierte a un
/// temporal y recién al terminar se renombra al destino. Una conversión cortada
/// a la mitad no puede quedar como una canción a medias que el catálogo dé por
/// buena.</para>
/// </summary>
public static class AudioTranscoder
{
    /// <summary>
    /// 256 kbps, lo que pidió la Maestra. Es el escalón donde la diferencia con
    /// el original deja de oírse en unos audífonos normales, y a la vez una
    /// décima parte de lo que pesa el WAV.
    ///
    /// <para><c>CreateMp3</c> pide la frecuencia y los canales; el bitrate se
    /// fija después sobre el perfil. Si el codificador no puede dar CBR exacto,
    /// entrega ese valor como promedio — que para lo que hace falta es lo
    /// mismo.</para>
    /// </summary>
    public const uint TargetBitsPerSecond = 256_000;

    /// <summary>Donde viven los WAV intermedios. Fuera de la biblioteca, a propósito.</summary>
    public static string WorkDirectory => Path.Combine(Path.GetTempPath(), "Aura");

    /// <summary>
    /// Borra lo que haya quedado de corridas anteriores (ST-244).
    ///
    /// <para>Cada conversión borra su intermedio en su <c>finally</c>, pero un
    /// corte de luz o un cierre forzado no ejecutan ningún <c>finally</c>: sin
    /// esto, la carpeta temporal va acumulando un WAV de cien megabytes por cada
    /// vez que la app se cerró mal. Se limpia al empezar y no al terminar,
    /// porque terminar es justamente lo que a veces no pasa.</para>
    ///
    /// <para>Solo borra lo que es nuestro y solo si nadie lo tiene abierto: un
    /// archivo en uso es de una conversión que está corriendo ahora.</para>
    /// </summary>
    public static void CleanLeftovers()
    {
        try
        {
            if (!Directory.Exists(WorkDirectory)) return;

            foreach (string leftover in Directory.EnumerateFiles(WorkDirectory, "*.wav"))
                TryDelete(leftover);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Limpiar es higiene, no una precondición: si no se puede, se sigue.
        }
    }

    /// <summary>
    /// Convierte <paramref name="sourcePath"/> a MP3. Atajo de
    /// <see cref="ConvertAsync"/> para quien ya sabe que quiere MP3.
    /// </summary>
    public static Task<AudioTranscodeResult> ToMp3Async(
        string sourcePath, string destinationPath, CancellationToken ct = default) =>
        ConvertAsync(sourcePath, destinationPath, AudioCodec.Mp3, ct);

    /// <summary>
    /// La forma que espera <c>PreparedMusicBuilder</c> (ST-244): convierte y
    /// devuelve los bytes escritos.
    ///
    /// <para>Vive acá y no en cada llamador porque son dos —la importación y la
    /// edición— y el codificador es de la plataforma mientras que el preparador
    /// es de Core.</para>
    /// </summary>
    public static async Task<long> ForPreparedAsync(
        string sourcePath, string destinationPath, AudioCodec codec, CancellationToken ct)
    {
        AudioTranscodeResult result =
            await ConvertAsync(sourcePath, destinationPath, codec, ct).ConfigureAwait(false);

        return result.BytesWritten;
    }

    /// <summary>
    /// Convierte <paramref name="sourcePath"/> al códec pedido (ST-244).
    ///
    /// <para><b>ALAC cuando el usuario pidió "sin pérdida"</b>, y no MP3:
    /// "sin pérdida" tiene que significar sin pérdida, y convertir a MP3 ahí
    /// sería esconder una pérdida debajo de una etiqueta que promete lo
    /// contrario. ALAC lo escriben las dos plataformas de forma nativa —macOS
    /// no trae codificador MP3, Windows sí trae ALAC— y el iPod con Aura lo
    /// reproduce.</para>
    /// </summary>
    /// <exception cref="AudioTranscodeException">
    /// El archivo no se pudo leer, el formato no se pudo convertir, el
    /// codificador falló, o esta versión de Windows no trae el códec pedido.
    /// Nunca deja el destino a medias, y <b>nunca copia el original sin
    /// convertir</b>: eso dejaría un WAV de cien megabytes en el iPod haciéndose
    /// pasar por lo que el usuario pidió.
    /// </exception>
    public static async Task<AudioTranscodeResult> ConvertAsync(
        string sourcePath, string destinationPath, AudioCodec codec, CancellationToken ct = default)
    {
        if (codec == AudioCodec.None)
            throw new AudioTranscodeException("no se pidió ninguna conversión");

        long started = Environment.TickCount64;

        // Lo que dejó un cierre forzado anterior. Se limpia al empezar, porque
        // terminar es justamente lo que a veces no pasa.
        CleanLeftovers();

        Directory.CreateDirectory(Path.GetDirectoryName(destinationPath)!);

        // El temporal NUNCA se llama como música (ST-242): un `.aura-tmp` tirado
        // al lado de la biblioteca es basura evidente que nadie va a importar;
        // un `.mp3` tirado es una canción duplicada.
        string temporary = destinationPath + LibraryFileCopier.TemporarySuffix;

        // El WAV intermedio del AIFF sí lleva su extensión, y por eso vive en la
        // carpeta temporal de la app y no al lado de la música: Media Foundation
        // elige el decodificador por la extensión —el mismo tropiezo que TagLib#
        // en ST-242— y ahí un `.wav` no le estorba a nadie.
        string? intermediate = null;

        try
        {
            string decodable = sourcePath;

            if (IsAiff(sourcePath))
            {
                intermediate = Path.Combine(WorkDirectory, $"{Guid.NewGuid():N}.wav");

                await Task.Run(() => ConvertAiff(sourcePath, intermediate), ct).ConfigureAwait(false);
                decodable = intermediate;
            }

            await RunTranscodeAsync(decodable, temporary, codec, ct).ConfigureAwait(false);

            long bytes = new FileInfo(temporary).Length;
            if (bytes == 0) throw new AudioTranscodeException("la conversión no produjo audio");

            File.Move(temporary, destinationPath, overwrite: true);

            return new AudioTranscodeResult(
                destinationPath, bytes, TimeSpan.FromMilliseconds(Environment.TickCount64 - started));
        }
        catch (AiffFormatException ex)
        {
            throw new AudioTranscodeException(ex.Message);
        }
        catch (Exception ex) when (ex is not (OperationCanceledException or AudioTranscodeException
                                       or OutOfMemoryException))
        {
            throw new AudioTranscodeException($"no se pudo convertir a {NameOf(codec)}: {ex.Message}");
        }
        finally
        {
            TryDelete(temporary);
            if (intermediate is not null) TryDelete(intermediate);
        }
    }

    /// <summary>
    /// El perfil de Media Foundation para cada códec.
    ///
    /// <para><c>CreateAlac</c> existe desde Windows 10 1803. En una versión
    /// anterior <b>se falla con el motivo dicho</b>: copiar el WAV sin convertir
    /// dejaría cien megabytes en el iPod haciéndose pasar por lo que el usuario
    /// pidió, y "sin pérdida" no puede significar "sin convertir".</para>
    /// </summary>
    private static MediaEncodingProfile ProfileFor(AudioCodec codec)
    {
        try
        {
            if (codec == AudioCodec.Alac) return MediaEncodingProfile.CreateAlac(AudioEncodingQuality.High);

            MediaEncodingProfile mp3 = MediaEncodingProfile.CreateMp3(AudioEncodingQuality.High);
            mp3.Audio.Bitrate = TargetBitsPerSecond;

            return mp3;
        }
        catch (Exception ex) when (ex is not OutOfMemoryException)
        {
            throw new AudioTranscodeException(
                Strings.Format("audio-transcoder.no-encoder", NameOf(codec), ex.Message));
        }
    }

    /// <summary>
    /// Le pone al perfil la frecuencia, los canales y los bits del archivo de
    /// entrada, para no remuestrear nada (ST-244).
    ///
    /// <para><b>Ocho bits suben a dieciséis</b>: ALAC no admite 8 bits, y subir
    /// no pierde nada —cada muestra se representa exacta— mientras que bajar sí.
    /// Es la única conversión de formato que se permite bajo "sin pérdida", y es
    /// la que la Maestra fijó.</para>
    ///
    /// <para>Si no se pueden leer las propiedades del origen se sigue con el
    /// perfil por omisión: mejor convertir con el perfil de Windows que no
    /// convertir.</para>
    /// </summary>
    private static async Task MatchSourceFormatAsync(MediaEncodingProfile profile, StorageFile source)
    {
        try
        {
            MediaEncodingProfile input = await MediaEncodingProfile.CreateFromFileAsync(source);
            if (input.Audio is not { } audio) return;

            if (audio.SampleRate > 0) profile.Audio.SampleRate = audio.SampleRate;
            if (audio.ChannelCount > 0) profile.Audio.ChannelCount = audio.ChannelCount;
            if (audio.BitsPerSample > 0) profile.Audio.BitsPerSample = Math.Max(16u, audio.BitsPerSample);
        }
        catch (Exception ex) when (ex is not OutOfMemoryException)
        {
            // Sin propiedades legibles, queda el perfil por omisión.
        }
    }

    private static string NameOf(AudioCodec codec) => codec switch
    {
        AudioCodec.Alac => "ALAC",
        AudioCodec.Mp3 => "MP3",
        _ => "ninguno"
    };

    private static void ConvertAiff(string aiffPath, string wavPath)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(wavPath)!);

        using FileStream aiff = File.OpenRead(aiffPath);
        using FileStream wav = File.Create(wavPath);

        AiffToWav.Convert(aiff, wav);
    }

    private static async Task RunTranscodeAsync(
        string sourcePath, string destinationPath, AudioCodec codec, CancellationToken ct)
    {
        StorageFile source = await StorageFile.GetFileFromPathAsync(sourcePath);

        // El destino se crea vacío acá para poder pedirlo como StorageFile: la
        // API trabaja sobre archivos, no sobre rutas.
        File.WriteAllBytes(destinationPath, []);
        StorageFile destination = await StorageFile.GetFileFromPathAsync(destinationPath);

        MediaEncodingProfile profile = ProfileFor(codec);

        // "Sin pérdida" es sin pérdida también en la frecuencia de muestreo.
        // `CreateAlac(AudioEncodingQuality.High)` trae su propio perfil —48 kHz—
        // y con una canción de 44,1 kHz eso es un remuestreo: el archivo diría
        // "ALAC, sin pérdida" y las muestras ya no serían las del usuario.
        // Medido: sin esto, las muestras decodificadas no coinciden con las de
        // la entrada por ningún desplazamiento.
        if (codec == AudioCodec.Alac) await MatchSourceFormatAsync(profile, source).ConfigureAwait(false);

        var transcoder = new MediaTranscoder { HardwareAccelerationEnabled = false };

        PrepareTranscodeResult prepared =
            await transcoder.PrepareFileTranscodeAsync(source, destination, profile);

        if (!prepared.CanTranscode)
        {
            // El motivo que da Windows suele ser "Unknown", que no le dice nada
            // a nadie. Se acompaña con lo que de verdad pasa casi siempre —el
            // archivo está dañado o no es del formato que dice su extensión—,
            // dicho como lo probable y no como algo comprobado (ST-246).
            throw new AudioTranscodeException(
                Strings.Format("audio-transcoder.cannot-read",
                    Path.GetFileName(sourcePath), prepared.FailureReason));
        }

        await prepared.TranscodeAsync().AsTask(ct).ConfigureAwait(false);
    }

    private static bool IsAiff(string path) =>
        Path.GetExtension(path).TrimStart('.').ToLowerInvariant() is "aif" or "aiff" or "aifc";

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path)) File.Delete(path);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Lo que importa es que el original está bien.
        }
    }
}
