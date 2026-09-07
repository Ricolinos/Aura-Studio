using System.Security.Cryptography;
using AuraStudio.Core.Media;
using Windows.Media.MediaProperties;
using Windows.Media.Transcoding;
using Windows.Storage;

namespace AuraStudio.Tools.CopyModeCheck;

/// <summary>
/// Decodifica audio a PCM para poder comparar <b>lo que suena</b>, no lo que
/// pesa (ST-244, encargo recibido de ST-222).
///
/// <para><b>Por qué hace falta.</b> Escribir etiquetas en un M4A obliga a mover
/// el <c>moov</c> y a corregir los offsets de <c>stco</c>/<c>co64</c>. Un offset
/// mal corregido produce un archivo que <b>abre sin error, se lee sin error y
/// suena mal</b>: ninguna prueba que mire etiquetas o tamaños lo detecta. La
/// única forma de saberlo es decodificar antes y después y comparar las
/// muestras.</para>
///
/// <para>Se decodifica con Media Foundation —el mismo decodificador que usaría
/// cualquier reproductor de Windows— y se compara el resumen de las muestras. Si
/// TagLib# corrige bien los offsets, los dos resúmenes son idénticos; si no, no
/// lo son, y eso es exactamente lo que hay que saber.</para>
/// </summary>
internal static class Decoded
{
    /// <summary>Convierte a M4A/AAC. Sirve para fabricar un M4A con audio de verdad.</summary>
    public static Task ToM4aAsync(string source, string destination) =>
        TranscodeAsync(source, destination, MediaEncodingProfile.CreateM4a(AudioEncodingQuality.High));

    /// <summary>
    /// Convierte a FLAC. Sirve para fabricar un FLAC con audio de verdad: el
    /// FLAC mínimo del fixture es solo su <c>STREAMINFO</c> y no tiene muestras,
    /// así que con él la fila "FLAC con Comprimido" no probaría nada.
    /// </summary>
    public static Task ToFlacAsync(string source, string destination) =>
        TranscodeAsync(source, destination, MediaEncodingProfile.CreateFlac(AudioEncodingQuality.High));

    /// <summary>
    /// El resumen SHA-256 de las muestras decodificadas, y cuántos bytes son.
    /// Se decodifica a WAV PCM en la carpeta temporal —nunca al lado de la
    /// música, regla de ST-242— y se resume solo el bloque <c>data</c>: la
    /// cabecera lleva tamaños que cambian con cualquier cosa.
    /// </summary>
    public static async Task<(string Hash, long Bytes)> PcmSummaryAsync(string audioPath)
    {
        ReadOnlyMemory<byte> samples = await PcmOfAsync(audioPath);

        return (Convert.ToHexString(SHA256.HashData(samples.Span))[..16], samples.Length);
    }

    /// <summary>
    /// Las muestras decodificadas, en un formato <b>fijo</b>: 44,1 kHz, estéreo,
    /// 16 bits.
    ///
    /// <para>Se fija a propósito. <c>CreateWav(AudioEncodingQuality.High)</c>
    /// impone su propio perfil —remuestrea a 48 kHz— y entonces la comparación
    /// no mide si el audio cambió, mide cómo remuestrea Windows. Con el formato
    /// fijo, dos archivos que suenan igual dan los mismos bytes.</para>
    ///
    /// <para>Un AIFF pasa antes por <see cref="AiffToWav"/>: Media Foundation no
    /// tiene fuente nativa para AIFF, que es justamente por lo que ese lector
    /// existe.</para>
    /// </summary>
    public static async Task<ReadOnlyMemory<byte>> PcmOfAsync(string audioPath)
    {
        string work = Path.Combine(Path.GetTempPath(), "Aura");
        string decodable = audioPath;
        string? intermediate = null;
        string wav = Path.Combine(work, $"{Guid.NewGuid():N}.wav");

        try
        {
            if (Path.GetExtension(audioPath).TrimStart('.').ToLowerInvariant() is "aif" or "aiff" or "aifc")
            {
                intermediate = Path.Combine(work, $"{Guid.NewGuid():N}.wav");
                Directory.CreateDirectory(work);

                using (FileStream aiff = File.OpenRead(audioPath))
                using (FileStream converted = File.Create(intermediate))
                {
                    AiffToWav.Convert(aiff, converted);
                }

                decodable = intermediate;
            }

            MediaEncodingProfile profile = MediaEncodingProfile.CreateWav(AudioEncodingQuality.High);
            profile.Audio = AudioEncodingProperties.CreatePcm(44100, 2, 16);

            await TranscodeAsync(decodable, wav, profile);

            return DataChunkOf(await File.ReadAllBytesAsync(wav));
        }
        finally
        {
            foreach (string temporary in new[] { wav, intermediate })
            {
                try { if (temporary is not null && File.Exists(temporary)) File.Delete(temporary); }
                catch { /* higiene */ }
            }
        }
    }

    /// <summary>
    /// Compara las muestras de dos archivos.
    ///
    /// <para>Se compara el <b>tramo común</b> y se informan los dos largos por
    /// separado, en vez de exigir que midan igual. Un codificador puede dejar
    /// unas milésimas de relleno al final —el bloque no cierra justo— y eso no
    /// es pérdida de audio: pérdida sería que las muestras que sí están fueran
    /// otras. Decir "no coincide" por el relleno taparía el caso que de verdad
    /// importa.</para>
    /// </summary>
    public static async Task<(bool SameSamples, long Left, long Right, long CommonBytes)> ComparePcmAsync(
        string leftPath, string rightPath)
    {
        ReadOnlyMemory<byte> left = await PcmOfAsync(leftPath);
        ReadOnlyMemory<byte> right = await PcmOfAsync(rightPath);

        int common = (int)Math.Min(left.Length, right.Length);
        bool same = left.Span[..common].SequenceEqual(right.Span[..common]);

        return (same, left.Length, right.Length, common);
    }

    /// <summary>
    /// Busca con qué desplazamiento coinciden dos tandas de muestras.
    ///
    /// <para>Un codificador puede meter unos cuadros de <b>preámbulo</b> al
    /// principio; al decodificar salen antes que el audio de verdad y corren
    /// todo lo demás. Comparando desde el byte cero, dos archivos idénticos
    /// darían "distintos" — y la conclusión sería falsa. Acá se prueba a
    /// alinear: si con un desplazamiento de N cuadros las muestras coinciden
    /// exactamente, la conversión <b>sí</b> fue sin pérdida y N es el preámbulo.
    /// Si no coinciden con ningún desplazamiento, se perdió audio de verdad.</para>
    /// </summary>
    /// <returns>El desplazamiento en cuadros, o <c>null</c> si no alinean con ninguno.</returns>
    public static async Task<int?> FindSampleAlignmentAsync(
        string referencePath, string candidatePath, int maxFrames = 4096, int frameBytes = 4)
    {
        ReadOnlyMemory<byte> reference = await PcmOfAsync(referencePath);
        ReadOnlyMemory<byte> candidate = await PcmOfAsync(candidatePath);

        // Se compara un tramo del medio: el principio y el final son justo donde
        // vive el relleno, y coincidir ahí no diría nada.
        int window = Math.Min(1 << 16, reference.Length / 4);
        int from = reference.Length / 3 / frameBytes * frameBytes;

        ReadOnlySpan<byte> needle = reference.Span.Slice(from, window);

        for (int frames = 0; frames <= maxFrames; frames++)
        {
            int offset = from + frames * frameBytes;
            if (offset + window > candidate.Length) break;

            if (candidate.Span.Slice(offset, window).SequenceEqual(needle)) return frames;
        }

        return null;
    }

    /// <summary>
    /// Reescribe un MP4 con el <c>moov</c> <b>antes</b> del <c>mdat</c>,
    /// corrigiendo los offsets de <c>stco</c>.
    ///
    /// <para>Es <b>fixture, no código de producción</b>: `MediaTranscoder`
    /// escribe el <c>moov</c> al final, que es el caso fácil —crecerlo no mueve
    /// ninguna muestra—. El caso delicado, el que la Maestra pidió probar, es el
    /// contrario: con el <c>moov</c> adelante, escribir etiquetas lo agranda y
    /// <b>todas</b> las muestras se corren, así que cada offset hay que
    /// corregirlo. Sin un archivo así, la prueba no prueba nada.</para>
    ///
    /// <para>Que este remuxer esté bien se comprueba solo: el archivo resultante
    /// tiene que decodificar a las mismas muestras que el original <i>antes</i>
    /// de escribirle nada.</para>
    /// </summary>
    public static void RewriteWithMoovFirst(string sourcePath, string destinationPath)
    {
        byte[] file = File.ReadAllBytes(sourcePath);

        var boxes = new List<(string Type, int Start, int Length)>();
        int position = 0;

        while (position + 8 <= file.Length)
        {
            int size = (file[position] << 24) | (file[position + 1] << 16)
                       | (file[position + 2] << 8) | file[position + 3];

            if (size <= 0 || position + size > file.Length) break;

            boxes.Add((System.Text.Encoding.ASCII.GetString(file, position + 4, 4), position, size));
            position += size;
        }

        (string Type, int Start, int Length) moov = boxes.Single(box => box.Type == "moov");
        (string Type, int Start, int Length) mdat = boxes.Single(box => box.Type == "mdat");

        if (moov.Start < mdat.Start)
        {
            File.Copy(sourcePath, destinationPath, overwrite: true);
            return;
        }

        // El moov se adelanta: todo lo que estaba entre el final del encabezado
        // y el moov se corre hacia adelante por el tamaño del moov.
        var rewritten = new List<byte>(file.Length);

        foreach ((string type, int start, int length) in boxes)
        {
            if (type == "moov") continue;
            if (type == "mdat") rewritten.AddRange(file.AsSpan(moov.Start, moov.Length).ToArray());

            rewritten.AddRange(file.AsSpan(start, length).ToArray());
        }

        byte[] result = [.. rewritten];

        // Y los offsets: el mdat se movió `moov.Length` bytes hacia adelante.
        ShiftChunkOffsets(result, moov.Length);

        File.WriteAllBytes(destinationPath, result);
    }

    /// <summary>
    /// Le suma <paramref name="delta"/> a cada entrada de cada <c>stco</c>.
    /// Busca la caja por su firma en todo el archivo: alcanza para un fixture, y
    /// no se usa en producción.
    /// </summary>
    private static void ShiftChunkOffsets(byte[] file, int delta)
    {
        for (int i = 0; i + 8 < file.Length; i++)
        {
            if (file[i] != 's' || file[i + 1] != 't' || file[i + 2] != 'c' || file[i + 3] != 'o') continue;

            int entries = (file[i + 8] << 24) | (file[i + 9] << 16) | (file[i + 10] << 8) | file[i + 11];
            int entry = i + 12;

            for (int n = 0; n < entries && entry + 4 <= file.Length; n++, entry += 4)
            {
                uint offset = ((uint)file[entry] << 24) | ((uint)file[entry + 1] << 16)
                              | ((uint)file[entry + 2] << 8) | file[entry + 3];

                offset += (uint)delta;

                file[entry] = (byte)(offset >> 24);
                file[entry + 1] = (byte)(offset >> 16);
                file[entry + 2] = (byte)(offset >> 8);
                file[entry + 3] = (byte)offset;
            }
        }
    }

    /// <summary>
    /// El orden de las cajas de primer nivel de un MP4. Importa porque corregir
    /// los offsets solo es delicado cuando el <c>moov</c> va <b>antes</b> del
    /// <c>mdat</c>: ahí crecer el <c>moov</c> mueve todas las muestras.
    /// </summary>
    public static string TopLevelBoxOrder(string mp4Path)
    {
        using FileStream file = File.OpenRead(mp4Path);
        var boxes = new List<string>();
        long position = 0;

        Span<byte> header = stackalloc byte[8];

        while (position + 8 <= file.Length && boxes.Count < 32)
        {
            file.Position = position;
            file.ReadExactly(header);

            long size = ((long)header[0] << 24) | ((long)header[1] << 16)
                        | ((long)header[2] << 8) | header[3];

            string type = System.Text.Encoding.ASCII.GetString(header[4..]);
            boxes.Add(type);

            if (size <= 0) break;
            position += size;
        }

        return string.Join(" ", boxes);
    }

    private static async Task TranscodeAsync(string source, string destination, MediaEncodingProfile profile)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
        await File.WriteAllBytesAsync(destination, []);

        StorageFile input = await StorageFile.GetFileFromPathAsync(source);
        StorageFile output = await StorageFile.GetFileFromPathAsync(destination);

        var transcoder = new MediaTranscoder { HardwareAccelerationEnabled = false };
        PrepareTranscodeResult prepared = await transcoder.PrepareFileTranscodeAsync(input, output, profile);

        if (!prepared.CanTranscode)
            throw new InvalidOperationException($"Windows no puede decodificar «{source}»: {prepared.FailureReason}");

        await prepared.TranscodeAsync();
    }

    /// <summary>El bloque <c>data</c> de un WAV, recorriendo los bloques en vez de suponer 44 bytes.</summary>
    private static ReadOnlyMemory<byte> DataChunkOf(byte[] wav)
    {
        int position = 12;   // "RIFF" + tamaño + "WAVE"

        while (position + 8 <= wav.Length)
        {
            string id = System.Text.Encoding.ASCII.GetString(wav, position, 4);
            int size = BitConverter.ToInt32(wav, position + 4);

            if (id == "data") return wav.AsMemory(position + 8, Math.Min(size, wav.Length - position - 8));

            position += 8 + size + (size % 2);
        }

        return wav.AsMemory(Math.Min(44, wav.Length));
    }
}
