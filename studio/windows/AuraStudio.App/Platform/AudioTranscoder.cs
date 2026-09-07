using AuraStudio.Core.Media;
using Windows.Media.MediaProperties;
using Windows.Media.Transcoding;
using Windows.Storage;

namespace AuraStudio.App.Platform;

/// <summary>Un audio que no se pudo convertir, con el motivo dicho.</summary>
public sealed class AudioTranscodeException(string message) : Exception(message);

/// <summary>Qué salió de convertir un audio (ST-243).</summary>
/// <param name="Path">El MP3 que quedó.</param>
/// <param name="BytesWritten">Cuánto pesa.</param>
/// <param name="Elapsed">Cuánto tardó, para poder reportarlo.</param>
public readonly record struct AudioTranscodeResult(string Path, long BytesWritten, TimeSpan Elapsed);

/// <summary>
/// Convierte WAV y AIFF a MP3 con el codificador que <b>ya trae Windows</b>
/// (ST-243).
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

    /// <summary>Lo que hay que convertir, y lo que no.</summary>
    public static readonly IReadOnlySet<string> ConvertibleExtensions =
        new HashSet<string>(["wav", "wave", "aif", "aiff", "aifc"], StringComparer.OrdinalIgnoreCase);

    public static bool NeedsConversion(string? path)
    {
        if (path is not { Length: > 0 }) return false;

        return ConvertibleExtensions.Contains(Path.GetExtension(path).TrimStart('.'));
    }

    /// <summary>
    /// Convierte <paramref name="sourcePath"/> a un MP3 en
    /// <paramref name="destinationPath"/>.
    /// </summary>
    /// <exception cref="AudioTranscodeException">
    /// El archivo no se pudo leer, el formato no se pudo convertir, o el
    /// codificador falló. Nunca deja el destino a medias.
    /// </exception>
    public static async Task<AudioTranscodeResult> ToMp3Async(
        string sourcePath, string destinationPath, CancellationToken ct = default)
    {
        long started = Environment.TickCount64;

        Directory.CreateDirectory(Path.GetDirectoryName(destinationPath)!);

        // El temporal NUNCA se llama como música (ST-242): un `.aura-tmp` tirado
        // al lado de la biblioteca es basura evidente que nadie va a importar;
        // un `.mp3` tirado es una canción duplicada.
        string temporary = destinationPath + ".aura-tmp";

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
                intermediate = Path.Combine(
                    Path.GetTempPath(), "Aura", $"{Guid.NewGuid():N}.wav");

                await Task.Run(() => ConvertAiff(sourcePath, intermediate), ct).ConfigureAwait(false);
                decodable = intermediate;
            }

            await RunTranscodeAsync(decodable, temporary, ct).ConfigureAwait(false);

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
            throw new AudioTranscodeException($"no se pudo convertir a MP3: {ex.Message}");
        }
        finally
        {
            TryDelete(temporary);
            if (intermediate is not null) TryDelete(intermediate);
        }
    }

    private static void ConvertAiff(string aiffPath, string wavPath)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(wavPath)!);

        using FileStream aiff = File.OpenRead(aiffPath);
        using FileStream wav = File.Create(wavPath);

        AiffToWav.Convert(aiff, wav);
    }

    private static async Task RunTranscodeAsync(string sourcePath, string destinationPath, CancellationToken ct)
    {
        StorageFile source = await StorageFile.GetFileFromPathAsync(sourcePath);

        // El destino se crea vacío acá para poder pedirlo como StorageFile: la
        // API trabaja sobre archivos, no sobre rutas.
        File.WriteAllBytes(destinationPath, []);
        StorageFile destination = await StorageFile.GetFileFromPathAsync(destinationPath);

        MediaEncodingProfile profile = MediaEncodingProfile.CreateMp3(AudioEncodingQuality.High);
        profile.Audio.Bitrate = TargetBitsPerSecond;

        var transcoder = new MediaTranscoder { HardwareAccelerationEnabled = false };

        PrepareTranscodeResult prepared =
            await transcoder.PrepareFileTranscodeAsync(source, destination, profile);

        if (!prepared.CanTranscode)
        {
            throw new AudioTranscodeException(
                $"Windows no puede convertir este archivo ({prepared.FailureReason}).");
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
