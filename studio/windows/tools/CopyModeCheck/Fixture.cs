namespace AuraStudio.Tools.CopyModeCheck;

/// <summary>
/// El fixture del arnés: archivos sintetizados en el momento (ST-243).
///
/// <para>El WAV y el AIFF llevan <b>muestras de verdad</b> —un tono, no
/// silencio— porque de ellos sale el número que interesa: a qué bitrate y en
/// cuánto tiempo los convierte Windows. Los otros tres son contenedores
/// mínimos: para copiar y etiquetar no hace falta más.</para>
///
/// <para>Nada de esto sale de la máquina del dueño. Su biblioteca no se toca
/// ni en copia.</para>
/// </summary>
internal static class Fixture
{
    public const int SampleRate = 44100;
    public const int Channels = 2;
    public const int Seconds = 10;

    /// <summary>Un WAV PCM 16 bits estéreo con un la de 440 Hz.</summary>
    public static string WriteWav(string path)
    {
        byte[] samples = Tone();

        using FileStream file = Create(path);

        Ascii(file, "RIFF");
        LittleEndian32(file, (uint)(36 + samples.Length));
        Ascii(file, "WAVE");

        Ascii(file, "fmt ");
        LittleEndian32(file, 16);
        LittleEndian16(file, 1);                                  // PCM
        LittleEndian16(file, Channels);
        LittleEndian32(file, SampleRate);
        LittleEndian32(file, (uint)(SampleRate * Channels * 2));
        LittleEndian16(file, Channels * 2);
        LittleEndian16(file, 16);

        Ascii(file, "data");
        LittleEndian32(file, (uint)samples.Length);
        file.Write(samples);

        return path;
    }

    /// <summary>El mismo tono, en AIFF: mismas muestras con los bytes al revés.</summary>
    public static string WriteAiff(string path)
    {
        byte[] samples = Tone();
        for (int i = 0; i + 2 <= samples.Length; i += 2) (samples[i], samples[i + 1]) = (samples[i + 1], samples[i]);

        uint frames = (uint)(samples.Length / (Channels * 2));

        byte[] common =
        [
            .. BigEndian16(Channels),
            .. BigEndian32(frames),
            .. BigEndian16(16),
            .. Extended80(SampleRate)
        ];

        byte[] sound = [.. BigEndian32(0), .. BigEndian32(0), .. samples];

        byte[] chunks =
        [
            .. Ascii("COMM"), .. BigEndian32(common.Length), .. common,
            .. Ascii("SSND"), .. BigEndian32(sound.Length), .. sound
        ];

        using FileStream file = Create(path);
        file.Write([.. Ascii("FORM"), .. BigEndian32(4 + chunks.Length), .. Ascii("AIFF"), .. chunks]);

        return path;
    }

    /// <summary>Cuarenta tramas MPEG-1 Layer III. Suficiente para copiar y etiquetar.</summary>
    public static string WriteMp3(string path)
    {
        var bytes = new List<byte>();

        for (int i = 0; i < 40; i++)
        {
            bytes.AddRange([0xFF, 0xFB, 0x90, 0x64]);
            bytes.AddRange(new byte[413]);
        }

        using FileStream file = Create(path);
        file.Write([.. bytes]);

        return path;
    }

    /// <summary>Un FLAC con solo su STREAMINFO.</summary>
    public static string WriteFlac(string path)
    {
        var bytes = new List<byte> { 0x66, 0x4C, 0x61, 0x43, 0x80, 0x00, 0x00, 0x22 };

        bytes.AddRange(BigEndian16(4096));
        bytes.AddRange(BigEndian16(4096));
        bytes.AddRange([0, 0, 0, 0, 0, 0]);

        ulong packed = ((ulong)SampleRate << 44) | ((ulong)1 << 41) | ((ulong)15 << 36) | SampleRate;
        for (int shift = 56; shift >= 0; shift -= 8) bytes.Add((byte)(packed >> shift));

        bytes.AddRange(new byte[16]);

        using FileStream file = Create(path);
        file.Write([.. bytes]);

        return path;
    }

    /// <summary>Un M4A con la cadena de cajas que exige el formato.</summary>
    public static string WriteM4a(string path)
    {
        byte[] ftyp = Box("ftyp", [.. Ascii("M4A "), .. BigEndian32(0x200), .. Ascii("M4A "), .. Ascii("isom"), .. Ascii("mp42")]);

        byte[] mvhd = FullBox("mvhd", 0,
        [
            .. BigEndian32(0), .. BigEndian32(0), .. BigEndian32(SampleRate), .. BigEndian32(SampleRate),
            .. BigEndian32(0x00010000), .. BigEndian16(0x0100), .. new byte[2], .. new byte[8],
            .. UnityMatrix(), .. new byte[24], .. BigEndian32(2)
        ]);

        byte[] tkhd = FullBox("tkhd", 7,
        [
            .. BigEndian32(0), .. BigEndian32(0), .. BigEndian32(1), .. new byte[4],
            .. BigEndian32(SampleRate), .. new byte[8], .. BigEndian16(0), .. BigEndian16(0),
            .. BigEndian16(0x0100), .. new byte[2], .. UnityMatrix(), .. BigEndian32(0), .. BigEndian32(0)
        ]);

        byte[] mdhd = FullBox("mdhd", 0,
        [
            .. BigEndian32(0), .. BigEndian32(0), .. BigEndian32(SampleRate), .. BigEndian32(SampleRate),
            .. BigEndian16(0x55C4), .. BigEndian16(0)
        ]);

        byte[] hdlr = FullBox("hdlr", 0, [.. new byte[4], .. Ascii("soun"), .. new byte[12], 0]);
        byte[] smhd = FullBox("smhd", 0, [.. BigEndian16(0), .. BigEndian16(0)]);
        byte[] dinf = Box("dinf", FullBox("dref", 0, [.. BigEndian32(1), .. FullBox("url ", 1, [])]));

        byte[] mp4a = Box("mp4a",
        [
            .. new byte[6], .. BigEndian16(1), .. new byte[8], .. BigEndian16(Channels),
            .. BigEndian16(16), .. BigEndian16(0), .. BigEndian16(0), .. BigEndian32(SampleRate << 16)
        ]);

        byte[] stbl = Box("stbl",
        [
            .. FullBox("stsd", 0, [.. BigEndian32(1), .. mp4a]),
            .. FullBox("stts", 0, BigEndian32(0)),
            .. FullBox("stsc", 0, BigEndian32(0)),
            .. FullBox("stsz", 0, [.. BigEndian32(0), .. BigEndian32(0)]),
            .. FullBox("stco", 0, BigEndian32(0))
        ]);

        byte[] moov = Box("moov",
        [
            .. mvhd,
            .. Box("trak", [.. tkhd, .. Box("mdia", [.. mdhd, .. hdlr, .. Box("minf", [.. smhd, .. dinf, .. stbl])])])
        ]);

        using FileStream file = Create(path);
        file.Write([.. ftyp, .. moov, .. Box("mdat", [])]);

        return path;
    }

    // MARK: - Muestras

    /// <summary>Un la de 440 Hz, estéreo, 16 bits, en little-endian (lo que espera WAV).</summary>
    private static byte[] Tone()
    {
        int frames = SampleRate * Seconds;
        byte[] samples = new byte[frames * Channels * 2];

        for (int frame = 0; frame < frames; frame++)
        {
            short value = (short)(Math.Sin(2 * Math.PI * 440 * frame / SampleRate) * 12000);

            for (int channel = 0; channel < Channels; channel++)
            {
                int offset = (frame * Channels + channel) * 2;
                samples[offset] = (byte)value;
                samples[offset + 1] = (byte)(value >> 8);
            }
        }

        return samples;
    }

    // MARK: - Bytes

    private static FileStream Create(string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        return File.Create(path);
    }

    private static byte[] Box(string type, byte[] payload) =>
        [.. BigEndian32(8 + payload.Length), .. Ascii(type), .. payload];

    private static byte[] FullBox(string type, int flags, byte[] payload) =>
        Box(type, [0, (byte)(flags >> 16), (byte)(flags >> 8), (byte)flags, .. payload]);

    private static byte[] UnityMatrix() =>
    [
        .. BigEndian32(0x00010000), .. BigEndian32(0), .. BigEndian32(0),
        .. BigEndian32(0), .. BigEndian32(0x00010000), .. BigEndian32(0),
        .. BigEndian32(0), .. BigEndian32(0), .. BigEndian32(0x40000000)
    ];

    private static byte[] Extended80(int value)
    {
        int exponent = 16383 + 63;
        ulong mantissa = (ulong)value;

        while ((mantissa & 0x8000_0000_0000_0000) == 0 && mantissa != 0)
        {
            mantissa <<= 1;
            exponent--;
        }

        byte[] bytes = new byte[10];
        bytes[0] = (byte)(exponent >> 8);
        bytes[1] = (byte)exponent;
        for (int i = 0; i < 8; i++) bytes[2 + i] = (byte)(mantissa >> (56 - i * 8));

        return bytes;
    }

    private static byte[] Ascii(string value) => System.Text.Encoding.ASCII.GetBytes(value);

    private static void Ascii(Stream stream, string value) => stream.Write(Ascii(value));

    private static byte[] BigEndian32(long value) =>
        [(byte)(value >> 24), (byte)(value >> 16), (byte)(value >> 8), (byte)value];

    private static byte[] BigEndian16(int value) => [(byte)(value >> 8), (byte)value];

    private static void LittleEndian32(Stream stream, uint value) =>
        stream.Write([(byte)value, (byte)(value >> 8), (byte)(value >> 16), (byte)(value >> 24)]);

    private static void LittleEndian16(Stream stream, int value) =>
        stream.Write([(byte)value, (byte)(value >> 8)]);
}
