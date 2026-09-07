namespace AuraStudio.Core.Media;

/// <summary>Lo que se leyó de un AIFF (ST-243).</summary>
/// <param name="Channels">1 mono, 2 estéreo.</param>
/// <param name="SampleRate">Muestras por segundo.</param>
/// <param name="BitsPerSample">8, 16, 24 o 32.</param>
/// <param name="Frames">Cuántas muestras por canal.</param>
/// <param name="SamplesAreLittleEndian">
/// Las muestras ya vienen en el orden de WAV y no hay que darlas vuelta. Pasa
/// con el AIFF-C <c>sowt</c>, que es lo que escribe QuickTime: es PCM sin
/// comprimir, pero little-endian. Darlo vuelta "para convertirlo" produciría
/// ruido — la clase de defecto que se oye y no se ve.
/// </param>
public readonly record struct AiffFormat(
    int Channels, int SampleRate, int BitsPerSample, uint Frames, bool SamplesAreLittleEndian = false)
{
    public int BytesPerSample => (BitsPerSample + 7) / 8;

    public long DataBytes => (long)Frames * Channels * BytesPerSample;
}

/// <summary>Un AIFF que no se pudo leer, con el motivo dicho.</summary>
public sealed class AiffFormatException(string message) : Exception(message);

/// <summary>
/// Convierte un AIFF a WAV (ST-243).
///
/// <para><b>Por qué existe.</b> El modo copia convierte WAV y AIFF a MP3 al
/// importarlos, con el codificador que trae Windows. Media Foundation
/// <b>decodifica WAV directo</b> y <b>no tiene fuente nativa para AIFF</b>: sin
/// esto, la mitad de la promesa no se puede cumplir. Y AIFF es un formato
/// trivial —una cabecera con el formato y un bloque con las muestras—, así que
/// leerlo acá cuesta menos que agregarle una dependencia a la app.</para>
///
/// <para><b>La única diferencia real con WAV es el orden de los bytes.</b> AIFF
/// guarda todo en big-endian (los enteros de las cabeceras y las muestras PCM);
/// WAV, en little-endian. Convertir es leer el formato, dar vuelta las muestras
/// de a dos, tres o cuatro bytes, y escribir las cabeceras de WAV. <b>No se
/// remuestrea ni se recodifica nada</b>: las muestras son las mismas, con los
/// bytes en el otro orden.</para>
///
/// <para><b>AIFF-C comprimido no se acepta.</b> Un <c>AIFC</c> cuya compresión
/// no sea "ninguna" trae los datos ya codificados —IMA4, µ-law, incluso MP3— y
/// darlos vuelta como si fueran PCM produciría ruido. Se dice que no; no se
/// entrega ruido.</para>
/// </summary>
public static class AiffToWav
{
    /// <summary>
    /// El formato de un AIFF, sin convertir nada. Sirve para decidir antes de
    /// gastar el disco.
    /// </summary>
    public static AiffFormat ReadFormat(Stream aiff) => Parse(aiff).Format;

    /// <summary>
    /// Escribe en <paramref name="wav"/> el mismo audio en WAV PCM y devuelve su
    /// formato.
    /// </summary>
    /// <exception cref="AiffFormatException">
    /// El archivo no es un AIFF, está truncado, o es AIFF-C comprimido.
    /// </exception>
    public static AiffFormat Convert(Stream aiff, Stream wav)
    {
        (AiffFormat format, long soundDataOffset) = Parse(aiff);

        aiff.Position = soundDataOffset;
        WriteWavHeader(wav, format);
        CopySwapped(aiff, wav, format);

        return format;
    }

    // MARK: - Leer el AIFF

    private static (AiffFormat Format, long SoundDataOffset) Parse(Stream aiff)
    {
        aiff.Position = 0;

        if (ReadTag(aiff) != "FORM") throw new AiffFormatException("no es un AIFF: falta la marca FORM");

        ReadBigEndian32(aiff);                                  // tamaño del FORM: no hace falta

        string kind = ReadTag(aiff);
        if (kind is not ("AIFF" or "AIFC"))
            throw new AiffFormatException($"no es un AIFF: el contenido dice \"{kind}\"");

        AiffFormat? format = null;
        long soundDataOffset = -1;

        while (aiff.Position + 8 <= aiff.Length)
        {
            string chunk = ReadTag(aiff);
            uint size = ReadBigEndian32(aiff);
            long next = aiff.Position + size;

            // Los bloques van alineados a par: un tamaño impar lleva un byte de
            // relleno que no cuenta.
            if (size % 2 != 0) next++;

            switch (chunk)
            {
                case "COMM":
                    format = ReadCommon(aiff, kind == "AIFC");
                    break;

                case "SSND":
                    // Los dos enteros del SSND son desplazamiento y tamaño de
                    // bloque, casi siempre cero. Las muestras empiezan después.
                    uint offset = ReadBigEndian32(aiff);
                    ReadBigEndian32(aiff);
                    soundDataOffset = aiff.Position + offset;
                    break;
            }

            if (next <= aiff.Position && chunk is not ("COMM" or "SSND")) break;
            aiff.Position = next;
        }

        if (format is not { } common) throw new AiffFormatException("el AIFF no trae su bloque COMM");
        if (soundDataOffset < 0) throw new AiffFormatException("el AIFF no trae audio (falta el bloque SSND)");

        if (soundDataOffset + common.DataBytes > aiff.Length)
            throw new AiffFormatException("el AIFF está truncado: dice tener más audio del que hay");

        return (common, soundDataOffset);
    }

    private static AiffFormat ReadCommon(Stream aiff, bool compressed)
    {
        int channels = ReadBigEndian16(aiff);
        uint frames = ReadBigEndian32(aiff);
        int bits = ReadBigEndian16(aiff);
        int sampleRate = (int)Math.Round(ReadExtended80(aiff));

        bool littleEndian = false;

        if (compressed)
        {
            // En AIFF-C el COMM sigue con el identificador de compresión.
            // "NONE" y "twos" son PCM big-endian, como el AIFF de siempre;
            // "sowt" es PCM little-endian —lo que escribe QuickTime— y ya viene
            // en el orden de WAV. Cualquier otro trae los datos codificados.
            string compression = ReadTag(aiff);

            littleEndian = compression == "sowt";

            if (compression is not ("NONE" or "sowt" or "twos"))
                throw new AiffFormatException($"AIFF-C comprimido ({compression}): no se puede convertir");
        }

        if (channels is < 1 or > 8) throw new AiffFormatException($"canales fuera de rango: {channels}");
        if (bits is not (8 or 16 or 24 or 32)) throw new AiffFormatException($"bits por muestra no admitidos: {bits}");
        if (sampleRate is < 1000 or > 384000) throw new AiffFormatException($"frecuencia fuera de rango: {sampleRate}");

        return new AiffFormat(channels, sampleRate, bits, frames, littleEndian);
    }

    /// <summary>
    /// La frecuencia viene como un flotante de 80 bits (el <c>extended</c> del
    /// 68k), que .NET no tiene. Se arma a mano: un bit de signo, quince de
    /// exponente y sesenta y cuatro de mantisa explícita.
    /// </summary>
    private static double ReadExtended80(Stream stream)
    {
        Span<byte> bytes = stackalloc byte[10];
        ReadExactly(stream, bytes);

        int exponent = ((bytes[0] & 0x7F) << 8) | bytes[1];
        ulong mantissa = 0;
        for (int i = 2; i < 10; i++) mantissa = (mantissa << 8) | bytes[i];

        if (exponent == 0 && mantissa == 0) return 0;

        double value = mantissa * Math.Pow(2, exponent - 16383 - 63);
        return (bytes[0] & 0x80) != 0 ? -value : value;
    }

    // MARK: - Escribir el WAV

    private static void WriteWavHeader(Stream wav, AiffFormat format)
    {
        int blockAlign = format.Channels * format.BytesPerSample;
        long dataBytes = format.DataBytes;

        Write(wav, "RIFF");
        WriteLittleEndian32(wav, (uint)Math.Min(uint.MaxValue, 36 + dataBytes));
        Write(wav, "WAVE");

        Write(wav, "fmt ");
        WriteLittleEndian32(wav, 16);
        WriteLittleEndian16(wav, 1);                            // PCM
        WriteLittleEndian16(wav, (ushort)format.Channels);
        WriteLittleEndian32(wav, (uint)format.SampleRate);
        WriteLittleEndian32(wav, (uint)(format.SampleRate * blockAlign));
        WriteLittleEndian16(wav, (ushort)blockAlign);
        WriteLittleEndian16(wav, (ushort)format.BitsPerSample);

        Write(wav, "data");
        WriteLittleEndian32(wav, (uint)Math.Min(uint.MaxValue, dataBytes));
    }

    /// <summary>
    /// Las muestras, con los bytes de cada una dados vuelta. De a bloques, no de
    /// a muestras: un AIFF de un disco entero son cientos de megabytes y leerlo
    /// de a dos bytes tardaría lo que no hay que tardar.
    ///
    /// <para>Ocho bits es la excepción: no hay nada que dar vuelta, pero AIFF los
    /// guarda con signo y WAV sin él, así que se corre el cero.</para>
    /// </summary>
    private static void CopySwapped(Stream aiff, Stream wav, AiffFormat format)
    {
        int width = format.BytesPerSample;
        long remaining = format.DataBytes;

        byte[] buffer = new byte[Math.Min(1 << 20, Math.Max(width, remaining))];

        while (remaining > 0)
        {
            int wanted = (int)Math.Min(buffer.Length - buffer.Length % width, remaining);
            aiff.ReadExactly(buffer, 0, wanted);

            if (width == 1)
            {
                for (int i = 0; i < wanted; i++) buffer[i] = (byte)(buffer[i] + 128);
            }
            else if (!format.SamplesAreLittleEndian)
            {
                for (int i = 0; i + width <= wanted; i += width) buffer.AsSpan(i, width).Reverse();
            }

            wav.Write(buffer, 0, wanted);
            remaining -= wanted;
        }
    }

    // MARK: - Bytes

    private static string ReadTag(Stream stream)
    {
        Span<byte> bytes = stackalloc byte[4];
        ReadExactly(stream, bytes);

        return System.Text.Encoding.ASCII.GetString(bytes);
    }

    private static uint ReadBigEndian32(Stream stream)
    {
        Span<byte> bytes = stackalloc byte[4];
        ReadExactly(stream, bytes);

        return ((uint)bytes[0] << 24) | ((uint)bytes[1] << 16) | ((uint)bytes[2] << 8) | bytes[3];
    }

    private static int ReadBigEndian16(Stream stream)
    {
        Span<byte> bytes = stackalloc byte[2];
        ReadExactly(stream, bytes);

        return (bytes[0] << 8) | bytes[1];
    }

    private static void ReadExactly(Stream stream, Span<byte> destination)
    {
        try
        {
            stream.ReadExactly(destination);
        }
        catch (EndOfStreamException)
        {
            throw new AiffFormatException("el AIFF está truncado");
        }
    }

    private static void Write(Stream stream, string ascii) =>
        stream.Write(System.Text.Encoding.ASCII.GetBytes(ascii));

    private static void WriteLittleEndian32(Stream stream, uint value) =>
        stream.Write([(byte)value, (byte)(value >> 8), (byte)(value >> 16), (byte)(value >> 24)]);

    private static void WriteLittleEndian16(Stream stream, ushort value) =>
        stream.Write([(byte)value, (byte)(value >> 8)]);
}
