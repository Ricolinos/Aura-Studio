using AuraStudio.Core.Media;
using Xunit;

namespace AuraStudio.Core.Tests;

/// <summary>
/// El lector de AIFF (ST-243). Media Foundation decodifica WAV directo y no
/// tiene fuente nativa para AIFF, así que sin esto la mitad de la conversión a
/// MP3 no se podría cumplir.
///
/// <para>La única diferencia real entre AIFF y WAV es el orden de los bytes, así
/// que lo que se prueba es justamente eso: que las muestras salgan dadas vuelta
/// —y que las que ya venían al derecho <b>no</b> se den vuelta—.</para>
/// </summary>
public class AiffToWavTests
{
    [Fact]
    public void SeLeeElFormatoDelBloqueComun()
    {
        AiffFormat format = AiffToWav.ReadFormat(new MemoryStream(Aiff(
            channels: 2, sampleRate: 44100, bits: 16, samples: [0x12, 0x34, 0x56, 0x78])));

        Assert.Equal(2, format.Channels);
        Assert.Equal(44100, format.SampleRate);
        Assert.Equal(16, format.BitsPerSample);
        Assert.Equal(1u, format.Frames);          // 4 bytes / (2 canales × 2 bytes)
        Assert.False(format.SamplesAreLittleEndian);
    }

    /// <summary>
    /// Lo esencial: AIFF guarda las muestras en big-endian y WAV en
    /// little-endian. Convertir es darlas vuelta — no se remuestrea ni se
    /// recodifica nada.
    /// </summary>
    [Fact]
    public void LasMuestrasSalenDadasVuelta()
    {
        byte[] wav = Convert(Aiff(2, 44100, 16, [0x12, 0x34, 0x56, 0x78]));

        Assert.Equal<byte[]>([0x34, 0x12, 0x78, 0x56], DataOf(wav));
    }

    [Fact]
    public void VeinticuatroBitsTambienSeDanVuelta()
    {
        byte[] wav = Convert(Aiff(1, 48000, 24, [0x11, 0x22, 0x33, 0xAA, 0xBB, 0xCC]));

        Assert.Equal<byte[]>([0x33, 0x22, 0x11, 0xCC, 0xBB, 0xAA], DataOf(wav));
    }

    /// <summary>
    /// A ocho bits no hay nada que dar vuelta, pero AIFF los guarda con signo y
    /// WAV sin él: sin correr el cero, la canción sale con un chasquido en cada
    /// muestra.
    /// </summary>
    [Fact]
    public void OchoBitsPasanDeConSignoASinSigno()
    {
        byte[] wav = Convert(Aiff(1, 22050, 8, [0x00, 0x7F, 0x80, 0xFF]));

        Assert.Equal<byte[]>([0x80, 0xFF, 0x00, 0x7F], DataOf(wav));
    }

    /// <summary>
    /// <c>sowt</c> es PCM little-endian —lo que escribe QuickTime— y ya viene en
    /// el orden de WAV. Darlo vuelta "para convertirlo" produce ruido: la clase
    /// de defecto que se oye y no se ve.
    /// </summary>
    [Fact]
    public void ElAiffCLittleEndianNoSeDaVuelta()
    {
        byte[] aiff = Aiff(2, 44100, 16, [0x12, 0x34, 0x56, 0x78], compression: "sowt");

        Assert.True(AiffToWav.ReadFormat(new MemoryStream(aiff)).SamplesAreLittleEndian);
        Assert.Equal<byte[]>([0x12, 0x34, 0x56, 0x78], DataOf(Convert(aiff)));
    }

    [Fact]
    public void ElAiffCSinComprimirSiSeDaVuelta()
    {
        Assert.Equal<byte[]>([0x34, 0x12],
            DataOf(Convert(Aiff(1, 44100, 16, [0x12, 0x34], compression: "NONE"))));
    }

    // MARK: - La cabecera del WAV

    [Fact]
    public void LaCabeceraDelWavDiceLoQueDeciaElAiff()
    {
        byte[] wav = Convert(Aiff(2, 44100, 16, new byte[8]));

        Assert.Equal("RIFF", Ascii(wav, 0, 4));
        Assert.Equal("WAVE", Ascii(wav, 8, 4));
        Assert.Equal("fmt ", Ascii(wav, 12, 4));

        Assert.Equal(1, LittleEndian16(wav, 20));            // PCM
        Assert.Equal(2, LittleEndian16(wav, 22));            // canales
        Assert.Equal(44100u, LittleEndian32(wav, 24));       // frecuencia
        Assert.Equal(44100u * 4, LittleEndian32(wav, 28));   // bytes por segundo
        Assert.Equal(4, LittleEndian16(wav, 32));            // alineación de bloque
        Assert.Equal(16, LittleEndian16(wav, 34));           // bits por muestra

        Assert.Equal("data", Ascii(wav, 36, 4));
        Assert.Equal(8u, LittleEndian32(wav, 40));
    }

    // MARK: - Lo que se rechaza

    /// <summary>
    /// Un AIFF-C de verdad comprimido trae los datos ya codificados —IMA4,
    /// µ-law, incluso MP3— y darlos vuelta como si fueran PCM produciría ruido.
    /// Se dice que no; no se entrega ruido.
    /// </summary>
    [Fact]
    public void UnAiffCComprimidoSeRechazaEnVezDeEntregarRuido()
    {
        AiffFormatException error = Assert.Throws<AiffFormatException>(
            () => Convert(Aiff(2, 44100, 16, new byte[8], compression: "ima4")));

        Assert.Contains("ima4", error.Message);
    }

    [Theory]
    [InlineData("no es un AIFF")]
    public void LoQueNoEsUnAiffSeDiceConTodasLasLetras(string expected)
    {
        byte[] noAiff = [.. System.Text.Encoding.ASCII.GetBytes("RIFF"), .. new byte[20]];

        Assert.Contains(expected,
            Assert.Throws<AiffFormatException>(() => Convert(noAiff)).Message);
    }

    [Fact]
    public void UnAiffTruncadoNoSeConvierteAMedias()
    {
        // Dice tener dos muestras y trae una.
        byte[] aiff = Aiff(1, 44100, 16, [0x12, 0x34], framesOverride: 2);

        Assert.Contains("truncado", Assert.Throws<AiffFormatException>(() => Convert(aiff)).Message);
    }

    [Fact]
    public void UnAiffSinAudioSeRechaza()
    {
        byte[] sinSsnd = Form("AIFF", Chunk("COMM", Common(1, 44100, 16, 0, null)));

        Assert.Contains("SSND", Assert.Throws<AiffFormatException>(() => Convert(sinSsnd)).Message);
    }

    // MARK: - Armar un AIFF

    private static byte[] Aiff(
        int channels, int sampleRate, int bits, byte[] samples,
        string? compression = null, uint? framesOverride = null)
    {
        uint frames = framesOverride
                      ?? (uint)(samples.Length / (channels * ((bits + 7) / 8)));

        return Form(compression is null ? "AIFF" : "AIFC",
        [
            .. Chunk("COMM", Common(channels, sampleRate, bits, frames, compression)),
            .. Chunk("SSND", [.. BigEndian32(0), .. BigEndian32(0), .. samples])
        ]);
    }

    private static byte[] Common(int channels, int sampleRate, int bits, uint frames, string? compression) =>
    [
        .. BigEndian16(channels),
        .. BigEndian32(frames),
        .. BigEndian16(bits),
        .. Extended80(sampleRate),
        .. compression is null ? Array.Empty<byte>() : System.Text.Encoding.ASCII.GetBytes(compression)
    ];

    private static byte[] Form(string kind, byte[] chunks) =>
    [
        .. System.Text.Encoding.ASCII.GetBytes("FORM"),
        .. BigEndian32(4 + chunks.Length),
        .. System.Text.Encoding.ASCII.GetBytes(kind),
        .. chunks
    ];

    private static byte[] Chunk(string tag, byte[] payload)
    {
        byte[] chunk =
        [
            .. System.Text.Encoding.ASCII.GetBytes(tag),
            .. BigEndian32(payload.Length),
            .. payload
        ];

        // Los bloques van alineados a par.
        return payload.Length % 2 == 0 ? chunk : [.. chunk, 0];
    }

    /// <summary>La frecuencia como el flotante de 80 bits del 68k.</summary>
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

    private static byte[] BigEndian32(long value) =>
        [(byte)(value >> 24), (byte)(value >> 16), (byte)(value >> 8), (byte)value];

    private static byte[] BigEndian16(int value) => [(byte)(value >> 8), (byte)value];

    // MARK: - Leer el WAV

    private static byte[] Convert(byte[] aiff)
    {
        var wav = new MemoryStream();
        AiffToWav.Convert(new MemoryStream(aiff), wav);

        return wav.ToArray();
    }

    /// <summary>Las muestras: todo lo que hay después de la cabecera de 44 bytes.</summary>
    private static byte[] DataOf(byte[] wav) => wav[44..];

    private static string Ascii(byte[] bytes, int offset, int length) =>
        System.Text.Encoding.ASCII.GetString(bytes, offset, length);

    private static uint LittleEndian32(byte[] bytes, int offset) =>
        BitConverter.ToUInt32(bytes, offset);

    private static int LittleEndian16(byte[] bytes, int offset) =>
        BitConverter.ToUInt16(bytes, offset);
}
